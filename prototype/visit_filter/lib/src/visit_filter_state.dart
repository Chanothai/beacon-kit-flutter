import 'epoch_millis.dart';
import 'visit_event.dart';

/// การมาเยือนที่เปิดค้างอยู่ของ region หนึ่ง
final class OpenVisit {
  const OpenVisit({required this.startedAtMs, required this.evidence});

  final EpochMillis startedAtMs;
  final VisitStartEvidence evidence;

  @override
  bool operator ==(Object other) =>
      other is OpenVisit &&
      other.startedAtMs == startedAtMs &&
      other.evidence == evidence;

  @override
  int get hashCode => Object.hash(startedAtMs, evidence);

  @override
  String toString() => 'OpenVisit(${debugTime(startedAtMs)}, ${evidence.name})';
}

/// state ของ **region เดียว**
///
/// ⚠️ ห้ามยุบรวมหลาย region เข้าตัวแปรชุดเดียว — ตอนนี้มี region เดียวจึงยังไม่
/// เห็นปัญหา แต่ทันทีที่มี region ที่สอง เหตุการณ์ "ออกจากสาขา A แล้วเข้าสาขา B"
/// จะถูกกลืนหายทั้งคู่ เพราะ B จะไปทับ absence ของ A
final class RegionState {
  const RegionState({
    required this.present,
    this.lastPresentAtMs,
    this.absentSinceMs,
    this.silencePausedMs = 0,
    this.visit,
  });

  /// ความเชื่อล่าสุดว่าอยู่ในโซนหรือไม่ (จาก observation ล่าสุดที่บอกได้)
  final bool present;

  /// หลักฐานล่าสุดที่ยืนยันว่า **อยู่** — `null` ถ้ายังไม่เคยเห็นเลย
  final EpochMillis? lastPresentAtMs;

  /// ความเงียบเริ่มเมื่อไร — `null` เมื่อ [present] เป็น `true`
  ///
  /// เก็บ **เวลาที่ประกาศว่าไม่เห็นครั้งแรกของช่วงนั้น** ไม่ใช่ครั้งล่าสุด —
  /// `exit` ซ้ำติดกันจึงไม่รีเซ็ต cooldown ให้ยาวออกไปเรื่อย ๆ
  final EpochMillis? absentSinceMs;

  /// เวลาที่ **ถูกหักออก** จากความเงียบช่วงปัจจุบันเพราะเราตาบอด
  ///
  /// นาฬิกา cooldown หยุดเดินระหว่างตาบอด ค่านี้คือผลรวมที่หยุดไป ·
  /// **รีเซ็ตเป็นศูนย์ทุกครั้งที่ความเงียบช่วงใหม่เริ่ม** (เห็น beacon อีกครั้ง
  /// หรือเปลี่ยนจากอยู่เป็นไม่อยู่)
  ///
  /// เก็บแยกจาก [absentSinceMs] โดยตั้งใจ — [absentSinceMs] และ [lastPresentAtMs] เป็น
  /// **ข้อเท็จจริงที่วัดได้** และถูกรายงานใน `VisitEnded.endedAtMs` การเลื่อนค่าพวกนั้น
  /// ให้ตรงกับนาฬิกาที่หยุดจะทำให้ไฟล์หลักฐานโกหก
  final EpochMillis silencePausedMs;

  final OpenVisit? visit;

  /// state ตั้งต้นของ region ที่ **ยังไม่รู้อะไรเลย**
  static const RegionState unknown = RegionState(present: false);

  /// state ของ region ที่ **รู้ว่ากำลังอยู่ในโซน** ตั้งแต่ก่อน observation แรก
  ///
  /// ใช้ตอนกู้ state กลับมาหลัง process ตาย (Android) — [seenAtMs] คือหลักฐาน
  /// ล่าสุดที่บันทึกไว้ ไม่ใช่เวลาที่กู้กลับมา
  factory RegionState.insideSince(EpochMillis seenAtMs, {OpenVisit? visit}) =>
      RegionState(present: true, lastPresentAtMs: seenAtMs, visit: visit);

  RegionState copyWith({
    bool? present,
    EpochMillis? lastPresentAtMs,
    EpochMillis? absentSinceMs,
    bool clearAbsentSince = false,
    EpochMillis? silencePausedMs,
    OpenVisit? visit,
    bool clearVisit = false,
  }) =>
      RegionState(
        present: present ?? this.present,
        lastPresentAtMs: lastPresentAtMs ?? this.lastPresentAtMs,
        absentSinceMs:
            clearAbsentSince ? null : (absentSinceMs ?? this.absentSinceMs),
        silencePausedMs: silencePausedMs ?? this.silencePausedMs,
        visit: clearVisit ? null : (visit ?? this.visit),
      );

  @override
  bool operator ==(Object other) =>
      other is RegionState &&
      other.present == present &&
      other.lastPresentAtMs == lastPresentAtMs &&
      other.absentSinceMs == absentSinceMs &&
      other.silencePausedMs == silencePausedMs &&
      other.visit == visit;

  @override
  int get hashCode => Object.hash(
      present, lastPresentAtMs, absentSinceMs, silencePausedMs, visit);

  @override
  String toString() => 'RegionState(present: $present, '
      'lastPresentAtMs: $lastPresentAtMs, absentSinceMs: $absentSinceMs, '
      'silencePausedMs: $silencePausedMs, visit: $visit)';
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
    required this.lastObservationAtMs,
    this.sensing = SensingStatus.available,
    this.sensingLostAtMs,
  });

  /// state แยกต่อ region — key คือ region identifier
  final Map<String, RegionState> regions;

  /// เวลาของ observation ล่าสุดที่ **รับไว้** — ใช้ปฏิเสธเวลาที่เดินถอยหลัง
  final EpochMillis? lastObservationAtMs;

  /// มองเห็นอยู่หรือไม่ — **สถานะรวมของทั้งชั้นกรอง**
  final SensingStatus sensing;

  /// ช่วงตาบอดปัจจุบันเริ่มเมื่อไร — `null` เมื่อ [sensing] เป็น
  /// [SensingStatus.available]
  final EpochMillis? sensingLostAtMs;

  bool get isBlind => sensing != SensingStatus.available;

  static const VisitFilterState initial =
      VisitFilterState(regions: {}, lastObservationAtMs: null);

  RegionState regionState(String regionId) =>
      regions[regionId] ?? RegionState.unknown;

  /// region ที่มีการมาเยือนเปิดค้างอยู่ตอนนี้ (เรียงตาม identifier)
  List<String> get regionsWithOpenVisit => (regions.entries
          .where((e) => e.value.visit != null)
          .map((e) => e.key)
          .toList())
      ..sort();

  @override
  String toString() =>
      'VisitFilterState(lastObservationAtMs: $lastObservationAtMs, '
      'sensing: ${sensing.name}, sensingLostAtMs: $sensingLostAtMs, '
      'regions: $regions)';
}
