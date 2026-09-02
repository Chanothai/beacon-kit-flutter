import 'package:test/test.dart';
import 'package:visit_filter_prototype/region_log.dart';
import 'package:visit_filter_prototype/visit_filter.dart';

/// เกณฑ์รับจาก `docs/test-data/GROUND_TRUTH.md`
///
/// ทั้งสองคืนเก็บภายใต้เงื่อนไขที่รู้คำตอบล่วงหน้าแน่นอน — **มือถือวางนิ่ง จอดับ
/// K9P วางนิ่งข้าง ๆ ไม่มีใครแตะทั้งคืน** ความจริงภาคสนามคือ **enter 1 · exit 0**
/// ทุกบรรทัด `exit` ในสองไฟล์นี้จึงเป็น exit ปลอมทั้งหมด
///
/// ⚠️ **ต้องใช้พารามิเตอร์ชุดเดียวกันทั้งสองไฟล์** — ถ้าต้องปรับค่าต่อแพลตฟอร์ม
/// ถึงจะผ่าน นั่นคือการ fit กับข้อมูลสองชุด ไม่ใช่ตัวกรอง
/// `blindnessCeiling` **ไม่มีผลกับสองไฟล์นี้เลย** — ไม่มี observation ชนิด
/// `SensingLost` อยู่ในไฟล์หลักฐานทั้งสอง (บิลด์ที่เก็บ log ยังไม่มีการตรวจว่า
/// ตาบอด) ค่าที่ใส่จึงเป็นแค่ค่าที่ต้องใส่ให้ครบพารามิเตอร์
final VisitFilter filter = VisitFilter(
  cooldownMs: const Duration(minutes: 5).inMilliseconds,
  blindnessCeilingMs: const Duration(minutes: 15).inMilliseconds,
);

const String testDataDir = '../../docs/test-data';

final class Expectation {
  const Expectation({
    required this.file,
    required this.platform,
    required this.rawEnter,
    required this.rawExit,
    required this.visitStartsAt,
    required this.visitEndsAt,
    required this.startEvidence,
  });

  final String file;
  final String platform;
  final int rawEnter;
  final int rawExit;

  /// เวลาท้องถิ่นของเครื่องทดสอบ **พร้อม offset** ตรงตามที่เขียนในไฟล์
  final String visitStartsAt;
  final String visitEndsAt;

  /// หลักฐานที่ทำให้การมาเยือนถูกยิง — **ต่างกันจริงระหว่างสองไฟล์**
  final VisitStartEvidence startEvidence;
}

const List<Expectation> expectations = [
  Expectation(
    file: '2026-08-30_overnight_region_flapping.log',
    platform: 'iOS (CoreLocation)',
    rawEnter: 86,
    rawExit: 86,
    visitStartsAt: '2026-08-30T18:34:47.313+07:00',
    visitEndsAt: '2026-08-31T08:41:07.768+07:00',
    // บรรทัดแรกของไฟล์ที่เป็น event คือ `exit` → reducer เห็นการมาถึงจริง
    startEvidence: VisitStartEvidence.arrivalObserved,
  ),
  Expectation(
    file: '2026-09-01_android_overnight_region_flapping.log',
    platform: 'Android (startScan + PendingIntent + นาฬิกาปลุก)',
    rawEnter: 63,
    rawExit: 62,
    visitStartsAt: '2026-09-01T15:50:11.073+07:00',
    visitEndsAt: '2026-09-02T08:48:34.516+07:00',
    // ไฟล์นี้ไม่มี `exit` นำหน้า `enter` แรกเลย — reducer จึงตอบได้แค่ว่า
    // "พบว่าอยู่ในโซนตั้งแต่ observation แรก" ไม่ใช่ "เห็นการมาถึง"
    startEvidence: VisitStartEvidence.alreadyInsideAtFirstObservation,
  ),
];

