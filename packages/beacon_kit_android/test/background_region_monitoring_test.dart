import 'package:beacon_kit_android/beacon_kit_android.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// เทสต์ของเส้นทาง "เฝ้า region เบื้องหลัง" (ADR-14)
///
/// ## สิ่งที่เทสต์ชุดนี้พิสูจน์ได้ และสิ่งที่พิสูจน์ไม่ได้
///
/// พิสูจน์ได้: **สัญญาที่ข้าม method/event channel** — ชื่อเมธอด รูปร่าง argument
/// การแปลงค่าที่รับกลับมา และการไม่กลืน event ทิ้ง
///
/// **พิสูจน์ไม่ได้เลย:** ว่า Android จะปลุก process ขึ้นมาส่งผลสแกนจริงหรือไม่,
/// `FLAG_MUTABLE` จำเป็นจริงหรือไม่, การลงทะเบียนรอดข้าม force-stop หรือรีบูตหรือไม่
/// ตาม CONTRIBUTING ข้อ 4: **unit test ที่เขียวไม่นับเป็นการยืนยัน** สำหรับอะไรที่
/// คุยกับ OS — ข้อเหล่านั้นต้องยืนยันบนเครื่องจริงเท่านั้น
/// (เช็คลิสต์ `docs/test-checklists/android_background_runbook.md`)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('beacon_kit_android/methods');
  const backgroundEventChannel = 'beacon_kit_android/background_region_events';

  final calls = <MethodCall>[];
  Object? Function(MethodCall call)? respond;

  setUp(() {
    calls.clear();
    respond = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          calls.add(call);
          return respond?.call(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('AndroidBeaconRegion', () {
    test('ส่ง major/minor ข้าม channel เฉพาะเมื่อระบุจริง', () {
      expect(
        const AndroidBeaconRegion(
          identifier: 'wide',
          uuid: '7777772e-6b6b-6d63-6e2e-636f6d000001',
        ).toMap(),
        {'identifier': 'wide', 'uuid': '7777772e-6b6b-6d63-6e2e-636f6d000001'},
      );

      expect(
        const AndroidBeaconRegion(
          identifier: 'branch-1',
          uuid: '7777772e-6b6b-6d63-6e2e-636f6d000001',
          major: 1,
          minor: 2,
        ).toMap(),
        {
          'identifier': 'branch-1',
          'uuid': '7777772e-6b6b-6d63-6e2e-636f6d000001',
          'major': 1,
          'minor': 2,
        },
      );
    });

    test(
      'ระบุ minor โดยไม่ระบุ major ไม่ได้ — โครงของ ScanFilter ทำไม่ได้',
      () {
        // byte ของ minor อยู่ถัดจาก major ใน iBeacon payload การกรองจึงข้ามไป
        // เฉพาะ minor ไม่ได้ ถ้าปล่อยผ่าน ตัวกรองจะเงียบ ๆ กลายเป็นกรองแค่ UUID
        // แล้วรายงาน enter ของสาขาอื่นว่าเป็นสาขานี้
        expect(
          () => AndroidBeaconRegion(
            identifier: 'bad',
            uuid: '7777772e-6b6b-6d63-6e2e-636f6d000001',
            minor: 2,
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });

  group('startBackgroundRegionMonitoring', () {
    test('ส่ง regions + exitTimeoutSeconds ตามที่ผู้เรียกกำหนด', () async {
      respond = (_) => <Object?, Object?>{
        'registered': ['k9p-default'],
        'failed': <Object?, Object?>{},
      };

      await const BeaconKitAndroid().startBackgroundRegionMonitoring(
        regions: const [
          AndroidBeaconRegion(
            identifier: 'k9p-default',
            uuid: '7777772e-6b6b-6d63-6e2e-636f6d000001',
          ),
        ],
        exitTimeoutSeconds: 90,
      );

      expect(calls.single.method, 'startBackgroundRegionMonitoring');
      expect(calls.single.arguments, {
        'regions': [
          {
            'identifier': 'k9p-default',
            'uuid': '7777772e-6b6b-6d63-6e2e-636f6d000001',
          },
        ],
        'exitTimeoutSeconds': 90,
      });
    });

    test('ค่า exit เริ่มต้น 30 วินาที — ตรงกับที่วัดได้จาก iOS เพื่อให้เทียบผลกันได้', () async {
      // ADR-11 หัวข้อ 2: 43.5% ของช่วงที่วัดได้บน iOS ตกในหน้าต่าง 29.5-30.5
      // วินาที การเริ่มด้วยค่าเดียวกันทำให้ผลรอบทดสอบแรกของสองแพลตฟอร์มต่างกัน
      // เพราะกลไก ไม่ใช่เพราะตั้งค่าคนละแบบ
      respond = (_) => <Object?, Object?>{
        'registered': <Object?>[],
        'failed': <Object?, Object?>{},
      };

      await const BeaconKitAndroid().startBackgroundRegionMonitoring(
        regions: const [
          AndroidBeaconRegion(
            identifier: 'k9p-default',
            uuid: '7777772e-6b6b-6d63-6e2e-636f6d000001',
          ),
        ],
      );

      expect((calls.single.arguments as Map)['exitTimeoutSeconds'], 30);
    });

    test('คืนความล้มเหลว **รายอัน** ไม่ยุบเหลือ success/fail ค่าเดียว', () async {
      // ถ้ายุบเป็นค่าเดียว ผู้เรียกจะไม่มีทางรู้ว่าสาขาไหนลงทะเบียนไม่ติด แล้ว
      // อาการจะออกมาเป็น "บางสาขาใช้ได้ บางสาขาไม่ได้" ที่ไล่หาสาเหตุยากมาก
      respond = (_) => <Object?, Object?>{
        'registered': ['a'],
        'failed': <Object?, Object?>{
          'b': 'SCAN_FAILED_SCANNING_TOO_FREQUENTLY',
        },
      };

      final result = await const BeaconKitAndroid()
          .startBackgroundRegionMonitoring(
            regions: const [
              AndroidBeaconRegion(
                identifier: 'a',
                uuid: '0000feaa-0000-1000-8000-00805f9b34fb',
              ),
              AndroidBeaconRegion(
                identifier: 'b',
                uuid: '0000feaa-0000-1000-8000-00805f9b34fb',
              ),
            ],
          );

      expect(result.registered, ['a']);
      expect(result.failed, {'b': 'SCAN_FAILED_SCANNING_TOO_FREQUENTLY'});
      expect(result.isCompleteSuccess, isFalse);
    });

    test(
      'native ไม่ตอบอะไรมา = ไม่มีอะไรลงทะเบียนสำเร็จ ไม่ใช่สำเร็จเงียบ',
      () async {
        respond = (_) => null;

        final result = await const BeaconKitAndroid()
            .startBackgroundRegionMonitoring(
              regions: const [
                AndroidBeaconRegion(
                  identifier: 'a',
                  uuid: '0000feaa-0000-1000-8000-00805f9b34fb',
                ),
              ],
            );

        expect(result.registered, isEmpty);
        expect(
          result.isCompleteSuccess,
          isFalse,
          reason:
              'ไม่มี region ลงทะเบียนสำเร็จ ต้องไม่ถูกนับว่าสำเร็จ — '
              '"สำเร็จเงียบแล้วไม่มี event" คืออาการที่ดีบักยากที่สุด',
        );
      },
    );
  });

  group('getBackgroundRegionMonitoringStatus', () {
    test('แปลงสถานะครบทุกฟิลด์ รวมจำนวน event ที่คิวไว้', () async {
      respond = (_) => <Object?, Object?>{
        'isActive': true,
        'regionIdentifiers': ['k9p-default'],
        'exitTimeoutSeconds': 30,
        'queuedEventCount': 4,
      };

      final status = await const BeaconKitAndroid()
          .getBackgroundRegionMonitoringStatus();

      expect(status.isActive, isTrue);
      expect(status.regionIdentifiers, ['k9p-default']);
      expect(status.exitTimeoutSeconds, 30);
      expect(
        status.queuedEventCount,
        4,
        reason:
            'จำนวน event ที่คิวไว้ตอนไม่มี engine คือหลักฐานว่ามีอะไรเกิดขึ้น'
            'ตอนแอปปิดอยู่ — ถ้าไม่ส่งออกมา จะไม่มีใครรู้ว่ามันเคยมี',
      );
    });
  });

  group('backgroundRegionEvents', () {
    /// ป้อน payload เข้า event channel จริง แล้วอ่านค่าที่ Dart แปลงได้
    Future<List<AndroidBackgroundRegionEvent>> eventsFrom(
      List<Map<String, Object?>> payloads,
    ) async {
      final platform = MethodChannelBeaconKitAndroid();
      final future = platform.backgroundRegionEvents
          .take(payloads.where((p) => p['state'] != 'nonsense').length)
          .toList();

      const codec = StandardMethodCodec();
      for (final payload in payloads) {
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              backgroundEventChannel,
              codec.encodeSuccessEnvelope(payload),
              (_) {},
            );
      }
      return future;
    }

    test('แปลง enter/exit พร้อมเวลาที่ native บันทึกไว้', () async {
      final events = await eventsFrom([
        {
          'regionIdentifier': 'k9p-default',
          'state': 'enter',
          'timestampMillis': 1756600000000,
          'fromBackgroundProcess': true,
        },
      ]);

      expect(events.single.regionIdentifier, 'k9p-default');
      expect(events.single.state, AndroidRegionState.enter);
      expect(
        events.single.timestamp.millisecondsSinceEpoch,
        1756600000000,
        reason:
            'ต้องเป็นเวลาที่ native บันทึก ไม่ใช่เวลาที่ Dart ได้รับ — event ที่ถูก'
            'คิวไว้ตอนแอปปิดอาจเก่ากว่าตอนนี้หลายชั่วโมง',
      );
      expect(events.single.fromBackgroundProcess, isTrue);
    });

    test('บรรทัดที่ผิดรูปแบบถูกข้าม แต่ไม่ทำให้ stream ตาย', () async {
      // stream ที่ตายเพราะ event เดียวผิดรูป = event ที่เหลือทั้งหมดหายตามไปด้วย
      // ซึ่งแย่กว่าการข้าม event เดียวมาก
      final events = await eventsFrom([
        {'regionIdentifier': 'k9p-default', 'state': 'nonsense'},
        {
          'regionIdentifier': 'k9p-default',
          'state': 'exit',
          'timestampMillis': 1,
          'fromBackgroundProcess': false,
        },
      ]);

      expect(events.single.state, AndroidRegionState.exit);
    });
  });

  group('stopBackgroundRegionMonitoring', () {
    test('เรียกเมธอดตรงชื่อ', () async {
      respond = (_) => null;
      await const BeaconKitAndroid().stopBackgroundRegionMonitoring();
      expect(calls.single.method, 'stopBackgroundRegionMonitoring');
    });
  });
}
