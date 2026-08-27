/// คำขอ monitor+range iBeacon region หนึ่ง region — ส่งเป็น `List<IBeaconRegionRequest>`
/// ไปยัง `BeaconKitIos.startIBeaconMonitoring` เพื่อ**แทนที่**ชุด region ที่กำลัง
/// monitor อยู่เดิมทั้งหมด (ไม่ merge เข้ากับของเดิม)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-4 "iOS platform channel contract"
class IBeaconRegionRequest {
  /// ตัวระบุ region ฝั่งแอป — ใช้อ้างอิงตอนเรียก `stopIBeaconMonitoring` แบบเจาะจง
  /// บาง region เท่านั้น (ไม่ใช่ identity ของ beacon ทางกายภาพ)
  final String identifier;

  /// iBeacon proximity UUID — ฝั่ง native ต้อง parse เป็น `NSUUID` ได้ ไม่เช่นนั้นจะได้
  /// `PlatformException(code: 'INVALID_REGION_UUID')` กลับมา
  final String uuid;

  /// เจาะจง major เพิ่มเติมจาก uuid (optional — ไม่ระบุ = ครอบคลุมทุก major ภายใต้ uuid นี้)
  final int? major;

  /// เจาะจง minor เพิ่มเติมจาก major (optional — ต้องระบุ major ก่อนถึงจะระบุ minor ได้
  /// ตามข้อจำกัดของ `CLBeaconIdentityConstraint`)
  final int? minor;

  const IBeaconRegionRequest({
    required this.identifier,
    required this.uuid,
    this.major,
    this.minor,
  });

  /// แปลงเป็น map ตาม shape ที่ method channel `beacon_kit_ios/methods` คาดหวัง
  /// (ดู ARCHITECTURE.md, ADR-4)
  Map<String, dynamic> toMap() => <String, dynamic>{
    'identifier': identifier,
    'uuid': uuid,
    'major': major,
    'minor': minor,
  };

  @override
  String toString() =>
      'IBeaconRegionRequest(identifier: $identifier, uuid: $uuid, '
      'major: $major, minor: $minor)';
}