({
  List<VisitEvent> events,
  List<ObservationRejection> rejections,
  VisitFilterState state,
}) runLog(String path) {
  final entries = parseRegionLog(path);
  var state = VisitFilterState.initial;
  final events = <VisitEvent>[];
  final rejections = <ObservationRejection>[];
  for (final observation in observationsFromLog(entries)) {
    final reduction = filter.reduce(state, observation);
    state = reduction.state;
    events.addAll(reduction.events);
    final rejection = reduction.rejection;
    if (rejection != null) rejections.add(rejection);
  }
  return (events: events, rejections: rejections, state: state);
}

void main() {
  for (final expected in expectations) {
    group('${expected.file} — ${expected.platform}', () {
      final path = '$testDataDir/${expected.file}';
      final entries = parseRegionLog(path);
      final offsetMs = entries.first.utcOffsetMs;
      final result = runLog(path);
      final starts = result.events.whereType<VisitStarted>().toList();
      final ends = result.events.whereType<VisitEnded>().toList();

      test('จำนวน event ดิบในไฟล์ตรงกับ GROUND_TRUTH.md', () {
        expect(entries.where((e) => e.event == 'enter'), hasLength(expected.rawEnter));
        expect(entries.where((e) => e.event == 'exit'), hasLength(expected.rawExit));
      });

      test('ทุก observation ถูกรับไว้ — ไม่มีอันไหนที่ reducer รับไม่ได้', () {
        expect(result.rejections, isEmpty);
      });

      test('VisitStarted 1 ครั้ง', () {
        expect(
          starts,
          hasLength(1),
          reason: 'enter ดิบ ${expected.rawEnter} ครั้ง · '
              'ความจริงภาคสนามคือมาเยือน 1 ครั้ง',
        );
      });

      test('หลักฐานการเริ่มการมาเยือนตรงกับสิ่งที่ไฟล์บอกได้จริง', () {
        expect(starts.single.evidence, expected.startEvidence);
      });

      test('การมาเยือนเริ่มที่เวลาท้องถิ่นตรงกับ GROUND_TRUTH.md', () {
        expect(
          formatWithOffset(starts.single.atMs, offsetMs),
          expected.visitStartsAt,
        );
      });

      test('ช่วงที่เปิดค้างถูกปิดที่ขอบข้อมูล ไม่ใช่ถูกทิ้ง', () {
        expect(ends, hasLength(1));
        expect(ends.single.reason, VisitEndReason.observationsEnded,
            reason: 'ไฟล์จบขณะยังอยู่ในโซน');
        expect(formatWithOffset(ends.single.endedAtMs, offsetMs), expected.visitEndsAt);
        expect(result.state.regionsWithOpenVisit, isEmpty);
      });

      test('เวลาในไฟล์เป็น local +07:00 ไม่ใช่ UTC', () {
        expect(offsetMs, const Duration(hours: 7).inMilliseconds);
        // ตัวกรองที่ตีความเป็น UTC จะรายงานเวลาเลื่อนไป 7 ชั่วโมง ซึ่งทำให้
        // ข้อสรุปเรื่อง "ช่วงกลางคืน" ผิดทั้งหมด — ล็อกส่วนต่างไว้ตรงนี้
        expect(
          formatWithOffset(starts.single.atMs, 0),
          isNot(expected.visitStartsAt),
        );
        expect(
          starts.single.atMs -
              DateTime.parse(expected.visitStartsAt).millisecondsSinceEpoch,
          0,
        );
      });
    });
  }

  test('ทั้งสองไฟล์ผ่านด้วย cooldown ค่าเดียวกัน', () {
    for (final expected in expectations) {
      final result = runLog('$testDataDir/${expected.file}');
      expect(
        result.events.whereType<VisitStarted>(),
        hasLength(1),
        reason: '${expected.file} ต้องผ่านด้วย cooldown '
            '${filter.cooldownMs} ms ตัวเดียวกับอีกไฟล์',
      );
    }
  });
}
