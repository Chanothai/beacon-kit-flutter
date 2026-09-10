import CoreLocation
import Foundation
import XCTest

@testable import Runner
@testable import beacon_kit_ios

/// XCTest ของ **ชั้นที่ 2 (proximity) ฝั่ง iOS** ตาม ARCHITECTURE.md **ADR-21**
/// — รันได้บน **simulator** ล้วน ไม่ต้องมี iPhone จริง ไม่ต้องมีบีคอน K9P
///
/// ## ที่มาของทุกเคสในไฟล์นี้
///
/// เคสทั้งหมด **port มาจาก `packages/beacon_kit/test/proximity/proximity_gate_test.dart`
/// ซึ่งเป็น reference implementation** (ADR-21 หัวข้อ 2: "ทั้งสองภาษาต้อง == Dart
/// ไม่ใช่ == กันเอง") — ตัวเลขทุกตัว (`windowSize = 5` · `dwellSamples = 3` ·
/// `staleAfter = 10_000 ms` ตาม ADR-19 หัวข้อ 8) **ไม่ได้คิดใหม่ที่นี่แม้แต่ตัวเดียว**
///
/// เส้นทางที่ port มาคือ **Apple bucket เท่านั้น** — เส้นทาง median/เมตร
/// (`estimateDistanceMeters` + hysteresis `enterMeters`/`exitMeters`) **ไม่มีตัวตน
/// ฝั่ง Swift** (ADR-21 หัวข้อ 2) เคสกลุ่ม B/C/F/H ของฝั่ง Dart จึงไม่มีคู่ที่นี่
/// โดยตั้งใจ ไม่ใช่เพราะลืม:
/// - **B (median ทน outlier)** · **C (hysteresis เชิงเมตร)** · **F
///   (`droppedNoTxPowerCount`)** — ทั้งสามผูกกับ `rssi`/`ibeaconTxPower` ซึ่ง
///   `push(key:bucket:)` ฝั่ง Swift ไม่รับเข้ามาตั้งแต่ระดับ signature
/// - **H (assert `exitMeters <= enterMeters`)** — ไม่มีพารามิเตอร์คู่นั้นให้ assert
/// - **I (ห้าม emit `unknown`)** — ฝั่ง Swift บังคับด้วย**ชนิดข้อมูล**แทน runtime
///   invariant (`ProximityBucket` ไม่มี case `unknown`) จึงเหลือแค่เทสต์ยืนยันว่า
///   enum ยังมี 3 case เท่าเดิม (`testBucketEnumHasNoUnknownCase`)
///
/// ## ห้ามรอเวลาจริงในไฟล์นี้เด็ดขาด
///
/// ทุกเคสที่เกี่ยวกับ `staleAfterMillis` เดินเวลาผ่าน [FakeClock] ที่ฉีดเข้า
/// `ProximityGate.init(clock:)` เท่านั้น — **ไม่มี `sleep` และไม่มี `expectation`
/// ที่ผูกกับ *เวลาของ gate* แม้แต่บรรทัดเดียว** (เหตุผลเดียวกับที่ ADR-21 หัวข้อ 2
/// ห้าม `ProximityGate.swift` เรียก `Date()` เอง)
///
/// ข้อยกเว้นเดียวคือ `testApplicationStateIsActiveIsFalseOffMainThread` ซึ่งใช้
/// `expectation` รอ **การสลับเธรด** ไม่ใช่รอเวลาผ่านไป — ไม่มีทางอื่นที่จะพิสูจน์
/// พฤติกรรมนอกเธรด main ได้ (`DispatchQueue.sync` บนคิว concurrent รันบนเธรดผู้เรียก
/// ซึ่งจะทำให้เคสนี้ไม่ได้ทดสอบอะไรเลย) และมันไม่ flaky ตามจังหวะเครื่อง
///
/// ## สิ่งที่ไฟล์นี้ **ไม่** พิสูจน์ (อ่านก่อนเชื่อ)
///
/// ไม่ได้รัน `CLLocationManager` จริง ไม่ได้พิสูจน์ว่า CoreLocation ยิง `didRange`
/// มาด้วยจังหวะไหน ไม่ได้พิสูจน์ว่า `allowsBackgroundLocationUpdates` มีผลกับ
/// *ranging* จริง (ADR-21 หัวข้อ 1 บันทึกไว้เองว่าไม่มีเอกสาร Apple ยืนยัน) และ
/// **ไม่ได้พิสูจน์ว่าชั้น 2 ทำงานได้บนเครื่องจริง** — ADR-21 ยังเป็น
/// `code-complete, unverified` และไฟล์นี้ไม่เปลี่ยนสถานะนั้น
///
/// รันด้วย: `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
///   -destination 'platform=iOS Simulator,name=iPhone 17'`

// MARK: - เครื่องมือร่วม

/// นาฬิกาปลอมที่เทสต์คุมเองทั้งหมด — คู่ขนานกับ `_FakeClock` ของ
/// `proximity_gate_test.dart` เป๊ะ ต่างแค่หน่วย (epoch millis แทน `DateTime`)
/// ตามสัญญาของ `ProximityGate.clock: () -> Int64`
final class FakeClock {
  private(set) var nowMillis: Int64

  init(startMillis: Int64 = 0) {
    self.nowMillis = startMillis
  }

  func now() -> Int64 { nowMillis }

  func advance(millis: Int64) { nowMillis += millis }
}

/// key ตัวอย่างที่ประกอบด้วย [ProximityKeyCodec] จริง ไม่ใช่สตริงมั่ว ๆ —
/// เพื่อให้เคสของ gate ใช้รูปแบบเดียวกับที่ `IBeaconRangingManager` ใช้จริง
private let sampleKey = ProximityKeyCodec.key(
  regionIdentifier: "bigc-ladprao",
  uuid: "7777772e-6b6b-6d63-6e2e-636f6d000001",
  major: 1,
  minor: 42
)

private let otherKey = ProximityKeyCodec.key(
  regionIdentifier: "bigc-ladprao",
  uuid: "7777772e-6b6b-6d63-6e2e-636f6d000001",
  major: 1,
  minor: 43
)

// MARK: - เส้นทาง Apple bucket: mode + tie-break + dwell

/// port ของกลุ่ม **E** (เส้นทาง iOS), **D** (dwell), **J[4]** และ **K.c**
/// (tie-break) จาก `proximity_gate_test.dart`
final class ProximityGateAppleBucketTests: XCTestCase {

