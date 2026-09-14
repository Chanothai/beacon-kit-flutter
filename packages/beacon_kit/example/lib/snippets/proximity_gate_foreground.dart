/// Snippet สำหรับ README §3 แถว "ProximityGate (foreground)" — ป้อนผลสแกนดิบ
/// เข้า [ProximityGate] แล้วเรียก [ProximityGate.sweepStale] ซ้ำด้วย [Timer]
///
/// `ProximityGate` ไม่มี `Timer` อยู่ในตัวเอง (ตั้งใจ — เพื่อให้ pure/testable)
/// host app จึงต้องเป็นคนตั้งเวลาเรียก `sweepStale()` ซ้ำเอง เหมือนที่
/// `example/lib/main.dart` ทำจริง
library;

import 'dart:async';

import 'package:beacon_kit/beacon_kit.dart';

const String _proximityUuid = '<PROXIMITY_UUID>';

/// เริ่มป้อนผลสแกนเข้า [ProximityGate] คืน callback สำหรับปิดทั้ง subscription
/// และ timer เมื่อไม่ต้องการเฝ้าต่อ
Future<void Function()> runProximityForeground() async {
  final adapter = GenericIBeaconEddystoneAdapter(
    iBeaconRegions: const [
      IBeaconRegionConfig(identifier: 'store-default', uuid: _proximityUuid),
    ],
  );

  // ค่า threshold ใช้ default ของ ProximityGate ทั้งหมด — ค่าที่ example app
  // (main.dart) ตั้งเองเป็น POC policy ตาม ADR-19 §8 ไม่ใช่ default ที่ต้อง
  // demo ซ้ำที่นี่
  final gate = ProximityGate(clock: DateTime.now);

  void handleTransition(ProximityTransition transition) {
    // นโยบายว่าจะทำอะไรกับ transition (แจ้งเตือน, อัปเดต UI, ฯลฯ) เป็นของ
    // host app ทั้งหมด — ดู README §4 / docs/integration-guide.md
  }

  final subscription = adapter.scan().listen((advertisement) {
    final transition = gate.push(advertisement);
    if (transition != null) {
      handleTransition(transition);
    }
  });

  final sweepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    for (final transition in gate.sweepStale()) {
      handleTransition(transition);
    }
  });

  return () {
    unawaited(subscription.cancel());
    sweepTimer.cancel();
  };
}
