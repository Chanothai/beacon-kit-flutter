// Test ของ [BeaconManager] — registry กลางที่ merge stream จากหลาย [BeaconAdapter]
// ใช้ fake adapter (ควบคุมด้วย StreamController เอง) ไม่ต้อง mock เต็มรูป ตาม
// SPRINT.md ข้อ 2 (domain-level facade เทสต์ได้ล้วน ๆ ไม่ต้องพึ่งฮาร์ดแวร์)
library;

import 'dart:async';

import 'package:beacon_kit/beacon_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// fake adapter อย่างง่าย — คุม stream เองผ่าน [StreamController] ที่เทสต์เข้าถึง
/// ได้โดยตรง เพื่อยิง [BeaconAdvertisement] เข้าไปตอนไหนก็ได้
class _FakeAdapter implements BeaconAdapter {
  _FakeAdapter(this.vendorId);

  @override
  final String vendorId;

  @override
  bool get supportsConnect => false;

  final StreamController<BeaconAdvertisement> controller =
      StreamController<BeaconAdvertisement>.broadcast();

  @override
  Stream<BeaconAdvertisement> scan() => controller.stream;

  @override
  Future<BeaconConnection> connect({
    required String macAddress,
    required String password,
    Duration timeout = const Duration(seconds: 15),
  }) {
    throw UnsupportedError('$vendorId ไม่รองรับ connect');
  }

  BeaconAdvertisement advertisement(String deviceIdValue) =>
      BeaconAdvertisement(
        deviceId: BeaconDeviceId(
          value: deviceIdValue,
          kind: DeviceIdKind.coreBluetoothPeripheralId,
        ),
        rssi: -50,
        source: AdvertisementSource.rawParsed,
        timestamp: DateTime.utc(2026, 8, 27),
      );
}

void main() {
  tearDown(BeaconManager.unregisterAll);

  test('scanAll() ก่อนลงทะเบียน adapter ใด ๆ คืน stream ว่าง', () async {
    final events = await BeaconManager.scanAll().toList();
    expect(events, isEmpty);
  });

  test(
    'scanAll() merge event จาก adapter A และ B ทั้งคู่เข้า stream เดียวกัน',
    () async {
      final adapterA = _FakeAdapter('adapter-a');
      final adapterB = _FakeAdapter('adapter-b');
      BeaconManager.register(adapterA);
      BeaconManager.register(adapterB);

      final received = <String>[];
      final subscription = BeaconManager.scanAll().listen(
        (advertisement) => received.add(advertisement.deviceId.value),
      );

      adapterA.controller.add(adapterA.advertisement('from-a'));
      adapterB.controller.add(adapterB.advertisement('from-b'));
      await Future<void>.delayed(Duration.zero);

      expect(received, containsAll(['from-a', 'from-b']));
      expect(received, hasLength(2));

      await subscription.cancel();
      await adapterA.controller.close();
      await adapterB.controller.close();
    },
  );

  test('unregisterAll() เคลียร์ adapter list จริง — scanAll() หลังจากนั้นต้องไม่มี '
      'stream จาก adapter เก่าอีก', () async {
    final adapter = _FakeAdapter('adapter-old');
    BeaconManager.register(adapter);

    BeaconManager.unregisterAll();

    final received = <String>[];
    final subscription = BeaconManager.scanAll().listen(
      (advertisement) => received.add(advertisement.deviceId.value),
    );

    // ยิง event เข้า controller เก่า — ต้องไม่โผล่ใน scanAll() ใหม่เพราะ
    // scanAll() หลัง unregisterAll ไม่ได้ merge stream ของ adapter ตัวนี้อีกแล้ว
    adapter.controller.add(adapter.advertisement('stale'));
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);

    await subscription.cancel();
    await adapter.controller.close();
  });
}
