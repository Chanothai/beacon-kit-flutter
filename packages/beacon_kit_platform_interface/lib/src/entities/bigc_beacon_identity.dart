/// Identity triple (UUID, Major, Minor) ที่สังเกตได้จริงจาก iBeacon advertisement
/// หนึ่งตัว — เป็นแค่ value holder ของสิ่งที่ observe มา ไม่ validate ช่วงค่าใด ๆ
/// ที่นี่ (การ validate เป็นหน้าที่ของ usecase ที่ใช้ค่านี้ เช่น
/// `ResolveBigcBeaconMetadata`)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-5 "BigC ID Scheme สำหรับ multi-vendor
/// provisioning", ADR-7 "ตำแหน่งของ domain entity/usecase สำหรับ BigC ID mapping"
final class BigcBeaconIdentity {
  /// ตามที่รับมาจาก wire — ไม่บังคับ case ตอนสร้าง entity นี้ การ normalize
  /// เป็น lowercase เพื่อเทียบค่าเป็นหน้าที่ของผู้ใช้ (เช่น
  /// `ResolveBigcBeaconMetadata`)
  final String uuid;

  /// ไม่ validate ช่วงตรงนี้ — เป็นแค่ value holder ของสิ่งที่สังเกตได้จริงจาก
  /// advertisement
  final int major;
  final int minor;

  const BigcBeaconIdentity({
    required this.uuid,
    required this.major,
    required this.minor,
  });

  @override
  bool operator ==(Object other) =>
      other is BigcBeaconIdentity &&
      other.uuid == uuid &&
      other.major == major &&
      other.minor == minor;

  @override
  int get hashCode => Object.hash(uuid, major, minor);

  @override
  String toString() =>
      'BigcBeaconIdentity(uuid: $uuid, major: $major, minor: $minor)';
}
