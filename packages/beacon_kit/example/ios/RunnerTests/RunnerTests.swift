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

  // MARK: - ADR-16: `AppDelegate.runContext(applicationState:hasEverBecomeActive:)`

  /// `state=active` ต้องได้ `"foreground"` **ไม่ว่า `hasEverBecomeActive` จะเป็น
  /// อะไรก็ตาม** — ตารางการตัดสินใน ADR-16 หัวข้อ 1 เช็ค `applicationState` ก่อน
  /// เสมอ ไม่สนใจ flag เลยในกรณีนี้ ทดสอบทั้งสองค่าของ flag เพื่อล็อกว่าไม่มีทาง
  /// ที่ใครจะแอบเพิ่มเงื่อนไขให้ `foreground` ขึ้นกับ `hasEverBecomeActive`
  func testActiveStateAlwaysMapsToForegroundRegardlessOfEverActiveFlag() {
    XCTAssertEqual(
      AppDelegate.runContext(applicationState: .active, hasEverBecomeActive: true),
      "foreground"
    )
    XCTAssertEqual(
      AppDelegate.runContext(applicationState: .active, hasEverBecomeActive: false),
      "foreground",
      "นี่คือรูปแบบที่ตรงกับหลักฐานบั๊กจริงใน ADR-16 หัวข้อ 0 (process ed11d170: "
        + "state=active everActive=false พร้อมกัน) — ต้องยังได้ foreground ไม่ใช่ "
        + "ค่าอื่น"
    )
  }

  /// `state=background`/`.inactive` + **เคย** active แล้ว → `"background"`
  ///
  /// ทดสอบทั้ง `.background` และ `.inactive` เพราะ `runContext` จัดสองสถานะนี้ไว้
  /// กลุ่มเดียวกัน (`case .background, .inactive:`) — ถ้าใครแยก branch ออกจากกัน
  /// ในอนาคตแล้วพลาด เทสต์นี้ต้องจับได้ทั้งคู่
  func testBackgroundOrInactiveWithPriorActiveMapsToBackground() {
    XCTAssertEqual(
      AppDelegate.runContext(applicationState: .background, hasEverBecomeActive: true),
      "background"
    )
    XCTAssertEqual(
      AppDelegate.runContext(applicationState: .inactive, hasEverBecomeActive: true),
      "background"
    )
  }

  /// `state=background`/`.inactive` + **ไม่เคย** active เลย → `"relaunchedFromTerminated"`
  ///
  /// นี่คือค่าที่ B5 ต้องเห็นในไฟล์ log จึงจะถือว่าผ่าน (ADR-16 หัวข้อ 4) — ห้ามมี
  /// ใครแก้สตริงนี้เพราะ Android (`ProcessState.kt`) และ Dart
  /// (`AppRunContext.relaunchedFromTerminated` ใน `launch_context.dart`) ผูกกับ
  /// ค่านี้เป๊ะ
  func testBackgroundOrInactiveWithoutPriorActiveMapsToRelaunchedFromTerminated() {
    XCTAssertEqual(
      AppDelegate.runContext(applicationState: .background, hasEverBecomeActive: false),
      "relaunchedFromTerminated"
    )
    XCTAssertEqual(
      AppDelegate.runContext(applicationState: .inactive, hasEverBecomeActive: false),
      "relaunchedFromTerminated"
    )
  }

  /// **เทสต์ end-to-end ตัวเดียวที่จับบั๊กคลาสนี้ได้ตั้งแต่ต้น (ADR-16 หัวข้อ 5)**
  ///
  /// สามเทสต์ข้างบนพิสูจน์แค่ว่า `runContext` เป็น pure function ที่ถูกตาม
  /// สัญญาที่เรา *คิดว่า* ถูก — พิสูจน์ไม่ได้เลยว่า
  /// `UIApplication.didBecomeActiveNotification` ถูก post จริงภายใต้ UIScene
  /// lifecycle ตามที่เอกสาร Apple อ้างใน ADR-16 หัวข้อ 1.1 (ซึ่งเป็นสมมติฐานที่
  /// บั๊กเดิมพิสูจน์แล้วว่าเชื่อไม่ได้เฉย ๆ ถ้าไม่ได้รันจริง — override
  /// `applicationDidBecomeActive` เดิมก็ "ดูเหมือนถูกต้อง" ตามสัญญาเดียวกันทุก
  /// ประการ แต่ไม่เคยถูกเรียกเลยเมื่อแอปใช้ scene)
  ///
  /// **ทำไมเทสต์นี้ทำได้จริง ไม่ใช่แค่ mock:** `RunnerTests` ถูกตั้งเป็น
  /// **hosted test bundle** (`TEST_HOST = Runner.app` ใน `project.pbxproj`) —
  /// XCTest จึงรันโค้ดนี้**ข้างในแอป `Runner` ที่ launch เต็มรูปแบบจริงบน
  /// simulator** ผ่าน `didFinishLaunchingWithOptions` ตามปกติทุกขั้นตอน
  /// (รวมถึงการลงทะเบียน observer ที่ ADR-16 เพิ่ม) ไม่ใช่การเรียกฟังก์ชันเปล่า ๆ
  /// แยกจากบริบทแอป
  ///
  /// เมื่อ test runner ของ Xcode รัน XCTest bundle มันต้องนำแอป host ขึ้นมา
  /// **foreground/active** ก่อนเสมอเพื่อ inject ตัวเทสต์เข้าไป — ถึงตอนที่เทสต์
  /// เมธอดนี้เริ่มทำงาน แอปควรจะผ่าน `didBecomeActiveNotification` มาแล้วจริง
  /// ครั้งหนึ่งตามธรรมชาติของการรัน ไม่ใช่สิ่งที่เทสต์ต้องจำลองเอง
  ///
  /// ถ้าบั๊กเดิมยังไม่ถูกแก้ (observer ไม่ทำงาน หรือแอปเลิกใช้ observer แล้วกลับไป
  /// พึ่ง `override applicationDidBecomeActive` ที่ตายภายใต้ scene) เทสต์นี้จะ
  /// **แดง** เพราะ `applicationState` เป็น `.active` จริงแต่
  /// `hasEverBecomeActiveForTesting` จะยังเป็น `false` — ตรงกับรูปแบบหลักฐานบั๊ก
  /// จริงที่บันทึกไว้ใน ADR-16 หัวข้อ 0 เป๊ะ (`state=active everActive=false`
  /// พร้อมกัน)
  ///
  /// **แก้ 3 ก.ย. 2026 — ทำให้ deterministic:** เดิมเทสต์นี้ skip ทันทีถ้าเห็น
  /// `applicationState != .active` ณ ตอนเทสต์เริ่ม ซึ่งไม่ deterministic เลย
  /// (ขึ้นกับจังหวะที่ simulator พาแอปไป active เทียบกับจังหวะที่ XCTest เริ่มรัน
  /// เทสต์เมธอด) — ขัดกับภาคผนวกข้อ 1 ของ runbook ที่บอกว่าเครื่องมือวัดต้องรอด
  /// ในสภาพที่กำลังทดสอบ ไม่ใช่หายไปเองตามจังหวะเครื่อง ตอนนี้เช็ก flag ที่ตั้งไว้
  /// แล้วก่อนเสมอ แล้วค่อย**รอ**การยืนยันจริงด้วย `XCTestExpectation` + timeout
  /// ก่อนจะ skip — skip จึงเกิดเฉพาะกรณีที่แอปไม่ยอมขึ้น active เลยภายในเวลาที่ให้
  /// จริง ๆ เท่านั้น
  func testDidBecomeActiveObserverFiresOnRealAppLifecycle() throws {
    // เช็ก flag ปัจจุบันก่อนเสมอ — **ห้ามข้ามขั้นนี้ไปรอ notification เลย**:
    // ถ้าแอป active ไปแล้วก่อนเทสต์นี้เริ่ม (กรณีปกติเวลารันแบบ interactive บน
    // เครื่อง dev) `didBecomeActiveNotification` ถูก post ไปแล้วในอดีต จะไม่มีวัน
    // ถูก post ซ้ำให้ observer ที่เพิ่งลงทะเบียนในเทสต์ตอนนี้เห็นเลย — รอเฉย ๆ จะ
    // timeout ทุกครั้งทั้งที่ไม่มีอะไรผิดปกติ
    if let alreadyActive = AppDelegate.hasEverBecomeActiveForTesting, alreadyActive {
      // มีหลักฐานอยู่แล้วว่า observer เคยยิงสำเร็จมาก่อนหน้านี้ในรอบทดสอบนี้
      return
    }

    // ยังไม่เคย active (หรืออ่านค่าไม่ได้ — กรณีนั้นจะ fail ตอน XCTUnwrap ด้านล่าง
    // ไม่ใช่ค้างเงียบ ๆ ที่นี่) — รอการยืนยันจริงด้วย timeout แทนที่จะ skip ทันที
    let becameActive = expectation(
      forNotification: UIApplication.didBecomeActiveNotification,
      object: nil,
      handler: nil
    )
    let waitResult = XCTWaiter().wait(for: [becameActive], timeout: 5.0)

    guard waitResult == .completed else {
      throw XCTSkip(
        "แอป host ไม่ได้ post didBecomeActiveNotification เลยภายใน 5 วินาที "
          + "(applicationState=\(UIApplication.shared.applicationState.rawValue) "
          + "ตอนหมดเวลา) — เทสต์นี้ต้องการสภาพแวดล้อมที่แอปจริงถูก launch ขึ้นมา "
          + "active บน simulator ไม่งั้นพิสูจน์อะไรไม่ได้ ดู ADR-16 หัวข้อ 5"
      )
    }

    // ได้รับ notification จริงแล้ว — ตรวจว่า observer ของ AppDelegate (ซึ่ง
    // ลงทะเบียนไว้ก่อนเทสต์นี้ตั้งแต่ตอน didFinishLaunchingWithOptions) ตั้ง flag
    // ทันเวลาจริง `nil` (อ่านไม่ได้เลย) ต้องทำให้เทสต์ fail ชัดเจน ไม่ใช่เงียบเป็น
    // `false` ที่ดูเหมือนผลที่ถูกต้อง (ดูเหตุผลเต็มที่ `hasEverBecomeActiveForTesting`)
    let becameActiveFlag = try XCTUnwrap(
      AppDelegate.hasEverBecomeActiveForTesting,
      "อ่านค่า hasEverBecomeActive จาก AppDelegate ไม่ได้เลย (cast "
        + "UIApplication.shared.delegate เป็น AppDelegate ไม่สำเร็จ หรือไม่มี "
        + "delegate) — นี่คือปัญหาของทางผ่านที่ใช้ทดสอบเอง ไม่ใช่บั๊กของ observer"
    )
    XCTAssertTrue(
      becameActiveFlag,
      "ได้รับ didBecomeActiveNotification จริงแล้ว แต่ hasEverBecomeActive ยังเป็น "
        + "false — แปลว่า observer ของ didBecomeActiveNotification ที่ลงทะเบียนใน "
        + "didFinishLaunchingWithOptions ไม่ทำงาน (นี่คือรูปแบบเดียวกับบั๊กเดิมที่ "
        + "ADR-16 บันทึกไว้จากอุปกรณ์จริง: state=active everActive=false พร้อมกัน)"
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
