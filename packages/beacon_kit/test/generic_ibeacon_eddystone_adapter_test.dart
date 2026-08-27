// Test ของ [GenericIBeaconEddystoneAdapter] — mock [BeaconKitIosPlatform]
// (ไม่ใช่ mock [BeaconKitIos] เอง เพราะ `BeaconKitIos` เป็น concrete class ที่
// delegate ไปยัง `BeaconKitIosPlatform.instance` ทุกเมธอด — mock ที่ระดับ
// platform interface (จุดที่ federated plugin ออกแบบมาให้แทนที่ implementation
// ได้) จึงยังทดสอบ real `BeaconKitIos()` delegation ไปด้วยในตัว ไม่ใช่แค่ mock
// เรียก mock)
//
// *** สำคัญ — Track B (SPRINT.md) ***
// เทสต์ไฟล์นี้พิสูจน์ได้แค่ว่า "โค้ด Dart ของเราเรียก mock ตามสัญญาที่เราคิดว่า
// ถูก (ตาม ADR-4 ใน ARCHITECTURE.md)" **ไม่ได้พิสูจน์ว่า CoreLocation/
// CoreBluetooth จริงบนอุปกรณ์ตอบสนองแบบนั้น** ห้ามอ้างว่า adapter นี้
// "ใช้งานได้จริงกับ K9P" จาก mock test ระดับนี้เด็ดขาด — ต้องรอ
// hardware-in-the-loop checklist ที่ docs/test-checklists/ios_broadcast_scanning.md
// ยืนยันกับอุปกรณ์จริงก่อนเท่านั้น
library;

import 'dart:async';

import 'package:beacon_kit/beacon_kit.dart';
import 'package:beacon_kit_ios/beacon_kit_ios.dart' as ios;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

const String _eddystoneServiceUuid = '0000feaa-0000-1000-8000-00805f9b34fb';

/// fake [ios.BeaconKitIosPlatform] — extend (ไม่ implement) เพื่อได้ token
/// เดียวกันจาก `super()` อัตโนมัติ ผ่าน `PlatformInterface.verifyToken` ตอน set
/// เป็น [ios.BeaconKitIosPlatform.instance] (ตาม federated plugin test pattern
/// มาตรฐาน)
class _FakeBeaconKitIosPlatform extends ios.BeaconKitIosPlatform {
  final List<String> calls = [];
  List<ios.IBeaconRegionRequest>? lastStartRegions;
  List<String>? lastStopIdentifiers;
  List<String>? lastStartServiceUuids;

  Object? startIBeaconError;
  Object? startBluetoothError;

  final StreamController<BeaconAdvertisement> rangingController =
      StreamController<BeaconAdvertisement>.broadcast();
  final StreamController<BeaconAdvertisement> rawController =
      StreamController<BeaconAdvertisement>.broadcast();

  @override
  Future<void> startIBeaconMonitoring(
    List<ios.IBeaconRegionRequest> regions,
  ) async {
    calls.add('startIBeaconMonitoring');
    lastStartRegions = regions;
    final error = startIBeaconError;
    if (error != null) throw error;
  }

  @override
  Future<void> stopIBeaconMonitoring([List<String>? identifiers]) async {
    calls.add('stopIBeaconMonitoring');
    lastStopIdentifiers = identifiers;
  }

  @override
  Future<void> startBluetoothScan(List<String> serviceUuids) async {
    calls.add('startBluetoothScan');
    lastStartServiceUuids = serviceUuids;
    final error = startBluetoothError;
    if (error != null) throw error;
  }

  @override
  Future<void> stopBluetoothScan() async {
    calls.add('stopBluetoothScan');
  }

  @override
  Stream<BeaconAdvertisement> get iBeaconRangingEvents =>
      rangingController.stream;

  @override
  Stream<BeaconAdvertisement> get rawAdvertisementEvents =>
      rawController.stream;

  Future<void> dispose() async {
    await rangingController.close();
    await rawController.close();
  }
}

BeaconAdvertisement _fakeCoreLocationEvent(String value) => BeaconAdvertisement(
  deviceId: BeaconDeviceId(value: value, kind: DeviceIdKind.iBeaconLogicalId),
  rssi: -55,
  source: AdvertisementSource.coreLocation,
  timestamp: DateTime.utc(2026, 8, 27),
);

BeaconAdvertisement _fakeCoreBluetoothEvent(String value) =>
    BeaconAdvertisement(
      deviceId: BeaconDeviceId(
        value: value,
        kind: DeviceIdKind.coreBluetoothPeripheralId,
      ),
      rssi: -60,
      source: AdvertisementSource.coreBluetooth,
      timestamp: DateTime.utc(2026, 8, 27),
    );

