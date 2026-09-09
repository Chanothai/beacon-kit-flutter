import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

import 'distance_estimator.dart';

/// Key ที่ระบุ "beacon ตัวไหน" สำหรับ [ProximityGate] — คู่ (uuid, major, minor)
/// ตามสัญญาของ iBeacon ตามที่ ADR-19 กำหนด (**ไม่ใช่** [BeaconDeviceId] ซึ่งผูกกับ
/// identity ของวิทยุที่ตรวจจับ — บน iOS ค่านั้นสุ่มใหม่ทุกครั้งที่ถอน-ลงแอปใหม่ตาม
/// คอมเมนต์ของ `DeviceIdKind.coreBluetoothPeripheralId` — ในขณะที่ proximity เป็น
/// แนวคิดที่ผูกกับ "สินค้า/ชั้นวางที่ broadcast uuid/major/minor นี้" ซึ่งคงที่กว่า)
///
/// เป็น Dart record — ได้ value equality ตามโครงสร้าง (structural equality) จาก
/// ภาษาเองโดยตรง ไม่ต้องเขียน `==`/`hashCode` เอง (`uuid` มาจาก
/// `BeaconAdvertisement.ibeaconUuid` ซึ่งเป็น lowercase อยู่แล้วตามสัญญาที่ระบุไว้
/// ในเอนทิตี จึงเทียบตรง ๆ ได้โดยไม่ต้อง normalize เพิ่ม)
typedef ProximityBeaconKey = ({String uuid, int major, int minor});

/// เหตุผลของการเปลี่ยน bucket ที่ [ProximityGate] ยืนยัน (แนบมากับทุก
/// [ProximityTransition] ที่ [ProximityGate.push]/[ProximityGate.sweepStale]
/// คืนออกมา)
enum ProximityTransitionReason {
  /// bucket ใหม่ **ใกล้กว่า** bucket เดิม และผ่านเกณฑ์ dwell ติดกันครบ
  /// `dwellSamples` sample แล้ว — ต้นทุนของการประกาศ "ใกล้" ผิดพลาดแพงกว่าอีกทาง
  /// (ADR-19 หัวข้อ 6(ค)) จึงต้อง dwell ก่อนยืนยัน
  closer,

  /// bucket ใหม่ **ไกลกว่า** bucket เดิม — ยืนยันทันทีโดยไม่ต้อง dwell (ADR-19
  /// หัวข้อ 6(ค): "การประกาศ 'ไกล' ช้าไปเป็นแค่ความไม่แม่นยำเล็กน้อย ไม่มีผลกระทบ
  /// ธุรกิจที่แพงเท่ากัน")
  farther,

  /// ไม่มี sample ใหม่เข้ามานานเกิน `staleAfter` — ถือว่า "วัดไม่ได้อีกแล้ว" ไม่ใช่
  /// "ไกล" (ADR-19 หัวข้อ 6(ฉ): "วัดไม่ได้" ไม่เท่ากับ "ไกล" ไม่ว่าจะเกิดจากสาเหตุ
  /// อะไร) `to` ของ [ProximityTransition] จะเป็น `null` เสมอเมื่อ reason นี้ —
  /// เกิดได้ทั้งจาก [ProximityGate.push] (ตรวจตอนมี sample ใหม่เข้ามา) และ
  /// [ProximityGate.sweepStale] (ตรวจโดยไม่ต้องรอ sample ใหม่เลย — ดู ADR-19
  /// หัวข้อ 3 เรื่องเหตุผลที่ gate ไม่มี timer ในตัวเอง)
  stale,
}

/// ผลลัพธ์ตอน bucket ของบีคอนหนึ่งตัวเปลี่ยนไป — [ProximityGate.push]/
/// [ProximityGate.sweepStale] คืนค่านี้ **เฉพาะตอน bucket เปลี่ยนจริงเท่านั้น**
/// ไม่ใช่ทุก sample ที่ push เข้ามา (sample ที่ไม่ทำให้ bucket เปลี่ยน หรือถูกทิ้ง
/// ตาม ADR-19 หัวข้อ 6(ง)/6(จ) จะได้ `null` กลับจาก [ProximityGate.push])
///
/// **`to == null` แปลว่า "gate ไม่มีคำตอบให้แล้ว" ไม่ใช่ "ไกล" (`BeaconProximity.far`)**
/// — ปัจจุบันเกิดได้ทางเดียวเท่านั้น: [reason] เป็น
/// [ProximityTransitionReason.stale] ผู้เรียกที่ต้องการ trigger เฉพาะตอน "ยืนยัน
/// ว่าไกลแล้วจริง ๆ" ต้องเช็ค `to == BeaconProximity.far` ตรง ๆ ไม่ใช่แค่เช็ค
/// `to != BeaconProximity.near && to != BeaconProximity.immediate`
///
/// **`to` จะไม่มีวันเป็น `BeaconProximity.unknown`** — นี่คือ invariant ที่ ADR-19
/// หัวข้อ 6(ช) บังคับไว้จากการ reuse enum `BeaconProximity` เดิมแทนการสร้าง enum
/// ใหม่: `unknown` มีความหมายเฉพาะฝั่งอินพุต ("วัดไม่ได้") ต้องไม่รั่วออกทาง
/// เอาต์พุตสาธารณะของ gate เลย ทุก code path ที่ gate ไม่มีคำตอบต้องคืน `null`
/// ของ Dart แทนเสมอ
///
/// [from] เป็น `null` ได้เช่นกัน — หมายถึงนี่คือ transition ที่ยืนยัน bucket แรก
/// ของ key นี้ (ไม่เคยมี confirmed bucket มาก่อน)
class ProximityTransition {
  const ProximityTransition({
    required this.key,
    required this.from,
    required this.to,
    required this.reason,
    required this.medianMeters,
  });

