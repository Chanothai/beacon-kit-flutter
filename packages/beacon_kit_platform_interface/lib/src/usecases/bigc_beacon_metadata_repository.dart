import '../entities/bigc_beacon_identity.dart';
import '../entities/bigc_beacon_metadata.dart';

/// สัญญาการค้นหาข้อมูลธุรกิจของ BigC จาก identity triple — implementation จริง
/// (เรียก backend/database ตาม ADR-5) อยู่นอกแพ็กเกจนี้และนอกสโคปสปรินต์นี้
///
/// อ้างอิง: ARCHITECTURE.md, ADR-5 "BigC ID Scheme สำหรับ multi-vendor
/// provisioning", ADR-7 "ตำแหน่งของ domain entity/usecase สำหรับ BigC ID mapping"
abstract class BigcBeaconMetadataRepository {
  /// คืน null ถ้าไม่พบ [identity] นี้ใน mapping (เช่น major/minor ที่ไม่เคย
  /// provision)
  Future<BigcBeaconMetadata?> resolve(BigcBeaconIdentity identity);
}
