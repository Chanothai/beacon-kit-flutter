/// การตั้งค่า region ของ iBeacon หนึ่งตัวที่ต้องการให้ adapter เฝ้าฟัง
///
/// เป็น public API ของ `beacon_kit` เอง — จงใจไม่ผูกกับ `beacon_kit_ios`
/// (`IBeaconRegionRequest`) โดยตรง เพื่อให้ผู้เรียก `beacon_kit` ไม่ต้อง import
/// package ระดับ platform เลย (ตรงตามหลัก facade) การแปลงเป็น
/// `IBeaconRegionRequest` ทำภายใน `GenericIBeaconEddystoneAdapter` เท่านั้น
class IBeaconRegionConfig {
  /// ตัวระบุ region ที่ผู้เรียกกำหนดเอง เช่น `'k9p-default'` — ใช้ตอน stop
  /// monitoring เฉพาะ region นี้ได้ภายหลัง
  final String identifier;

  /// UUID ของ iBeacon (8-4-4-4-12), ไม่สนตัวพิมพ์เล็ก/ใหญ่ตอนส่งเข้า
  final String uuid;

  /// จำกัดเฉพาะ major/minor ที่ระบุ — `null` = รับทุกค่า
  final int? major;
  final int? minor;

  const IBeaconRegionConfig({
    required this.identifier,
    required this.uuid,
    this.major,
    this.minor,
  });
}