  final ProximityBeaconKey key;
  final BeaconProximity? from;
  final BeaconProximity? to;
  final ProximityTransitionReason reason;

  /// ค่า median ของระยะ (เมตร) ในหน้าต่างปัจจุบันที่ใช้ตัดสิน transition นี้ —
  /// `null` เมื่อ bucket มาจาก `advertisement.proximity` ของ Apple (ผ่านการ
  /// smoothing ด้วย mode ของหน้าต่าง ไม่ใช่การคำนวณระยะเอง — ดู ADR-19 หัวข้อ 4
  /// ข้อ 1) หรือเมื่อเป็น transition จาก [ProximityGate.sweepStale] **ไม่ใช่
  /// `null` เพราะคำนวณไม่ได้**
  final double? medianMeters;

  @override
  String toString() =>
      'ProximityTransition(key: $key, from: $from, to: $to, reason: $reason, '
      'medianMeters: $medianMeters)';
}

/// ภาพรวมสถานะภายในของ [ProximityGate] สำหรับ key เดียว — มีไว้ให้หน้าจอ
/// diagnostic ของ host app (เช่น `example/`) อ่านไปแสดงผลเท่านั้น ไม่ใช่ API ที่
/// ตรรกะทางธุรกิจควรอ่านไปตัดสินใจต่อ (ใช้ [ProximityGate.currentBucket] สำหรับ
/// การตัดสินใจจริง)
class ProximityGateSnapshot {
  const ProximityGateSnapshot({
    required this.key,
    required this.confirmedBucket,
    required this.window,
    required this.medianMeters,
    required this.appleProximityWindow,
    required this.pendingCloserBucket,
    required this.pendingCloserCount,
    required this.droppedNoTxPowerCount,
    required this.lastSampleAt,
  });

  final ProximityBeaconKey key;

  /// bucket ที่ยืนยันแล้ว ณ ตอนนี้ — เหมือนกับผลของ
  /// `ProximityGate.currentBucket(key)`
  final BeaconProximity? confirmedBucket;

  /// หน้าต่างระยะ (เมตร) ที่ใช้คำนวณ median ปัจจุบัน — ว่างเสมอถ้า sample ล่าสุด
  /// ของ key นี้มาจาก `advertisement.proximity` ของ Apple (เคสนั้นดู
  /// [appleProximityWindow] แทน — คนละหน้าต่างกัน ไม่ผสมกัน)
  final List<double> window;

  /// median ของ [window] — `null` เมื่อ [window] ว่าง
  final double? medianMeters;

  /// หน้าต่าง bucket ดิบจาก `advertisement.proximity` ของ Apple (ก่อนหา mode) —
  /// ว่างเสมอถ้า key นี้มาจากเส้นทางคำนวณระยะเอง (ดู [window] แทน) — ADR-19
  /// หัวข้อ 4 (แก้ไข 8 ก.ย. 2026): เส้นทาง iOS ต้อง smoothing ด้วย mode ของ
  /// หน้าต่างนี้เหมือนกับที่เส้นทาง Android ใช้ median ของ [window]
  final List<BeaconProximity> appleProximityWindow;

  /// bucket ที่กำลังรอ dwell อยู่ (ยังไม่ผ่านเกณฑ์ `dwellSamples` ติดกัน) —
  /// `null` เมื่อไม่มี bucket ใดกำลังรอ dwell
  final BeaconProximity? pendingCloserBucket;

  /// จำนวน sample ติดกันที่ตรงกับ [pendingCloserBucket] แล้ว (ยังไม่ถึง
  /// `dwellSamples`)
  final int pendingCloserCount;

  /// จำนวน sample ที่ถูกทิ้งเพราะตัดสินอะไรไม่ได้เลย (ADR-19 หัวข้อ 6(จ):
  /// `ibeaconTxPower == null && proximity == null`) — สะสมตั้งแต่ key นี้เริ่มมี
  /// state (รีเซ็ตกลับ 0 เมื่อ key นี้ผ่านรอบ stale ตาม ADR-19 หัวข้อ 6(ฉ))
  final int droppedNoTxPowerCount;

  /// เวลา (จาก `clock` ที่ inject เข้า [ProximityGate]) ของ sample **ที่ใช้
  /// ตัดสินใจได้จริง** ล่าสุดของ key นี้ — `null` เมื่อยังไม่เคยมี sample ที่ใช้
  /// ตัดสินใจได้เลย (มีแต่ sample ที่ถูกทิ้งตาม ADR-19 หัวข้อ 6(ง)/6(จ)) **sample
  /// ที่ถูกทิ้งไม่ทำให้ค่านี้ขยับ** — นี่คือสิ่งที่ทำให้ staleness ตรวจจับความเงียบ
  /// จริง ๆ ได้ ไม่ใช่แค่ "ยังมีสัญญาณเข้ามาแต่ใช้อะไรไม่ได้เลย"
  final DateTime? lastSampleAt;