  /// **กลุ่ม E ฝั่ง Dart:** "proximity = near ให้ bucket near โดยไม่แตะ
  /// ibeaconTxPower เลย"
  ///
  /// **ดัดแปลงอย่างไร:** ฝั่ง Swift **ไม่มี `txPower` ให้แตะตั้งแต่ระดับ signature**
  /// (`push(key:bucket:)` รับ bucket อย่างเดียว ตาม ADR-21 หัวข้อ 2) ข้อพิสูจน์
  /// "ไม่แตะ txPower" จึงเปลี่ยนรูปเป็นการยืนยันว่า **ไม่มีเส้นทางคำนวณระยะเกิดขึ้น
  /// เลย**: `medianMeters == nil` และหน้าต่างที่ถูกเติมคือหน้าต่าง **bucket**
  /// (`window: [ProximityBucket]`) ไม่ใช่หน้าต่างเมตรแบบฝั่ง Android
  func testAppleBucketIsUsedDirectlyWithoutAnyDistanceMath() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1)

    let transition = gate.push(key: sampleKey, bucket: .near)

    XCTAssertNotNil(transition)
    XCTAssertEqual(transition?.to, .near)
    XCTAssertNil(transition?.from, "sample แรกของ key นี้ยังไม่เคยมี bucket ที่ยืนยัน")
    XCTAssertEqual(transition?.reason, .closer)
    XCTAssertNil(
      transition?.medianMeters,
      "เส้นทาง Apple bucket ไม่คำนวณระยะเองเลย — medianMeters ต้อง nil เสมอ (ADR-21 หัวข้อ 2)"
    )

    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)
    XCTAssertEqual(
      gate.stateOf(key: sampleKey)?.window,
      [.near],
      "หน้าต่างที่ถูกเติมคือ bucket ดิบของ Apple ไม่ใช่ระยะเป็นเมตร"
    )
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.lastSampleAt, 0)
  }

  /// invariant ของ **ADR-19 หัวข้อ 6(ช)** ("ห้าม emit `unknown` ออก public API")
  /// ฝั่ง Swift บังคับด้วยชนิดข้อมูล — ถ้าวันหนึ่งมีใครเติม case `unknown` เข้า
  /// `ProximityBucket` เพื่อความสะดวก เทสต์นี้จะแดงทันทีก่อนที่ค่านั้นจะรั่วออกไป
  /// ทาง `push`/`sweepStale`/`currentBucket` ได้
  func testBucketEnumHasNoUnknownCase() {
    XCTAssertEqual(ProximityBucket.allCases, [.immediate, .near, .far])
    XCTAssertNil(ProximityBucket.fromWireName("unknown"))
    XCTAssertNil(ProximityBucket.fromWireName(nil))
  }

  /// **หัวใจข้อ 2 ของรอบนี้: candidate = mode ของหน้าต่าง ไม่ใช่ค่าล่าสุด**
  ///
  /// นี่คือกฎที่ **ADR-19 หัวข้อ 4 ข้อ 1 เพิ่มเข้ามาหลังรอบ implement แรก** (ก่อน
  /// หน้านั้นเส้นทาง iOS ใช้ bucket ของ Apple ตรง ๆ ทำให้ไม่มี hysteresis เลย
  /// ผสมกับกฎ "ไกลขึ้นไม่ต้อง dwell" ของ 6(ค) แล้ว flap ได้ทุกไม่กี่วินาที)
  func testCandidateIsWindowModeNotLatestSample() {
    let clock = FakeClock()
    // windowSize = 5 (ค่า default จาก ADR-19 หัวข้อ 8) พอดีกับ 5 sample ด้านล่าง
    // จึงไม่มี eviction เกิดขึ้นระหว่างทาง
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1)

    for bucket in [ProximityBucket.immediate, .near, .near, .near, .far] {
      _ = gate.push(key: sampleKey, bucket: bucket)
    }

    XCTAssertEqual(
      gate.stateOf(key: sampleKey)?.window,
      [.immediate, .near, .near, .near, .far],
      "หน้าต่างต้องเก็บตามลำดับที่เข้ามา ตัวใหม่สุดอยู่ท้าย"
    )
    XCTAssertEqual(
      gate.currentBucket(key: sampleKey),
      .near,
      "mode ของหน้าต่างคือ near (3 จาก 5) — sample ล่าสุดเป็น far แต่ห้ามชนะ"
    )
  }

  /// **J[4] ฝั่ง Dart:** "เส้นทาง iOS ต้องไม่ flap — near ×4 แล้ว far ×1 ต้องยังเป็น
  /// near" (port ตรง ไม่ดัดแปลง)
  func testSingleFarOutlierDoesNotFlipConfirmedNear() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1)

    for _ in 0..<4 {
      _ = gate.push(key: sampleKey, bucket: .near)
    }
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)

    let farTransition = gate.push(key: sampleKey, bucket: .far)

    XCTAssertNil(farTransition, "ไม่มี transition — mode ของหน้าต่างยังเป็น near 4 ต่อ 1")
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)
  }

  /// **เทสต์ที่สำคัญที่สุดของรอบนี้ (ข้อ 3 ของโจทย์): เสมอกันต้องเลือกตัวที่ไกลกว่า**
  ///
  /// ล็อกหลัก **ต้นทุนไม่สมมาตรของ ADR-19 หัวข้อ 6(ค)** ("การประกาศ 'ใกล้' ผิดพลาด
  /// แพงกว่า จึงไม่ควรชนะเมื่อข้อมูลก้ำกึ่งพอ ๆ กัน") — ถ้าใครเผลอแก้ `>` เป็น `<`
  /// ใน `bucketCandidate` หรือเปลี่ยนไปใช้ "ตัวที่เจอก่อน" **จะไม่มีอะไรฟ้องเลย**
  /// นอกจากเทสต์นี้: ผลลัพธ์ยังดูสมเหตุสมผลทุกทาง แค่ประกาศ "ใกล้" บ่อยเกินจริง
  ///
  /// ตรวจที่ pure function ตรง ๆ ทุกสาขา (`bucketCandidate` เป็น `internal static`
  /// เพื่อการนี้โดยเฉพาะ ตามคอมเมนต์ในตัวมันเอง)
  func testTieBreakAlwaysPicksTheFartherBucket() {
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.immediate, .far]),
      .far,
      "1 ต่อ 1 ระหว่าง immediate/far -> ต้องได้ far"
    )
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.near, .far]),
      .far,
      "1 ต่อ 1 ระหว่าง near/far -> ต้องได้ far"
    )
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.immediate, .near]),
      .near,
      "1 ต่อ 1 ระหว่าง immediate/near -> ต้องได้ near (ไกลกว่าในคู่นี้)"
    )
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.immediate, .near, .far]),
      .far,
      "เสมอกันสามทาง -> ต้องได้ far ซึ่งไกลที่สุด"
    )
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.far, .immediate]),
      .far,
      "ลำดับที่เข้ามาต้องไม่มีผลกับ tie-break — สลับอินพุตแล้วต้องได้ค่าเดิม"
    )
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.near, .immediate]),
      .near,
      "สลับอินพุตของคู่ immediate/near แล้วต้องได้ near เหมือนเดิม"
    )

    // เสียงข้างมากยังต้องชนะตามปกติเมื่อไม่เสมอ — กันไม่ให้ใครแก้เป็น
    // "เลือกตัวที่ไกลที่สุดเสมอ" แล้วเทสต์ข้างบนยังเขียวอยู่
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.immediate, .immediate, .far]),
      .immediate,
      "2 ต่อ 1 ไม่ใช่เสมอ -> เสียงข้างมาก (immediate) ต้องชนะ"
    )
    XCTAssertEqual(
      ProximityGate.bucketCandidate(window: [.near, .near, .far, .immediate]),
      .near
    )
  }

  /// **K.c ฝั่ง Dart:** `window [immediate, immediate, near, near, far]` -> candidate
  /// ต้องเป็น `near` — ตรวจผ่าน `push()` จริงทั้งเส้นทาง ไม่ใช่แค่ pure function
  /// (พิสูจน์ว่ากฎ tie-break ถูกเรียกใช้จริงใน `push` ไม่ใช่แค่มีอยู่)
  func testTieBreakThroughFullPushPath() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1)

    for bucket in [ProximityBucket.immediate, .immediate, .near, .near, .far] {
      _ = gate.push(key: sampleKey, bucket: bucket)
    }

    XCTAssertEqual(
      gate.stateOf(key: sampleKey)?.window,
      [.immediate, .immediate, .near, .near, .far]
    )
    XCTAssertEqual(
      gate.currentBucket(key: sampleKey),
      .near,
      "immediate 2 เสมอกับ near 2 -> เลือก near ที่ไกลกว่า (ADR-19 หัวข้อ 4 ข้อ 1)"
    )
  }

  /// หน้าต่างต้องไม่โตเกิน `windowSize` และต้องตัด**หัว** (ตัวเก่าสุด) ทิ้ง —
  /// ถ้าตัดผิดด้าน mode จะคำนวณจากข้อมูลที่ผิดยุคโดยไม่มีอะไรฟ้อง
  func testWindowEvictsOldestFirstAndNeverExceedsWindowSize() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 3, dwellSamples: 1)

    for bucket in [ProximityBucket.far, .far, .immediate, .near, .near] {
      _ = gate.push(key: sampleKey, bucket: bucket)
    }

    XCTAssertEqual(
      gate.stateOf(key: sampleKey)?.window,
      [.immediate, .near, .near],
      "เหลือแค่ 3 ตัวท้าย — far สองตัวแรกถูกตัดจากหัว"
    )
  }

  /// **กลุ่ม D ฝั่ง Dart (dwell):** 2 sample ที่ใกล้กว่าแล้วหลุดก่อนครบ
  /// `dwellSamples` (3) -> **ไม่มี transition เลย และ pending ถูกล้าง**
  ///
  /// **ดัดแปลงอย่างไร:** ฝั่ง Dart ใช้ `rssi` สองค่า (~2.51 m กับ ~6.31 m) แทน
  /// "ใกล้"/"ไกล" — ที่นี่ใช้ bucket ตรง ๆ (`.near` / `.far`) เพราะไม่มีเมตร ·
  /// `windowSize = 1` ตามฝั่ง Dart เป๊ะ เพื่อแยกทดสอบ dwell ล้วน ๆ ไม่ให้ปนกับผล
  /// ของ mode · `dwellSamples` ใช้ค่า default (3) ตรง ๆ ตามที่โจทย์ระบุ
  func testDwellNotReachedThenFallsOutProducesNoTransitionAndClearsPending() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1)

    // priming: ยืนยัน baseline far ก่อน (เหตุผลเดียวกับฝั่ง Dart — ไม่ assert ผล
    // ของ push นี้ นอกจากว่ามันทำให้ confirmedBucket เป็น far จริง)
    _ = gate.push(key: sampleKey, bucket: .far)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .far)

    let t1 = gate.push(key: sampleKey, bucket: .near)
    let t2 = gate.push(key: sampleKey, bucket: .near)
    XCTAssertNil(t1)
    XCTAssertNil(t2)
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.pendingCloserBucket, .near)
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.pendingCloserCount, 2)

    // "หลุด" — กลับไป far ก่อนครบ 3 sample ติดกัน
    let t3 = gate.push(key: sampleKey, bucket: .far)

    XCTAssertNil(t3, "candidate กลับไปเท่ากับ bucket ที่ยืนยันอยู่ -> ไม่มีการเปลี่ยนแปลง")
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .far, "ไม่เคยขยับไป near เลย")
    XCTAssertNil(gate.stateOf(key: sampleKey)?.pendingCloserBucket, "pending ต้องถูกล้าง")
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.pendingCloserCount, 0)
  }

  /// dwell ครบพอดีที่ sample ที่ 3 (ไม่ใช่ที่ 2 และไม่ใช่ที่ 4) — ล็อกตัวเลข
  /// `dwellSamples = 3` ของ ADR-19 หัวข้อ 8 ไว้ตรง ๆ
  func testCloserConfirmsExactlyOnTheThirdConsecutiveSample() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1)

    _ = gate.push(key: sampleKey, bucket: .far)

    XCTAssertNil(gate.push(key: sampleKey, bucket: .near), "sample ที่ 1 ยังไม่ครบ dwell")
    XCTAssertNil(gate.push(key: sampleKey, bucket: .near), "sample ที่ 2 ยังไม่ครบ dwell")

    let confirmed = gate.push(key: sampleKey, bucket: .near)

    XCTAssertEqual(confirmed?.to, .near)
    XCTAssertEqual(confirmed?.from, .far)
    XCTAssertEqual(confirmed?.reason, .closer)
    XCTAssertNil(confirmed?.medianMeters)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.pendingCloserCount, 0, "pending ถูกล้างหลังยืนยัน")
  }

  /// **ข้อ 5 ของโจทย์ (ครึ่งแรก): ไกลขึ้นยืนยันทันที ไม่ต้อง dwell**
  ///
  /// ADR-19 หัวข้อ 6(ค): "การประกาศ 'ไกล' ช้าไปเป็นแค่ความไม่แม่นยำเล็กน้อย
  /// ไม่มีผลกระทบธุรกิจที่แพงเท่ากัน" — ความไม่สมมาตรนี้ต้องมีเทสต์คู่กับ
  /// tie-break เสมอ ไม่งั้นเหลือแค่ครึ่งเดียวของกฎ
  func testFartherConfirmsImmediatelyWithoutDwell() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1)

    for _ in 0..<3 {
      _ = gate.push(key: sampleKey, bucket: .near)
    }
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)

    // ครั้งเดียวพอ — ไม่ต้องรอครบ dwellSamples เหมือนทางใกล้ขึ้น
    let transition = gate.push(key: sampleKey, bucket: .far)

    XCTAssertEqual(transition?.from, .near)
    XCTAssertEqual(transition?.to, .far)
    XCTAssertEqual(transition?.reason, .farther)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .far)
  }

  /// **ข้อ 5 ของโจทย์ (ครึ่งหลัง): sample แรกของ key ใช้ baseline = far**
  ///
  /// ADR-19 หัวข้อ 6(ซ) — candidate แรกที่เป็น `far` ยืนยันได้ทันทีเหมือน "ไกลกว่า"
  /// ปกติ ส่วน candidate แรกที่เป็น `near`/`immediate` **ยังต้อง dwell**
  func testFirstSampleUsesFarAsBaseline() {
    let clock = FakeClock()
    let farGate = ProximityGate(clock: clock.now, windowSize: 1)

    let first = farGate.push(key: sampleKey, bucket: .far)

    XCTAssertNotNil(first, "far ตัวแรกของ key ต้องยืนยันทันที (baseline เทียบเท่า far)")
    XCTAssertNil(first?.from)
    XCTAssertEqual(first?.to, .far)
    XCTAssertEqual(first?.reason, .farther)

    // ตรงข้าม: near ตัวแรกของ key ต้องเงียบเพราะยังต้อง dwell
    let nearGate = ProximityGate(clock: clock.now, windowSize: 1)
    XCTAssertNil(
      nearGate.push(key: otherKey, bucket: .near),
      "near ตัวแรกยังต้อง dwell — ต้นทุนของการประกาศ 'ใกล้' ผิดพลาดแพงกว่า"
    )
    XCTAssertNil(nearGate.currentBucket(key: otherKey))
  }

  /// แต่ละ key ต้องมีสถานะของตัวเองแยกกันเด็ดขาด — บั๊กชนิด "ทุกบีคอนใช้ state
  /// เดียวกัน" คือสิ่งที่ ADR-21 หัวข้อ 7 ข้อ 1 เสียเวลาสอบสวนทั้งรอบฝั่ง Android
  func testStatesAreIsolatedPerKey() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, dwellSamples: 1)

    _ = gate.push(key: sampleKey, bucket: .near)
    _ = gate.push(key: otherKey, bucket: .far)

    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)
    XCTAssertEqual(gate.currentBucket(key: otherKey), .far)
    XCTAssertEqual(gate.snapshotStates().map(\.key), [sampleKey, otherKey], "ลำดับที่เห็น key ครั้งแรก")
  }
}

// MARK: - stale (นาฬิกาปลอมล้วน)

/// port ของกลุ่ม **G**, **J[1]**, **K.a**, **K.b** จาก `proximity_gate_test.dart`
final class ProximityGateStaleTests: XCTestCase {

