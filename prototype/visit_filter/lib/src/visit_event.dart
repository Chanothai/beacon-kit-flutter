/// หลักฐานที่ทำให้ [VisitStarted] ถูกยิง — **แยก "เห็นการมาถึง" ออกจาก "พบว่าอยู่แล้ว"**
enum VisitStartEvidence {
  /// เห็นการเปลี่ยนจาก "ไม่อยู่" เป็น "อยู่" จริง — `at` คือเวลาที่มาถึง
  arrivalObserved,

  /// observation แรกของ region นี้บอกว่า "อยู่" อยู่แล้ว
  ///
  /// เกิดได้สองทาง: ข้อมูลเริ่มตอนอยู่ในโซนอยู่แล้ว (ไฟล์ log ที่เริ่มกลางคัน)
  /// หรือกู้ state ที่บันทึกไว้ว่ากำลังอยู่ในโซนกลับมา
  ///
  /// ⚠️ `at` ของ event นี้คือ **ขอบบนของเวลาที่มาถึง ไม่ใช่เวลาที่มาถึง** — การมาถึง
  /// จริงเกิดขึ้น ณ เวลานั้นหรือก่อนหน้า และ reducer ไม่มีทางรู้ว่าก่อนหน้าเท่าไร
  alreadyInsideAtFirstObservation,
}

/// สาเหตุที่การมาเยือนถูกปิด
enum VisitEndReason {
  /// เงียบครบ cooldown แล้วยังไม่กลับมา — **ปิดสมบูรณ์**
  cooldownElapsed,

  /// ข้อมูลหมดขณะการมาเยือนยังเปิดค้าง — **ยังไม่รู้ว่าจบจริงเมื่อไร**
  ///
  /// ห้ามรายงานเป็นการมาเยือนที่จบแล้ว และห้ามทิ้ง — ดู `GROUND_TRUTH.md`
  observationsEnded,

  /// ตาบอดนานเกิน `VisitFilter.blindnessCeiling` — **ไม่รู้อะไรเลยระหว่างนั้น**
  ///
  /// ต่างจาก [cooldownElapsed] ตรงที่**ไม่ได้แปลว่าผู้ใช้ออกไป** แปลว่าเราขาด
  /// ข้อมูลนานเกินกว่าจะอ้างความต่อเนื่องได้ · `endedAt` คือหลักฐานสุดท้ายที่เห็น
  /// ซึ่งอาจเก่ากว่าเวลาที่ผู้ใช้ออกไปจริงมาก — **ห้ามใช้คำนวณระยะเวลาที่อยู่ในสาขา**
  sensingLostBeyondCeiling,
}

/// event ที่ reducer ยิงออกมา
sealed class VisitEvent {
  const VisitEvent({required this.regionId});

  final String regionId;
}

/// เริ่มการมาเยือนใหม่
final class VisitStarted extends VisitEvent {
  const VisitStarted({
    required super.regionId,
    required this.at,
    required this.evidence,
  });

  final DateTime at;
  final VisitStartEvidence evidence;

  @override
  bool operator ==(Object other) =>
      other is VisitStarted &&
      other.regionId == regionId &&
      other.at == at &&
      other.evidence == evidence;

  @override
  int get hashCode => Object.hash(regionId, at, evidence);

  @override
  String toString() => 'VisitStarted($regionId, $at, ${evidence.name})';
}

/// จบการมาเยือน
final class VisitEnded extends VisitEvent {
  const VisitEnded({
    required super.regionId,
    required this.startedAt,
    required this.endedAt,
    required this.reason,
  });

  final DateTime startedAt;

  /// หลักฐานสุดท้ายที่ยืนยันว่ายังอยู่ — **ไม่ใช่เวลาที่ reducer รู้ตัวว่าจบ**
  ///
  /// การรายงานเวลาที่รู้ตัวจะทำให้ทุกการมาเยือนยาวเกินจริงเท่ากับ cooldown
  final DateTime endedAt;

  final VisitEndReason reason;

  Duration get duration => endedAt.difference(startedAt);

  @override
  bool operator ==(Object other) =>
      other is VisitEnded &&
      other.regionId == regionId &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(regionId, startedAt, endedAt, reason);

  @override
  String toString() =>
      'VisitEnded($regionId, $startedAt → $endedAt, ${reason.name})';
}
