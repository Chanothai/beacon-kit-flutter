// Test ของ [MethodChannelBeaconKitIos] — mock ที่ระดับ *platform channel เอง*
// (ผ่าน `TestDefaultBinaryMessengerBinding`) ไม่ใช่ mock ที่ระดับ
// `BeaconKitIosPlatform` เพราะแบบนั้นเทสต์แค่ mock เรียก mock ไม่มีความหมาย —
// ดู SPRINT.md ข้อ 1
//
// ครอบคลุม:
// 1. method call names + arguments shape ตาม ADR-4 (ARCHITECTURE.md)
// 2. PlatformException error code หลุดออกมาถึงผู้เรียกตรง ๆ ไม่ถูกกลืน/แปลง
// 3. event channel #1 (iBeacon ranging) flatten batch -> event แยกกันถูกต้อง
// 4. event channel #2 (raw advertisement) integration กับ EddystoneParser จริง
//    (ไม่ mock parser) ด้วย byte layout จาก docs/fixtures/eddystone_uid_valid.json
// 5. เคส parse ไม่สำเร็จ -> ยังได้ BeaconAdvertisement ออกมา ไม่ drop event
//
// หมายเหตุ Track B (SPRINT.md): เทสต์ไฟล์นี้ mock method/event channel เอง —
// พิสูจน์ได้แค่ว่าโค้ด Dart เข้ารหัส/ถอดรหัส message ตรงตามที่เรา *คิดว่า* ตรงกับ
// ADR-4 เท่านั้น ไม่ได้พิสูจน์ว่า `BeaconKitIosPlugin.swift` ตัวจริงส่ง/รับ message
// รูปแบบนี้บนอุปกรณ์จริง — ต้องรอ hardware-in-the-loop checklist ที่
// docs/test-checklists/ios_broadcast_scanning.md
library;

import 'package:beacon_kit_ios/beacon_kit_ios.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// mock handler ของ method call ที่ event channel ส่งมาตอน subscribe/unsubscribe
/// (`listen`/`cancel`) — ต้องตอบสำเร็จ (return null) ไม่งั้น
/// `EventChannel.receiveBroadcastStream()` จะ report error ผ่าน `FlutterError`
void _mockEventChannelHandshake(String channelName) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(channelName), (call) async {
        expect(call.method, anyOf('listen', 'cancel'));
        return null;
      });
}

void _unmockEventChannel(String channelName) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MethodChannel(channelName), null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(channelName, null);
}

/// จำลอง native ส่ง event ขึ้นมาบน event channel — เข้ารหัสด้วย
/// `StandardMethodCodec` เดียวกับที่ `EventChannel` ใช้ถอดรหัสจริง แล้วป้อนผ่าน
/// `handlePlatformMessage` ราวกับมาจากฝั่ง platform จริง
Future<void> _pushEvent(String channelName, dynamic payload) async {
  final data = const StandardMethodCodec().encodeSuccessEnvelope(payload);
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(channelName, data, (ByteData? _) {});
}

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

const String _eddystoneServiceUuid = '0000feaa-0000-1000-8000-00805f9b34fb';

// จาก docs/fixtures/eddystone_uid_valid.json — parser = "eddystone", ป้อนตรงเข้า
// EddystoneParser.parse() ได้เลย (ไม่รวม 2-byte service UUID)
const String _eddystoneUidValidHex = '00eaaabbccddeeff001122334455667788990000';