void main() {
  late _FakeBeaconKitIosPlatform fake;

  setUp(() {
    fake = _FakeBeaconKitIosPlatform();
    ios.BeaconKitIosPlatform.instance = fake;
  });

  tearDown(() => fake.dispose());

  test('scan() เรียก startIBeaconMonitoring/startBluetoothScan ด้วย region/serviceUuid '
      'ที่ถูกต้องตอนเริ่ม listen', () async {
    final adapter = GenericIBeaconEddystoneAdapter(
      iBeaconRegions: const [
        IBeaconRegionConfig(
          identifier: 'k9p-default',
          uuid: 'UUID-1',
          major: 1,
          minor: 2,
        ),
      ],
    );

    final subscription = adapter.scan().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(fake.calls, contains('startIBeaconMonitoring'));
    expect(fake.calls, contains('startBluetoothScan'));

    expect(fake.lastStartRegions, hasLength(1));
    final region = fake.lastStartRegions!.single;
    expect(region.identifier, 'k9p-default');
    expect(region.uuid, 'UUID-1');
    expect(region.major, 1);
    expect(region.minor, 2);

    expect(fake.lastStartServiceUuids, [_eddystoneServiceUuid]);

    await subscription.cancel();
  });

  test(
    'scanEddystone: false -> ไม่เรียก startBluetoothScan/stopBluetoothScan เลย',
    () async {
      final adapter = GenericIBeaconEddystoneAdapter(
        iBeaconRegions: const [
          IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
        ],
        scanEddystone: false,
      );

      final subscription = adapter.scan().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(fake.calls, isNot(contains('startBluetoothScan')));
      expect(fake.calls, isNot(contains('stopBluetoothScan')));
      expect(fake.calls, contains('startIBeaconMonitoring'));
      expect(fake.calls, contains('stopIBeaconMonitoring'));
    },
  );

  test(
    'stream subscription ถูก cancel -> ต้องเรียก stopIBeaconMonitoring/'
    'stopBluetoothScan จริง (anti-leak — ห้ามปล่อย native scan ค้าง)',
    () async {
      final adapter = GenericIBeaconEddystoneAdapter(
        iBeaconRegions: const [
          IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
        ],
      );

      final subscription = adapter.scan().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(fake.calls, isNot(contains('stopIBeaconMonitoring')));
      expect(fake.calls, isNot(contains('stopBluetoothScan')));

      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(fake.calls, contains('stopIBeaconMonitoring'));
      expect(fake.calls, contains('stopBluetoothScan'));
      expect(fake.lastStopIdentifiers, ['k9p-default']);
    },
  );

  test(
    'scan() รวม event จาก iBeaconRangingEvents และ rawAdvertisementEvents เข้า '
    'stream เดียวกัน',
    () async {
      final adapter = GenericIBeaconEddystoneAdapter(
        iBeaconRegions: const [
          IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
        ],
      );

      final received = <String>[];
      final subscription = adapter.scan().listen(
        (advertisement) => received.add(advertisement.deviceId.value),
      );
      await Future<void>.delayed(Duration.zero);

      fake.rangingController.add(_fakeCoreLocationEvent('ranging-1'));
      fake.rawController.add(_fakeCoreBluetoothEvent('raw-1'));
      await Future<void>.delayed(Duration.zero);

      expect(received, containsAll(['ranging-1', 'raw-1']));

      await subscription.cancel();
    },
  );

  test('startIBeaconMonitoring throw PlatformException -> forward เป็น stream error '
      '(ไม่กลืน error ทิ้งเงียบ ๆ)', () async {
    fake.startIBeaconError = PlatformException(code: 'TOO_MANY_REGIONS');

    final adapter = GenericIBeaconEddystoneAdapter(
      iBeaconRegions: const [
        IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
      ],
    );

    final errors = <Object>[];
    final subscription = adapter.scan().listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single, isA<PlatformException>());
    expect((errors.single as PlatformException).code, 'TOO_MANY_REGIONS');

    await subscription.cancel();
  });

  // ===================================================================
  // Regression: บั๊ก "กด Start ครั้งที่ 2 แล้วเงียบสนิท" ที่เจอจากการทดสอบบน
  // iPhone จริงรอบ 2 (27 ส.ค. 2026)
  //
  // ลำดับที่ผู้ใช้เจอ: Start #1 -> Don't Allow -> ได้ LOCATION_PERMISSION_DENIED
  // ถูกต้อง -> Start #2 ไม่มีอะไรเกิดขึ้นเลย ไม่มี error ไม่ crash -> ไปเปิดสิทธิ์
  // ใน Settings กลับมากด Start #3 ก็ยังเงียบ -> force quit แล้วเปิดใหม่ถึงใช้ได้
  //
  // สาเหตุอยู่ฝั่ง Dart ในไฟล์ที่เทสต์นี้คุม (ไม่ใช่ Swift): controller ที่ start
  // ล้มเหลวถูกปล่อยค้างพร้อม listener เดิม การ listen รอบถัดไปจึงขยับผู้ฟัง
  // 1 -> 2 ซึ่งไม่ยิง onListen -> ไม่มีการเรียก native อีกเลย
  //
  // เทสต์ชุดนี้เป็น Dart ล้วน ทดสอบได้โดยไม่ต้องมีอุปกรณ์ (Track A)
  // ===================================================================

  test('REGRESSION: start ล้มเหลว -> scan() รอบถัดไปต้องเรียก native start ใหม่จริง '
      '(ไม่เงียบ) และรอบถัดไปสำเร็จได้ถ้า error หายไปแล้ว', () async {
    final adapter = GenericIBeaconEddystoneAdapter(
      iBeaconRegions: const [
        IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
      ],
    );

    // --- Start #1: ผู้ใช้กด Don't Allow ---
    fake.startIBeaconError = PlatformException(
      code: 'LOCATION_PERMISSION_DENIED',
    );
    final firstErrors = <Object>[];
    final firstSubscription = adapter.scan().listen(
      (_) {},
      onError: firstErrors.add,
    );
    await Future<void>.delayed(Duration.zero);

    expect(firstErrors, hasLength(1), reason: 'Start #1 ต้องได้ error');
    expect(
      fake.calls.where((c) => c == 'startIBeaconMonitoring'),
      hasLength(1),
    );

    // --- Start #2: ยังไม่ได้สิทธิ์ ต้องเรียก native ซ้ำและได้ error อีกครั้ง ---
    // (เดิมบั๊ก: onListen ไม่ยิง -> ไม่เรียก native เลย -> เงียบสนิท)
    final secondErrors = <Object>[];
    final secondSubscription = adapter.scan().listen(
      (_) {},
      onError: secondErrors.add,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      fake.calls.where((c) => c == 'startIBeaconMonitoring'),
      hasLength(2),
      reason: 'Start #2 ต้องเรียก native start ใหม่ ไม่ใช่เงียบไปเฉย ๆ',
    );
    expect(
      secondErrors,
      hasLength(1),
      reason: 'Start #2 ต้องได้ error กลับมา ไม่ใช่ไม่มีอะไรเกิดขึ้น',
    );

    // --- Start #3: ผู้ใช้ไปเปิดสิทธิ์ใน Settings แล้วกลับมา (ไม่ force quit) ---
    fake.startIBeaconError = null;
    final thirdErrors = <Object>[];
    final thirdSubscription = adapter.scan().listen(
      (_) {},
      onError: thirdErrors.add,
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      fake.calls.where((c) => c == 'startIBeaconMonitoring'),
      hasLength(3),
      reason: 'Start #3 ต้องเรียก native start ใหม่',
    );
    expect(
      thirdErrors,
      isEmpty,
      reason: 'สิทธิ์ผ่านแล้ว Start #3 ต้องสำเร็จโดยไม่ต้อง restart แอป',
    );

    // stream ที่ใช้งานได้จริงต้องส่ง advertisement ถึงผู้ฟังได้ด้วย
    final received = <BeaconAdvertisement>[];
    final activeSubscription = adapter.scan().listen(received.add);
    fake.rangingController.add(_fakeCoreLocationEvent('AA'));
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));

    await firstSubscription.cancel();
    await secondSubscription.cancel();
    await thirdSubscription.cancel();
    await activeSubscription.cancel();
  });

  test('REGRESSION: start ล้มเหลว -> stream เดิมถูกปิด (ผู้ฟังได้ done) '
      'ไม่ปล่อย controller ค้างไว้ให้ listen รอบถัดไปไปเกาะ', () async {
    fake.startIBeaconError = PlatformException(
      code: 'LOCATION_PERMISSION_DENIED',
    );

    final adapter = GenericIBeaconEddystoneAdapter(
      iBeaconRegions: const [
        IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
      ],
    );

    var isDone = false;
    final errors = <Object>[];
    final subscription = adapter.scan().listen(
      (_) {},
      onError: errors.add,
      onDone: () => isDone = true,
    );
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(
      isDone,
      isTrue,
      reason: 'stream ที่ start ไม่สำเร็จต้องถูกปิด ไม่ค้างเป็น zombie',
    );
    expect(
      fake.calls,
      contains('stopIBeaconMonitoring'),
      reason: 'ต้องสั่งหยุด native scan ตอนรื้อ ไม่ leak การสแกนค้างไว้',
    );

    await subscription.cancel();
  });

  test('supportsConnect == false', () {
    final adapter = GenericIBeaconEddystoneAdapter(
      iBeaconRegions: const [
        IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
      ],
    );

    expect(adapter.supportsConnect, isFalse);
  });

  test('connect() throw UnsupportedError เสมอ (broadcast-only adapter)', () {
    final adapter = GenericIBeaconEddystoneAdapter(
      iBeaconRegions: const [
        IBeaconRegionConfig(identifier: 'k9p-default', uuid: 'UUID-1'),
      ],
    );

    expect(
      () => adapter.connect(macAddress: 'AA:BB:CC:DD:EE:FF', password: 'x'),
      throwsUnsupportedError,
    );
  });
}
