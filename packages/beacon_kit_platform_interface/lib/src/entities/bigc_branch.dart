/// สาขาหนึ่งแห่งของ BigC ที่มี beacon ติดตั้งอยู่ พร้อมตำแหน่งคร่าว ๆ สำหรับใช้
/// จัดลำดับว่าควรลงทะเบียน region ของสาขาไหนก่อน (ดู ARCHITECTURE.md ADR-8)
///
/// pure Dart — ไม่ผูกกับ CoreLocation หรือ Flutter ใด ๆ
class BigcBranch {
  /// รหัสสาขา — ใช้เป็น `identifier` ของ `CLBeaconRegion` ชั้นที่ 2 ตรง ๆ
  ///
  /// Apple ระบุว่า identifier string คือทางเดียวที่การันตีว่าระบุ region ได้
  /// ภายหลัง (ห้ามเทียบ pointer) การใส่รหัสสาขาไว้ตรงนี้จึงทำให้ `didEnterRegion`
  /// บอกได้ทันทีว่าเข้าสาขาไหนโดยไม่ต้องรอ ranging
  final String branchCode;

  /// ค่า major ตาม BigC ID Scheme (ADR-5) — เลขรันล้วน ความหมายอยู่ใน DB
  final int major;

  /// ตำแหน่งคร่าว ๆ ของสาขา ใช้จัดลำดับความใกล้เท่านั้น ไม่ต้องแม่นระดับเมตร
  final double latitude;
  final double longitude;

  const BigcBranch({
    required this.branchCode,
    required this.major,
    required this.latitude,
    required this.longitude,
  });

  @override
  String toString() =>
      'BigcBranch(branchCode: $branchCode, major: $major, '
      'latitude: $latitude, longitude: $longitude)';
}

/// ตำแหน่งคร่าว ๆ ของผู้ใช้ ใช้เลือกว่าสาขาไหนใกล้ที่สุด
class ApproximateLocation {
  final double latitude;
  final double longitude;

  const ApproximateLocation({required this.latitude, required this.longitude});

  @override
  String toString() =>
      'ApproximateLocation(latitude: $latitude, longitude: $longitude)';
}
