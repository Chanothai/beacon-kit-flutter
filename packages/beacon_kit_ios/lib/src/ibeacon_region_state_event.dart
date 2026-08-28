/// State ของ enter/exit ของ iBeacon region หนึ่งตัว — ตาม ARCHITECTURE.md ADR-6
/// หัวข้อ 2 "Event/method channel contract ที่เปลี่ยน" (payload shape ของ
/// `beacon_kit_ios/region_state_events`)
enum IBeaconRegionState {
  /// อุปกรณ์เข้าโซนของ region — มาจาก native `didEnterRegion` หรือ
  /// `didDetermineState` ที่ผลเป็น `.inside`
  enter,

  /// อุปกรณ์ออกจากโซนของ region — มาจาก native `didExitRegion` หรือ
  /// `didDetermineState` ที่ผลเป็น `.outside`
  exit,

  /// CoreLocation ยังไม่รู้ state จริง — มาจาก `didDetermineState` ที่ผลเป็น
  /// `.unknown` เท่านั้น (ไม่มี native callback อื่นที่ยิง state นี้)
  unknown,
}

/// event หนึ่งตัวจาก `beacon_kit_ios/region_state_events` (ADR-6) — ยิงเฉพาะตอน
/// state ของ region เปลี่ยนจริงเท่านั้น (native dedupe ให้แล้ว ดู
/// `IBeaconRangingManager.emitRegionStateIfChanged` ฝั่ง Swift) ต่างจาก
/// [IBeaconRegionRequest] ที่เป็นคำขอเริ่ม monitor ไม่ใช่ผลลัพธ์
///
/// อ้างอิง: ARCHITECTURE.md, ADR-6 "จาก ranging-only เป็น region monitoring
/// (enter/exit)"
class IBeaconRegionStateEvent {
  const IBeaconRegionStateEvent({
    required this.regionIdentifier,
    required this.uuid,
    required this.major,
    required this.minor,
    required this.state,
    required this.timestamp,
  });

  /// identifier ที่แอปกำหนดตอนเรียก `startIBeaconMonitoring` — ตรงกับ
  /// [IBeaconRegionRequest.identifier] ของ region เดียวกัน
  final String regionIdentifier;

  /// iBeacon proximity UUID ของ region นี้ (lowercase, hyphenated)
  final String uuid;

  /// `null` ถ้า region นี้เป็น wildcard ไม่ระบุ major (ตาม ADR-5)
  final int? major;

  /// `null` เช่นเดียวกับ major (ต้องระบุ major ก่อนถึงจะระบุ minor ได้)
  final int? minor;

  final IBeaconRegionState state;

  /// เวลาที่ native สร้าง event (UTC)
  final DateTime timestamp;

  @override
  String toString() =>
      'IBeaconRegionStateEvent(regionIdentifier: $regionIdentifier, '
      'uuid: $uuid, major: $major, minor: $minor, state: $state, '
      'timestamp: $timestamp)';
}