  /// **กลุ่ม G + K.b ฝั่ง Dart รวมเป็นเคสเดียว:** เลยเวลา `staleAfterMillis` ->
  /// `push()` คืน transition ที่ `to == nil` reason `stale` **และ sample ที่จุด
  /// ชนวนถูกทิ้ง ไม่ประมวลผลต่อ**
  ///
  /// การทิ้ง sample เป็น **design choice ที่บันทึกไว้ใน ADR-19 หัวข้อ 7** (push()
  /// คืนได้ทีละ 1 transition) — ล็อกไว้ที่นี่เพื่อไม่ให้ใครมาแก้ "ให้ดีขึ้น" โดย
  /// ไม่รู้ตัว: หลัง transition state ต้องว่างเปล่าสนิท ไม่ใช่มี `.near` ค้างอยู่
  /// ในหน้าต่างจาก sample ที่จุดชนวน
  func testStaleEmitsTransitionAndDiscardsTriggeringSample() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .near)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)

    clock.advance(millis: 11_000)  // เกิน staleAfter โดยไม่มีการรอเวลาจริงเลย

    let transition = gate.push(key: sampleKey, bucket: .near)

    XCTAssertEqual(transition?.from, .near)
    XCTAssertNil(transition?.to, "to ต้องเป็น nil — 'วัดไม่ได้' ไม่ใช่ 'ไกล' (ADR-19 6(ฉ))")
    XCTAssertEqual(transition?.reason, .stale)
    XCTAssertNil(transition?.medianMeters)
    XCTAssertNil(gate.currentBucket(key: sampleKey))

    XCTAssertEqual(
      gate.stateOf(key: sampleKey),
      ProximityKeyState(),
      "sample ที่จุดชนวน stale ต้องถูกทิ้ง — state ต้องว่างเปล่าทุกฟิลด์"
    )
  }

  /// ขอบเขตของ `staleAfterMillis`: `== staleAfter` **ยังไม่ stale** (`>` เท่านั้น)
  /// ตรงกับ `_resetIfStale` ฝั่ง Dart ที่คืน "ไม่ stale" เมื่อ `<= staleAfter`
  func testExactlyAtStaleThresholdIsNotStaleYet() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .near)
    clock.advance(millis: 10_000)

    XCTAssertNil(
      gate.push(key: sampleKey, bucket: .near),
      "ห่างเท่ากับ staleAfter พอดี -> ยังไม่ stale และ candidate ยังเท่าเดิม"
    )
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)

    clock.advance(millis: 10_001)
    XCTAssertEqual(
      gate.push(key: sampleKey, bucket: .near)?.reason,
      .stale,
      "เกินไป 1 ms -> stale"
    )
  }

  /// **J[1] เวอร์ชัน iOS — sample ที่ถูกทิ้งห้ามต่ออายุ staleness**
  ///
  /// **ดัดแปลงอย่างไร:** บนเส้นทางนี้ sample ที่ถูกทิ้งคือ **`bucket == nil`**
  /// (= `CLProximity.unknown`) ไม่ใช่ `txPower == null` แบบฝั่ง Android —
  /// `IBeaconRangingManager.proximityBucket(_:)` แปลง `.unknown` เป็น `nil`
  /// **ไม่ใช่ `.far`** ตาม ADR-19 หัวข้อ 6(ง)
  ///
  /// ถ้า sample ที่ t=5s เผลอไปขยับ `lastSampleAt` (บั๊กเดิมของฝั่ง Dart ที่แก้ใน
  /// `ea7e12c`) ช่องว่างที่ t=11s จะเหลือแค่ 6 วินาที = ไม่ stale = บีคอนที่เงียบ
  /// สนิทแต่ยังมี `unknown` ไหลเข้ามาจะ **ค้าง `near` ตลอดไป**
  func testDroppedUnknownSampleDoesNotRenewStaleness() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .near)  // t=0 ยืนยัน near
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)
    let stateAtT0 = gate.stateOf(key: sampleKey)
    XCTAssertEqual(stateAtT0?.lastSampleAt, 0)

    clock.advance(millis: 5_000)
    let dropped = gate.push(key: sampleKey, bucket: nil)  // t=5s (ยังไม่ stale)

    XCTAssertNil(dropped)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near, "ยังไม่หลุด")
    // ADR-21 หัวข้อ 2 บังคับคำต่อคำ: "ทิ้ง sample **ห้ามแตะ state แม้แต่ฟิลด์เดียว**"
    // เทียบทั้ง struct ทีเดียว (Equatable) แทนการไล่เช็คทีละฟิลด์ซึ่งลืมได้
    XCTAssertEqual(
      gate.stateOf(key: sampleKey),
      stateAtT0,
      "unknown ต้องไม่แตะ state แม้แต่ฟิลด์เดียว (รวม lastSampleAt/window/pending)"
    )

    clock.advance(millis: 6_000)  // now = t=11s เทียบกับ lastSampleAt ที่ยังค้างที่ t=0
    let transition = gate.push(key: sampleKey, bucket: nil)

    XCTAssertEqual(
      transition?.reason,
      .stale,
      "ช่องว่างจริงต้องนับจาก t=0 (11s > 10s) ไม่ใช่จาก t=5s ที่เป็น sample ที่ถูกทิ้ง"
    )
    XCTAssertEqual(transition?.from, .near)
    XCTAssertNil(transition?.to)
  }

  /// `unknown` รัว ๆ ตั้งแต่ต้นต้องไม่สร้างสถานะอะไรเลย — คู่ขนานกับ **K.d**
  /// ฝั่ง Dart (ที่นั่นเช็ค `droppedNoTxPowerCount == 0` ด้วย ส่วนฝั่ง Swift
  /// **ไม่มี counter นั้นตั้งแต่แรก** ตามหมายเหตุข้อ 1 ของ ADR-21)
  func testUnknownOnlyStreamNeverCreatesState() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now)

    for _ in 0..<10 {
      XCTAssertNil(gate.push(key: sampleKey, bucket: nil))
      clock.advance(millis: 1_000)
    }

    XCTAssertNil(gate.stateOf(key: sampleKey))
    XCTAssertNil(gate.currentBucket(key: sampleKey))
    XCTAssertTrue(gate.snapshotStates().isEmpty, "ไม่มี entry ขยะค้างไว้ให้ต้อง evict ทีหลัง")
  }

  /// **K.a ฝั่ง Dart:** stale ขณะ **pending dwell** (ยังไม่เคย confirm) ->
  /// **ไม่มี transition เลย** และ pending **เริ่มนับใหม่จาก 1 ไม่ใช่สานต่อจาก 2**
  ///
  /// เคสนี้ล็อกบั๊ก 2/4 ของฝั่ง Dart (`ea7e12c`) ไปพร้อมกัน: การรีเซ็ตตอนหลุด
  /// stale ต้องล้าง **ทุกฟิลด์** ไม่ใช่แค่ `confirmedBucket`
  func testStaleWhilePendingDwellRestartsCountFromOneWithNoTransition() {
    let clock = FakeClock()
    // dwellSamples ใช้ค่า default (3) — ต้อง > 1 เพื่อให้มีสถานะ "pending" ให้ทดสอบ
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    XCTAssertNil(gate.push(key: sampleKey, bucket: .near))
    XCTAssertNil(gate.push(key: sampleKey, bucket: .near))
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.pendingCloserCount, 2)
    XCTAssertNil(gate.currentBucket(key: sampleKey), "ไม่เคย confirm มาก่อน")

    clock.advance(millis: 11_000)

    let transition = gate.push(key: sampleKey, bucket: .near)

    XCTAssertNil(transition, "ไม่มีอะไรให้ประกาศว่าหลุด เพราะไม่เคย confirm มาก่อน")
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.pendingCloserBucket, .near)
    XCTAssertEqual(
      gate.stateOf(key: sampleKey)?.pendingCloserCount,
      1,
      "เริ่มนับใหม่จาก 1 ไม่ใช่สานต่อจาก 2"
    )
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.window, [.near], "หน้าต่างเก่าถูกล้างไปด้วย")
    XCTAssertNil(gate.currentBucket(key: sampleKey))
  }
}

// MARK: - sweepStale()

/// port ของ **J[3]** ฝั่ง Dart + ข้อ 9 ของโจทย์ (key ที่ยัง pending ต้องถูกล้าง
/// เงียบ ๆ · เรียกซ้ำต้องไม่ยิงอะไรอีก)
final class ProximityGateSweepStaleTests: XCTestCase {

  /// เคสหลักของฟีเจอร์: **"ลูกค้าเดินออกจากร้าน"** — ไม่มี sample ใหม่ให้ `push()`
  /// จับความเงียบได้เองอีกเลย ถ้าไม่มี `sweepStale()` key นั้นจะไม่มีวันได้
  /// transition `to: nil` (บั๊กจากรอบ implement แรกฝั่ง Dart)
  func testSweepEmitsForConfirmedKeyAndSilentlyClearsPendingKey() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    // key ที่ 1: confirm ได้ทันทีเพราะ far ใช้ baseline far (ADR-19 6(ซ))
    XCTAssertNotNil(gate.push(key: sampleKey, bucket: .far))
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .far)

    // key ที่ 2: ค้างอยู่ที่ pending dwell (1 จาก 3) ยังไม่เคย confirm
    XCTAssertNil(gate.push(key: otherKey, bucket: .near))
    XCTAssertEqual(gate.stateOf(key: otherKey)?.pendingCloserCount, 1)

    clock.advance(millis: 11_000)
    let transitions = gate.sweepStale()  // ไม่มี push() ใด ๆ ระหว่างนี้เลย

    XCTAssertEqual(transitions.count, 1, "เฉพาะ key ที่เคย confirm เท่านั้นที่มีอะไรให้ประกาศ")
    XCTAssertEqual(transitions.first?.key, sampleKey)
    XCTAssertEqual(transitions.first?.from, .far)
    XCTAssertNil(transitions.first?.to)
    XCTAssertEqual(transitions.first?.reason, .stale)
    XCTAssertNil(transitions.first?.medianMeters)

    XCTAssertNil(gate.currentBucket(key: sampleKey))
    XCTAssertEqual(
      gate.stateOf(key: otherKey),
      ProximityKeyState(),
      "key ที่ยัง pending ต้องถูกล้างเงียบ ๆ — ล้างจริง แต่ไม่มี transition"
    )
  }

  /// เรียกซ้ำทันทีต้องไม่ยิงอะไรอีก — กันบั๊ก "stale ซ้ำทุก callback" ซึ่งบน
  /// เครื่องจริงจะกลายเป็นสแปมบรรทัดหลักฐาน/notification ที่อ่านไม่ออกว่าเกิดอะไร
  func testSweepIsIdempotentWithinTheSameSilence() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .near)
    clock.advance(millis: 11_000)

    XCTAssertEqual(gate.sweepStale().count, 1)
    XCTAssertTrue(gate.sweepStale().isEmpty, "เรียกซ้ำทันทีต้องเงียบ")

    clock.advance(millis: 60_000)
    XCTAssertTrue(
      gate.sweepStale().isEmpty,
      "เงียบต่ออีกนานก็ยังต้องไม่ยิงซ้ำ — state ถูกล้างไปแล้วตั้งแต่ครั้งแรก"
    )
  }

  /// key ที่ยังสดต้องไม่ถูกกวาดไปด้วย
  func testSweepLeavesFreshKeysAlone() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .near)
    clock.advance(millis: 9_000)

    XCTAssertTrue(gate.sweepStale().isEmpty)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .near)
  }
}

// MARK: - ProximityKeyCodec

/// pure function ล้วน (ADR-21 หัวข้อ 3) — ทดสอบได้ 100% โดยไม่ต้องมีอุปกรณ์
final class ProximityKeyCodecTests: XCTestCase {

  func testRoundTripOfPlainRegionIdentifier() {
    let key = ProximityKeyCodec.key(
      regionIdentifier: "bigc-ladprao",
      uuid: "7777772e-6b6b-6d63-6e2e-636f6d000001",
      major: 1,
      minor: 42
    )

    XCTAssertEqual(key, "bigc-ladprao|7777772e-6b6b-6d63-6e2e-636f6d000001|1|42")

    let parsed = ProximityKeyCodec.parse(key)
    XCTAssertEqual(parsed?.regionIdentifier, "bigc-ladprao")
    XCTAssertEqual(parsed?.uuid, "7777772e-6b6b-6d63-6e2e-636f6d000001")
    XCTAssertEqual(parsed?.major, 1)
    XCTAssertEqual(parsed?.minor, 42)
  }

  /// uuid ถูกบังคับเป็นตัวพิมพ์เล็กตอนประกอบ (ADR-21 หัวข้อ 3) — ไม่งั้นบีคอนตัว
  /// เดียวกันจะกลายเป็นคนละ key เมื่อผู้เรียกส่งตัวพิมพ์ใหญ่มา
  func testUuidIsLowercasedWhenBuildingKey() {
    let key = ProximityKeyCodec.key(
      regionIdentifier: "r",
      uuid: "7777772E-6B6B-6D63-6E2E-636F6D000001",
      major: 1,
      minor: 2
    )

    XCTAssertEqual(key, "r|7777772e-6b6b-6d63-6e2e-636f6d000001|1|2")
    XCTAssertEqual(
      key,
      ProximityKeyCodec.key(
        regionIdentifier: "r",
        uuid: "7777772e-6b6b-6d63-6e2e-636f6d000001",
        major: 1,
        minor: 2
      )
    )
  }

