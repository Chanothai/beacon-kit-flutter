import CoreLocation
import Flutter
import UIKit
import XCTest

@testable import Runner
@testable import beacon_kit_ios

/// XCTest ที่รันได้บน **simulator** โดยไม่ต้องมี iPhone หรือ beacon จริง
///
/// ครอบคลุมอะไร:
/// - ตารางการตัดสินใจ `IBeaconRangingManager.authorizationDecision(for:)` ซึ่ง
///   เป็นจุดที่บั๊กจากการทดสอบเครื่องจริงรอบ 2 เกิด — ถ้ามีใครแก้ให้ `.denied`
///   ไหลไปเข้าทาง "พักรอ callback" อีก เทสต์ชุดนี้จะแดงทันที
/// - (B6, ADR-6 หัวข้อ 5) ลำดับ `.authorizedWhenInUse -> .notDetermined` ที่เกิด
///   จาก "Allow Once" หมดอายุเอง — ต้องยังคง defer ได้ปกติ ไม่ error/ค้าง
/// - (B6) `IBeaconRangingManager.authorizationLevel(for:)` ตารางแปลงระดับสิทธิ์
///   ที่ส่งกลับไปยัง Dart layer ผ่าน `getIBeaconAuthorizationLevel`
///
/// **ไม่ครอบคลุมอะไร (อ่านก่อนเชื่อ):** ไม่ได้รัน `CLLocationManager` จริง ไม่ได้
/// จำลอง system permission prompt และไม่ได้พิสูจน์ว่า CoreLocation เรียก delegate
/// ตามที่เราคาด (รวมถึง `didEnterRegion`/`didExitRegion`/`didDetermineState` ของ
/// ADR-6 ที่ยังไม่มี XCTest คลุมเพราะต้องมี `CLLocationManager`/`CLRegion` จริง
/// เรียก delegate — ยืนยันได้แค่บนอุปกรณ์จริงเท่านั้น) การยืนยันระดับนั้นยังต้อง
/// ทำบนเครื่องจริงตาม `docs/test-checklists/ios_broadcast_scanning.md`
///
/// หมายเหตุ: `flutter test` **ไม่รัน**ไฟล์นี้ (เป็นคนละ test runner)
/// รันด้วย: `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
///   -destination 'platform=iOS Simulator,name=<ชื่อเครื่อง>'`
class RunnerTests: XCTestCase {

  // MARK: - ตารางการตัดสินใจ authorization

  func testAuthorizedStatusesProceedImmediately() {
    XCTAssertEqual(
      IBeaconRangingManager.authorizationDecision(for: .authorizedAlways),
      .proceed
    )
    XCTAssertEqual(
      IBeaconRangingManager.authorizationDecision(for: .authorizedWhenInUse),
      .proceed,
      "ranging ใช้ได้ด้วยสิทธิ์ whenInUse ไม่ควรบังคับ always"
    )
  }

  func testNotDeterminedDefersUntilCallback() {
    XCTAssertEqual(
      IBeaconRangingManager.authorizationDecision(for: .notDetermined),
      .deferUntilAuthorizationCallback,
      "ยังไม่เคยถาม -> ต้องขอสิทธิ์แล้วรอ delegate ห้ามอ่านสถานะแบบ synchronous"
    )
  }

  /// นี่คือเทสต์ที่กันบั๊กจากการทดสอบเครื่องจริงรอบ 2 โดยตรง
  func testDeniedNeverDefersAndFailsImmediately() {
    XCTAssertEqual(
      IBeaconRangingManager.authorizationDecision(for: .denied),
      .denyImmediately,
      "denied ต้องคืน error ทันที ห้ามพักรอ callback — requestAlwaysAuthorization() "
        + "เป็น no-op เมื่อ denied อยู่แล้ว callback จึงไม่มีวันมา = คำขอค้างตลอดกาล"
    )
    XCTAssertEqual(
      IBeaconRangingManager.authorizationDecision(for: .restricted),
      .denyImmediately
    )
  }