// จาก docs/fixtures/eddystone_uid_too_short.json — 14 bytes, ต่ำกว่า 20 bytes
// ที่ Eddystone UID frame บังคับ
const String _eddystoneUidTooShortHex = '00eaaabbccddeeff001122334455';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelBeaconKitIos — method channel (beacon_kit_ios/methods)', () {
    late MethodChannelBeaconKitIos platform;
    late List<MethodCall> calls;

    setUp(() {
      platform = MethodChannelBeaconKitIos();
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, null);
    });

    test('startIBeaconMonitoring: method name + regions map ตาม ADR-4 '
        '(identifier/uuid/major/minor)', () async {
      await platform.startIBeaconMonitoring(const [
        IBeaconRegionRequest(
          identifier: 'r1',
          uuid: 'UUID-1',
          major: 1,
          minor: 2,
        ),
        IBeaconRegionRequest(identifier: 'r2', uuid: 'UUID-2'),
      ]);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'startIBeaconMonitoring');
      expect(calls.single.arguments, {
        'regions': [
          {'identifier': 'r1', 'uuid': 'UUID-1', 'major': 1, 'minor': 2},
          {'identifier': 'r2', 'uuid': 'UUID-2', 'major': null, 'minor': null},
        ],
      });
    });

    test(
      'stopIBeaconMonitoring(null): ส่ง identifiers: null (หมายถึงหยุดทั้งหมด)',
      () async {
        await platform.stopIBeaconMonitoring();

        expect(calls.single.method, 'stopIBeaconMonitoring');
        expect(calls.single.arguments, {'identifiers': null});
      },
    );

    test(
      'stopIBeaconMonitoring(list): ส่ง identifiers ตรงตามที่ระบุ',
      () async {
        await platform.stopIBeaconMonitoring(['r1', 'r2']);

        expect(calls.single.method, 'stopIBeaconMonitoring');
        expect(calls.single.arguments, {
          'identifiers': ['r1', 'r2'],
        });
      },
    );

    test('startBluetoothScan: ส่ง serviceUuids ตรงตามที่ระบุ', () async {
      await platform.startBluetoothScan([_eddystoneServiceUuid]);

      expect(calls.single.method, 'startBluetoothScan');
      expect(calls.single.arguments, {
        'serviceUuids': [_eddystoneServiceUuid],
      });
    });

    test('stopBluetoothScan: เรียกโดยไม่มี argument พิเศษ', () async {
      await platform.stopBluetoothScan();

      expect(calls.single.method, 'stopBluetoothScan');
    });

    test(
      'startIBeaconMonitoring: PlatformException(TOO_MANY_REGIONS) จาก native '
      'หลุดออกมาถึงผู้เรียกตรง ๆ ไม่ถูกกลืน/แปลงเป็นอย่างอื่น',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(platform.methodChannel, (call) async {
              throw PlatformException(
                code: 'TOO_MANY_REGIONS',
                message: 'regions.length + currently monitored > 20',
              );
            });

        await expectLater(
          platform.startIBeaconMonitoring(const [
            IBeaconRegionRequest(identifier: 'r1', uuid: 'UUID-1'),
          ]),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'TOO_MANY_REGIONS',
            ),
          ),
        );
      },
    );

    test('startIBeaconMonitoring: PlatformException(INVALID_REGION_UUID) '
        'หลุดออกมาถึงผู้เรียกตรง ๆ', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            throw PlatformException(code: 'INVALID_REGION_UUID');
          });

      await expectLater(
        platform.startIBeaconMonitoring(const [
          IBeaconRegionRequest(identifier: 'r1', uuid: 'not-a-uuid'),
        ]),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'INVALID_REGION_UUID',
          ),
        ),
      );
    });

    // ข้อจำกัดของเทสต์ตัวนี้ (อ่านก่อนเชื่อ): mock handler จำลอง native ว่าโยน
    // INVALID_ARGUMENT — จึงพิสูจน์ได้แค่ว่า **ชั้น Dart forward code นี้ออกไปโดย
    // ไม่กลืน/ไม่แปลง** ไม่ได้พิสูจน์ว่า BeaconKitIosPlugin.handleStartBluetoothScan
    // ฝั่ง Swift โยน code นี้จริงตอนได้ argument ผิดรูปแบบ (ตาม SPRINT.md ข้อ 2:
    // mock ไม่นับเป็นการยืนยันพฤติกรรมของ native)
    // หลักฐานฝั่ง native ที่มีตอนนี้คือ string INVALID_ARGUMENT ถูกคอมไพล์ลง
    // arm64 object จริง — การยืนยันเต็มรูปแบบต้องรันบนอุปกรณ์ตาม
    // docs/test-checklists/ios_broadcast_scanning.md
    test('startBluetoothScan: PlatformException(INVALID_ARGUMENT) จาก native '
        '(argument ผิดรูปแบบ) หลุดออกมาถึงผู้เรียกตรง ๆ และไม่ถูกแปลงเป็น '
        'BLUETOOTH_UNAVAILABLE', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            throw PlatformException(
              code: 'INVALID_ARGUMENT',
              message:
                  "'serviceUuids' ต้องเป็น List<String> (ไม่มี wildcard scan)",
            );
          });

      await expectLater(
        platform.startBluetoothScan([_eddystoneServiceUuid]),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'INVALID_ARGUMENT',
          ),
        ),
      );
    });

    test('startBluetoothScan: PlatformException(BLUETOOTH_UNAVAILABLE) '
        'หลุดออกมาถึงผู้เรียกตรง ๆ', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform.methodChannel, (call) async {
            throw PlatformException(code: 'BLUETOOTH_UNAVAILABLE');
          });

      await expectLater(
        platform.startBluetoothScan([_eddystoneServiceUuid]),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'BLUETOOTH_UNAVAILABLE',
          ),
        ),
      );
    });
  });

  group('MethodChannelBeaconKitIos — iBeaconRangingEvents '
      '(event channel #1: beacon_kit_ios/ibeacon_ranging_events)', () {
    late MethodChannelBeaconKitIos platform;
    late String channelName;

    setUp(() {
      platform = MethodChannelBeaconKitIos();
      channelName = platform.iBeaconRangingEventChannel.name;
      _mockEventChannelHandshake(channelName);
    });

    tearDown(() => _unmockEventChannel(channelName));

    test('batch 2 รายการจาก native -> 2 BeaconAdvertisement แยกกัน (flatten ถูกต้อง), '
        'source == coreLocation, deviceId.kind == iBeaconLogicalId', () async {
      final events = <BeaconAdvertisement>[];
      final sub = platform.iBeaconRangingEvents.listen(events.add);
      await Future<void>.delayed(Duration.zero);

      await _pushEvent(channelName, [
        {
          'regionIdentifier': 'r1',
          'uuid': 'UUID-1',
          'major': 1,
          'minor': 2,
          'rssi': -60,
          'proximity': 'near',
          'timestamp': 1700000000000,
        },
        {
          'regionIdentifier': 'r1',
          'uuid': 'UUID-1',
          'major': 1,
          'minor': 3,
          'rssi': -70,
          'proximity': 'far',
          'timestamp': 1700000000001,
        },
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));

      expect(events[0].source, AdvertisementSource.coreLocation);
      expect(events[0].deviceId.kind, DeviceIdKind.iBeaconLogicalId);
      expect(events[0].deviceId.value, 'UUID-1:1:2');
      expect(events[0].rssi, -60);
      expect(events[0].ibeaconUuid, 'UUID-1');
      expect(events[0].ibeaconMajor, 1);
      expect(events[0].ibeaconMinor, 2);
      expect(events[0].proximity, BeaconProximity.near);

      expect(events[1].source, AdvertisementSource.coreLocation);
      expect(events[1].deviceId.kind, DeviceIdKind.iBeaconLogicalId);
      expect(events[1].deviceId.value, 'UUID-1:1:3');
      expect(events[1].rssi, -70);
      expect(events[1].proximity, BeaconProximity.far);

      await sub.cancel();
    });
  });

  group('MethodChannelBeaconKitIos — rawAdvertisementEvents '
      '(event channel #2: beacon_kit_ios/raw_advertisement_events)', () {
    late MethodChannelBeaconKitIos platform;
    late String channelName;

    setUp(() {
      platform = MethodChannelBeaconKitIos();
      channelName = platform.rawAdvertisementEventChannel.name;
      _mockEventChannelHandshake(channelName);
    });

    tearDown(() => _unmockEventChannel(channelName));

    test('Eddystone UID service data ที่ถูกต้อง (fixture: eddystone_uid_valid.json) '
        '-> raw["eddystone"] เป็น EddystoneUidFrame ค่าตรงกับ fixture, '
        'source == coreBluetooth (integration กับ EddystoneParser จริง ไม่ mock parser)', () async {
      final events = <BeaconAdvertisement>[];
      final sub = platform.rawAdvertisementEvents.listen(events.add);
      await Future<void>.delayed(Duration.zero);

      await _pushEvent(channelName, {
        'peripheralId': 'PERIPH-1',
        'rssi': -55,
        'serviceData': {
          _eddystoneServiceUuid: _hexToBytes(_eddystoneUidValidHex),
        },
        'timestamp': 1700000000000,
      });
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      final advertisement = events.single;
      expect(advertisement.source, AdvertisementSource.coreBluetooth);
      expect(
        advertisement.deviceId.kind,
        DeviceIdKind.coreBluetoothPeripheralId,
      );
      expect(advertisement.deviceId.value, 'PERIPH-1');
      expect(advertisement.rssi, -55);

      final frame = advertisement.raw['eddystone'];
      expect(frame, isA<EddystoneUidFrame>());
      frame as EddystoneUidFrame;
      expect(frame.txPower, -22);
      expect(frame.namespaceId, 'aabbccddeeff00112233');
      expect(frame.instanceId, '445566778899');
      expect(advertisement.rawBytes, isNotNull);

      await sub.cancel();
    });

    test(
      'service data ที่พัง (สั้นเกิน — fixture: eddystone_uid_too_short.json) '
      '-> ยังได้ BeaconAdvertisement ออกมา (ไม่ drop event) แต่ raw ว่างเปล่าและ '
      'rawBytes เป็น null ตาม contract',
      () async {
        final events = <BeaconAdvertisement>[];
        final sub = platform.rawAdvertisementEvents.listen(events.add);
        await Future<void>.delayed(Duration.zero);

        await _pushEvent(channelName, {
          'peripheralId': 'PERIPH-2',
          'rssi': -80,
          'serviceData': {
            _eddystoneServiceUuid: _hexToBytes(_eddystoneUidTooShortHex),
          },
          'timestamp': 1700000000000,
        });
        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        final advertisement = events.single;
        expect(advertisement.source, AdvertisementSource.coreBluetooth);
        expect(advertisement.deviceId.value, 'PERIPH-2');
        expect(advertisement.raw, isEmpty);
        expect(advertisement.rawBytes, isNull);

        await sub.cancel();
      },
    );

    test(
      'ไม่มี serviceData เลย (peripheral broadcast ฟอร์แมตอื่นที่ไม่ใช่ Eddystone) '
      '-> ยังได้ BeaconAdvertisement, raw ว่างเปล่า, rawBytes เป็น null',
      () async {
        final events = <BeaconAdvertisement>[];
        final sub = platform.rawAdvertisementEvents.listen(events.add);
        await Future<void>.delayed(Duration.zero);

        await _pushEvent(channelName, {
          'peripheralId': 'PERIPH-3',
          'rssi': -90,
          'serviceData': null,
          'timestamp': 1700000000000,
        });
        await Future<void>.delayed(Duration.zero);

        expect(events, hasLength(1));
        expect(events.single.raw, isEmpty);
        expect(events.single.rawBytes, isNull);

        await sub.cancel();
      },
    );
  });
}