  /// **เคสที่โจทย์เจาะจงให้ล็อก: regionIdentifier ที่มี `|` อยู่ในตัว**
  ///
  /// `parse` **ตัดจากท้าย** เพราะสามส่วนท้าย (uuid/major/minor) มีรูปแบบตายตัว
  /// ส่วน `regionIdentifier` เป็นสตริงอิสระที่ host app ตั้งเอง (ADR-8 ใช้เป็น
  /// รหัสสาขา) ถ้าตัดจากหัว key ของ region ที่ชื่อมี `|` จะถอดผิด**เงียบ ๆ**
  /// เทสต์นี้ล็อกพฤติกรรมนั้นไว้ ไม่ใช่แค่ยืนยันว่า "ไม่ crash"
  func testRegionIdentifierContainingSeparatorSurvivesRoundTrip() {
    let region = "bigc|ladprao|floor-3"
    let key = ProximityKeyCodec.key(
      regionIdentifier: region,
      uuid: "7777772e-6b6b-6d63-6e2e-636f6d000001",
      major: 7,
      minor: 8
    )

    let parsed = ProximityKeyCodec.parse(key)

    XCTAssertEqual(parsed?.regionIdentifier, region, "ต้องได้ชื่อ region กลับมาครบทั้ง 3 ท่อน")
    XCTAssertEqual(parsed?.uuid, "7777772e-6b6b-6d63-6e2e-636f6d000001")
    XCTAssertEqual(parsed?.major, 7)
    XCTAssertEqual(parsed?.minor, 8)
  }

  /// region ว่างเปล่าก็ยังต้อง round-trip ได้ (`omittingEmptySubsequences: false`)
  func testEmptyRegionIdentifierRoundTrips() {
    let key = ProximityKeyCodec.key(regionIdentifier: "", uuid: "u", major: 0, minor: 0)

    XCTAssertEqual(key, "|u|0|0")
    let parsed = ProximityKeyCodec.parse(key)
    XCTAssertEqual(parsed?.regionIdentifier, "")
    XCTAssertEqual(parsed?.major, 0)
    XCTAssertEqual(parsed?.minor, 0)
  }

  /// ขอบของ `UInt16` ทั้งสองด้าน — major/minor ของ iBeacon เป็น 16 บิตเต็ม
  func testBoundaryValuesOfMajorAndMinor() {
    let key = ProximityKeyCodec.key(regionIdentifier: "r", uuid: "u", major: 65535, minor: 65535)

    let parsed = ProximityKeyCodec.parse(key)
    XCTAssertEqual(parsed?.major, 65535)
    XCTAssertEqual(parsed?.minor, 65535)
  }

  /// **เคสพัง — ต้องคืน `nil` ทั้งก้อน ห้ามเดาค่าแทน**
  func testMalformedKeysReturnNilInsteadOfGuessing() {
    let malformed: [String: String] = [
      "": "สตริงว่าง",
      "bigc-ladprao": "มีท่อนเดียว",
      "bigc|uuid|1": "ขาดไป 1 ท่อน (3 < 4)",
      "bigc|uuid|abc|42": "major ไม่ใช่ตัวเลข",
      "bigc|uuid|1|xyz": "minor ไม่ใช่ตัวเลข",
      "bigc|uuid|1|65536": "minor ล้น UInt16",
      "bigc|uuid|65536|1": "major ล้น UInt16",
      "bigc|uuid|-1|1": "major ติดลบ",
      "bigc|uuid|1|-1": "minor ติดลบ",
      "bigc|uuid|1|4 2": "minor มีช่องว่างปน",
      "bigc|uuid|1|": "minor ว่าง",
    ]

    for (key, reason) in malformed {
      XCTAssertNil(ProximityKeyCodec.parse(key), "ต้องคืน nil: \(reason) — \"\(key)\"")
    }
  }

  /// `separator` ต้องเป็นตัวเดียวกับที่ประกอบ key จริง — ประกาศไว้ที่เดียวเพื่อ
  /// ไม่ให้มีสตริง `"|"` ลอยอยู่หลายที่แล้ว drift กัน
  func testSeparatorIsPipe() {
    XCTAssertEqual(ProximityKeyCodec.separator, "|")
  }
}

// MARK: - ProximityGateStore

/// ADR-21 หัวข้อ 3 — สถานะต้องรอดข้าม process ไม่งั้น `dwellSamples = 3`
/// **ไม่มีวันครบ** และ gate จะเงียบตลอดทั้งที่ผู้ใช้ยืนอยู่หน้าชั้นวาง
final class ProximityGateStoreTests: XCTestCase {

  /// suite ชั่วคราวต่อเคส — ไม่แตะ suite จริงของ SDK
  /// (`ProximityGateStore.suiteName`) และไม่แตะ `UserDefaults.standard`
  private var suiteName: String!
  private var defaults: UserDefaults!

  /// ชื่อคีย์เดียวกับ `ProximityGateStore.statesKey` ซึ่งเป็น `private` —
  /// จำเป็นต้องเขียนซ้ำที่นี่เพื่อ**ยัด JSON เสียหายเข้าไปตรง ๆ** ให้ `load()`
  /// อ่านเจอ (ไม่มีทางอื่นที่ไม่ต้องแก้โค้ด production) ถ้าวันหนึ่งชื่อคีย์ฝั่ง
  /// production เปลี่ยน เคส `testCorruptJson...` จะกลายเป็นเทสต์ที่ไม่ทดสอบอะไร
  /// เลย — `testCorruptJsonKeyConstantStillMatchesProduction` คอยกันข้อนั้น
  private let statesKeyMirror = "states"

  override func setUp() {
    super.setUp()
    suiteName = "beacon-kit-test-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  /// กันไม่ให้ [statesKeyMirror] drift จาก production เงียบ ๆ — เขียนผ่าน `save()`
  /// จริงแล้วยืนยันว่าอ่านเจอที่คีย์เดียวกับที่เคส JSON เสียหายใช้
  func testCorruptJsonKeyConstantStillMatchesProduction() {
    let store = ProximityGateStore(defaults: defaults)
    store.save([ProximityKeyEntry(key: "k", state: ProximityKeyState())])

    XCTAssertNotNil(
      defaults.string(forKey: statesKeyMirror),
      "ชื่อคีย์ที่เทสต์ใช้ยัด JSON เสียหายต้องตรงกับที่ production เขียนจริง"
    )
  }

  /// **ข้อ 11 ของโจทย์: round-trip ข้าม process จริง ๆ**
  ///
  /// จำลอง "process ตายกลางคัน" ด้วยการ **สร้าง `ProximityGateStore` และ
  /// `ProximityGate` ใหม่ทั้งคู่** (ไม่ reuse instance เดิมแม้แต่ตัวเดียว) —
  /// ถ้า dwell ไม่รอดข้าม process sample ถัดไปจะได้ `pendingCloserCount = 1`
  /// แทนที่จะ confirm และเทสต์จะแดง
  func testDwellSurvivesProcessRestartThroughStore() {
    let clockBeforeCrash = FakeClock()
    let storeBeforeCrash = ProximityGateStore(defaults: defaults)
    let gateBeforeCrash = ProximityGate(
      clock: clockBeforeCrash.now,
      windowSize: 1,
      dwellSamples: 3,
      staleAfterMillis: 10_000
    )

    XCTAssertNil(gateBeforeCrash.push(key: sampleKey, bucket: .near))
    XCTAssertNil(gateBeforeCrash.push(key: sampleKey, bucket: .near))
    XCTAssertEqual(gateBeforeCrash.stateOf(key: sampleKey)?.pendingCloserCount, 2)

    storeBeforeCrash.save(gateBeforeCrash.snapshotStates())
    XCTAssertNil(storeBeforeCrash.lastError, "การเขียนต้องไม่มี error")

    // ---- process ตาย แล้วระบบสร้างใหม่ ----
    let clockAfterRelaunch = FakeClock(startMillis: 1_000)
    let storeAfterRelaunch = ProximityGateStore(defaults: defaults)
    let gateAfterRelaunch = ProximityGate(
      clock: clockAfterRelaunch.now,
      windowSize: 1,
      dwellSamples: 3,
      staleAfterMillis: 10_000
    )

    let restored = storeAfterRelaunch.load()
    XCTAssertNil(storeAfterRelaunch.lastError, "การอ่านต้องไม่มี error")
    XCTAssertEqual(restored.count, 1)
    XCTAssertEqual(restored.first?.key, sampleKey)
    XCTAssertEqual(restored.first?.state.pendingCloserCount, 2)
    XCTAssertEqual(restored.first?.state.pendingCloserBucket, .near)
    XCTAssertEqual(restored.first?.state.window, [.near])
    XCTAssertEqual(restored.first?.state.lastSampleAt, 0)

    gateAfterRelaunch.restoreStates(restored)

    let transition = gateAfterRelaunch.push(key: sampleKey, bucket: .near)

    XCTAssertEqual(
      transition?.to,
      .near,
      "sample ที่ 3 ต้อง confirm ได้ทันที — พิสูจน์ว่า dwell ไม่รีเซ็ตตอน process ตาย"
    )
    XCTAssertEqual(transition?.reason, .closer)
    XCTAssertNil(transition?.from)
  }

  /// ลำดับของ key และลำดับใน window ต้องรอดข้าม process ด้วย — ถ้าลำดับ window
  /// สลับ การตัดหัวรอบถัดไปจะตัดผิดตัวโดยไม่มีอะไรฟ้อง
  func testOrderOfKeysAndWindowSurvivesRoundTrip() {
    let entries = [
      ProximityKeyEntry(
        key: "r|u|1|1",
        state: ProximityKeyState(
          confirmedBucket: .near,
          pendingCloserBucket: .immediate,
          pendingCloserCount: 2,
          window: [.far, .near, .immediate],
          lastSampleAt: 1_234_567_890_123
        )
      ),
      ProximityKeyEntry(
        key: "r|u|1|2",
        state: ProximityKeyState(window: [.far])
      ),
    ]

    let store = ProximityGateStore(defaults: defaults)
    store.save(entries)
    let loaded = ProximityGateStore(defaults: defaults).load()

    XCTAssertEqual(loaded, entries, "ทุกฟิลด์และทุกลำดับต้องเท่าเดิมเป๊ะ")
    XCTAssertEqual(loaded.map(\.key), ["r|u|1|1", "r|u|1|2"])
    XCTAssertEqual(loaded.first?.state.window, [.far, .near, .immediate])
  }

  /// **ข้อ 11 ครึ่งหลัง: JSON เสียหาย -> คืนว่าง และ `lastError` ต้องไม่ nil**
  ///
  /// ADR-21 หัวข้อ 7 ข้อ 2 (บทเรียนตรงจากรอบ Android): "เริ่มนับใหม่" เงียบ ๆ
  /// **แยกไม่ออกจาก "ไม่มีบีคอนอยู่ใกล้"** ในไฟล์หลักฐาน — ความล้มเหลวจึงต้องมี
  /// ร่องรอยเสมอ
  func testCorruptJsonReturnsEmptyAndRecordsLastError() {
    defaults.set("{ นี่ไม่ใช่ JSON ที่ถอดได้", forKey: statesKeyMirror)

    let store = ProximityGateStore(defaults: defaults)
    let loaded = store.load()

    XCTAssertTrue(loaded.isEmpty, "อ่านไม่ออก -> เริ่มนับใหม่ ไม่ใช่เดาค่า")
    XCTAssertNotNil(store.lastError, "ห้ามล้มเหลวเงียบ ๆ (ADR-21 หัวข้อ 7 ข้อ 2)")
    XCTAssertTrue(
      store.lastError?.hasPrefix("load:unparsable") ?? false,
      "lastError ต้องบอกได้ว่าพังที่ขั้นไหน — ได้: \(store.lastError ?? "nil")"
    )
  }

  /// JSON ที่ถอดออกได้แต่ผิดรูป (object แทน array) ก็ต้องนับเป็นความล้มเหลว
  func testJsonOfWrongShapeAlsoRecordsLastError() {
    defaults.set("{\"states\":[]}", forKey: statesKeyMirror)

    let store = ProximityGateStore(defaults: defaults)

    XCTAssertTrue(store.load().isEmpty)
    XCTAssertNotNil(store.lastError)
  }

  /// **"ไม่มีอะไรเก็บไว้" ต้องไม่ถูกนับเป็นความล้มเหลว** — ความต่างเดียวกับ
  /// `[]` vs `<read-failed:...>` ของ ADR-17 ถ้าแยกไม่ออก บรรทัดหลักฐานจะฟ้อง
  /// error ทุกครั้งที่แอปเพิ่งติดตั้งใหม่
  func testEmptyStoreIsNotAnError() {
    let freshStore = ProximityGateStore(defaults: defaults)
    XCTAssertTrue(freshStore.load().isEmpty, "ยังไม่เคยเขียนอะไรลงไปเลย")
    XCTAssertNil(freshStore.lastError)

    freshStore.save([])
    let afterEmptySave = ProximityGateStore(defaults: defaults)
    XCTAssertTrue(afterEmptySave.load().isEmpty)
    XCTAssertNil(afterEmptySave.lastError, "\"[]\" คือ 'ไม่มีอะไรเก็บไว้' ไม่ใช่ 'ถอดไม่ออก'")
  }

  /// `resetLastError()` ต้องล้างจริง — instance ของ store ฝั่ง iOS มีอายุเท่ากับ
  /// process ถ้าไม่ล้าง error จากรอบที่แล้วจะติดค้างในบรรทัดหลักฐานของรอบที่ปกติดี
  func testResetLastErrorClearsPreviousFailure() {
    defaults.set("ขยะ", forKey: statesKeyMirror)
    let store = ProximityGateStore(defaults: defaults)
    _ = store.load()
    XCTAssertNotNil(store.lastError)

    store.resetLastError()

    XCTAssertNil(store.lastError)
  }

  /// รายการที่ถอดไม่ออกถูกข้ามไปทีละรายการ ไม่ล้มทั้ง batch — และ bucket ที่ชื่อ
  /// ไม่ตรงกับ enum ต้องกลายเป็น `nil` ไม่ใช่ถูกเดาเป็นค่าใดค่าหนึ่ง
  func testEntriesFromJsonSkipsBrokenRecordsWithoutGuessing() {
    let json = """
      [
        {"key":"good|u|1|1","confirmedBucket":"near","pendingCloserCount":2,"window":["near","far"]},
        {"confirmedBucket":"near"},
        {"key":"bad-bucket|u|1|2","confirmedBucket":"very-near","window":["near","สวัสดี","far"]}
      ]
      """

    let entries = ProximityGateStore.entriesFromJson(json)

    XCTAssertEqual(entries.count, 2, "รายการที่ไม่มี key ถูกข้าม ส่วนอีกสองรายการยังอ่านได้")
    XCTAssertEqual(entries[0].key, "good|u|1|1")
    XCTAssertEqual(entries[0].state.confirmedBucket, .near)
    XCTAssertEqual(entries[0].state.pendingCloserCount, 2)
    XCTAssertEqual(entries[0].state.window, [.near, .far])
    XCTAssertNil(entries[0].state.lastSampleAt, "คีย์ที่ไม่มีในต้นทาง -> nil ไม่ใช่ 0")

    XCTAssertEqual(entries[1].key, "bad-bucket|u|1|2")
    XCTAssertNil(entries[1].state.confirmedBucket, "ชื่อ bucket ที่ไม่รู้จัก -> nil ห้ามเดา")
    XCTAssertEqual(entries[1].state.window, [.near, .far], "ตัวที่ถอดไม่ออกถูกตัดออกจากหน้าต่าง")
  }

  /// ฟิลด์ที่เป็น `nil` ต้อง**ไม่ถูกเขียนเป็นคีย์** (ไม่ใช่ `null`) ตามคอมเมนต์
  /// ของ `entriesToJson` — และต้องอ่านกลับได้เป็น `nil` พอดี
  func testNilFieldsAreOmittedFromJson() {
    let json = ProximityGateStore.entriesToJson([
      ProximityKeyEntry(key: "k", state: ProximityKeyState())
    ])

    XCTAssertNotNil(json)
    XCTAssertFalse(json!.contains("confirmedBucket"))
    XCTAssertFalse(json!.contains("pendingCloserBucket"))
    XCTAssertFalse(json!.contains("lastSampleAt"))
    XCTAssertFalse(json!.contains("null"))

    let back = ProximityGateStore.entriesFromJson(json!)
    XCTAssertEqual(back, [ProximityKeyEntry(key: "k", state: ProximityKeyState())])
  }

  /// `removeStates(matchingPrefix:)` — ADR-21 หัวข้อ 7 ข้อ 2: region ที่เลิกเฝ้า
  /// แล้วต้องไม่ทิ้ง dwell/หน้าต่างเก่าไว้ให้รอบการเฝ้าครั้งหน้ามาสานต่อ
  func testRemoveStatesMatchingPrefixOnlyRemovesThatRegion() {
    let store = ProximityGateStore(defaults: defaults)
    store.save([
      ProximityKeyEntry(key: "branch-a|u|1|1", state: ProximityKeyState(confirmedBucket: .near)),
      ProximityKeyEntry(key: "branch-b|u|1|1", state: ProximityKeyState(confirmedBucket: .far)),
    ])

    store.removeStates(matchingPrefix: "branch-a|")

    let remaining = ProximityGateStore(defaults: defaults).load()
    XCTAssertEqual(remaining.map(\.key), ["branch-b|u|1|1"])
  }
}

// MARK: - allowsBackgroundLocationUpdates

/// **ฟังก์ชันที่ถ้าผิดแล้วแอปของ host ตายทันที**
///
/// Apple ระบุคำต่อคำว่าการตั้ง `allowsBackgroundLocationUpdates = true` ทั้งที่
/// `Info.plist` ไม่มี `UIBackgroundModes`/`location` เป็น **"a fatal error that
/// terminates the app"** (`docs/sources/apple_proximity_ranging.md` หัวข้อ 6 ·
/// ADR-21 หัวข้อ 1) — `beacon_kit` เป็นไลบรารีที่รันอยู่ในแอปของคนอื่น
/// การตัดสินผิดที่นี่ = SDK ฆ่าแอปของ host เพราะเขาลืมใส่ plist
///
/// ทุกสาขาของฟังก์ชันต้องมีเทสต์คลุม
final class IBeaconRangingBackgroundModesTests: XCTestCase {

