/// ผลลัพธ์ของการ parse ADV packet — ใช้แทนการ throw exception ทั่วไป
/// เพื่อบังคับให้ผู้เรียกต้อง handle กรณี parse ล้มเหลวอย่างชัดเจนผ่าน
/// pattern matching (Dart 3 sealed class)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-3 "Parser contract — EddystoneParser / IBeaconParser"
sealed class ParseResult<T> {
  const ParseResult();
}

/// Parse สำเร็จ — ได้ [value] เป็นผลลัพธ์
final class ParseSuccess<T> extends ParseResult<T> {
  final T value;

  const ParseSuccess(this.value);

  @override
  String toString() => 'ParseSuccess<$T>(value: $value)';
}

/// Parse ล้มเหลว — [reason] บอกสาเหตุ, [detail] เป็นข้อความเสริมสำหรับ debug
/// (เช่น "expected total length 20 bytes, got 14")
final class ParseFailure<T> extends ParseResult<T> {
  final ParseFailureReason reason;
  final String? detail;

  const ParseFailure(this.reason, {this.detail});

  @override
  String toString() => 'ParseFailure<$T>(reason: $reason, detail: $detail)';
}

/// สาเหตุที่ parse ล้มเหลว
enum ParseFailureReason {
  /// ความยาวรวมน้อยกว่าค่าต่ำสุดของ frame type นั้น
  tooShort,

  /// ความยาวรวมเกินขนาดสูงสุดที่ ADV payload รองรับ (31 bytes)
  tooLong,

  /// byte แรก ๆ ไม่ตรง prefix ที่ frame type นั้นกำหนด
  /// (เช่น iBeacon ต้องเป็น 0x02 0x15)
  invalidPrefix,

  /// byte ที่ควรเป็น frame type ไม่ตรงกับค่าใด ๆ ที่ spec นิยามไว้เลย
  invalidFrameType,

  /// byte พอสำหรับ frame type แต่ field ใด field หนึ่งถูกตัดสั้นกลางคัน
  truncatedField,

  /// frame type ที่ spec นิยามไว้จริง แต่ parser เวอร์ชันนี้ยังไม่ implement
  /// decode logic (เช่น Eddystone-EID 0x30)
  unsupportedFrameType,
}
