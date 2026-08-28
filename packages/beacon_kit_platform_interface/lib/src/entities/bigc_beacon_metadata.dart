/// ข้อมูลธุรกิจของ BigC ที่ผูกอยู่กับ identity triple หนึ่งตัว — ตาม ADR-5
/// ความหมายทางธุรกิจ (ยี่ห้อ / ล็อต / กลุ่ม / ตำแหน่ง) ไม่ได้ encode ลงในบิตของ
/// major/minor เลย แต่เก็บไว้ที่ backend/database แยกต่างหาก entity นี้คือรูปร่าง
/// ของผลลัพธ์ที่ resolve มาจาก backend นั้น
///
/// อ้างอิง: ARCHITECTURE.md, ADR-5 "BigC ID Scheme สำหรับ multi-vendor
/// provisioning", ADR-7 "ตำแหน่งของ domain entity/usecase สำหรับ BigC ID mapping"
final class BigcBeaconMetadata {
  /// ยี่ห้อ
  final String brand;

  /// ล็อต
  final String lot;

  /// กลุ่ม
  final String group;

  /// ตำแหน่ง (ติดตั้ง/สาขา/โซน)
  final String location;

  const BigcBeaconMetadata({
    required this.brand,
    required this.lot,
    required this.group,
    required this.location,
  });

  @override
  bool operator ==(Object other) =>
      other is BigcBeaconMetadata &&
      other.brand == brand &&
      other.lot == lot &&
      other.group == group &&
      other.location == location;

  @override
  int get hashCode => Object.hash(brand, lot, group, location);

  @override
  String toString() =>
      'BigcBeaconMetadata(brand: $brand, lot: $lot, group: $group, '
      'location: $location)';
}