  func testLocationPresentEnablesBackgroundUpdates() {
    XCTAssertTrue(IBeaconRangingManager.allowsBackgroundLocationUpdates(backgroundModes: ["location"]))
  }

  func testLocationAmongOtherModesEnablesBackgroundUpdates() {
    XCTAssertTrue(
      IBeaconRangingManager.allowsBackgroundLocationUpdates(
        backgroundModes: ["audio", "location", "fetch", "remote-notification"]
      )
    )
  }

  func testMissingLocationDoesNotEnableBackgroundUpdates() {
    XCTAssertFalse(
      IBeaconRangingManager.allowsBackgroundLocationUpdates(
        backgroundModes: ["audio", "fetch", "bluetooth-central"]
      ),
      "ไม่มี location -> ห้ามตั้ง ไม่งั้นแอปของ host ตายทันที"
    )
  }

  func testEmptyArrayDoesNotEnableBackgroundUpdates() {
    XCTAssertFalse(IBeaconRangingManager.allowsBackgroundLocationUpdates(backgroundModes: []))
  }

  /// `nil` = host app ไม่มีคีย์ `UIBackgroundModes` ใน `Info.plist` เลย ซึ่งเป็น
  /// **เคสของแอปส่วนใหญ่** และเป็นเคสที่ Apple บอกว่าทำให้แอปตาย
  func testNilBackgroundModesDoesNotEnableBackgroundUpdates() {
    XCTAssertFalse(IBeaconRangingManager.allowsBackgroundLocationUpdates(backgroundModes: nil))
  }

  /// ค่าใน `Info.plist` เป็น `location` ตัวพิมพ์เล็กเท่านั้น — ตัวพิมพ์ใหญ่/
  /// สตริงที่แค่มีคำว่า location อยู่ข้างในต้องไม่ผ่าน (ถ้าเผลอใช้
  /// `contains(where:)` แบบ substring จะพลาดข้อนี้)
  func testNearMissStringsDoNotEnableBackgroundUpdates() {
    XCTAssertFalse(IBeaconRangingManager.allowsBackgroundLocationUpdates(backgroundModes: ["Location"]))
    XCTAssertFalse(IBeaconRangingManager.allowsBackgroundLocationUpdates(backgroundModes: ["location-updates"]))
    XCTAssertFalse(IBeaconRangingManager.allowsBackgroundLocationUpdates(backgroundModes: [""]))
  }
}

// MARK: - บรรทัดหลักฐานของ example app

/// `AppDelegate.proximityRawSignalsSuffix` — pure function ที่ประกอบ**ส่วนต่อท้าย
/// ของคอลัมน์สัญญาณดิบ** ในบรรทัด `event=proximity`
///
/// ADR-21 หัวข้อ 7 ข้อ 1-2 บังคับให้มี `beacon=` และ `store=` **ตั้งแต่คอมมิตแรก**
/// เพราะรอบ Android เสียเวลาสอบสวนทั้งรอบจากการที่บรรทัดหลักฐานของคนละบีคอน
/// พิมพ์ออกมาเหมือนกันหมด และความล้มเหลวของ store ไม่เคยปรากฏในไฟล์เลย
final class ProximityRawSignalsSuffixTests: XCTestCase {

  private func makeEvent(
    from: ProximityBucket? = .far,
    to: ProximityBucket? = .near,
    reason: ProximityTransitionReason = .closer,
    major: UInt16? = 1,
    minor: UInt16? = 42,
    storeError: String? = nil,
    rangeCallbackCount: Int = 41,
    inArrayCount: Int = 12,
    unknownCount: Int = 3
  ) -> BeaconKitProximityChangedEvent {
    return BeaconKitProximityChangedEvent(
      regionIdentifier: "bigc-ladprao",
      uuid: "7777772e-6b6b-6d63-6e2e-636f6d000001",
      major: major,
      minor: minor,
      from: from,
      to: to,
      reason: reason,
      medianMeters: nil,
      timestampMillis: 1_757_000_000_000,
      storeError: storeError,
      rangeCallbackCount: rangeCallbackCount,
      inArrayCount: inArrayCount,
      unknownCount: unknownCount
    )
  }

  func testHappyPathSuffixHasEveryFieldInOrder() {
    let suffix = AppDelegate.proximityRawSignalsSuffix(makeEvent())

    XCTAssertEqual(
      suffix,
      " bucket=near from=far reason=closer beacon=1/42 store=ok"
        + " rangeCb=41 inArray=12 unknown=3"
    )
  }

  /// **ทุกค่าที่ "ไม่มี" ต้องอ่านออกได้ ห้ามเป็นช่องว่าง** — คอลัมน์สัญญาณดิบคั่น
  /// ด้วยช่องว่าง ถ้าค่าใดว่าง ตัวอ่านจะเห็นเป็นคนละ key โดยไม่มีอะไรฟ้อง
  ///
  /// `from=none` (ไม่ใช่ `n/a`) เมื่อไม่เคยมี bucket ที่ยืนยันมาก่อน — คนละความ
  /// หมายกัน: `none` = "ยืนยัน bucket แรกของบีคอนตัวนี้" ซึ่งเป็นข้อเท็จจริงที่รู้
  /// แน่ · `n/a` = "ตอบไม่ได้"
  func testStaleEventWithNothingKnownStillPrintsReadableValues() {
    let suffix = AppDelegate.proximityRawSignalsSuffix(
      makeEvent(from: nil, to: nil, reason: .stale, major: nil, minor: nil)
    )

    XCTAssertEqual(
      suffix,
      " bucket=n/a from=none reason=stale beacon=n/a store=ok"
        + " rangeCb=41 inArray=12 unknown=3"
    )
  }

  func testStoreErrorIsReportedAndSpacesAreReplaced() {
    let suffix = AppDelegate.proximityRawSignalsSuffix(
      makeEvent(storeError: "load:unparsable (17B) ขยะ")
    )

    XCTAssertTrue(suffix.contains("store=load:unparsable_(17B)_ขยะ"))
    XCTAssertFalse(
      suffix.hasSuffix(" "),
      "ค่าห้ามมีช่องว่างปน ไม่งั้นตัวอ่านคอลัมน์จะเห็นเป็นคนละ key"
    )
  }

