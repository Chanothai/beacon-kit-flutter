import '../entities/bigc_beacon_identity.dart';
import 'bigc_beacon_metadata_repository.dart';
import 'resolve_bigc_beacon_metadata_result.dart';

/// Usecase หลักที่แปลง identity triple (UUID, Major, Minor) ของ iBeacon เป็น
/// ข้อมูลธุรกิจของ BigC (ยี่ห้อ/ล็อต/กลุ่ม/ตำแหน่ง ตาม ADR-5) — pure Dart
/// ทดสอบได้โดยไม่ต้องมีอุปกรณ์จริง (query จริงผ่าน [repository] ที่ inject เข้ามา)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-5 "BigC ID Scheme สำหรับ multi-vendor
/// provisioning", ADR-7 "ตำแหน่งของ domain entity/usecase สำหรับ BigC ID mapping"
class ResolveBigcBeaconMetadata {
  /// proximity UUID ของ BigC ที่ต้อง inject เข้ามาจากภายนอก (config/backend) —
  /// **ห้าม hardcode ค่า UUID จริงของ BigC ไว้ในไฟล์นี้หรือที่ไหนในแพ็กเกจนี้
  /// เด็ดขาด** ตาม ARCHITECTURE.md ADR-5 (ดู docs/sources/bigc_provisioning.md
  /// สำหรับค่าจริงที่เก็บไว้ที่เดียว — ห้าม copy ค่านั้นมาไว้ในซอร์สโค้ดนี้)
  final String bigcProximityUuid;
  final BigcBeaconMetadataRepository repository;

  const ResolveBigcBeaconMetadata({
    required this.bigcProximityUuid,
    required this.repository,
  });

  static const int _uint16Max = 65535;

  /// ลำดับการตรวจ: uuid mismatch -> major range -> minor range -> repository
  /// lookup (ตรวจ argument ที่ผิดก่อนเสมอ ไม่ต้อง query repository ถ้า input
  /// ผิดรูปแบบอยู่แล้ว)
  Future<ResolveBigcBeaconMetadataResult> call(
    BigcBeaconIdentity identity,
  ) async {
    if (identity.uuid.toLowerCase() != bigcProximityUuid.toLowerCase()) {
      return const ResolveBigcBeaconMetadataFailure(
        ResolveBigcBeaconMetadataFailureReason.uuidMismatch,
      );
    }
    if (identity.major < 0 || identity.major > _uint16Max) {
      return const ResolveBigcBeaconMetadataFailure(
        ResolveBigcBeaconMetadataFailureReason.majorOutOfRange,
      );
    }
    if (identity.minor < 0 || identity.minor > _uint16Max) {
      return const ResolveBigcBeaconMetadataFailure(
        ResolveBigcBeaconMetadataFailureReason.minorOutOfRange,
      );
    }
    final metadata = await repository.resolve(identity);
    if (metadata == null) {
      return const ResolveBigcBeaconMetadataFailure(
        ResolveBigcBeaconMetadataFailureReason.notFound,
      );
    }
    return ResolveBigcBeaconMetadataSuccess(metadata);
  }
}
