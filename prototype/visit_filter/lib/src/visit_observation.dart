/// สิ่งที่ป้อนเข้า reducer
///
/// ⚠️ **ทุกชนิดพก `at` มาเอง** — reducer ห้ามอ่านนาฬิกาเด็ดขาด เพราะฝั่ง Android
/// โค้ดนี้จะถูกรันในกระบวนการที่ระบบปลุกขึ้นมาเพื่อ `onReceive` แล้วตายภายใน
/// หลักสิบมิลลิวินาที ไม่มี process ที่มีชีวิตให้ตั้ง `Timer` และไม่มีอะไร
/// รับประกันว่านาฬิกาที่อ่านตอนนั้นเป็นนาฬิกาเดียวกับที่ event ถูกประทับเวลา
sealed class VisitObservation {
  const VisitObservation({required this.at});

  /// เวลาที่ผู้เรียกยืนยันว่าเป็น "ตอนนี้" ของ observation นี้
  final DateTime at;
}

/// แพลตฟอร์มยืนยันว่า **ยังอยู่ในโซน** ณ เวลา [at]
///
/// iOS = `didEnterRegion` · Android = ผลสแกนที่เข้ามาทาง `PendingIntent`
final class RegionSeen extends VisitObservation {
  const RegionSeen({required this.regionId, required super.at});

  final String regionId;

  @override
  String toString() => 'RegionSeen($regionId, $at)';
}

/// แพลตฟอร์มยืนยันว่า **ไม่อยู่ในโซนแล้ว** ณ เวลา [at]
///
/// iOS = `didExitRegion` · Android = นาฬิกาปลุก exit ของเราเองที่ดังแล้ว
///
/// ⚠️ **นี่ไม่ใช่หลักฐานว่าผู้ใช้เดินออกไปจริงตอน [at]** — ทั้งสองแพลตฟอร์มหน่วง
/// ก่อนประกาศ (iOS ~30 วินาทีที่วัดได้เอง ADR-11 · Android ขึ้นกับ `AlarmManager`
/// ADR-15) reducer จึงเริ่มนับความเงียบจากเวลานี้ ไม่ใช่จากเวลาที่เห็นครั้งสุดท้าย
final class RegionNotSeen extends VisitObservation {
  const RegionNotSeen({required this.regionId, required super.at});

  final String regionId;

  @override
  String toString() => 'RegionNotSeen($regionId, $at)';
}

/// สาเหตุที่มองไม่เห็น — **เก็บไว้เป็นสัญญาณดิบ ไม่มีผลกับการตัดสินใจของ reducer**
///
/// แยกไว้เพื่อให้ไฟล์หลักฐานตอบได้ว่าช่วงตาบอดแต่ละช่วงมาจากอะไร ซึ่งเป็นคนละ
/// คำถามกับ "ควรนับเวลานั้นเข้า cooldown ไหม" (คำตอบคือไม่นับ ทุกสาเหตุเหมือนกัน)
enum SensingLossCause {
  bluetoothOff,
  locationServicesOff,
  permissionRevoked,

  /// การลงทะเบียนสแกนหายไปโดยที่เราไม่ได้สั่ง (เช่น Bluetooth stack รีสตาร์ต)
  scanRegistrationLost,

  /// รู้ว่ามองไม่เห็น แต่ระบุสาเหตุไม่ได้
  unknown,
}