  /// สัญญาเชิงโครงสร้างของ suffix — ตรวจครบทุกเคสที่เป็นไปได้ของ `to`/`from`/
  /// `reason`/`beacon`/`store` พร้อมกัน: ขึ้นต้นด้วยช่องว่าง 1 ตัว, มีครบ 8 คู่
  /// (5 คู่เดิม + ตัวนับ 3 ตัวของ ADR-21 หัวข้อ 9), ทุกคู่เป็น `key=value` ที่ value
  /// ไม่ว่าง — `reason` รวม `regionExit` ที่เพิ่มเข้ามาหลังรอบเดินจริง 10 ก.ย. 2026 ด้วย
  func testSuffixShapeHoldsForEveryCombination() {
    let buckets: [ProximityBucket?] = [nil, .immediate, .near, .far]
    let reasons: [ProximityTransitionReason] = [.closer, .farther, .stale, .regionExit]
    let storeErrors: [String?] = [nil, "save:serialize-failed", "init:suite-unavailable"]

    for to in buckets {
      for from in buckets {
        for reason in reasons {
          for storeError in storeErrors {
            for major: UInt16? in [nil, 65535] {
              let suffix = AppDelegate.proximityRawSignalsSuffix(
                makeEvent(
                  from: from,
                  to: to,
                  reason: reason,
                  major: major,
                  minor: major == nil ? nil : 7,
                  storeError: storeError
                )
              )

              XCTAssertTrue(suffix.hasPrefix(" "), "ต้องขึ้นต้นด้วยช่องว่าง 1 ตัว: \"\(suffix)\"")

              let pairs = suffix.dropFirst().split(separator: " ", omittingEmptySubsequences: false)
              XCTAssertEqual(
                pairs.map { String($0.split(separator: "=", maxSplits: 1)[0]) },
                ["bucket", "from", "reason", "beacon", "store", "rangeCb", "inArray", "unknown"],
                "ลำดับและชื่อคอลัมน์ต้องคงที่: \"\(suffix)\""
              )
              for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1)
                XCTAssertEqual(parts.count, 2, "ทุกคู่ต้องเป็น key=value: \"\(pair)\"")
                XCTAssertFalse(parts[1].isEmpty, "ค่าห้ามว่าง: \"\(pair)\" ใน \"\(suffix)\"")
              }
            }
          }
        }
      }
    }
  }

  /// `beacon=<major>/<minor>` คือ **ตัวแยกว่าบรรทัดนี้เป็นของบีคอนตัวไหน** —
  /// บีคอนคนละตัวใน region เดียวกันต้องให้ suffix ที่ต่างกัน ไม่งั้น `stale`
  /// หลายบรรทัดติดกันจะอ่านเหมือนบั๊กยิงซ้ำ (เกิดจริงรอบ Android 9 ก.ย. 2026)
  func testDifferentBeaconsProduceDifferentSuffixes() {
    let first = AppDelegate.proximityRawSignalsSuffix(makeEvent(major: 1, minor: 42))
    let second = AppDelegate.proximityRawSignalsSuffix(makeEvent(major: 1, minor: 43))

    XCTAssertNotEqual(first, second)
    XCTAssertTrue(first.contains(" beacon=1/42 "))
    XCTAssertTrue(second.contains(" beacon=1/43 "))
  }
}

// MARK: - ค่า default และการแปลง CLProximity (เพิ่มจากรีวิว 10 ก.ย. 2026)

/// ล็อก**ค่าที่ทั้งรอบทดสอบเครื่องจริงมีไว้เพื่อพิสูจน์** — ไม่มีเทสตัวไหนก่อนหน้านี้
/// จับได้เลยถ้าใครแก้ค่าเหล่านี้
///
/// เทส stale ทุกตัวในไฟล์นี้ส่ง `staleAfterMillis:` เข้าไปเอง แปลว่าถ้ามีคนแก้ค่า
/// default เป็น `60_000` ตามของ ADR-20 หัวข้อ 7 (ซึ่ง **ADR-21 หัวข้อ 4 ห้ามไว้ชัดที่สุด
/// ในทั้งฉบับ** เพราะ 60 วินาทีคำนวณจากอัตรา batch ของ Android ที่วัดได้จริง ส่วน iOS
/// ยังไม่มีไฟล์ข้อมูลของตัวเองเลย) **เทสทั้ง 73 เคสจะยังเขียวหมด** — ช่องว่างชนิดที่
/// เจอได้เฉพาะตอนรีวิว ไม่ใช่ตอนรัน
final class ProximityGateDefaultsTests: XCTestCase {

  func testDefaultsMatchAdr19Section8Exactly() {
    let gate = ProximityGate(clock: { 0 })

    XCTAssertEqual(gate.windowSize, 5, "ADR-19 หัวข้อ 8")
    XCTAssertEqual(gate.dwellSamples, 3, "ADR-19 หัวข้อ 8")
    XCTAssertEqual(
      gate.staleAfterMillis, 10_000,
      "ADR-19 หัวข้อ 8 · **ห้ามยืม 60_000 ของ ADR-20 หัวข้อ 7** — ค่านั้นมาจากอัตรา "
        + "batch ของ Android ที่วัดได้จริง iOS ยังไม่มีข้อมูลของตัวเอง (ADR-21 หัวข้อ 4)"
    )
  }
}

/// `CLProximity.unknown` **ต้องกลายเป็น `nil` ห้ามกลายเป็น `.far`**
///
/// นี่คือจุดเดียวในโค้ดที่บังคับ invariant ของ ADR-19 6(ฉ) ("วัดไม่ได้" ไม่เท่ากับ "ไกล")
/// ที่ขอบระหว่าง CoreLocation กับ gate — ก่อนเทสนี้ไม่มีอะไรฟ้องเลยถ้ามีคนแก้เป็น
/// `case .unknown: return .far` ซึ่งจะทำให้ sample ที่ Apple บอกว่า "ไม่รู้" ถูกนับเป็น
/// หลักฐานว่าลูกค้าเดินออกห่าง แล้วไหลเข้า dwell ของทิศ "ไกลขึ้น" ที่ยืนยันทันทีโดยไม่ต้อง
/// รอ — ผลคือ bucket หลุดทั้งที่ไม่มีใครขยับ
final class ProximityBucketMappingTests: XCTestCase {

  func testUnknownBecomesNilNeverFar() {
    XCTAssertNil(
      IBeaconRangingManager.proximityBucket(.unknown),
      "ADR-19 6(ฉ): \"วัดไม่ได้\" ไม่เท่ากับ \"ไกล\" — ห้ามคืน .far เด็ดขาด"
    )
  }

  func testKnownProximitiesMapOneToOne() {
    XCTAssertEqual(IBeaconRangingManager.proximityBucket(.immediate), .immediate)
    XCTAssertEqual(IBeaconRangingManager.proximityBucket(.near), .near)
    XCTAssertEqual(IBeaconRangingManager.proximityBucket(.far), .far)
  }
}

// MARK: - ลำดับ sweep ใหม่หลังรอบเดินจริง 10 ก.ย. 2026 (ADR-21 หัวข้อ 8)

/// key ของ **อีก region หนึ่ง** — มีไว้พิสูจน์ว่า `regionExit` ไม่แตะข้ามบ้าน
private let otherRegionKey = ProximityKeyCodec.key(
  regionIdentifier: "bigc-rama4",
  uuid: "7777772e-6b6b-6d63-6e2e-636f6d000001",
  major: 1,
  minor: 42
)

private let regionPrefix = "bigc-ladprao\(ProximityKeyCodec.separator)"

/// เลียนแบบ **ลำดับใหม่** ของ `IBeaconRangingManager.runProximityLayer` หนึ่งรอบ:
/// push ทุกตัวที่อยู่ใน array ให้ครบก่อน **แล้วค่อย `sweepStale()` เสมอ แม้ array ว่าง**
///
/// เทสต์ในกลุ่มนี้จงใจไม่แตะ `CLLocationManager` เลย — สิ่งที่ต้องล็อกคือ**ลำดับ**
/// ซึ่งเป็นตรรกะล้วน ๆ ที่นาฬิกาปลอมพิสูจน์ได้ 100% (ADR-21 หัวข้อ 4: ไม่มี `Timer`
/// ใน SDK · จังหวะจริงของ CoreLocation พิสูจน์ได้เฉพาะบนเครื่องจริงเท่านั้น)
private func runOneCallback(
  _ gate: ProximityGate,
  samples: [(key: String, bucket: ProximityBucket?)]
) -> [ProximityTransition] {
  var pending: [ProximityTransition] = []
  for sample in samples {
    if let transition = gate.push(key: sample.key, bucket: sample.bucket) {
      pending.append(transition)
    }
  }
  pending.append(contentsOf: gate.sweepStale())
  return pending
}

/// **ที่มาของทั้งกลุ่ม: `docs/test-data/2026-09-10_ios_proximity_walk.log`**
///
/// ไฟล์นั้นมี `event=rangefail` **0 บรรทัด** ทั้งที่ผู้ทดสอบเดินพ้นสัญญาณสองนาทีและ
/// iOS ประกาศ `exit` จริง — แปลว่า **จุด sweep ที่สองของ ADR-21 หัวข้อ 4
/// (`didFailRangingFor`) ไม่เคยทำงานเลย** สิ่งที่เหลือคือ `didRange` ซึ่งอาจยิงมา
/// พร้อม array ที่ไม่มีบีคอนตัวที่หายไป (หรือว่างเปล่า) จึง**ต้อง sweep ทุกครั้ง**
final class ProximityGateSweepOrderTests: XCTestCase {

  /// **เคสหลักของรอบนี้:** `didRange` ที่ array ว่าง N ครั้ง ต้องทำให้เกิด `stale`
  /// ภายใน `staleAfterMillis` — ไม่ต้องมี `didFailRangingFor` ไม่ต้องมี `Timer`
  ///
  /// ถ้าใครย้าย `sweepStale()` กลับไปไว้หลัง `guard beacons.isEmpty` หรือเลิกเรียก
  /// มันตอน array ว่าง เทสนี้จะแดงทันที
  func testEmptyArrayCallbacksProduceStaleWithinStaleAfter() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    XCTAssertNotNil(gate.push(key: sampleKey, bucket: .far), "ยืนยัน far ที่ t=0")

    // callback ที่ array ว่างเปล่า ห่างกันวินาทีละครั้ง จนกว่าจะมีอะไรออกมา
    // (เพดาน 15 รอบ = 15 วินาที ซึ่งเกิน staleAfter 10 วินาทีไปมากพอที่ "ไม่เกิดเลย"
    // จะแปลว่าบั๊กจริง ไม่ใช่เทสต์นับรอบไม่พอ)
    var transitions: [ProximityTransition] = []
    var elapsedMillis: Int64 = 0
    for _ in 0..<15 {
      clock.advance(millis: 1_000)
      elapsedMillis += 1_000
      let batch = runOneCallback(gate, samples: [])
      transitions.append(contentsOf: batch)
      if !batch.isEmpty { break }
    }