  /// จำลองลำดับที่ผู้ใช้เจอจริงบน iPhone: notDetermined -> denied ->
  /// กด Start ซ้ำตอน denied -> ไปเปิดสิทธิ์ใน Settings แล้วกลับมา
  func testFullSequenceFromRealDeviceReport() {
    let sequence: [CLAuthorizationStatus] = [
      .notDetermined,  // Start #1 — prompt ขึ้น
      .denied,  // ผู้ใช้กด Don't Allow
      .denied,  // Start #2 — ต้องได้ error ทันที ไม่ใช่เงียบ
      .authorizedWhenInUse,  // เปิดสิทธิ์ใน Settings แล้วกลับมา
    ]

    let decisions = sequence.map(IBeaconRangingManager.authorizationDecision(for:))

    XCTAssertEqual(
      decisions,
      [.deferUntilAuthorizationCallback, .denyImmediately, .denyImmediately, .proceed],
      "ไม่มีขั้นไหนในลำดับนี้ที่ถูกปล่อยให้เงียบ (ทุกขั้นต้องมีผลลัพธ์ชัดเจน)"
    )
  }

  // MARK: - B6 (ADR-6 หัวข้อ 5, เพิ่ม 28 ส.ค. 2026): "Allow Once" หมดอายุ

  /// ยืนยันว่า `authorizationDecision(for:)` เป็น pure function ของค่า status
  /// ปัจจุบันเท่านั้น (ไม่มี state/history ภายใน) — จำลองลำดับที่ผู้ใช้เลือก
  /// "Allow Once" ตอน prompt (รายงานเป็น `.authorizedWhenInUse` ชั่วคราวตาม
  /// ARCHITECTURE.md ADR-6 หัวข้อ 5) แล้ว CoreLocation เปลี่ยนสถานะกลับเป็น
  /// `.notDetermined` เองเมื่อจบ session โดยไม่มี action ของผู้ใช้ที่มองเห็น
  /// ชัดเจน — ถ้าแอปเรียก `startIBeaconMonitoring` ใหม่ตอนนั้น ต้องขอสิทธิ์ใหม่
  /// ตามปกติ (defer + prompt) ไม่ใช่ error/ค้าง
  func testAllowOnceExpiryReturnsToDeferNotErrorOrHang() {
    let sequence: [CLAuthorizationStatus] = [
      .notDetermined,  // Start #1 — prompt ขึ้น
      .authorizedWhenInUse,  // ผู้ใช้กด "Allow Once" (หรือ "While Using the App")
      // — แยกไม่ออกจากค่านี้อย่างเดียวตาม ADR-6 หัวข้อ 5
      .notDetermined,  // "Allow Once" หมดอายุเอง (session จบ) — ไม่ใช่บั๊ก
      // เป็นพฤติกรรมตั้งใจของ CoreLocation ตามเอกสาร
    ]

    let decisions = sequence.map(IBeaconRangingManager.authorizationDecision(for:))

    XCTAssertEqual(
      decisions,
      [.deferUntilAuthorizationCallback, .proceed, .deferUntilAuthorizationCallback],
      "notDetermined ที่เกิดจาก Allow Once หมดอายุ ต้องได้ผลเดียวกับ notDetermined "
        + "ที่ยังไม่เคยถามเลย (defer + ขอสิทธิ์ใหม่) ห้าม error หรือค้าง — ฟังก์ชันนี้"
        + "ต้องไม่พึ่ง history ใด ๆ เพราะ CoreLocation เองก็ไม่แยกสองเคสนี้ให้เรา"
    )
  }