  @override
  String toString() =>
      'ProximityGateSnapshot(key: $key, confirmedBucket: $confirmedBucket, '
      'window: $window, medianMeters: $medianMeters, '
      'appleProximityWindow: $appleProximityWindow, '
      'pendingCloserBucket: $pendingCloserBucket, '
      'pendingCloserCount: $pendingCloserCount, '
      'droppedNoTxPowerCount: $droppedNoTxPowerCount, '
      'lastSampleAt: $lastSampleAt)';
}

/// อันดับความใกล้ของ bucket — ใช้เทียบว่า candidate bucket ใหม่ "ใกล้กว่า" หรือ
/// "ไกลกว่า" bucket ที่ยืนยันอยู่ตอนนี้ (ยิ่งเลขน้อยยิ่งใกล้) สำหรับตรรกะ dwell
/// ใน [ProximityGate._applyDwell] และตรรกะ tie-break ของ
/// [ProximityGate._appleBucketCandidate]
///
/// `BeaconProximity.unknown` ไม่มีอันดับ — ต้องไม่มีวันไหลมาถึงจุดที่ต้องจัดอันดับ
/// เพราะ [ProximityGate.push] ทิ้ง sample ที่ unknown ไปตั้งแต่ต้นแล้ว (ADR-19
/// หัวข้อ 6(ง))
int _rankOf(BeaconProximity bucket) {
  switch (bucket) {
    case BeaconProximity.immediate:
      return 0;
    case BeaconProximity.near:
      return 1;
    case BeaconProximity.far:
      return 2;
    case BeaconProximity.unknown:
      throw StateError(
        'BeaconProximity.unknown ไหลมาถึง _rankOf ได้อย่างไร — ProximityGate '
        'ต้องทิ้ง sample ที่ unknown ไปตั้งแต่ push() แล้วตาม ADR-19 หัวข้อ 6(ง). '
        'ถ้าเห็น error นี้แปลว่ามีบั๊กในลำดับการตัดสินของ push()',
      );
  }
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// สถานะภายในต่อ 1 [ProximityBeaconKey] — private ล้วน ผู้เรียกภายนอกอ่านผ่าน
/// [ProximityGate.currentBucket]/[ProximityGate.debugSnapshot] เท่านั้น
class _KeyState {
  BeaconProximity? confirmedBucket;
  BeaconProximity? pendingCloserBucket;
  int pendingCloserCount = 0;
  int droppedNoTxPowerCount = 0;
  final List<double> window = [];
  final List<BeaconProximity> appleProximityWindow = [];

  /// เวลาของ sample **ที่ใช้ตัดสินใจได้จริง** ล่าสุด — `null` จนกว่าจะมี sample
  /// แรกที่ไม่ถูกทิ้ง (ดู dartdoc ของ [ProximityGateSnapshot.lastSampleAt] สำหรับ
  /// เหตุผลเต็ม ๆ ว่าทำไม sample ที่ถูกทิ้งห้ามขยับค่านี้)
  DateTime? lastSampleAt;
}

/// ชั้นตัดสินใจ "ใกล้พอหรือยัง" จาก `BeaconAdvertisement` แต่ละตัว — ตาม
/// ARCHITECTURE.md ADR-19
///
/// เป็น **pure Dart class ล้วน** — ไม่มี I/O, ไม่แตะ BLE API, ไม่มี `Timer`
/// ภายในตัวเอง, ไม่รู้จัก `BackgroundRegionMonitor`/`reconcile()` เลย รับแค่
/// [BeaconAdvertisement] ทีละตัวผ่าน [push] เป็นอินพุต และคืน [ProximityTransition]
/// เฉพาะตอน bucket ที่ยืนยันแล้วของ key นั้นเปลี่ยนไปจริง (ADR-19 หัวข้อ 1 และ 3)
///
/// **ชั้นนี้ไม่ปลุกแอปจาก background ได้** — ต้องมีบางอย่าง (region monitoring
/// ของ ADR-9/14/17) ทำให้ sample ไหลเข้ามาก่อนเสมอ [push] ถึงจะมีอะไรให้ตัดสิน
/// (ADR-19 หัวข้อ 1)
///
/// **ทำไมไม่มี `Timer` ในคลาสนี้ (ADR-19 หัวข้อ 3):** การมี timer ภายในจะทำให้
/// คลาสนี้มี I/O แฝง (ผูกกับนาฬิกาจริงของระบบ) ซึ่งขัดกับเป้าหมาย pure/testable
/// ของทั้งไฟล์นี้โดยตรง (ทดสอบ timer จริงต้องรอเวลาจริงหรือ mock `Timer` ซึ่งซับซ้อน
/// กว่าการ mock `clock` เฉย ๆ มาก) — **host app เป็นเจ้าของ lifecycle ของแอปเอง**
/// (foreground/background, dispose ตอนปิดหน้าจอ ฯลฯ) จึงเป็นคนที่เหมาะจะตั้งเวลา
/// เรียกซ้ำเอง ผ่าน [sweepStale] ไม่ใช่ให้ gate ผูกตัวเองไว้กับนาฬิกาของระบบ
///
/// **ทุก threshold เป็น constructor parameter ที่ host app กำหนด** ไม่มีค่าที่
/// SDK ตัดสินใจแทนแบบซ่อนอยู่ข้างใน (ADR-19 หัวข้อ 3) — ค่า default ของแต่ละ
/// พารามิเตอร์ในนี้คือ**ค่าตั้งต้นสำหรับ POC เท่านั้น** ตรงกับตาราง ADR-19 §8
/// เป๊ะ **ไม่ใช่ค่าที่ calibrate จากสาขาจริง** ห้ามใช้เป็นค่า production โดยไม่
/// ผ่านรอบเก็บข้อมูลภาคสนามก่อน (ดู ADR-19 หัวข้อ 7/8)
///
/// **ลำดับการตัดสินต่อ sample ที่ [push] ใช้ (ADR-19 หัวข้อ 4/6, แก้ไข 8 ก.ย. 2026):**
/// 1. `advertisement.proximity != null` (iOS ranging, `osDecoded`) →
///    `BeaconProximity.unknown` ทิ้ง sample ทันที ไม่นับเป็น `far` และ**ไม่แตะ
///    state ใด ๆ เลย** (หัวข้อ 6(ง)) — ค่าอื่นใส่ลงหน้าต่าง bucket ขนาด
///    [windowSize] แล้วหา **mode** (ค่าที่พบบ่อยที่สุด) ถ้าเสมอกันเลือกตัวที่
///    **ไกลกว่า** (สอดคล้องต้นทุนไม่สมมาตรของหัวข้อ 6(ค)) ไม่ใช้ค่าล่าสุดตรง ๆ
///    เพราะ Apple เองก็รายงาน bucket แกว่งเป็นครั้งคราวได้ (ดูหัวข้อ 4 ในเอกสาร
///    ADR)
/// 2. `ibeaconTxPower == null && proximity == null` → ตัดสินอะไรไม่ได้เลย ทิ้ง
///    sample และนับ [ProximityGateSnapshot.droppedNoTxPowerCount] เพิ่ม (เท่านั้น
///    — **ไม่แตะ field อื่นของ state เลย รวมถึงเวลา sample ล่าสุด**) — ห้าม
///    default ค่า txPower เงียบ ๆ (หัวข้อ 6(จ))
/// 3. อื่น ๆ (Android ปกติ) → คำนวณระยะด้วย [estimateDistanceMeters], ใส่ลง
///    หน้าต่างขนาด [windowSize], หา **median** (ไม่ใช่ average — หัวข้อ 6(ก))
/// 4. hysteresis: เข้า `near`/`immediate` เมื่อ median ≤ [enterMeters], ออกเมื่อ
///    median > [exitMeters], `immediate` เมื่อ median ≤ [immediateMeters]
///    (หัวข้อ 6(ข)) — ใช้กับ candidate จากข้อ 3 เท่านั้น (candidate จาก Apple ใน
///    ข้อ 1 ไม่ผ่านขั้นนี้ เพราะไม่มี median ให้เทียบ)
/// 5. dwell: เปลี่ยนเป็น bucket ที่**ใกล้กว่า**ต้องผ่านเกณฑ์ติดกัน ≥
///    [dwellSamples] sample — เปลี่ยนเป็น bucket ที่**ไกลกว่า**ยืนยันทันที ไม่ต้อง
///    dwell (หัวข้อ 6(ค)) — ใช้กับ candidate จากทั้งข้อ 1 และข้อ 3-4 เหมือนกัน
/// 6. stale: ไม่มี sample **ที่ตัดสินใจได้จริง** เข้ามานานเกิน [staleAfter] (วัด
///    จาก [clock] ไม่ใช่ `advertisement.timestamp`) → transition `to` เป็น
///    `null` (ไม่ใช่ `far`) พร้อม `reason` เป็น [ProximityTransitionReason.stale]
///    (หัวข้อ 6(ฉ)) — ตรวจได้สองทาง: ตอน [push] มี sample ใหม่เข้ามาหลังช่องว่าง
///    เวลานาน หรือตอนเรียก [sweepStale] แบบไม่ต้องรอ sample เลย (จำเป็นสำหรับ
///    เคส "ลูกค้าเดินออกจากร้าน" ที่ไม่มี sample เข้ามาอีกเลย)
///
/// **บีคอนที่ไม่ใช่ iBeacon (เช่น Eddystone ล้วน ไม่มี `ibeaconUuid`)** — [push]
/// คืน `null` เสมอโดยไม่แตะ state ใด ๆ เพราะไม่มีทางสร้าง [ProximityBeaconKey]
/// ได้เลย ADR-19 ทั้งฉบับพูดถึงเฉพาะ proximity ของ iBeacon เท่านั้น (ไม่ใช่
/// นโยบายที่ ADR ตัดสินใจปฏิเสธ แค่ไม่มี field ให้คำนวณ)
class ProximityGate {
  ProximityGate({
    required this.clock,
    this.enterMeters = 3.0,
    this.exitMeters = 5.0,
    this.immediateMeters = 1.0,
    this.windowSize = 5,
    this.dwellSamples = 3,
    this.pathLossExponent = 2.5,
    this.staleAfter = const Duration(seconds: 10),
  }) : assert(
         exitMeters > enterMeters,
         'exitMeters ต้องมากกว่า enterMeters เสมอ — ไม่งั้น hysteresis dead zone '
         'ของ ADR-19 หัวข้อ 6(ข) จะกลับด้าน (ออกง่ายกว่าเข้า) ซึ่งไม่ป้องกัน flap '
         'ตามที่ออกแบบไว้',
       );

  /// ระยะ (เมตร) ที่ median ต้องต่ำกว่าหรือเท่ากับ ถึงจะเริ่มนับเป็น `near`/
  /// `immediate` — ใช้เฉพาะตอนกำลัง "เข้า" จาก bucket ที่ไกลกว่า (ADR-19 §6(ข))
  ///
  /// ค่าตั้งต้น `3.0` ตรงกับตาราง ADR-19 §8 — เป็นค่าตัวอย่างสำหรับ POC เท่านั้น
  final double enterMeters;

  /// ระยะ (เมตร) ที่ median ต้องมากกว่า ถึงจะเริ่มนับว่า "ออกจาก" `near`/
  /// `immediate` แล้ว — คนละค่ากับ [enterMeters] โดยตั้งใจเพื่อสร้าง dead zone
  /// กัน flap (ADR-19 §6(ข))
  ///
  /// ค่าตั้งต้น `5.0` ตรงกับตาราง ADR-19 §8
  final double exitMeters;

  /// ระยะ (เมตร) ที่ median ต้องต่ำกว่าหรือเท่ากับ ถึงจะนับเป็น `immediate`
  /// (แทนที่ `near`) — เทียบตรง ๆ ไม่มี hysteresis แยกสำหรับขอบเขตนี้ (ADR-19 §6(ข))
  ///
  /// ค่าตั้งต้น `1.0` ตรงกับตาราง ADR-19 §8 (ตรงกับ `d0 = 1m` ของโมเดล)
  final double immediateMeters;

  /// จำนวน sample สูงสุดที่เก็บไว้คำนวณ median (เส้นทาง Android) หรือ mode
  /// (เส้นทาง iOS) ต่อ key หนึ่ง — ค่าตั้งต้น `5` ตรงกับตาราง ADR-19 §8
  final int windowSize;

  /// จำนวน sample ติดกันขั้นต่ำที่ candidate bucket ที่ใกล้กว่าต้องผ่าน ก่อนจะ
  /// ยืนยัน transition จริง — ค่าตั้งต้น `3` ตรงกับตาราง ADR-19 §8
  final int dwellSamples;

  /// path loss exponent (`n`) ที่ส่งต่อให้ [estimateDistanceMeters] — ค่าตั้งต้น
  /// `2.5` ตรงกับตาราง ADR-19 §8 (กึ่งกลางของช่วงตัวอย่างจริงที่พบใน
  /// `docs/sources/rssi_path_loss_model.md`)
  final double pathLossExponent;

  /// ระยะเวลาสูงสุดที่ไม่มี sample **ที่ตัดสินใจได้จริง** เข้ามา ก่อนจะถือว่า
  /// key นั้น "วัดไม่ได้อีกแล้ว" (ไม่ใช่ "ไกล") — ค่าตั้งต้น 10 วินาที ตรงกับ
  /// ตาราง ADR-19 §8
  final Duration staleAfter;

  /// แหล่งเวลาที่ [push]/[sweepStale] ใช้ตัดสิน stale — **ต้อง inject เข้ามาเสมอ
  /// ไม่มี default** เพื่อให้เทสต์ควบคุมเวลาได้แบบ deterministic โดยไม่ต้องพึ่ง
  /// นาฬิกาจริงของเครื่อง (คลาสนี้ห้ามเรียกนาฬิกาของระบบตรง ๆ ข้างในตัวเองเด็ดขาด)
  final DateTime Function() clock;

  final Map<ProximityBeaconKey, _KeyState> _states = {};

  /// key ของ iBeacon ที่ [advertisement] แทน — `null` เมื่อไม่มี
  /// `ibeaconUuid`/`ibeaconMajor`/`ibeaconMinor` ครบ (ไม่ใช่ iBeacon หรือ Dart
  /// parser ยังถอดไม่สำเร็จ)
  ProximityBeaconKey? _keyOf(BeaconAdvertisement advertisement) {
    final uuid = advertisement.ibeaconUuid;
    final major = advertisement.ibeaconMajor;
    final minor = advertisement.ibeaconMinor;
    if (uuid == null || major == null || minor == null) return null;
    return (uuid: uuid, major: major, minor: minor);
  }

  /// จัด candidate bucket จาก median ระยะปัจจุบัน โดยใช้ hysteresis (ADR-19
  /// หัวข้อ 6(ข)): ทิศทาง "เข้า near/immediate" ใช้ [enterMeters], ทิศทาง
  /// "ออกจาก near/immediate" ใช้ [exitMeters] — ต้องรู้ bucket ที่ยืนยันอยู่ตอนนี้
  /// ([previousConfirmed]) ถึงจะรู้ว่ากำลังอยู่ทิศทางไหน
  BeaconProximity _classify(
    double medianMeters,
    BeaconProximity? previousConfirmed,
  ) {
    final wasClose =
        previousConfirmed == BeaconProximity.near ||
        previousConfirmed == BeaconProximity.immediate;
    final isClose = wasClose
        ? medianMeters <= exitMeters
        : medianMeters <= enterMeters;
    if (!isClose) return BeaconProximity.far;
    return medianMeters <= immediateMeters
        ? BeaconProximity.immediate
        : BeaconProximity.near;
  }

  /// หา candidate bucket จากหน้าต่าง bucket ดิบของ Apple ([_KeyState.appleProximityWindow])
  /// ด้วย **mode** (ค่าที่พบบ่อยที่สุด) — **ถ้าเสมอกันเลือกตัวที่ไกลกว่า** (rank
  /// สูงกว่าใน [_rankOf]) แทนที่จะใช้ sample ล่าสุดตรง ๆ
  ///
  /// **เหตุผล (แก้บั๊กจากรอบ implement แรก, ADR-19 หัวข้อ 4):** ใช้ bucket ของ
  /// Apple ตรง ๆ โดยไม่ smoothing ทำให้ไม่มี hysteresis เลยในเส้นทาง iOS — ผสมกับ
  /// กฎ "ไกลขึ้นไม่ต้อง dwell" (หัวข้อ 6(ค)) ทำให้ Apple ส่ง `far` มาแค่ครั้งเดียว
  /// ก็หลุดจาก `near` ทันที แล้วอีกไม่กี่ sample ต่อมากลับเข้า `near` ใหม่ วนซ้ำได้
  /// — การ smoothing ด้วย mode ของหน้าต่างขนาดเดียวกับเส้นทาง Android ([windowSize])
  /// ทำให้ outlier ครั้งเดียวไม่มีน้ำหนักพอเปลี่ยน candidate การเลือก "ไกลกว่า"
  /// ตอนเสมอกันสอดคล้องกับต้นทุนไม่สมมาตรของหัวข้อ 6(ค) เดิม (การประกาศ "ใกล้"
  /// ผิดพลาดแพงกว่า จึงไม่ควรเป็นฝ่ายชนะเมื่อข้อมูลไม่ชัดเจนพอ ๆ กัน)
  BeaconProximity _appleBucketCandidate(_KeyState state) {
    final counts = <BeaconProximity, int>{};
    for (final bucket in state.appleProximityWindow) {
      counts[bucket] = (counts[bucket] ?? 0) + 1;
    }

    BeaconProximity? best;
    var bestCount = -1;
    for (final entry in counts.entries) {
      final isMoreFrequent = entry.value > bestCount;
      final isTieButFarther =
          entry.value == bestCount &&
          best != null &&
          _rankOf(entry.key) > _rankOf(best);
      if (isMoreFrequent || isTieButFarther) {
        best = entry.key;
        bestCount = entry.value;
      }
    }

    // window มี sample อย่างน้อย 1 ตัวเสมอตอนฟังก์ชันนี้ถูกเรียก (push() เพิ่ง
    // add เข้าไปก่อนเรียก) — ปลอดภัยที่จะ assume ว่ามีคำตอบ
    return best!;
  }

  /// บังคับ dwell (ADR-19 หัวข้อ 6(ค)): candidate ที่ **ใกล้กว่า** bucket ที่
  /// ยืนยันอยู่ตอนนี้ ต้องผ่านเกณฑ์ติดกัน ≥ [dwellSamples] ก่อนยืนยันจริง —
  /// candidate ที่ **ไกลกว่าหรือเท่าเดิม** ยืนยันทันที
  ///
  /// **การตัดสินใจเติมช่องว่างที่ ADR-19 ไม่ได้ระบุไว้ตรง ๆ (ไม่ใช่ deviation
  /// จาก ADR — ผู้ใช้อนุมัติแล้ว บันทึกเป็นทางการที่ ADR-19 หัวข้อ 6(ช) เพิ่มเติม):**
  /// เมื่อยังไม่เคยมี confirmed bucket มาก่อนเลย (`current == null`, sample แรก
  /// ของ key นี้) ถือว่า baseline เทียบเท่า `far` (ไกลที่สุด) ไม่ใช่ "ต้อง dwell
  /// เสมอ" — ผลคือ candidate แรกที่เป็น `far` ยืนยันได้ทันทีเหมือนการ "ไกลกว่า"
  /// ปกติ ส่วน candidate แรกที่เป็น `near`/`immediate` ยังต้อง dwell ก่อน
  /// เหตุผลตรงกับหลักการต้นทุนไม่สมมาตรของ ADR-19 หัวข้อ 6(ค) เอง (การประกาศ
  /// "ใกล้" ผิดพลาดแพงกว่า) เพียงแต่ขยายให้ครอบคลุมถึง sample แรกสุดของ key ด้วย
  /// ไม่ใช่แค่ตอนเปลี่ยนจาก bucket อื่น
  ProximityTransition? _applyDwell(
    ProximityBeaconKey key,
    _KeyState state,
    BeaconProximity candidate,
    double? medianMeters,
  ) {
    final current = state.confirmedBucket;
    if (current == candidate) {
      state.pendingCloserBucket = null;
      state.pendingCloserCount = 0;
      return null;
    }

    final baselineRank = current != null
        ? _rankOf(current)
        : _rankOf(BeaconProximity.far);
    final becomingCloser = _rankOf(candidate) < baselineRank;

    if (!becomingCloser) {
      state.pendingCloserBucket = null;
      state.pendingCloserCount = 0;
      state.confirmedBucket = candidate;
      return ProximityTransition(
        key: key,
        from: current,
        to: candidate,
        reason: ProximityTransitionReason.farther,
        medianMeters: medianMeters,
      );
    }

    if (state.pendingCloserBucket == candidate) {
      state.pendingCloserCount++;
    } else {
      state.pendingCloserBucket = candidate;
      state.pendingCloserCount = 1;
    }

    if (state.pendingCloserCount < dwellSamples) {
      return null;
    }

    state.pendingCloserBucket = null;
    state.pendingCloserCount = 0;
    state.confirmedBucket = candidate;
    return ProximityTransition(
      key: key,
      from: current,
      to: candidate,
      reason: ProximityTransitionReason.closer,
      medianMeters: medianMeters,
    );
  }

  /// ตรวจว่า [state] เกิน [staleAfter] มาแล้วหรือยัง (เทียบกับ [now]) — ถ้าใช่
  /// **ล้าง window/pending ของ key นั้นเสมอ** ไม่ว่าจะเคยมี `confirmedBucket`
  /// มาก่อนหรือยัง (แก้บั๊กจากรอบ implement แรกที่ล้าง state เฉพาะตอน
  /// `confirmedBucket != null` ทำให้ key ที่กำลัง dwell อยู่ (`pendingCloserCount`
  /// ค้างอยู่) แล้วเงียบหายไปนาน พอกลับมา sample ถัดมาจะไปสานต่อ dwell เดิมทันที
  /// ทั้งที่ข้อมูลไม่ได้ต่อเนื่องจริง ๆ) — คืน [_KeyState] ใหม่ที่ล้างแล้วถ้า stale,
  /// คืน `null` ถ้ายังไม่ stale
  ///
  /// **emit [ProximityTransition] เฉพาะตอนเคยมี `confirmedBucket` มาก่อนเท่านั้น**
  /// (ผู้เรียกเป็นคนเช็คเองจาก `confirmedBucket` ของ [state] ที่ส่งเข้ามา ก่อน
  /// เรียกฟังก์ชันนี้) — ไม่มีอะไรให้ประกาศว่า "หลุด" ถ้าไม่เคยยืนยัน bucket ใด
  /// มาก่อนเลย
  _KeyState? _resetIfStale(_KeyState state, DateTime now) {
    final lastSampleAt = state.lastSampleAt;
    if (lastSampleAt == null) return null;
    if (now.difference(lastSampleAt) <= staleAfter) return null;
    return _KeyState();
  }

  /// ป้อน [advertisement] หนึ่งตัวเข้า gate — คืน [ProximityTransition] เฉพาะ
  /// ตอน bucket ที่ยืนยันแล้วของ key นี้เปลี่ยนไปจริง มิฉะนั้นคืน `null` (รวม
  /// กรณี sample ถูกทิ้งตาม ADR-19 หัวข้อ 6(ง)/6(จ) และกรณีที่ไม่ใช่ iBeacon เลย)
  ///
  /// ดู dartdoc ของคลาสนี้สำหรับลำดับการตัดสินเต็ม ๆ
  ProximityTransition? push(BeaconAdvertisement advertisement) {
    final key = _keyOf(advertisement);
    if (key == null) return null;

    final now = clock();
    var state = _states[key];

    // ---- stale check ก่อนอื่น (ADR-19 หัวข้อ 6(ฉ)) — ใช้ clock() ไม่ใช่
    // advertisement.timestamp เพราะความเงียบที่ต้องตรวจจับคือ "ไม่มี push()
    // เรียกเข้ามานานแค่ไหนตามเวลาจริงที่ gate ประมวลผล" ไม่ใช่ค่าที่ฝัง
    // มาในตัว advertisement เอง ----
    if (state != null) {
      final resetState = _resetIfStale(state, now);
      if (resetState != null) {
        final hadConfirmedBucket = state.confirmedBucket;
        _states[key] = resetState;
        state = resetState;
        if (hadConfirmedBucket != null) {
          // ทิ้ง sample ปัจจุบันไปพร้อมกับ transition นี้โดยตั้งใจ — push()
          // คืนได้ทีละ 1 transition ต่อ 1 call เท่านั้น sample ที่จุดชนวน
          // stale จะถูกประมวลผลใหม่ในรอบ push() ถัดไปด้วย state ที่รีเซ็ต
          // แล้ว (บันทึกเป็น design choice ที่ ADR-19 หัวข้อ 7)
          return ProximityTransition(
            key: key,
            from: hadConfirmedBucket,
            to: null,
            reason: ProximityTransitionReason.stale,
            medianMeters: null,
          );
        }
        // ไม่เคย confirm bucket มาก่อน (แค่กำลัง dwell อยู่ตอนหายไป) — ไม่มี
        // อะไรให้ประกาศว่าหลุด ใช้ sample ปัจจุบันเริ่ม state ใหม่ต่อได้ทันที
        // ในรอบเดียวกันนี้เลย (ไม่ต้องรอ push() รอบถัดไป)
      }
    }

    state ??= _KeyState();
    _states[key] = state;

    final BeaconProximity candidate;
    double? medianMeters;

    final proximity = advertisement.proximity;
    if (proximity != null) {
      // ADR-19 หัวข้อ 4 ข้อ 1: OS ถอดให้แล้ว ใช้ bucket ของ Apple (ผ่าน
      // smoothing ของ _appleBucketCandidate) ไม่คำนวณระยะเองทับ
      if (proximity == BeaconProximity.unknown) {
        // ADR-19 หัวข้อ 6(ง): unknown = "วัดไม่ได้" ต้องทิ้ง sample ทั้งหมด —
        // ห้ามแตะ state ใด ๆ เลยแม้แต่ lastSampleAt (sample นี้ไม่ได้ยืนยัน
        // อะไรเลย การขยับ lastSampleAt จะเป็นการต่ออายุ freshness ปลอม ๆ ให้
        // bucket ที่ยืนยันอยู่ก่อนหน้า)
        return null;
      }
      state.appleProximityWindow.add(proximity);
      while (state.appleProximityWindow.length > windowSize) {
        state.appleProximityWindow.removeAt(0);
      }
      state.lastSampleAt = now;
      candidate = _appleBucketCandidate(state);
    } else {
      final txPower = advertisement.ibeaconTxPower;
      if (txPower == null) {
        // ADR-19 หัวข้อ 6(จ): ตัดสินอะไรไม่ได้เลย ทิ้ง sample + นับ counter
        // เท่านั้น — ห้าม default ค่า txPower เงียบ ๆ และห้ามแตะ lastSampleAt
        // เหมือนกับเคส unknown ข้างบน (เหตุผลเดียวกันเป๊ะ)
        state.droppedNoTxPowerCount++;
        return null;
      }
      final distanceMeters = estimateDistanceMeters(
        rssi: advertisement.rssi,
        txPower: txPower,
        pathLossExponent: pathLossExponent,
      );
      state.window.add(distanceMeters);
      while (state.window.length > windowSize) {
        state.window.removeAt(0);
      }
      state.lastSampleAt = now;
      // ADR-19 หัวข้อ 6(ก): median ไม่ใช่ average
      medianMeters = _median(state.window);
      candidate = _classify(medianMeters, state.confirmedBucket);
    }

    return _applyDwell(key, state, candidate, medianMeters);
  }

  /// ตรวจทุก key ที่มี state อยู่ตอนนี้ว่าเกิน [staleAfter] หรือยัง **โดยไม่ต้อง
  /// รอให้มี [push] ใหม่เข้ามาก่อน** — จำเป็นเพราะเคสหลักของฟีเจอร์นี้คือ
  /// "ลูกค้าเดินออกจากร้าน" ซึ่งแปลว่า**ไม่มี sample ใหม่เข้ามาให้ [push] ตรวจจับ
  /// ความเงียบได้เองอีกเลย** ถ้าไม่มีทางตรวจแบบนี้ key นั้นจะไม่มีวันได้
  /// transition `to: null` เลย (บั๊กจากรอบ implement แรก)
  ///
  /// **คลาสนี้ไม่มี `Timer` ภายในตัวเอง** (ดู dartdoc ของคลาส) — ฟังก์ชันนี้
  /// **pure**: อ่านแค่ [clock] ที่ inject เข้ามา ไม่มี I/O ใด ๆ — **host app
  /// เป็นเจ้าของ lifecycle ของการเรียกซ้ำเอง** เช่นตั้ง `Timer.periodic` ในโค้ด
  /// ของแอปแล้วเรียกฟังก์ชันนี้ทุกครั้งที่ timer ยิง (ดู `example/` สำหรับ
  /// ตัวอย่างการใช้งาน)
  ///
  /// คืนรายการ [ProximityTransition] (reason [ProximityTransitionReason.stale])
  /// ของทุก key ที่เพิ่งหลุด stale จากการเรียกครั้งนี้เท่านั้น — ว่างเปล่าถ้า
  /// ไม่มี key ไหนหลุดใหม่ (รวมถึง key ที่ไม่เคยมี `confirmedBucket` มาก่อนเลย
  /// ซึ่งไม่มีอะไรให้ประกาศว่าหลุด แต่ state ของ key นั้นจะถูกล้างเงียบ ๆ อยู่ดี)
  List<ProximityTransition> sweepStale() {
    final now = clock();
    final transitions = <ProximityTransition>[];

    for (final key in _states.keys.toList()) {
      final state = _states[key]!;
      final resetState = _resetIfStale(state, now);
      if (resetState == null) continue;

      final hadConfirmedBucket = state.confirmedBucket;
      _states[key] = resetState;
      if (hadConfirmedBucket != null) {
        transitions.add(
          ProximityTransition(
            key: key,
            from: hadConfirmedBucket,
            to: null,
            reason: ProximityTransitionReason.stale,
            medianMeters: null,
          ),
        );
      }
    }

    return transitions;
  }

  /// bucket ที่ยืนยันแล้วของ [key] ณ ตอนนี้ — **คืน `null` เมื่อไม่มี state**
  /// (ไม่เคย push มาก่อน หรือหลุด stale ไปแล้ว) **ไม่มีวันคืน
  /// `BeaconProximity.unknown`** (invariant ตาม ADR-19 หัวข้อ 6(ช))
  BeaconProximity? currentBucket(ProximityBeaconKey key) =>
      _states[key]?.confirmedBucket;

  /// ภาพรวมสถานะภายในของ [key] สำหรับหน้าจอ diagnostic (เช่น `example/`) —
  /// `null` เมื่อไม่เคย push มาก่อนเลย
  ProximityGateSnapshot? debugSnapshot(ProximityBeaconKey key) {
    final state = _states[key];
    if (state == null) return null;
    return ProximityGateSnapshot(
      key: key,
      confirmedBucket: state.confirmedBucket,
      window: List.unmodifiable(state.window),
      medianMeters: state.window.isEmpty ? null : _median(state.window),
      appleProximityWindow: List.unmodifiable(state.appleProximityWindow),
      pendingCloserBucket: state.pendingCloserBucket,
      pendingCloserCount: state.pendingCloserCount,
      droppedNoTxPowerCount: state.droppedNoTxPowerCount,
      lastSampleAt: state.lastSampleAt,
    );
  }
}
