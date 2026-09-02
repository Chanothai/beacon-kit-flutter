import 'visit_event.dart';

/// การมาเยือนที่เปิดค้างอยู่ของ region หนึ่ง
final class OpenVisit {
  const OpenVisit({required this.startedAt, required this.evidence});

  final DateTime startedAt;
  final VisitStartEvidence evidence;

  @override
  bool operator ==(Object other) =>
      other is OpenVisit &&
      other.startedAt == startedAt &&
      other.evidence == evidence;

  @override
  int get hashCode => Object.hash(startedAt, evidence);

  @override
  String toString() => 'OpenVisit($startedAt, ${evidence.name})';
}

/// state ของ **region เดียว**
///
/// ⚠️ ห้ามยุบรวมหลาย region เข้าตัวแปรชุดเดียว — ตอนนี้มี region เดียวจึงยังไม่
/// เห็นปัญหา แต่ทันทีที่มี region ที่สอง เหตุการณ์ "ออกจากสาขา A แล้วเข้าสาขา B"
/// จะถูกกลืนหายทั้งคู่ เพราะ B จะไปทับ absence ของ A
final class RegionState {
  const RegionState({
    required this.present,
    this.lastPresentAt,
    this.absentSince,
    this.silencePaused = Duration.zero,
    this.visit,
  });

  /// ความเชื่อล่าสุดว่าอยู่ในโซนหรือไม่ (จาก observation ล่าสุดที่บอกได้)
  final bool present;

  /// หลักฐานล่าสุดที่ยืนยันว่า **อยู่** — `null` ถ้ายังไม่เคยเห็นเลย
  final DateTime? lastPresentAt;

  /// ความเงียบเริ่มเมื่อไร — `null` เมื่อ [present] เป็น `true`
  ///
  /// เก็บ **เวลาที่ประกาศว่าไม่เห็นครั้งแรกของช่วงนั้น** ไม่ใช่ครั้งล่าสุด —
  /// `exit` ซ้ำติดกันจึงไม่รีเซ็ต cooldown ให้ยาวออกไปเรื่อย ๆ
  final DateTime? absentSince;

  /// เวลาที่ **ถูกหักออก** จากความเงียบช่วงปัจจุบันเพราะเราตาบอด
  ///
  /// นาฬิกา cooldown หยุดเดินระหว่างตาบอด ค่านี้คือผลรวมที่หยุดไป ·
  /// **รีเซ็ตเป็นศูนย์ทุกครั้งที่ความเงียบช่วงใหม่เริ่ม** (เห็น beacon อีกครั้ง
  /// หรือเปลี่ยนจากอยู่เป็นไม่อยู่)
  ///
  /// เก็บแยกจาก [absentSince] โดยตั้งใจ — [absentSince] และ [lastPresentAt] เป็น
  /// **ข้อเท็จจริงที่วัดได้** และถูกรายงานใน `VisitEnded.endedAt` การเลื่อนค่าพวกนั้น
  /// ให้ตรงกับนาฬิกาที่หยุดจะทำให้ไฟล์หลักฐานโกหก
  final Duration silencePaused;

  final OpenVisit? visit;

  /// state ตั้งต้นของ region ที่ **ยังไม่รู้อะไรเลย**
  static const RegionState unknown = RegionState(present: false);

  /// state ของ region ที่ **รู้ว่ากำลังอยู่ในโซน** ตั้งแต่ก่อน observation แรก
  ///
  /// ใช้ตอนกู้ state กลับมาหลัง process ตาย (Android) — [seenAt] คือหลักฐาน
  /// ล่าสุดที่บันทึกไว้ ไม่ใช่เวลาที่กู้กลับมา
  factory RegionState.insideSince(DateTime seenAt, {OpenVisit? visit}) =>
      RegionState(present: true, lastPresentAt: seenAt, visit: visit);