  /// เช่นเดียวกับด้านบน แต่ตรวจแบบเจาะจงว่า `.notDetermined` (ไม่ว่าจะมาจากไหน)
  /// map ไปที่ `.deferUntilAuthorizationCallback` เสมอ — กันไม่ให้ในอนาคตมีใคร
  /// พยายามเพิ่ม branch พิเศษแยก "notDetermined ครั้งแรก" กับ "notDetermined
  /// หลัง Allow Once หมดอายุ" ออกจากกัน (ซึ่งเป็นไปไม่ได้อยู่แล้วเพราะ
  /// CLAuthorizationStatus ไม่มีข้อมูลนั้นให้)
  func testNotDeterminedAfterWhenInUseStillDefersRegardlessOfHistory() {
    XCTAssertEqual(
      IBeaconRangingManager.authorizationDecision(for: .notDetermined),
      .deferUntilAuthorizationCallback
    )
  }

  // MARK: - B6: authorizationLevel(for:) — สื่อสารระดับสิทธิ์จริงกลับไปยัง Dart

  func testAuthorizationLevelAlwaysMapsToAlways() {
    XCTAssertEqual(
      IBeaconRangingManager.authorizationLevel(for: .authorizedAlways),
      .always
    )
  }

  /// `.authorizedWhenInUse` ครอบคลุมทั้ง "Allow Once" ชั่วคราวและ "When In Use"
  /// ถาวร — ตั้งใจ map ไปที่ค่าเดียวกัน (`.whenInUse`) เพราะแยกไม่ออกจริงจาก
  /// `CLAuthorizationStatus` เพียงอย่างเดียว (ยืนยันจาก ADR-6 หัวข้อ 5)
  func testAuthorizationLevelWhenInUseMapsToWhenInUseRegardlessOfAllowOnce() {
    XCTAssertEqual(
      IBeaconRangingManager.authorizationLevel(for: .authorizedWhenInUse),
      .whenInUse
    )
  }

  func testAuthorizationLevelInsufficientCases() {
    XCTAssertEqual(
      IBeaconRangingManager.authorizationLevel(for: .notDetermined),
      .insufficient
    )
    XCTAssertEqual(
      IBeaconRangingManager.authorizationLevel(for: .denied),
      .insufficient
    )
    XCTAssertEqual(
      IBeaconRangingManager.authorizationLevel(for: .restricted),
      .insufficient
    )
  }

  // MARK: - Data Protection ของไฟล์ log (ความเสี่ยงของ B5)

  /// สถานการณ์จริงของ B5 คือมือถืออยู่ในกระเป๋า **จอล็อก** แล้วแอปถูกปลุก
  /// ถ้าไฟล์ log ได้ protection class ที่เข้มเกินไป (`.complete`) การเขียนจะล้มเหลว
  /// ตอนเครื่องล็อก = **แอปตื่นจริงแต่ไม่มีหลักฐาน** แล้วจะสรุปผิดว่า B5 ไม่ผ่าน
  ///
  /// **ข้อจำกัดที่ยืนยันด้วยการรันจริงแล้ว (สำคัญ อย่าลบคอมเมนต์นี้):**
  /// บน **simulator** `attributesOfItem` คืน `.protectionKey` เป็น `nil` เสมอ
  /// แม้เราจะเรียก `setAttributes` สำเร็จ — เพราะ simulator ไม่ได้ implement
  /// Data Protection จริง (ไม่มี Secure Enclave ไม่มีสถานะล็อกแบบเครื่องจริง)
  /// เทสต์นี้จึง **skip บน simulator** และจะ assert จริงเมื่อรันบนอุปกรณ์จริงเท่านั้น
  ///
  /// การยืนยันว่า "เขียนได้จริงตอนเครื่องล็อก" เป็น **Track B** ต้องทดสอบบนอุปกรณ์
  /// จริงตามเช็คลิสต์หัวข้อ 13 — เทสต์นี้ต่อให้ผ่านบนเครื่องจริงก็พิสูจน์แค่ว่า
  /// attribute ถูกตั้ง ไม่ได้พิสูจน์ว่า iOS ยอมให้เขียนตอนล็อก
  func testLogFileGetsExplicitProtectionClassNotDefault() throws {
    let fileName = "protection_probe_\(UUID().uuidString).log"

    let path = try AppDelegate.prepareLogFileForTesting(named: fileName)
    defer { try? FileManager.default.removeItem(atPath: path) }

    XCTAssertTrue(
      FileManager.default.fileExists(atPath: path),
      "prepareLogFile ต้องสร้างไฟล์จริง (ส่วนนี้ทดสอบได้ทุกที่)"
    )

    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let protection = attributes[.protectionKey] as? FileProtectionType else {
      throw XCTSkip(
        "แพลตฟอร์มนี้ไม่รายงาน .protectionKey (simulator ไม่ implement Data "
          + "Protection) — ต้องรันบนอุปกรณ์จริงถึงจะตรวจข้อนี้ได้ ดู Track B "
          + "เช็คลิสต์หัวข้อ 13"
      )
    }

    XCTAssertEqual(
      protection,
      .completeUntilFirstUserAuthentication,
      "ไฟล์ log ต้องได้ completeUntilFirstUserAuthentication เพื่อให้เขียนได้ตอน "
        + "เครื่องล็อก (หลังปลดล็อกครั้งแรกหลังบูต) — ถ้าเป็น .complete จะเขียนไม่ได้ "
        + "ตอนถูกปลุกขณะจอล็อก ซึ่งทำให้เสียหลักฐานของ B5 ทั้งรอบ"
    )
  }