    XCTAssertEqual(transitions.count, 1, "ต้องได้ stale พอดีหนึ่งใบ ไม่ใช่ซ้ำทุก callback")
    XCTAssertEqual(transitions.first?.from, .far)
    XCTAssertNil(transitions.first?.to, "'วัดไม่ได้' ไม่ใช่ 'ไกล'")
    XCTAssertEqual(transitions.first?.reason, .stale)
    XCTAssertEqual(
      elapsedMillis, 11_000,
      "callback แรกที่เลย staleAfter (10s) คือวินาทีที่ 11 — ไม่ใช่ 'ไม่เกิดเลย'"
    )
  }

  /// เรียกซ้ำหลังจากนั้นต้องเงียบสนิท — บรรทัด `stale` ที่ยิงทุก callback จะกลาย
  /// เป็นสแปมในไฟล์หลักฐานจนอ่านไม่ออกว่าเกิดอะไรขึ้นจริง
  func testEmptyArrayCallbacksAfterStaleStaySilent() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .far)
    clock.advance(millis: 11_000)
    XCTAssertEqual(runOneCallback(gate, samples: []).count, 1)

    for _ in 0..<5 {
      clock.advance(millis: 30_000)
      XCTAssertTrue(runOneCallback(gate, samples: []).isEmpty, "หลุดไปแล้วต้องไม่ยิงซ้ำ")
    }
  }

  /// **ลำดับกลับด้าน (push ก่อน sweep) แก้บั๊กอะไรจริง ๆ**
  ///
  /// ในไฟล์หลักฐานรอบ 10 ก.ย. มีคู่บรรทัดที่มิลลิวินาทีเดียวกันของ**บีคอนตัวเดียวกัน**:
  /// ```
  /// 13:41:25.073 ... bucket=n/a from=far  reason=stale   beacon=9903/3
  /// 13:41:25.073 ... bucket=far from=none reason=farther beacon=9903/3
  /// ```
  /// นั่นคืออาการของลำดับเดิม (sweep **ก่อน** push): sweep ยิง `stale` แล้ว push ของ
  /// รอบเดียวกันเริ่ม state ใหม่จนยืนยัน `far` ได้ทันที = สอง transition ต่อหนึ่ง
  /// callback ของ key เดียว
  ///
  /// ลำดับใหม่ให้ `push` เป็นผู้ประกาศ `stale` เอง (แล้ว**ทิ้ง sample ของรอบนั้น**
  /// ตาม ADR-19 หัวข้อ 7) ส่วน sweep ที่ตามมาเห็น state ที่รีเซ็ตแล้วจึงเงียบ
  func testKeyReportedInTheSameCallbackEmitsOnlyOneTransition() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .far)
    clock.advance(millis: 11_000)

    let batch = runOneCallback(gate, samples: [(sampleKey, .far)])

    XCTAssertEqual(batch.count, 1, "หนึ่ง callback ของ key เดียว = หนึ่ง transition")
    XCTAssertEqual(batch.first?.reason, .stale)
    XCTAssertNil(batch.first?.to)
  }

  /// key ที่ **ยังรายงานอยู่** ต้องไม่ถูก sweep ในรอบเดียวกัน แม้ key อื่นจะหลุด —
  /// นี่คือเหตุผลที่ `sweepStale()` ต้องอยู่ **หลัง** loop: `lastSampleAt` ของตัวที่
  /// เพิ่งรายงานต้องสดแล้วก่อนถูกกวาด
  func testFreshlyReportedKeySurvivesWhileMissingKeyIsSweptInTheSameCallback() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .far)
    _ = gate.push(key: otherKey, bucket: .far)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .far)
    XCTAssertEqual(gate.currentBucket(key: otherKey), .far)

    // เดินเวลาเป็นช่วง ๆ โดยมีแต่ sampleKey ที่ยังอยู่ใน array (otherKey หายไปเฉย ๆ
    // — เคสที่ Apple ถอดบีคอนออกจาก array ซึ่งตัวนับ `inArray` มีไว้วัดพอดี)
    var swept: [ProximityTransition] = []
    for _ in 0..<3 {
      clock.advance(millis: 5_000)
      swept.append(contentsOf: runOneCallback(gate, samples: [(sampleKey, .far)]))
    }

    XCTAssertEqual(swept.count, 1, "เฉพาะ key ที่หายไปเท่านั้นที่หลุด")
    XCTAssertEqual(swept.first?.key, otherKey)
    XCTAssertEqual(swept.first?.reason, .stale)
    XCTAssertEqual(
      gate.currentBucket(key: sampleKey), .far,
      "key ที่รายงานทุกรอบต้องไม่ถูกกวาดแม้เวลาผ่านไปเกิน staleAfter หลายเท่า"
    )
  }
}

// MARK: - regionExit (ADR-21 หัวข้อ 8)

/// ⚠️ **`regionExit` ไม่ใช่ parity กับ Android** — ฝั่งนั้นไม่มี reason นี้จริง ๆ
/// (ล้าง store ตอน `monitorStop` ของ example app ไม่ใช่ตอน region exit) และ
/// `proximity_gate.dart` ก็ไม่มี · เป็นการเบี่ยงจาก reference **โดยตั้งใจ** เพราะ
/// iOS มี boundary event ที่ระบบยืนยันเอง — และเป็น**หนี้**ที่ต้องยกขึ้นไปที่ Dart
/// แล้วไหลลงทั้งสอง port ในรอบถัดไป ไม่งั้นจะมีสามภาษาสามพฤติกรรม
final class ProximityGateRegionExitTests: XCTestCase {

  func testRegionExitEmitsForConfirmedKeysAndRemovesEveryKeyOfThatRegion() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .far)
    _ = gate.push(key: otherKey, bucket: .far)
    XCTAssertEqual(gate.currentBucket(key: sampleKey), .far)
    XCTAssertEqual(gate.currentBucket(key: otherKey), .far)

    let transitions = gate.clearStates(matchingPrefix: regionPrefix, emitting: .regionExit)

    XCTAssertEqual(transitions.count, 2)
    XCTAssertEqual(
      transitions.map(\.key), [sampleKey, otherKey],
      "เรียงตามลำดับที่เห็น key ครั้งแรก เหมือน sweepStale()"
    )
    for transition in transitions {
      XCTAssertEqual(transition.from, .far)
      XCTAssertNil(transition.to, "'ออกจาก region' ไม่ใช่ 'ไกล' — to ต้องเป็น nil")
      XCTAssertEqual(transition.reason, .regionExit)
      XCTAssertNil(transition.medianMeters)
    }

    XCTAssertNil(gate.stateOf(key: sampleKey), "ล้างทิ้งทั้ง entry ไม่ใช่รีเซ็ตเป็น state ว่าง")
    XCTAssertNil(gate.stateOf(key: otherKey))
    XCTAssertTrue(gate.snapshotStates().isEmpty)
  }

  /// key ที่ยังค้าง dwell (ไม่เคย confirm) ต้องถูกล้าง **เงียบ ๆ** — หลักการเดียวกับ
  /// `sweepStale()` เป๊ะ: ไม่เคยประกาศว่า "ใกล้" ก็ไม่มีอะไรให้ประกาศว่า "หลุด"
  func testPendingKeyIsClearedSilentlyOnRegionExit() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    XCTAssertNil(gate.push(key: sampleKey, bucket: .near), "dwell ยังไม่ครบ 3")
    XCTAssertEqual(gate.stateOf(key: sampleKey)?.pendingCloserCount, 1)
    XCTAssertNil(gate.currentBucket(key: sampleKey))

    let transitions = gate.clearStates(matchingPrefix: regionPrefix, emitting: .regionExit)

    XCTAssertTrue(transitions.isEmpty, "ไม่เคย confirm = ไม่มีอะไรให้ประกาศ")
    XCTAssertNil(gate.stateOf(key: sampleKey), "แต่ต้องถูกล้างจริง")
  }

  /// **key ของ region อื่นห้ามถูกแตะแม้แต่ฟิลด์เดียว** — เทียบทั้ง `struct` ด้วย
  /// `Equatable` แบบเดียวกับที่เทสของ ADR-19 6(ง) ทำ ไม่ใช่ไล่เช็คทีละฟิลด์ซึ่งลืมได้
  func testOtherRegionIsNotTouchedAtAll() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .far)
    _ = gate.push(key: otherRegionKey, bucket: .far)
    let untouched = gate.stateOf(key: otherRegionKey)
    XCTAssertNotNil(untouched)

    let transitions = gate.clearStates(matchingPrefix: regionPrefix, emitting: .regionExit)

    XCTAssertEqual(transitions.map(\.key), [sampleKey], "ต้องไม่มี key ของ region อื่นหลุดมา")
    XCTAssertEqual(
      gate.stateOf(key: otherRegionKey), untouched,
      "state ของ region อื่นต้องเท่าเดิมทุกฟิลด์ (confirmed/pending/window/lastSampleAt)"
    )
    XCTAssertEqual(gate.currentBucket(key: otherRegionKey), .far)
    XCTAssertEqual(gate.snapshotStates().map(\.key), [otherRegionKey])
  }

  /// เรียกซ้ำ (เช่น iOS ยิง `didExitRegion` สองครั้ง) ต้องเงียบสนิทครั้งที่สอง
  func testRegionExitIsIdempotent() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .far)

    XCTAssertEqual(gate.clearStates(matchingPrefix: regionPrefix, emitting: .regionExit).count, 1)
    XCTAssertTrue(gate.clearStates(matchingPrefix: regionPrefix, emitting: .regionExit).isEmpty)
  }

  /// `removeStates(matchingPrefix:)` (เส้นทาง `stopMonitoring`) ต้อง **ยังเงียบเหมือนเดิม**
  /// — การ refactor ให้สองเมธอดใช้แกนเดียวกันต้องไม่ทำให้เส้นทางเดิมเริ่ม emit
  func testSilentRemoveStillEmitsNothing() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, windowSize: 1, staleAfterMillis: 10_000)

    _ = gate.push(key: sampleKey, bucket: .far)
    _ = gate.push(key: otherRegionKey, bucket: .far)

    gate.removeStates(matchingPrefix: regionPrefix)

    XCTAssertNil(gate.stateOf(key: sampleKey))
    XCTAssertEqual(gate.snapshotStates().map(\.key), [otherRegionKey])
  }
}

// MARK: - ตัวนับ 3 ตัว (ADR-21 หัวข้อ 9)

/// **ห้ามรวมสามตัวเป็นตัวเดียว** — บน iOS "ไม่มี sample" มีสองความหมายที่แก้คนละทาง:
/// ranging ไม่เดิน (`rangeCb` ไม่ขยับ) กับ ranging เดินแต่ Apple ถอดบีคอนออกจาก array
/// (`rangeCb` ขยับ แต่ `inArray` ไม่ขยับ)
final class ProximitySampleCountersTests: XCTestCase {

  func testKnownBucketCountsInArrayOnly() {
    let counters = IBeaconRangingManager.ProximitySampleCounters()
      .counting(bucket: .near)

    XCTAssertEqual(counters.inArray, 1)
    XCTAssertEqual(counters.unknown, 0)
  }

  /// `unknown` **นับรวมอยู่ใน `inArray` ด้วย** — บีคอนที่ Apple ตอบว่า `unknown`
  /// ก็คือบีคอนที่ยังอยู่ใน array (เห็นอยู่ แต่ตอบไม่ได้ว่าใกล้แค่ไหน) ถ้าแยกขาด
  /// อัตราส่วน `unknown/inArray` ที่สมมติฐาน B ต้องใช้จะคำนวณจากบรรทัดเดียวไม่ได้
  func testUnknownBucketCountsBothInArrayAndUnknown() {
    let counters = IBeaconRangingManager.ProximitySampleCounters()
      .counting(bucket: nil)

    XCTAssertEqual(counters.inArray, 1)
    XCTAssertEqual(counters.unknown, 1)
  }

  func testCountsAccumulateInOrder() {
    var counters = IBeaconRangingManager.ProximitySampleCounters()
    for bucket in [ProximityBucket?.some(.far), nil, .some(.near), nil, nil] {
      counters = counters.counting(bucket: bucket)
    }

    XCTAssertEqual(counters, IBeaconRangingManager.ProximitySampleCounters(inArray: 5, unknown: 3))
  }

  /// **ล็อกกฎ ADR-19 6(ง) คู่กับตัวนับ:** sample ที่เป็น `unknown` ต้องถูก**นับ**
  /// (ไม่งั้นสมมติฐาน B ทดสอบไม่ได้) แต่ต้อง **ไม่ต่ออายุ `lastSampleAt`** เด็ดขาด
  /// — ถ้ามันต่ออายุ บีคอนที่เงียบสนิทแต่ยังมี `unknown` ไหลเข้ามาจะค้าง `near`
  /// ตลอดไปและ `stale` จะไม่มีวันเกิด
  func testUnknownIsCountedButNeverRenewsLastSampleAt() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1, staleAfterMillis: 10_000)
    var counters = IBeaconRangingManager.ProximitySampleCounters()

    counters = counters.counting(bucket: .near)
    _ = gate.push(key: sampleKey, bucket: .near)  // t=0
    let stateAtT0 = gate.stateOf(key: sampleKey)
    XCTAssertEqual(stateAtT0?.lastSampleAt, 0)

    for _ in 0..<9 {
      clock.advance(millis: 1_000)
      counters = counters.counting(bucket: nil)
      XCTAssertNil(gate.push(key: sampleKey, bucket: nil))
    }

    XCTAssertEqual(
      counters, IBeaconRangingManager.ProximitySampleCounters(inArray: 10, unknown: 9),
      "ตัวนับต้องเดินต่อ — นี่คือข้อมูลที่ใช้ตอบว่า Apple ส่ง unknown บ่อยแค่ไหน"
    )
    XCTAssertEqual(
      gate.stateOf(key: sampleKey), stateAtT0,
      "แต่ state ของ gate ต้องไม่ถูกแตะแม้แต่ฟิลด์เดียว (ADR-19 6(ง))"
    )

    clock.advance(millis: 2_000)  // t=11s เทียบกับ lastSampleAt ที่ยังค้างที่ t=0
    XCTAssertEqual(
      runOneCallback(gate, samples: [(sampleKey, nil)]).first?.reason,
      .stale,
      "ช่องว่างจริงนับจาก t=0 — `unknown` รัว ๆ ต้องไม่กันไม่ให้ stale เกิด"
    )
  }
}

