import 'visit_event.dart';
import 'visit_filter_state.dart';
import 'visit_observation.dart';

/// หนึ่งเคสของสัญญากลาง
///
/// **นิยามอยู่ที่นี่ที่เดียว** — ตัว generator ใช้สร้างไฟล์ vector ส่วนเทสต์ของ
/// Dart ใช้ยืนยันว่าไฟล์ที่ commit ไว้ยังตรงกับโค้ดปัจจุบัน · port ฝั่ง Kotlin
/// และ Swift อ่าน **ไฟล์ vector** ไม่ใช่ไฟล์นี้
final class ConformanceCase {
  const ConformanceCase({
    required this.name,
    required this.why,
    required this.cooldown,
    required this.blindnessCeiling,
    this.initialState = VisitFilterState.initial,
    this.observations,
    this.logFile,
  });

  final String name;

  /// เคสนี้กันอะไรไม่ให้พัง — เขียนไว้ให้คนรีวิว diff ของไฟล์ vector อ่านออก
  final String why;

  final Duration cooldown;
  final Duration blindnessCeiling;
  final VisitFilterState initialState;

  /// observation แบบเขียนตรง ๆ — `null` เมื่อใช้ [logFile]
  final List<VisitObservation>? observations;

  /// เส้นทางไฟล์หลักฐาน (สัมพัทธ์กับรากของ repo) ที่ทั้งสามภาษาต้องอ่านไฟล์เดียวกัน
  final String? logFile;
}

final DateTime _t0 = DateTime.utc(2026, 9, 2, 10);
DateTime _at(Duration offset) => _t0.add(offset);
const Duration _fiveMinutes = Duration(minutes: 5);

/// เพดานการตาบอดที่ใช้ในเคสส่วนใหญ่ — **เป็นค่าที่เลือกให้เทสต์อ่านง่าย
/// ไม่ใช่ค่าที่เสนอให้ใช้จริง** ยังไม่มีข้อมูลสนามสำหรับตั้งค่านี้เลย
const Duration _blindnessCeiling = Duration(minutes: 15);