/// **เราไม่มีความสามารถจะรู้ว่าอยู่ในโซนหรือไม่** ตั้งแต่ [at] เป็นต้นไป
///
/// ⚠️ **นี่คือคนละเรื่องกับ [RegionNotSeen] โดยสิ้นเชิง** และเป็นความต่างที่ทำให้
/// ลูกค้าได้แจ้งเตือนโปรโมชันซ้ำโดยไม่ได้ไปไหน:
///
/// | | [RegionNotSeen] | [SensingLost] |
/// |---|---|---|
/// | แปลว่า | **แพลตฟอร์มยืนยันว่าไม่อยู่แล้ว** | **เราตาบอด ตอบไม่ได้ว่าอยู่หรือไม่** |
/// | เป็นหลักฐานของ | การไม่อยู่ | ความสามารถของเรา ไม่ใช่ตำแหน่งของผู้ใช้ |
/// | นาฬิกา cooldown | **เดินต่อ** | **หยุด** |
/// | ถ้าใช้ผิดตัว | — | ปิด Bluetooth 10 นาทีขณะนั่งอยู่ที่เดิม = `VisitStarted` 2 ครั้ง |
///
/// **มีผลกับทุก region พร้อมกัน** ไม่ผูกกับ region ใด region หนึ่ง — Bluetooth ที่
/// ปิดอยู่ทำให้มองไม่เห็นทุกสาขาเท่ากันหมด
///
/// ส่ง [SensingLost] ซ้ำระหว่างที่ตาบอดอยู่แล้วไม่เลื่อนจุดเริ่ม — จุดเริ่มของช่วง
/// ตาบอดคืออันแรกเสมอ
final class SensingLost extends VisitObservation {
  const SensingLost({required super.at, required this.cause});

  final SensingLossCause cause;

  @override
  String toString() => 'SensingLost(${cause.name}, $at)';
}

/// **กลับมามองเห็นได้แล้ว** ตั้งแต่ [at] เป็นต้นไป
///
/// ช่วงเวลาระหว่าง [SensingLost] ถึงตัวนี้ **ถูกหักออกจากความเงียบ** ของทุก region
/// ที่กำลังนับ cooldown อยู่ — เท่ากับ "หยุดนาฬิกาแล้วเดินต่อ" ไม่ใช่ "รีเซ็ตนาฬิกา"
///
/// ⚠️ ถ้าช่วงตาบอดยาวเกิน `VisitFilter.blindnessCeiling` จะ **ไม่หัก** แต่ล้าง
/// สถานะทิ้งทั้งหมดแทน — เพราะตาบอดนานขนาดนั้นแล้วอ้างความต่อเนื่องไม่ได้อีก
final class SensingRestored extends VisitObservation {
  const SensingRestored({required super.at});

  @override
  String toString() => 'SensingRestored($at)';
}

/// "เวลาเดินไปถึง [at] แล้ว แต่ไม่มีข้อมูลใหม่ว่าอยู่หรือไม่อยู่"
///
/// จำเป็นเพราะ reducer ไม่มีนาฬิกาของตัวเอง — ถ้าไม่มีใครป้อนเวลาเข้ามา
/// การมาเยือนที่ค้างอยู่จะไม่มีวันถูกปิด · ผู้เรียกควรป้อนทุกครั้งที่ถูกปลุก
/// ไม่ว่าจะด้วยสาเหตุใด (process เกิดใหม่ · แอปกลับมา foreground · นาฬิกาปลุกอื่น)
final class TimeAdvanced extends VisitObservation {
  const TimeAdvanced({required super.at});

  @override
  String toString() => 'TimeAdvanced($at)';
}

/// ไม่มี observation หลังจากนี้อีกแล้ว — **ปิดการมาเยือนที่ยังค้างที่ขอบข้อมูล**
///
/// ใช้กับการวิเคราะห์ไฟล์ log ย้อนหลัง (ไฟล์จบขณะยังอยู่ในโซน) และกับการ
/// ปิดบัญชีตอนผู้ใช้สั่งหยุดเฝ้า region
///
/// ⚠️ ห้ามทิ้งช่วงที่ยังเปิดค้าง — `docs/test-data/GROUND_TRUTH.md` ระบุว่าถ้าทิ้ง
/// จะได้ 0 ช่วงจากทั้งสองไฟล์ ซึ่งผิดจากความจริงภาคสนาม
final class ObservationsEnded extends VisitObservation {
  const ObservationsEnded({required super.at});

  @override
  String toString() => 'ObservationsEnded($at)';
}