  /// เขียนต่อท้ายไฟล์ที่เตรียมไว้ได้จริง และ protection class ไม่ถูกรีเซ็ตหลังเขียน
  ///
  /// ส่วน "เขียนต่อท้ายได้" ทดสอบได้ทุกแพลตฟอร์ม (Track A) ส่วน protection class
  /// skip บน simulator ด้วยเหตุผลเดียวกับเทสต์ด้านบน
  func testAppendWriteWorksAndProtectionClassSurvives() throws {
    let fileName = "protection_append_\(UUID().uuidString).log"

    let path = try AppDelegate.prepareLogFileForTesting(named: fileName)
    defer { try? FileManager.default.removeItem(atPath: path) }

    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("probe line\n".utf8))
    try handle.close()

    let contents = try String(contentsOfFile: path, encoding: .utf8)
    XCTAssertTrue(
      contents.contains("probe line"),
      "ต้องเขียนต่อท้ายไฟล์ที่ prepareLogFile เตรียมไว้ได้จริง"
    )

    guard let after = AppDelegate.protectionOfLogFile(named: fileName) else {
      throw XCTSkip(
        "แพลตฟอร์มนี้ไม่รายงาน .protectionKey (simulator) — ตรวจบนอุปกรณ์จริงเท่านั้น"
      )
    }
    XCTAssertEqual(
      after,
      FileProtectionType.completeUntilFirstUserAuthentication.rawValue,
      "protection class ต้องไม่เปลี่ยนหลังเขียนต่อท้าย"
    )
  }

  /// prepareLogFile ต้องเรียกซ้ำได้โดยไม่ทำลายเนื้อหาเดิม — สำคัญเพราะโค้ดจริง
  /// เรียกทุกครั้งก่อน append เพื่อให้ protection class ถูกตั้งเสมอ ถ้ามันล้าง
  /// ไฟล์ทุกครั้ง หลักฐานทั้งหมดจะเหลือบรรทัดเดียว
  func testPrepareLogFileIsIdempotentAndDoesNotTruncate() throws {
    let fileName = "protection_idempotent_\(UUID().uuidString).log"

    let path = try AppDelegate.prepareLogFileForTesting(named: fileName)
    defer { try? FileManager.default.removeItem(atPath: path) }
    try "line one\n".write(toFile: path, atomically: true, encoding: .utf8)

    let pathAgain = try AppDelegate.prepareLogFileForTesting(named: fileName)

    XCTAssertEqual(path, pathAgain, "path ต้องคงที่ทุกครั้งที่เรียก")
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    XCTAssertEqual(
      contents,
      "line one\n",
      "เรียกซ้ำต้องไม่ล้างเนื้อหาเดิม ไม่งั้นหลักฐานจะเหลือบรรทัดเดียว"
    )
  }

  // MARK: - ADR-10: กู้ region ที่ระบบเก็บไว้ข้าม launch กลับมา

  /// จุดที่ทำให้ B5 รอบ 30 ส.ค. 2026 ไม่ผ่าน: process ใหม่ที่ถูกปลุกขึ้นมามี
  /// `constraintsByIdentifier` ว่างเปล่าเสมอ ทำให้ `emitRegionStateIfChanged`
  /// ทิ้ง event ทิ้งเงียบ ๆ — เทสต์นี้ล็อกไว้ว่า region ที่ระบบเก็บไว้ให้ต้องถูก
  /// อ่านกลับมาได้ครบพร้อม uuid/major/minor
  func testConstraintsAreRestoredFromSystemMonitoredRegions() {
    let uuid = UUID(uuidString: "7777772E-6B6B-6D63-6E2E-636F6D000001")!
    let fleetWide = CLBeaconRegion(
      beaconIdentityConstraint: CLBeaconIdentityConstraint(uuid: uuid),
      identifier: "bigc-fleet-wide"
    )
    let branch = CLBeaconRegion(
      beaconIdentityConstraint: CLBeaconIdentityConstraint(uuid: uuid, major: 1234),
      identifier: "branch-1234"
    )

    let restored = IBeaconRangingManager.constraints(
      fromMonitoredRegions: [fleetWide, branch]
    )

    XCTAssertEqual(Set(restored.keys), ["bigc-fleet-wide", "branch-1234"])
    XCTAssertEqual(restored["bigc-fleet-wide"]?.uuid, uuid)
    XCTAssertNil(restored["bigc-fleet-wide"]?.major)
    XCTAssertEqual(restored["branch-1234"]?.major, 1234)
    XCTAssertNil(restored["branch-1234"]?.minor)
  }

  /// region ที่ไม่ใช่ beacon (เช่นของ SDK อื่นในแอปเดียวกัน) ต้องถูกข้าม ไม่ใช่
  /// ทำให้ทั้งชุดพัง — และที่สำคัญกว่าคือเราต้องไม่ไปยุ่งกับมัน
  func testNonBeaconRegionsAreIgnoredNotAdopted() {
    let circular = CLCircularRegion(
      center: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018),
      radius: 100,
      identifier: "someone-elses-geofence"
    )
    let beacon = CLBeaconRegion(
      beaconIdentityConstraint: CLBeaconIdentityConstraint(
        uuid: UUID(uuidString: "7777772E-6B6B-6D63-6E2E-636F6D000001")!
      ),
      identifier: "bigc-fleet-wide"
    )

    let restored = IBeaconRangingManager.constraints(
      fromMonitoredRegions: [circular, beacon]
    )

    XCTAssertEqual(Array(restored.keys), ["bigc-fleet-wide"])
  }

  // MARK: - ADR-10: รูปแบบบรรทัด log ฝั่ง native

  /// หน้า "ดู log" ฝั่ง Dart แยกคอลัมน์ด้วย TAB — ถ้ารูปแบบเพี้ยน หลักฐานที่เก็บมา
  /// ทั้งรอบทดสอบจะอ่านไม่ออก เทสต์นี้จึงล็อกจำนวนคอลัมน์และลำดับไว้
  ///
  /// **6 คอลัมน์ตั้งแต่ ADR-14** — เพิ่ม `processId` เป็นคอลัมน์ที่ 2 ตัวอ่านฝั่ง
  /// Dart ยังต้องอ่านไฟล์เก่า 5 คอลัมน์ได้อยู่ (ดู `LogEntry.tryParse`)
  func testLogLineHasSixTabSeparatedColumnsInOrder() {
    let line = BackgroundEvidenceLog.line(
      timestamp: Date(timeIntervalSince1970: 0),
      processId: "a1b2c3d4",
      event: "enter",
      regionIdentifier: "bigc-fleet-wide",
      conclusion: "relaunchedFromTerminated",
      rawSignals: "launchKey=true everActive=false state=background uptime=0.4s"
    )

    let columns = line.components(separatedBy: "\t")
    XCTAssertEqual(columns.count, 6)
    XCTAssertEqual(columns[1], "a1b2c3d4")
    XCTAssertEqual(columns[2], "enter")
    XCTAssertEqual(columns[3], "bigc-fleet-wide")
    XCTAssertEqual(columns[4], "relaunchedFromTerminated")
    XCTAssertEqual(columns[5], "launchKey=true everActive=false state=background uptime=0.4s")
  }

  /// **ตัวระบุ process ต้องอยู่ครบทั้งสี่ค่า เรียงเหมือนฝั่ง Android**
  ///
  /// คู่แฝดของ `ตัวระบุ process มีครบสี่ค่าและเรียงตรงกับฝั่ง iOS` ใน
  /// `BackgroundEvidenceLogTest.kt` — ถ้าลำดับหรือชื่อ key ต่างกันแม้แค่ตัวเดียว
  /// การ `grep` ไฟล์ของสองแพลตฟอร์มด้วยคำสั่งเดียวกันจะได้ผลไม่เท่ากัน ซึ่งทำให้
  /// "เทียบ iOS กับ Android" กลายเป็นการเทียบสิ่งที่วัดคนละวิธี
  func testProcessMarkerHasAllFourKeysInOrder() {
    let marker = BackgroundEvidenceLog.processMarker(
      uptimeMillis: 1234,
      receiverEntry: true,
      processId: "a1b2c3d4",
      pid: 4242
    )

    XCTAssertEqual(marker, "procUuid=a1b2c3d4 pid=4242 uptimeMs=1234 receiverEntry=true")
  }

  /// `uptimeMs` ต้องเป็น **จำนวนเต็มมิลลิวินาที** ไม่ใช่วินาทีทศนิยมแบบเดิม
  ///
  /// ช่วงที่ต้องแยกให้ออกคือหลักร้อยมิลลิวินาที: event ที่มาถึงทันทีหลัง process
  /// เกิดคือหลักฐานว่า iOS สร้าง process ขึ้นมาเพื่อ event นั้น ถ้าปัดเป็น `0.4s`
  /// ความต่างระหว่าง 350 ms กับ 449 ms จะหายไป
  func testProcessMarkerUsesIntegerMilliseconds() {
    let marker = BackgroundEvidenceLog.processMarker(
      uptimeMillis: 350,
      receiverEntry: false,
      processId: "a1b2c3d4",
      pid: 4242
    )

    XCTAssertTrue(marker.contains(" uptimeMs=350 "), "ได้ \(marker)")
    XCTAssertTrue(marker.hasSuffix("receiverEntry=false"), "ได้ \(marker)")
  }

  /// `procUuid` ในสัญญาณดิบต้อง **เป็นค่าเดียวกับคอลัมน์ที่ 2 เสมอ**
  ///
  /// ทั้งสองที่ตั้งใจให้ซ้ำกัน (คอลัมน์ที่ 2 ไว้ให้คนอ่าน / key ไว้ให้เครื่องอ่าน
  /// คู่กับ pid+uptimeMs) — แต่ "ซ้ำกัน" มีค่าก็ต่อเมื่อ **ขัดแย้งกันไม่ได้**
  /// ถ้าวันหนึ่งสองที่มาจากคนละแหล่ง ไฟล์หลักฐานจะมีสองคำตอบสำหรับคำถามเดียว
  func testProcMarkerUuidMatchesSecondColumn() {
    let line = BackgroundEvidenceLog.line(
      timestamp: Date(timeIntervalSince1970: 0),
      event: "enter",
      regionIdentifier: "bigc-fleet-wide",
      conclusion: "relaunchedFromTerminated",
      rawSignals: BackgroundEvidenceLog.processMarker(
        uptimeMillis: 0,
        receiverEntry: true,
        pid: 4242
      )
    )

    let columns = line.components(separatedBy: "\t")
    XCTAssertTrue(
      columns[5].hasPrefix("procUuid=\(columns[1]) "),
      "procUuid ในสัญญาณดิบต้องตรงกับคอลัมน์ที่ 2 ได้ \(columns[5])"
    )
  }

  /// `processId` ต้องเป็นค่าที่**อ่านได้ด้วยตาบนหน้าจอมือถือ** และคงที่ตลอดอายุ
  /// process เดียวกัน — ถ้ามันเปลี่ยนระหว่าง process การแยก "process ใหม่" ออกจาก
  /// "process เดิม" จะพังทันที ซึ่งเป็นเหตุผลเดียวที่คอลัมน์นี้มีอยู่
  func testProcessIdIsStableEightHexCharacters() {
    let first = BackgroundEvidenceLog.processId
    let second = BackgroundEvidenceLog.processId

    XCTAssertEqual(first, second, "processId ต้องไม่เปลี่ยนภายใน process เดียวกัน")
    XCTAssertNotNil(
      first.range(of: "^[0-9a-f]{8}$", options: .regularExpression),
      "processId ต้องเป็นเลขฐานสิบหกตัวพิมพ์เล็ก 8 ตัว ได้ \(first)"
    )
  }

  /// ค่า default ของ `processId` ต้องถูกใช้จริงเมื่อผู้เรียกไม่ส่งมา — เส้นทางที่
  /// โค้ดจริงทั้งหมดใช้ ถ้าพลาดตรงนี้ log จะไม่มีตัวระบุ process เลยโดยไม่มีใครรู้
  func testLogLineUsesProcessIdByDefault() {
    let line = BackgroundEvidenceLog.line(
      timestamp: Date(timeIntervalSince1970: 0),
      event: "launch",
      regionIdentifier: "-",
      conclusion: "foreground",
      rawSignals: "-"
    )

    XCTAssertEqual(
      line.components(separatedBy: "\t")[1],
      BackgroundEvidenceLog.processId
    )
  }

  /// timestamp ต้องเป็นเวลา **local พร้อม offset** ไม่ใช่ UTC ล้วน และต้องเป็น
  /// ปฏิทินเกรกอเรียนเสมอ — เครื่องที่ตั้งปฏิทินพุทธ (พบทั่วไปในไทย) ต้องไม่ได้
  /// ปี 2569 ใน log ไม่งั้นเทียบเวลากับ log ฝั่งอื่นไม่ได้เลย
  func testLogTimestampIsGregorianLocalTimeWithOffset() {
    let stamp = BackgroundEvidenceLog.iso8601WithOffset(Date(timeIntervalSince1970: 0))

    // ตรวจ**รูปแบบ** ไม่ใช่ค่าเวลา เพราะค่าขึ้นกับ timezone ของเครื่องที่รันเทสต์
    // (epoch 0 เป็น 1970-01-01 ที่กรุงเทพ แต่เป็น 1969-12-31 ที่ฝั่งอเมริกา)
    let pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}([+-][0-9]{2}:[0-9]{2}|Z)$"
    XCTAssertNotNil(
      stamp.range(of: pattern, options: .regularExpression),
      "รูปแบบ timestamp ไม่ตรง ได้ \(stamp)"
    )
    // ปีต้องเป็นเกรกอเรียน ไม่ใช่ปฏิทินพุทธ (2512/2513) ไม่ว่าเครื่องจะตั้ง locale ไหน
    XCTAssertTrue(
      stamp.hasPrefix("1969-") || stamp.hasPrefix("1970-"),
      "ปีไม่ใช่เกรกอเรียน ได้ \(stamp)"
    )
  }
}