/// เคสทั้งหมดของสัญญากลาง
final List<ConformanceCase> conformanceCases = [
  ConformanceCase(
    name: 'arrival-observed',
    why: 'เห็นการเปลี่ยนจากไม่อยู่เป็นอยู่ → evidence ต้องเป็น arrivalObserved',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionNotSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionSeen(regionId: 'a', at: _at(const Duration(seconds: 10))),
    ],
  ),
  ConformanceCase(
    name: 'already-inside-at-first-observation',
    why: 'observation แรกบอกว่าอยู่แล้ว → ตอบเวลาที่มาถึงไม่ได้ '
        '(เกิดจริงกับไฟล์ Android)',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [RegionSeen(regionId: 'a', at: _at(Duration.zero))],
  ),
  ConformanceCase(
    name: 'still-present-when-cooldown-elapses',
    why: 'กับดักหลัก — ครบ cooldown ตอนยังเห็นอยู่ ห้ามปิดและห้ามยิงอะไร '
        'ไฟล์ iOS มีช่วงอยู่ในโซนต่อเนื่อง 3 ชม 10 น โดยไม่มี event เลย',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      TimeAdvanced(at: _at(const Duration(hours: 4))),
      TimeAdvanced(at: _at(const Duration(hours: 8))),
    ],
  ),
  ConformanceCase(
    name: 'absent-when-cooldown-elapses',
    why: 'ครบ cooldown ตอนไม่เห็นแล้ว → ปิดที่หลักฐานสุดท้าย '
        'ไม่ใช่ที่เวลาที่รู้ตัว และห้ามยิง VisitStarted ตรงนั้น',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 2))),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 3))),
      TimeAdvanced(at: _at(const Duration(hours: 9))),
    ],
  ),
  ConformanceCase(
    name: 'rearm-then-emit-on-next-sighting',
    why: 'ปิดแล้วครั้งหน้าที่เจอค่อยยิง · ลำดับ event ต้องเป็น '
        'started → ended → started',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 6, seconds: 1))),
    ],
  ),
  ConformanceCase(
    name: 'repeated-exit-does-not-extend-silence',
    why: 'exit ซ้ำติดกันต้องไม่เลื่อนจุดเริ่มความเงียบ '
        'มิฉะนั้น cooldown จะไม่มีวันครบถ้าแพลตฟอร์มยิง exit ถี่กว่า cooldown',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 2))),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 3))),
      TimeAdvanced(at: _at(const Duration(minutes: 6, seconds: 1))),
    ],
  ),
  ConformanceCase(
    name: 'regions-are-independent',
    why: 'ออกจาก A แล้วเข้า B ต้องไม่กลืนกัน · cooldown เดินแยกกันต่อ region',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      RegionSeen(regionId: 'b', at: _at(const Duration(minutes: 4))),
      RegionNotSeen(regionId: 'b', at: _at(const Duration(minutes: 5))),
      TimeAdvanced(at: _at(const Duration(minutes: 6, seconds: 30))),
      ObservationsEnded(at: _at(const Duration(minutes: 10))),
    ],
  ),
  ConformanceCase(
    name: 'multi-region-settle-order',
    why: 'หลาย region หมด cooldown พร้อมกัน → ลำดับ event เรียงตาม identifier '
        '**เคสนี้จับ Swift โดยเฉพาะ** เพราะ Dictionary ของ Swift ไม่มีลำดับ '
        'และลำดับเปลี่ยนได้ทุกครั้งที่รัน',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'zulu', at: _at(Duration.zero)),
      RegionSeen(regionId: 'alpha', at: _at(Duration.zero)),
      RegionSeen(regionId: 'mike', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'zulu', at: _at(const Duration(seconds: 1))),
      RegionNotSeen(regionId: 'alpha', at: _at(const Duration(seconds: 1))),
      RegionNotSeen(regionId: 'mike', at: _at(const Duration(seconds: 1))),
      TimeAdvanced(at: _at(const Duration(minutes: 6))),
    ],
  ),
  ConformanceCase(
    name: 'open-visit-closed-at-data-edge',
    why: 'ยังอยู่ในโซนตอนข้อมูลหมด → ปิดที่ขอบ ห้ามทิ้ง '
        '(GROUND_TRUTH.md: ถ้าทิ้งจะได้ 0 ช่วงจากทั้งสองไฟล์ ซึ่งผิด)',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      ObservationsEnded(at: _at(const Duration(hours: 3))),
    ],
  ),
  ConformanceCase(
    name: 'edge-close-while-absent-within-cooldown',
    why: 'ไม่อยู่แล้วแต่ยังไม่ครบ cooldown ตอนข้อมูลหมด → '
        'ปิดที่หลักฐานสุดท้าย ไม่ใช่ที่ขอบ',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      ObservationsEnded(at: _at(const Duration(minutes: 3))),
    ],
  ),
  ConformanceCase(
    name: 'timestamp-went-backwards-is-rejected',
    why: 'เวลาเดินถอยหลัง → ปฏิเสธ state ไม่ถูกแก้ '
        '**ห้ามปรับเวลาให้เอง** เพราะการปรับคือการเดา',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 5))),
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 4))),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 6))),
      ObservationsEnded(at: _at(const Duration(minutes: 7))),
    ],
  ),
  ConformanceCase(
    name: 'identical-timestamps-are-accepted',
    why: 'เวลาเท่ากันเป๊ะต้องรับได้ (ระบบคิว event แล้วส่งมาติดกัน) '
        'ผลขึ้นกับลำดับที่ป้อน — ล็อกลำดับที่ถือว่าถูกไว้ที่นี่',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionNotSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      ObservationsEnded(at: _at(const Duration(minutes: 2))),
    ],
  ),
  ConformanceCase(
    name: 'restored-state-with-open-visit',
    why: 'กู้ state ที่บันทึกไว้กลับมา (Android process ตายแล้วเกิดใหม่) '
        'ต้องไม่เริ่มการมาเยือนซ้ำ',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    initialState: VisitFilterState(
      regions: {
        'a': RegionState(
          present: true,
          lastPresentAt: _t0,
          visit: OpenVisit(
            startedAt: _t0,
            evidence: VisitStartEvidence.arrivalObserved,
          ),
        ),
      },
      lastObservationAt: _t0,
    ),
    observations: [
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 30))),
      ObservationsEnded(at: _at(const Duration(minutes: 31))),
    ],
  ),
  ConformanceCase(
    name: 'flap-storm-collapses-to-one-visit',
    why: 'เข้า-ออกทุก 30 วินาที 40 รอบ ภายใน cooldown → การมาเยือนเดียว',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionNotSeen(regionId: 'a', at: _at(Duration.zero)),
      for (var i = 0; i < 40; i++) ...[
        RegionSeen(regionId: 'a', at: _at(Duration(minutes: i))),
        RegionNotSeen(regionId: 'a', at: _at(Duration(minutes: i, seconds: 30))),
      ],
      ObservationsEnded(at: _at(const Duration(minutes: 45))),
    ],
  ),
  // ── ตาบอด ────────────────────────────────────────────────────────────────
  ConformanceCase(
    name: 'blindness-pauses-cooldown-below-ceiling',
    why: 'บั๊กที่พบจริง — ปิด Bluetooth 10 นาทีขณะนั่งอยู่ที่เดิม '
        'เดิมได้ VisitStarted 2 ครั้ง = ลูกค้าได้แจ้งเตือนโปรโมชันซ้ำ '
        'ต้องเหลือ 1 ครั้ง',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      SensingLost(
        at: _at(const Duration(minutes: 1)),
        cause: SensingLossCause.bluetoothOff,
      ),
      SensingRestored(at: _at(const Duration(minutes: 11))),
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 11))),
      ObservationsEnded(at: _at(const Duration(minutes: 12))),
    ],
  ),
  ConformanceCase(
    name: 'blindness-beyond-ceiling-resets',
    why: 'ตาบอดเกินเพดาน → ปิดการมาเยือนด้วย sensingLostBeyondCeiling '
        'และล้างสถานะทิ้ง · ครั้งหน้าที่เห็นต้องเป็น '
        'alreadyInsideAtFirstObservation เพราะเราไม่เคยเห็นการมาถึง',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      SensingLost(
        at: _at(const Duration(minutes: 2)),
        cause: SensingLossCause.bluetoothOff,
      ),
      SensingRestored(at: _at(const Duration(minutes: 30))),
      RegionSeen(regionId: 'a', at: _at(const Duration(minutes: 31))),
      ObservationsEnded(at: _at(const Duration(minutes: 32))),
    ],
  ),
  ConformanceCase(
    name: 'blindness-exactly-at-ceiling-resets',
    why: 'ขอบเพดานพอดี — ใช้เกณฑ์ >= เหมือน cooldown · '
        'ล็อกไว้เพื่อให้ทั้งสามภาษาตัดสินขอบเหมือนกัน',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      SensingLost(
        at: _at(const Duration(minutes: 2)),
        cause: SensingLossCause.locationServicesOff,
      ),
      SensingRestored(at: _at(const Duration(minutes: 17))),
      ObservationsEnded(at: _at(const Duration(minutes: 18))),
    ],
  ),
  ConformanceCase(
    name: 'blindness-one-millisecond-below-ceiling',
    why: 'อีกฝั่งของเพดาน — ขาด 1 มิลลิวินาทีต้องยัง**หัก**เวลา ไม่ใช่ล้างทิ้ง',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      SensingLost(
        at: _at(const Duration(minutes: 2)),
        cause: SensingLossCause.permissionRevoked,
      ),
      SensingRestored(
        at: _at(const Duration(minutes: 17, milliseconds: -1)),
      ),
      ObservationsEnded(at: _at(const Duration(minutes: 18))),
    ],
  ),
  ConformanceCase(
    name: 'blindness-straddles-cooldown-expiry',
    why: 'ตาบอดคาบเกี่ยวกับจังหวะที่ cooldown จะครบ — '
        'ห้ามปิดระหว่างตาบอด และหลังกลับมามองเห็นต้องนับเวลาที่เหลือต่อ '
        'ไม่ใช่เริ่มนับใหม่',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      SensingLost(
        at: _at(const Duration(minutes: 2)),
        cause: SensingLossCause.bluetoothOff,
      ),
      // ถ้านาฬิกาไม่หยุด cooldown จะครบตั้งแต่นาทีที่ 6 — ตรงนี้ต้องไม่มีอะไรออก
      TimeAdvanced(at: _at(const Duration(minutes: 9))),
      SensingRestored(at: _at(const Duration(minutes: 10))),
      // เงียบจริง 9 นาที หัก 8 นาทีที่ตาบอด = 1 นาที ยังไม่ครบ
      TimeAdvanced(at: _at(const Duration(minutes: 12))),
      // เงียบจริง 13 นาที หัก 8 = 5 นาที ครบพอดี
      TimeAdvanced(at: _at(const Duration(minutes: 14))),
      ObservationsEnded(at: _at(const Duration(minutes: 15))),
    ],
  ),
  ConformanceCase(
    name: 'blindness-starts-while-still-present',
    why: 'ตาบอดก่อนแล้วค่อยได้ exit — หักเฉพาะส่วนที่ทับกับความเงียบจริง '
        'ส่วนที่อยู่ก่อนความเงียบไม่ได้ถูกใครกินไปจึงไม่ต้องคืน',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      SensingLost(
        at: _at(const Duration(minutes: 1)),
        cause: SensingLossCause.scanRegistrationLost,
      ),
      // นาฬิกาปลุกของเราเองยังดังได้แม้ Bluetooth ปิด — exit ระหว่างตาบอดจึงเกิดจริง
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 3))),
      SensingRestored(at: _at(const Duration(minutes: 8))),
      TimeAdvanced(at: _at(const Duration(minutes: 12))),
      TimeAdvanced(at: _at(const Duration(minutes: 13))),
      ObservationsEnded(at: _at(const Duration(minutes: 14))),
    ],
  ),
  ConformanceCase(
    name: 'repeated-sensing-lost-does-not-move-ceiling',
    why: 'SensingLost ซ้ำระหว่างตาบอดต้องไม่เลื่อนจุดเริ่ม '
        'ไม่งั้นเพดานจะไม่มีวันถึงถ้าระบบยิงถี่กว่าเพดาน '
        '(หลักการเดียวกับ exit ซ้ำ)',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionSeen(regionId: 'a', at: _at(Duration.zero)),
      RegionNotSeen(regionId: 'a', at: _at(const Duration(minutes: 1))),
      SensingLost(
        at: _at(const Duration(minutes: 2)),
        cause: SensingLossCause.bluetoothOff,
      ),
      SensingLost(
        at: _at(const Duration(minutes: 8)),
        cause: SensingLossCause.bluetoothOff,
      ),
      SensingLost(
        at: _at(const Duration(minutes: 14)),
        cause: SensingLossCause.unknown,
      ),
      SensingRestored(at: _at(const Duration(minutes: 18))),
      ObservationsEnded(at: _at(const Duration(minutes: 19))),
    ],
  ),
  ConformanceCase(
    name: 'blindness-with-no-open-visit-emits-nothing',
    why: 'ตาบอดตอนไม่มีการมาเยือนเปิดค้าง — ต้องเงียบสนิท '
        'รวมถึงตอนเกินเพดานด้วย',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    observations: [
      RegionNotSeen(regionId: 'a', at: _at(Duration.zero)),
      SensingLost(
        at: _at(const Duration(minutes: 1)),
        cause: SensingLossCause.bluetoothOff,
      ),
      SensingRestored(at: _at(const Duration(minutes: 40))),
      ObservationsEnded(at: _at(const Duration(minutes: 41))),
    ],
  ),
  const ConformanceCase(
    name: 'real-log-ios-2026-08-30',
    why: 'เกณฑ์รับจาก GROUND_TRUTH.md — enter ดิบ 86 ครั้ง ความจริงคือมาเยือน 1 ครั้ง',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    logFile: 'docs/test-data/2026-08-30_overnight_region_flapping.log',
  ),
  const ConformanceCase(
    name: 'real-log-android-2026-09-01',
    why: 'เกณฑ์รับจาก GROUND_TRUTH.md — enter ดิบ 63 ครั้ง ความจริงคือมาเยือน 1 ครั้ง '
        'ต้องผ่านด้วย cooldown ค่าเดียวกับไฟล์ iOS',
    cooldown: _fiveMinutes,
    blindnessCeiling: _blindnessCeiling,
    logFile: 'docs/test-data/2026-09-01_android_overnight_region_flapping.log',
  ),
];
