import 'package:beacon_kit_android/beacon_kit_android.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// payload ที่ Kotlin ส่งข้าม event channel มาให้ — สร้างจาก byte จริงของ iBeacon
/// ที่ K9P broadcast (uuid/major/minor ตรงกับที่บันทึกไว้ในเช็คลิสต์ข้อ 2 จากการ
/// ทดสอบบน iPhone จริง) เพื่อให้เทสต์นี้พิสูจน์ว่า **parser ตัวเดียวกัน** ถอด
/// beacon ตัวเดียวกันได้ผลตรงกันทั้งสองแพลตฟอร์ม
///
/// ⚠️ นี่**ไม่ใช่** fixture ชนิด `captured` ตามกฎใน `docs/fixtures/README.md` —
/// byte ชุดนี้ประกอบขึ้นจาก uuid/major/minor ที่ OS ฝั่ง iOS ถอดมาให้ ไม่ได้ดักจับ
/// byte ดิบจากอากาศจริง จึงพิสูจน์ได้แค่ว่า **การต่อสายถูก** ไม่ได้พิสูจน์ว่า
/// byte ที่ K9P ส่งออกมาจริงมีหน้าตาแบบนี้ — การพิสูจน์ข้อหลังต้องทำบนเครื่องจริง
Uint8List _appleIBeaconManufacturerData({
  required int major,
  required int minor,
  required int txPower,
}) {
  return Uint8List.fromList([
    0x4C, 0x00, // company ID (Apple) — Kotlin ต่อกลับเข้าไปให้
    0x02, 0x15, // iBeacon type + length
    // uuid 7777772e-6b6b-6d63-6e2e-636f6d000001
    0x77, 0x77, 0x77, 0x2E,
    0x6B, 0x6B, 0x6D, 0x63,
    0x6E, 0x2E, 0x63, 0x6F,
    0x6D, 0x00, 0x00, 0x01,
    (major >> 8) & 0xFF, major & 0xFF,
    (minor >> 8) & 0xFF, minor & 0xFF,
    txPower & 0xFF,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eventChannel = 'beacon_kit_android/raw_advertisement_events';

  /// ป้อน payload เข้า event channel จริงแล้วอ่าน [BeaconAdvertisement] ที่ได้
  ///
  /// จงใจไม่ mock parser — เรียก `IBeaconParser`/`EddystoneParser` ตัวจริงตลอดทาง
  /// เพราะสิ่งที่ต้องพิสูจน์คือ "โค้ดถอดรหัสชุดเดียวกันใช้ได้กับ Android"
  Future<BeaconAdvertisement> firstEventFor(
    Map<String, Object?> payload,
  ) async {
    final platform = MethodChannelBeaconKitAndroid();
    final future = platform.rawAdvertisementEvents.first;

    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          eventChannel,
          codec.encodeSuccessEnvelope(payload),
          (_) {},
        );
    return future;
  }

  group(
    'MethodChannelBeaconKitAndroid — ถอด iBeacon ด้วย parser กลางตัวเดียวกัน',
    () {
      test(
        'ถอด uuid/major/minor/txPower จาก manufacturer data ของ Apple ได้ถูก',
        () async {
          final advertisement = await firstEventFor({
            'deviceAddress': 'AA:BB:CC:DD:EE:FF',
            'rssi': -63,
            'timestamp': 1756000000000,
            'serviceData': <String, Object?>{},
            'appleManufacturerData': _appleIBeaconManufacturerData(
              major: 229,
              minor: 24333,
              txPower: -59,
            ),
          });

          expect(
            advertisement.ibeaconUuid,
            '7777772e-6b6b-6d63-6e2e-636f6d000001',
          );
          expect(advertisement.ibeaconMajor, 229);
          expect(advertisement.ibeaconMinor, 24333);
          expect(advertisement.ibeaconTxPower, -59);
          // Android ให้ MAC จริง ต่างจาก iOS ที่ให้ UUID สุ่มต่อแอป (ADR-1)
          expect(advertisement.deviceId.kind, DeviceIdKind.macAddress);
          expect(advertisement.deviceId.value, 'AA:BB:CC:DD:EE:FF');
          // byte ดิบที่เราถอดเอง ไม่ใช่ OS ถอดให้ — ต้องเป็น rawParsed เสมอ (ADR-13)
          expect(advertisement.source, AdvertisementSource.rawParsed);
          expect(advertisement.proximity, isNull);
          expect(advertisement.rawBytes, isNotNull);
        },
      );

      test(
        'manufacturer data ที่ไม่ใช่ iBeacon → ไม่ throw และไม่ drop event',
        () async {
          final advertisement = await firstEventFor({
            'deviceAddress': 'AA:BB:CC:DD:EE:FF',
            'rssi': -80,
            'timestamp': 1756000000000,
            'serviceData': <String, Object?>{},
            // สั้นกว่า 25 bytes → IBeaconParser คืน ParseFailure
            'appleManufacturerData': Uint8List.fromList([0x4C, 0x00, 0x02]),
          });

          // ยังต้องส่ง event ออกมา เพราะ MAC/RSSI ยังมีประโยชน์ — การเงียบหายไปเฉย ๆ
          // คืออาการที่ดีบักยากที่สุด (บทเรียนจาก ADR-10)
          expect(advertisement.ibeaconUuid, isNull);
          expect(advertisement.rssi, -80);
          expect(advertisement.raw, isEmpty);
        },
      );

      test(
        'Eddystone URL frame ถอดด้วย EddystoneParser ตัวเดียวกับ iOS',
        () async {
          final advertisement = await firstEventFor({
            'deviceAddress': 'AA:BB:CC:DD:EE:FF',
            'rssi': -88,
            'timestamp': 1756000000000,
            'serviceData': <String, Object?>{
              '0000feaa-0000-1000-8000-00805f9b34fb': Uint8List.fromList([
                0x10, // frame type = URL
                0xDA, // txPower = -38
                0x03, // https://www.
                0x67, 0x6F, 0x6F, 0x67, 0x6C, 0x65, // "google"
                0x00, // .com/
              ]),
            },
            'appleManufacturerData': null,
          });

          expect(advertisement.raw['eddystone'], isA<EddystoneUrlFrame>());
          expect(advertisement.source, AdvertisementSource.rawParsed);
        },
      );
    },
  );
}