  RegionState copyWith({
    bool? present,
    DateTime? lastPresentAt,
    DateTime? absentSince,
    bool clearAbsentSince = false,
    Duration? silencePaused,
    OpenVisit? visit,
    bool clearVisit = false,
  }) =>
      RegionState(
        present: present ?? this.present,
        lastPresentAt: lastPresentAt ?? this.lastPresentAt,
        absentSince: clearAbsentSince ? null : (absentSince ?? this.absentSince),
        silencePaused: silencePaused ?? this.silencePaused,
        visit: clearVisit ? null : (visit ?? this.visit),
      );

  @override
  bool operator ==(Object other) =>
      other is RegionState &&
      other.present == present &&
      other.lastPresentAt == lastPresentAt &&
      other.absentSince == absentSince &&
      other.silencePaused == silencePaused &&
      other.visit == visit;

  @override
  int get hashCode =>
      Object.hash(present, lastPresentAt, absentSince, silencePaused, visit);

  @override
  String toString() => 'RegionState(present: $present, '
      'lastPresentAt: $lastPresentAt, absentSince: $absentSince, '
      'silencePaused: $silencePaused, visit: $visit)';
}

/// ความสามารถในการมองเห็นของเราตอนนี้ — **สถานะรวม ไม่แยกต่อ region**
enum SensingStatus {
  /// มองเห็นได้ตามปกติ — นาฬิกา cooldown เดิน
  available,

  /// มองไม่เห็น และยังไม่เกินเพดาน — **นาฬิกา cooldown หยุด**
  lost,

  /// มองไม่เห็นนานเกินเพดานแล้ว และ **ล้างสถานะทิ้งไปแล้วหนึ่งครั้ง**
  ///
  /// แยกจาก [lost] เพื่อไม่ให้การล้างเกิดซ้ำทุก observation ที่ตามมาระหว่าง
  /// ที่ยังตาบอดอยู่
  lostBeyondCeiling,
}

/// state ทั้งหมดของชั้นกรอง — **ข้อมูลล้วน ไม่มีพฤติกรรม**
///
/// ตั้งใจให้ serialize ลง `SharedPreferences` / `UserDefaults` ได้ตรง ๆ เพราะฝั่ง
/// Android ไม่มี process ที่มีชีวิตพอจะถือ state ไว้ในหน่วยความจำข้าม event
final class VisitFilterState {
  const VisitFilterState({
    required this.regions,
    required this.lastObservationAt,
    this.sensing = SensingStatus.available,
    this.sensingLostAt,
  });

  /// state แยกต่อ region — key คือ region identifier
  final Map<String, RegionState> regions;

  /// เวลาของ observation ล่าสุดที่ **รับไว้** — ใช้ปฏิเสธเวลาที่เดินถอยหลัง
  final DateTime? lastObservationAt;

  /// มองเห็นอยู่หรือไม่ — **สถานะรวมของทั้งชั้นกรอง**
  final SensingStatus sensing;

  /// ช่วงตาบอดปัจจุบันเริ่มเมื่อไร — `null` เมื่อ [sensing] เป็น
  /// [SensingStatus.available]
  final DateTime? sensingLostAt;

  bool get isBlind => sensing != SensingStatus.available;

  static const VisitFilterState initial =
      VisitFilterState(regions: {}, lastObservationAt: null);

  RegionState regionState(String regionId) =>
      regions[regionId] ?? RegionState.unknown;

  /// region ที่มีการมาเยือนเปิดค้างอยู่ตอนนี้ (เรียงตาม identifier)
  List<String> get regionsWithOpenVisit => (regions.entries
          .where((e) => e.value.visit != null)
          .map((e) => e.key)
          .toList())
      ..sort();

  @override
  String toString() => 'VisitFilterState(lastObservationAt: $lastObservationAt, '
      'sensing: ${sensing.name}, sensingLostAt: $sensingLostAt, '
      'regions: $regions)';
}