/// รูปแบบของคอลัมน์ตัวนับในไฟล์หลักฐาน — pure function เช่นเดียวกับ
/// `proximityRawSignalsSuffix`
final class RangeCounterSuffixTests: XCTestCase {

  func testAllThreeCountersAppearInOrder() {
    XCTAssertEqual(
      AppDelegate.rangeCounterSuffix(rangeCb: 41, inArray: 12, unknown: 3),
      " rangeCb=41 inArray=12 unknown=3"
    )
  }

  /// บรรทัด `launch` ไม่ได้พูดถึง key ใด — `inArray`/`unknown` ต้องเป็น `n/a`
  /// **ห้ามเป็น `0`** ซึ่งแปลว่า "นับแล้วได้ศูนย์" คนละความหมายกับ "ตอบไม่ได้"
  func testMissingKeyScopedCountersAreNotAnotherZero() {
    XCTAssertEqual(
      AppDelegate.rangeCounterSuffix(rangeCb: 0, inArray: nil, unknown: nil),
      " rangeCb=0 inArray=n/a unknown=n/a"
    )
  }

  /// ค่าห้ามว่างและห้ามมีช่องว่างปน — คอลัมน์สัญญาณดิบคั่นด้วยช่องว่าง
  func testEveryPairIsReadableForBoundaryValues() {
    for value: Int? in [nil, 0, 1, Int.max] {
      let suffix = AppDelegate.rangeCounterSuffix(rangeCb: 0, inArray: value, unknown: value)
      let pairs = suffix.dropFirst().split(separator: " ", omittingEmptySubsequences: false)

      XCTAssertEqual(
        pairs.map { String($0.split(separator: "=", maxSplits: 1)[0]) },
        ["rangeCb", "inArray", "unknown"]
      )
      for pair in pairs {
        let parts = pair.split(separator: "=", maxSplits: 1)
        XCTAssertEqual(parts.count, 2, "ทุกคู่ต้องเป็น key=value: \"\(pair)\"")
        XCTAssertFalse(parts[1].isEmpty, "ค่าห้ามว่าง: \"\(pair)\"")
      }
    }
  }
}

// MARK: - ADR-22: ชั้นที่ 2 = foreground เท่านั้น (บังคับด้วยโค้ด)

/// **ที่มาของทั้งกลุ่ม: `docs/test-data/2026-09-10_ios_proximity_counters.log`**
///
/// ไฟล์นั้นวัดได้ว่าตอนแอปถูกปลุกเบื้องหลัง `didRange` มาถึง **ทุก ~16 วินาที**
/// (เทียบกับ 2 Hz ตอน foreground) และ **67% ตอบ `unknown`** เหลือ sample ที่ใช้ได้จริง
/// **ต่อ key ราวทุก 84 วินาที** — ค่าคงที่ของ ADR-19 หัวข้อ 8 (`dwellSamples = 3` ·
/// `staleAfterMillis = 10_000`) จึงเป็นไปไม่ได้เชิงโครงสร้างในโหมดนั้น
///
/// กลุ่มนี้ล็อกว่าการตัดสินใจ "ไม่เดิน gate ตอน background" อยู่ใน**โค้ด** ไม่ใช่แค่
/// ในเอกสาร — ถ้าใครถอด `isForeground` ออกในอนาคต เทสต์กลุ่มนี้ต้องแดงทันที
///
/// ⚠️ สิ่งที่กลุ่มนี้ **ไม่** พิสูจน์: ไม่ได้พิสูจน์ว่า `UIApplication.applicationState`
/// ตอบว่าอะไรบนเครื่องจริงในรอบที่ถูกปลุก (ทดสอบบน simulator ไม่ได้) — พิสูจน์แค่ว่า
/// **เมื่อคำตอบคือ "ไม่ active" gate จะไม่ถูกแตะแม้แต่ฟิลด์เดียว**
final class ProximityForegroundOnlyTests: XCTestCase {

  /// **เคสหลักของ ADR-22:** background → ตัวนับเดิน แต่ state ของ gate นิ่งสนิท
  func testBackgroundCountsSamplesButNeverTouchesGateState() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now)

    // สร้างสถานะตั้งต้นด้วยรอบ foreground ปกติก่อน เพื่อให้มีอะไรให้ "ไม่ถูกแตะ"
    _ = IBeaconRangingManager.stepProximityBatch(
      samples: [IBeaconRangingManager.ProximitySample(key: sampleKey, bucket: .near)],
      gate: gate,
      counters: [:],
      isForeground: true
    )
    let stateBefore = gate.snapshotStates()
    XCTAssertFalse(stateBefore.isEmpty, "ต้องมี state ตั้งต้นจริง ไม่งั้นเคสนี้พิสูจน์อะไรไม่ได้")

    var counters: [String: IBeaconRangingManager.ProximitySampleCounters] = [:]
    for _ in 0..<10 {
      clock.advance(millis: 16_000)  // จังหวะจริงของ background ที่วัดได้
      let outcome = IBeaconRangingManager.stepProximityBatch(
        samples: [IBeaconRangingManager.ProximitySample(key: sampleKey, bucket: .immediate)],
        gate: gate,
        counters: counters,
        isForeground: false
      )
      counters = outcome.counters
      XCTAssertTrue(outcome.transitions.isEmpty, "background ต้องไม่ประกาศ transition ใด ๆ")
    }

    XCTAssertEqual(
      counters[sampleKey],
      IBeaconRangingManager.ProximitySampleCounters(inArray: 10, unknown: 0),
      "ตัวนับต้องเดิน — มันคือเครื่องมือวัดชิ้นเดียวที่ ADR-22 จะมีให้ใช้"
    )
    XCTAssertEqual(
      gate.snapshotStates(), stateBefore,
      "แต่ state ของ gate ต้องเหมือนเดิมทุกฟิลด์ แม้ป้อน bucket ที่ใกล้กว่าเดิม 10 รอบ"
    )
  }

  /// `unknown` ตอน background ก็ยังต้องถูกนับแยก — ไม่งั้นตัวเลข 67% ที่ ADR-22
  /// ทั้งฉบับตั้งอยู่บนนั้นจะวัดซ้ำไม่ได้ในรอบถัดไป
  func testBackgroundStillSeparatesUnknownFromInArray() {
    let gate = ProximityGate(clock: FakeClock().now)
    var counters: [String: IBeaconRangingManager.ProximitySampleCounters] = [:]

    for bucket in [ProximityBucket?.some(.far), nil, nil, .some(.near), nil] {
      counters = IBeaconRangingManager.stepProximityBatch(
        samples: [IBeaconRangingManager.ProximitySample(key: sampleKey, bucket: bucket)],
        gate: gate,
        counters: counters,
        isForeground: false
      ).counters
    }

    XCTAssertEqual(
      counters[sampleKey],
      IBeaconRangingManager.ProximitySampleCounters(inArray: 5, unknown: 3)
    )
    XCTAssertTrue(gate.snapshotStates().isEmpty, "gate ต้องไม่เคยรู้จัก key นี้เลย")
  }

  /// **`sweepStale()` ต้องไม่ทำงานตอน background** — ความเงียบตอนนั้นเป็นพฤติกรรมของ
  /// CoreLocation (callback ทุก ~16 วิ) ไม่ใช่ของบีคอน การกวาดจึงเป็นการสรุปผิดจาก
  /// ข้อมูลที่ไม่มีสิทธิ์สรุป
  func testBackgroundNeverSweepsStaleEvenAfterLongSilence() {
    let clock = FakeClock()
    let gate = ProximityGate(clock: clock.now, dwellSamples: 1, staleAfterMillis: 10_000)

    _ = IBeaconRangingManager.stepProximityBatch(
      samples: [IBeaconRangingManager.ProximitySample(key: sampleKey, bucket: .near)],
      gate: gate,
      counters: [:],
      isForeground: true
    )
    let stateBefore = gate.snapshotStates()

    clock.advance(millis: 600_000)  // เงียบ 10 นาที — เกิน staleAfter 60 เท่า

    let background = IBeaconRangingManager.stepProximityBatch(
      samples: [], gate: gate, counters: [:], isForeground: false
    )
    XCTAssertTrue(background.transitions.isEmpty, "background ห้ามกวาด stale")
    XCTAssertEqual(gate.snapshotStates(), stateBefore)

    // พอกลับมา foreground รอบเดียว `stale` ต้องเกิดทันที — กฎเดิมไม่ได้หายไปไหน
    let foreground = IBeaconRangingManager.stepProximityBatch(
      samples: [], gate: gate, counters: [:], isForeground: true
    )
    XCTAssertEqual(foreground.transitions.map(\.reason), [.stale])
  }

  /// **regression guard ของเส้นทาง foreground:** ADR-22 ต้องไม่เปลี่ยนพฤติกรรมเดิม
  /// แม้แต่นิดเดียวเมื่อ `isForeground == true` — เทียบกับ [runOneCallback] ซึ่งเป็น
  /// ลำดับของ ADR-21 หัวข้อ 8 ที่มีเทสต์ล็อกไว้แล้วทั้งกลุ่ม
  func testForegroundPathIsByteForByteTheOldOrder() {
    let clockA = FakeClock()
    let clockB = FakeClock()
    let gateA = ProximityGate(clock: clockA.now, dwellSamples: 2, staleAfterMillis: 10_000)
    let gateB = ProximityGate(clock: clockB.now, dwellSamples: 2, staleAfterMillis: 10_000)

    let script: [[(key: String, bucket: ProximityBucket?)]] = [
      [(sampleKey, .far), (otherKey, .near)],
      [(sampleKey, .far), (otherKey, .near)],
      [(sampleKey, nil)],
      [],
      [(sampleKey, .immediate), (otherKey, .immediate)],
      [(sampleKey, .immediate), (otherKey, .immediate)],
      [],
    ]

    for batch in script {
      clockA.advance(millis: 4_000)
      clockB.advance(millis: 4_000)

      let viaAdr22 = IBeaconRangingManager.stepProximityBatch(
        samples: batch.map {
          IBeaconRangingManager.ProximitySample(key: $0.key, bucket: $0.bucket)
        },
        gate: gateA,
        counters: [:],
        isForeground: true
      ).transitions
      let viaOldOrder = runOneCallback(gateB, samples: batch)

      XCTAssertEqual(viaAdr22, viaOldOrder)
    }

    XCTAssertEqual(gateA.snapshotStates(), gateB.snapshotStates())
  }

  /// ค่าเริ่มต้นของ `isApplicationActive` ต้องตอบ `false` เมื่อถามจากเธรดที่ไม่ใช่
  /// main — `UIApplication.shared` เป็น main-thread-only API จริง ๆ และทางที่
  /// ปลอดภัยคือ **ไม่เดิน gate** ไม่ใช่เดินด้วยค่าที่อ่านมาแบบผิดสัญญา
  func testApplicationStateIsActiveIsFalseOffMainThread() {
    let answered = expectation(description: "off-main answer")
    var result: Bool?
    DispatchQueue.global(qos: .userInitiated).async {
      result = IBeaconRangingManager.applicationStateIsActive()
      answered.fulfill()
    }
    wait(for: [answered], timeout: 5)

    XCTAssertEqual(result, false)
  }
}
