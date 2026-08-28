import '../entities/bigc_beacon_metadata.dart';

/// ผลลัพธ์ของการ resolve identity triple เป็นข้อมูลธุรกิจของ BigC — ตาม pattern
/// ของ `ParseResult` (ADR-3) เพื่อบังคับให้ผู้เรียกต้อง handle กรณีล้มเหลวอย่าง
/// ชัดเจนผ่าน pattern matching (Dart 3 sealed class) แทนการ throw exception
///
/// อ้างอิง: ARCHITECTURE.md, ADR-7 "ตำแหน่งของ domain entity/usecase สำหรับ
/// BigC ID mapping"
sealed class ResolveBigcBeaconMetadataResult {
  const ResolveBigcBeaconMetadataResult();
}

/// Resolve สำเร็จ — ได้ [metadata] เป็นข้อมูลธุรกิจของ BigC
final class ResolveBigcBeaconMetadataSuccess
    extends ResolveBigcBeaconMetadataResult {
  final BigcBeaconMetadata metadata;

  const ResolveBigcBeaconMetadataSuccess(this.metadata);

  @override
  String toString() => 'ResolveBigcBeaconMetadataSuccess(metadata: $metadata)';
}

/// Resolve ล้มเหลว — [reason] บอกสาเหตุ, [detail] เป็นข้อความเสริมสำหรับ debug
final class ResolveBigcBeaconMetadataFailure
    extends ResolveBigcBeaconMetadataResult {
  final ResolveBigcBeaconMetadataFailureReason reason;
  final String? detail;

  const ResolveBigcBeaconMetadataFailure(this.reason, {this.detail});

  @override
  String toString() =>
      'ResolveBigcBeaconMetadataFailure(reason: $reason, detail: $detail)';
}

/// สาเหตุที่ resolve ล้มเหลว
enum ResolveBigcBeaconMetadataFailureReason {
  /// uuid ของ identity ไม่ตรงกับ proximity UUID ของ BigC ที่ configure ไว้
  uuidMismatch,

  /// major อยู่นอกช่วง uint16 (0-65535)
  majorOutOfRange,

  /// minor อยู่นอกช่วง uint16 (0-65535)
  minorOutOfRange,

  /// uuid ตรง, major/minor อยู่ในช่วงที่ถูกต้อง แต่ repository ไม่พบ mapping
  /// (ยังไม่เคย provision triple นี้)
  notFound,
}
