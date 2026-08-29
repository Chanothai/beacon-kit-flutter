/// ชั้นของ region ตาม ADR-8 — บอกว่า region นี้ทำหน้าที่อะไรในแผน
enum RegionTier {
  /// ชั้นที่ 1 — region กว้างที่ระบุแค่ UUID ของ BigC ครอบคลุมทั้งฟลีต
  /// ลงทะเบียนถาวร ห้ามถอดออกไม่ว่ากรณีใด (ตาข่ายกันพลาด)
  fleetWide,

  /// ชั้นที่ 2 — region เจาะจงสาขา (UUID + major) สลับได้ตามตำแหน่งผู้ใช้
  branch,
}

/// region หนึ่งอันที่ควรลงทะเบียนกับ CoreLocation
///
/// เป็นผลลัพธ์ของ pure function [planRegionRegistration] — ตัวมันเองไม่แตะ
/// CoreLocation เลย ฝั่ง native เป็นคนแปลงเป็น `CLBeaconRegion` อีกที
class PlannedRegion {
  /// `identifier` ที่จะใช้กับ `CLBeaconRegion` — สำหรับชั้นที่ 2 คือรหัสสาขา
  final String identifier;

  /// proximity UUID ของ BigC (เหมือนกันทุก region ตาม ADR-5)
  final String uuid;

  /// `null` = ไม่ระบุ major (wildcard ครอบคลุมทุกค่า) ใช้กับชั้นที่ 1
  final int? major;

  final RegionTier tier;

  const PlannedRegion({
    required this.identifier,
    required this.uuid,
    required this.tier,
    this.major,
  });

  @override
  bool operator ==(Object other) =>
      other is PlannedRegion &&
      other.identifier == identifier &&
      other.uuid == uuid &&
      other.major == major &&
      other.tier == tier;

  @override
  int get hashCode => Object.hash(identifier, uuid, major, tier);

  @override
  String toString() =>
      'PlannedRegion(identifier: $identifier, uuid: $uuid, major: $major, '
      'tier: ${tier.name})';
}
