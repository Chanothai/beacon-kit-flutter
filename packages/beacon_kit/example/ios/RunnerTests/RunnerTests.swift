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
    // **แก้ 3 ก.ย. 2026 — unwrap ก่อนแยกแขนเสมอ:** เดิม `if let alreadyActive =
    // ..., alreadyActive` ปล่อยให้ `nil` (อ่านค่าไม่ได้ — cast delegate พัง/ไม่มี
    // delegate) ไหลลงไปแขนรอ notification ด้านล่างเงียบ ๆ แล้วจบเป็น `XCTSkip`
    // ธรรมดาในสภาพที่ดูปกติทุกอย่าง — ขัดกับเจตนาทั้งหมดของการเปลี่ยน
    // `hasEverBecomeActiveForTesting` เป็น `Bool?` (แยก "ทางผ่านของเทสต์เองพัง"
    // ออกจาก "ยังไม่เคย active") `nil` จึงต้อง **fail ทันทีตรงนี้เลย** ไม่ใช่ไหล
    // ต่อไปแขนไหนทั้งสิ้น
    let current = try XCTUnwrap(
      AppDelegate.hasEverBecomeActiveForTesting,
      "อ่านค่า hasEverBecomeActive จาก AppDelegate ไม่ได้เลย (cast "
        + "UIApplication.shared.delegate เป็น AppDelegate ไม่สำเร็จ หรือไม่มี "
        + "delegate) — นี่คือปัญหาของทางผ่านที่ใช้ทดสอบเอง ไม่ใช่บั๊กของ observer"
    )

    // ถ้าแอป active ไปแล้วก่อนเทสต์นี้เริ่ม (กรณีปกติเวลารันแบบ interactive บน
    // เครื่อง dev) `didBecomeActiveNotification` ถูก post ไปแล้วในอดีต จะไม่มีวัน
    // ถูก post ซ้ำให้ observer ที่เพิ่งลงทะเบียนในเทสต์ตอนนี้เห็นเลย — ต้องจบทันที
    // ตรงนี้ ห้ามไปรอ notification ต่อ เพราะรอเฉย ๆ จะ timeout ทุกครั้งทั้งที่ไม่มี
    // อะไรผิดปกติ (มีหลักฐานอยู่แล้วว่า observer เคยยิงสำเร็จมาก่อนหน้านี้)
    if current {
      return
    }

    // ยังไม่เคย active จริง (ไม่ใช่ `nil` — กรณีนั้นถูกดักไปแล้วด้านบน) — รอการ
    // ยืนยันจริงด้วย timeout แทนที่จะ skip ทันที
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

  // MARK: - ADR-25 §4/§4.1/§4.3 — คูลดาวน์ที่สอง 30 นาที (เพิ่มโดย beacon-qa, 16 ก.ย. 2026)
  //
  // ⚠️ **แก้ 17 ก.ย. 2026 (ADR-25 §4.3/§4.3.2, commit `ff72482`):** ฐานเวลาของ
  // ฟังก์ชันนี้เปลี่ยนจาก `ProcessInfo.processInfo.systemUptime` เป็น wall clock
  // (`Date().timeIntervalSince1970`) เพราะทิศทางของบั๊กที่ §4/§4.1 ยอมรับไว้ตอนแรก
  // กลับหัว (`systemUptime` ไม่เดินตอนเครื่องหลับ ต่างจากที่เดา) — **ชื่อฟังก์ชันและ
  // ตรรกะภายในไม่เปลี่ยนแม้แต่บรรทัดเดียว เปลี่ยนแค่ชื่อ argument label และความหมาย
  // ของค่าเวลา** ตัวเลข/assertion เดิมของเทสต์ด้านล่างยังใช้ได้ทั้งหมดตามที่ ADR
  // ยืนยันไว้ ยกเว้นชื่อ/คอมเมนต์ของเคส 6 ที่ต้องแก้เพราะความหมายของเงื่อนไข
  // `lastPosted > now` เปลี่ยนจาก "reboot แล้ว systemUptime รีเซ็ต" เป็น "นาฬิกา
  // เครื่องถูกปรับย้อนหลัง" (ดู §4.3.1/§4.3.2) และเพิ่มเทสต์ใหม่เคส 8 สำหรับช่องโหว่
  // ที่ guard นี้จับไม่ได้ (ก2 ใน §4.3.1)
  //
  // `AppDelegate.longCooldownSinceLastPostedMillisOrNull(lastPostedEpochSecondsOrZero:nowEpochSeconds:)`
  // เป็น `static func` ไม่มีการระบุ access modifier จึงเป็น `internal` ตามค่า
  // default ของ Swift — เข้าถึงได้จริงผ่าน `@testable import Runner` โดยไม่ต้อง
  // มี `AppDelegate` instance เพราะเป็น pure function ล้วน (8d31df0)
  //
  // ✅ **เคส 4 (รูปร่างของ key) เคยทดสอบที่นี่ไม่ได้ — แก้แล้วใน `6e3470d`:**
  // `proximityCooldownKey(for:)` เดิมเป็น `private func` (instance method) ซึ่ง
  // Swift `private` จำกัดการเข้าถึงไว้แค่ไฟล์เดียวกันเท่านั้น — `@testable import`
  // ไม่ทะลุ `private` เด็ดขาด ทำให้เรียกจากที่นี่ไม่ได้เลย ตอนนี้ถูกเปลี่ยนเป็น
  // `static func` แบบ default access (internal) เหมือน
  // `longCooldownSinceLastPostedMillisOrNull` แล้ว — เรียกได้ตรง ๆ ผ่าน
  // `AppDelegate.proximityCooldownKey(for:)` ด้านล่าง **ระหว่างแก้พบบั๊กจริงเพิ่ม
  // อีกข้อ (เจอโดยผู้ตรวจ commit `6e3470d`, ไม่ใช่โดยเทสต์ในไฟล์นี้ตอนนั้นเพราะ
  // ยังเรียกฟังก์ชันไม่ได้): เดิมไม่มี `.lowercased()` บน `uuid` ทำให้ key ไม่ตรงกับ
  // `ProximityKeyCodec.key()` ของ gate ฝั่ง iOS เอง (ซึ่งมี `.lowercased()`) และไม่
  // ตรงกับ `longCooldownKeyFor()` ฝั่ง Android — แก้แล้วเช่นกัน เทสต์ด้านล่างที่ส่ง
  // uuid ตัวพิมพ์ใหญ่เข้าไปยืนยันตัวพิมพ์เล็กของผลลัพธ์คือตัวที่กันบั๊กนี้ไม่ให้
  // กลับมาอีก
  //
  // ✅ **ค่าคงที่ `proximityLongNotificationCooldownSeconds` เคยเป็น `private` —
  // แก้แล้วใน `6e3470d` เช่นกัน:** ตอนนี้เป็น `static let` (internal) เทสต์ด้านล่าง
  // จึงอ้างค่าจริงตรง ๆ ผ่าน `AppDelegate.proximityLongNotificationCooldownSeconds`
  // ไม่ต้อง hardcode `30 * 60` ซ้ำอีกต่อไป — เท่ากับที่ฝั่ง Android อ้าง
  // `LONG_COOLDOWN_MILLIS` ตรง ๆ อยู่แล้ว

  /// เคส 1: ไม่เคยโพสต์คีย์นี้สำเร็จมาก่อน (`0` — sentinel ของ
  /// `UserDefaults.double(forKey:)` ที่ไม่พบ key) → ต้องยิงได้ (`nil`)
  func testLongCooldownAllowsFirstEverPostForKey() {
    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: 0,
      nowEpochSeconds: 1_000
    )

    XCTAssertNil(result, "ไม่เคยโพสต์คีย์นี้มาก่อนต้องยิงได้เสมอ")
  }

  /// เคส 2: โพสต์ครั้งที่สองภายใน 30 นาที → ต้องไม่ยิง (non-nil) **และค่า
  /// `sinceLastPostedMs` ที่คืนต้องตรงกับส่วนต่างจริง** ไม่ใช่แค่ตรวจว่า non-nil
  func testLongCooldownBlocksSecondPostWithinWindowAndReturnsExactElapsed() {
    let lastPosted: TimeInterval = 1_000
    let elapsedSeconds: TimeInterval = 5 * 60 // 5 นาที — ยังไม่ครบ 30 นาที
    let now = lastPosted + elapsedSeconds

    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPosted,
      nowEpochSeconds: now
    )

    XCTAssertEqual(
      result,
      Int64(elapsedSeconds * 1000),
      "ค่าที่คืนต้องเท่ากับ (now - lastPosted) เป็นมิลลิวินาทีเป๊ะ ไม่ใช่แค่ non-nil"
    )
  }

  /// เคส 3ก: ขอบล่าง — เหลืออีกน้อยกว่า 1 วินาทีจะครบ 30 นาที → ยังติดคูลดาวน์
  ///
  /// **อ้างค่าคงที่จริง ไม่ hardcode `30 * 60`** — `proximityLongNotificationCooldownSeconds`
  /// ถูกเปลี่ยนจาก `private` เป็น `internal` แล้ว (`6e3470d`) เทียบเท่าที่ฝั่ง
  /// Android อ้าง `LONG_COOLDOWN_MILLIS` ตรง ๆ อยู่แล้ว — ถ้าใครแก้ค่าจริงในอนาคต
  /// เทสต์นี้จะยังตรวจถูกจุดเสมอ ไม่มีค่าคู่ขนานให้ drift
  func testLongCooldownStillBlocksOneSecondBeforeWindowElapses() {
    // lastPosted ต้องไม่เป็น 0 — 0 คือ sentinel ของ "ไม่เคยโพสต์มาก่อน"
    let lastPosted: TimeInterval = 1
    let elapsed = AppDelegate.proximityLongNotificationCooldownSeconds - 1
    let now = lastPosted + elapsed

    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPosted,
      nowEpochSeconds: now
    )

    XCTAssertEqual(
      result,
      Int64(elapsed * 1000),
      "ยังไม่ครบ 30 นาที (ขาดอยู่ 1 วินาที) ต้องยังติดคูลดาวน์"
    )
  }

  /// เคส 3ข: ขอบพอดี — `now - lastPosted == 30 นาที` พอดี → ต้องยิงได้ เพราะ
  /// เงื่อนไขในโค้ดจริงเป็น `sinceSeconds < proximityLongNotificationCooldownSeconds`
  /// (ไม่ใช่ `<=`)
  func testLongCooldownAllowsExactlyAtWindowBoundary() {
    let lastPosted: TimeInterval = 1
    let now = lastPosted + AppDelegate.proximityLongNotificationCooldownSeconds

    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPosted,
      nowEpochSeconds: now
    )

    XCTAssertNil(result, "since == 30 นาทีพอดีต้องยิงได้ เพราะเงื่อนไขเป็น <")
  }

  /// เคส 3ค: เกินขอบไปแล้ว 1 วินาที → ต้องยิงได้เช่นกัน
  func testLongCooldownAllowsOneSecondAfterWindowElapses() {
    let lastPosted: TimeInterval = 1
    let now = lastPosted + AppDelegate.proximityLongNotificationCooldownSeconds + 1

    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPosted,
      nowEpochSeconds: now
    )

    XCTAssertNil(result, "เกิน 30 นาทีไปแล้วต้องยิงได้")
  }

  // MARK: - ADR-25 §4 เคส 4 — รูปร่างของ key (เปิดให้เทสได้แล้วใน `6e3470d`)
  //
  // ตัวช่วยสร้าง event สำหรับเทสกลุ่มนี้เท่านั้น — ค่า default ไม่มีความหมายพิเศษ
  // นอกจากทำให้ initializer ของ `BeaconKitProximityChangedEvent` (9 พารามิเตอร์แรก
  // + 4 ฟิลด์ log-only) เรียกสั้นลง
  private func proximityEvent(
    regionIdentifier: String = "bigc-test",
    uuid: String? = "7777772e-6b6b-6d63-6e2e-636f6d000001",
    major: UInt16? = 9902,
    minor: UInt16? = 2
  ) -> BeaconKitProximityChangedEvent {
    BeaconKitProximityChangedEvent(
      regionIdentifier: regionIdentifier,
      uuid: uuid,
      major: major,
      minor: minor,
      from: .far,
      to: .near,
      reason: .closer,
      medianMeters: 1.2,
      timestampMillis: 1_757_000_000_000,
      storeError: nil,
      rangeCallbackCount: 0,
      inArrayCount: 0,
      unknownCount: 0,
      mode: .background
    )
  }

  /// เคส 4ก: `proximityCooldownKey(for:)` ต้องได้คีย์ต่างกันเมื่อ event ต่างกัน
  /// แม้แค่ฟิลด์เดียว (region / uuid / major / minor) — ทดสอบทีละฟิลด์
  /// (เทียบเท่า `longCooldownKeyDiffersWhenAnySingleFieldDiffers` ฝั่ง Android)
  func testProximityCooldownKeyDiffersWhenAnySingleFieldDiffers() {
    let base = proximityEvent()
    let diffRegion = proximityEvent(regionIdentifier: "bigc-other")
    let diffUuid = proximityEvent(uuid: "aaaaaaaa-6b6b-6d63-6e2e-636f6d000001")
    let diffMajor = proximityEvent(major: 9903)
    let diffMinor = proximityEvent(minor: 3)

    let baseKey = AppDelegate.proximityCooldownKey(for: base)

    XCTAssertNotEqual(
      baseKey, AppDelegate.proximityCooldownKey(for: diffRegion), "region ต่างกันต้องได้คีย์ต่างกัน"
    )
    XCTAssertNotEqual(
      baseKey, AppDelegate.proximityCooldownKey(for: diffUuid), "uuid ต่างกันต้องได้คีย์ต่างกัน"
    )
    XCTAssertNotEqual(
      baseKey, AppDelegate.proximityCooldownKey(for: diffMajor), "major ต่างกันต้องได้คีย์ต่างกัน"
    )
    XCTAssertNotEqual(
      baseKey, AppDelegate.proximityCooldownKey(for: diffMinor), "minor ต่างกันต้องได้คีย์ต่างกัน"
    )
  }

  /// เคส 4ข — **เทสต์ที่กันบั๊กจริงที่พบใน `6e3470d` ไม่ให้กลับมา:** รูปร่างของ
  /// key ต้องเป็น `region|uuid|major|minor` และ `uuid` ต้อง**เป็นตัวพิมพ์เล็กเสมอ**
  /// ไม่ว่า event จะส่ง uuid มาเป็นตัวพิมพ์ใหญ่แค่ไหนก็ตาม — ต้องตรงกับ
  /// `ProximityKeyCodec.key()` ใน `packages/beacon_kit_ios/.../ProximityGate.swift`
  /// (`"\(regionIdentifier)|\(uuid.lowercased())|\(major)|\(minor)"`) เป๊ะ
  /// เพราะนี่คือหัวใจของ ADR-25 §4/§2: ถ้ารูปร่างไม่ตรงกับ key ของ gate จะกัน
  /// สแปมจากการล้าง state ไม่ได้ตรงจุด (และเคยเป็นบั๊กจริงมาก่อนแก้)
  func testProximityCooldownKeyShapeMatchesProximityKeyCodecAndLowercasesUuid() {
    let upperUuid = proximityEvent(
      uuid: "7777772E-6B6B-6D63-6E2E-636F6D000001", // ตัวพิมพ์ใหญ่โดยตั้งใจ
      major: 9902,
      minor: 2
    )

    let key = AppDelegate.proximityCooldownKey(for: upperUuid)

    XCTAssertEqual(
      key,
      "bigc-test|7777772e-6b6b-6d63-6e2e-636f6d000001|9902|2",
      "ต้องเป็น region|uuid(lowercase)|major|minor ตรงกับ ProximityKeyCodec.key() เป๊ะ"
    )
  }

  /// เคส 4ค: ฟิลด์ที่เป็น `nil` (uuid/major/minor) ต้องแทนด้วย `-` ไม่ใช่ปล่อย
  /// ว่างหรือ `"nil"`
  func testProximityCooldownKeyUsesDashForNilFields() {
    let allMissing = proximityEvent(uuid: nil, major: nil, minor: nil)

    let key = AppDelegate.proximityCooldownKey(for: allMissing)

    XCTAssertEqual(key, "bigc-test|-|-|-", "ฟิลด์ที่หายต้องเป็น - ไม่ใช่ nil หรือช่องว่าง")
  }

  /// เคส 5: cooldown รอดข้ามการที่ process ถูกฆ่าและปลุกใหม่ — **ทดสอบได้แค่
  /// บางส่วนเช่นเดียวกับฝั่ง Android** pure function นี้ไม่แตะ `UserDefaults`
  /// เลย พิสูจน์ได้แค่ว่า "ถ้าค่าที่ persist ไว้ (สมมติว่าอ่านคืนมาได้ถูกต้อง)
  /// ถูกส่งเข้ามาเป็นพารามิเตอร์ มันยังทำให้ติดคูลดาวน์เหมือนเดิม" — **ไม่ได้
  /// พิสูจน์ว่า `UserDefaults` เขียน/อ่านคืนค่าได้ถูกต้องจริงข้าม process ที่ถูก
  /// ระบบฆ่า** ส่วนนั้นเป็น I/O ที่ยืนยันได้เฉพาะบนอุปกรณ์จริงเท่านั้น
  func testLongCooldownStillBlocksWhenPersistedValueIsPassedInAfterSimulatedRestart() {
    let valueAsIfReadBackFromDefaultsAfterProcessRestart: TimeInterval = 100_000
    let elapsed: TimeInterval = 60 // 1 นาทีถัดมา
    let nowAfterRestart = valueAsIfReadBackFromDefaultsAfterProcessRestart + elapsed

    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: valueAsIfReadBackFromDefaultsAfterProcessRestart,
      nowEpochSeconds: nowAfterRestart
    )

    XCTAssertEqual(
      result,
      Int64(elapsed * 1000),
      "ค่าที่ persist ไว้ (จำลองว่าอ่านคืนมาได้) ต้องยังทำให้ติดคูลดาวน์"
    )
  }

  /// เคส 6 (ก1 ใน ADR-25 §4.3.1) — ค่าที่เก็บไว้มากกว่าเวลาปัจจุบัน → ต้องยิงได้
  ///
  /// ⚠️ **เปลี่ยนชื่อ/คอมเมนต์ 17 ก.ย. 2026 (ADR-25 §4.3/§4.3.2) — ถอนความหมายเดิม:**
  /// ชื่อเดิม `testLongCooldownAllowsWhenStoredValueIsAheadOfNowDueToReboot` และ
  /// คอมเมนต์เดิม ("เครื่อง reboot แล้ว `systemUptime` รีเซ็ตกลับไปนับจาก 0") ผูกกับ
  /// นาฬิกา `systemUptime` เดิมที่ถูกถอนไปแล้ว — ตอนนี้ฐานเวลาเป็น wall clock ซึ่ง
  /// **ไม่รีเซ็ตตอน reboot** เงื่อนไข `lastPosted > now` เดียวกันนี้จึงมีความหมายใหม่:
  /// **นาฬิกาเครื่องถูกปรับย้อนหลังมากกว่าเวลาที่ผ่านไปตั้งแต่โพสต์สำเร็จ (ก1)** เช่น
  /// เครื่องแบตหมดนานจน RTC รีเซ็ตใกล้ epoch 1970 แล้วค่อย sync ใหม่ทีหลัง — ตรรกะและ
  /// ตัวเลขเดิม (`10_000` / `5`) ยังพิสูจน์เคสนี้ได้ตรงเป๊ะ **จงใจไม่เปลี่ยนเป็นตัวเลข
  /// สเกล epoch จริง (~1.77×10⁹)** เพราะฟังก์ชันเป็น pure function ที่สนใจแค่ผลต่าง
  /// ของสองค่า ไม่สนใจสเกลสัมบูรณ์ — ตัวเลขเล็กอ่านง่ายกว่าและเป็นรูปแบบเดียวกับเทสต์
  /// อื่นในกลุ่มนี้ (เช่นเคส 2 ที่ใช้ `1_000`) การเปลี่ยนไปใช้เลข epoch จริงจะไม่เพิ่ม
  /// การครอบคลุมเคสใด ๆ มีแต่ทำให้ตัวเลขอ่านยากขึ้นเปล่า ๆ
  func testLongCooldownAllowsWhenClockWasSetBackwardsPastLastPosted() {
    let lastPostedEpochSecondsBeforeClockAdjustment: TimeInterval = 10_000
    let nowEpochSecondsAfterClockSetBackwards: TimeInterval = 5 // นาฬิกาเครื่องถูกปรับย้อนหลังผ่านจุดที่เคยโพสต์ไปแล้ว

    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPostedEpochSecondsBeforeClockAdjustment,
      nowEpochSeconds: nowEpochSecondsAfterClockSetBackwards
    )

    XCTAssertNil(
      result,
      "ค่าที่เก็บไว้มากกว่าปัจจุบันแปลว่านาฬิกาเครื่องถูกปรับย้อนหลังผ่านจุดนั้นไปแล้ว (ก1) — guard ต้องให้ยิงได้ (fail-open ตาม ADR-25 §4.3.1)"
    )
  }

  /// เคส 8 (ก2 ใน ADR-25 §4.3.1) — นาฬิกาถูกปรับย้อนหลัง **น้อยกว่า** เวลาที่ผ่านไป
  /// จริงตั้งแต่โพสต์สำเร็จ → guard `lastPosted > now` **ไม่ติด** (เพราะ `lastPosted`
  /// ยังไม่มากกว่า `now` ที่ปรับแล้ว) → ผลคือ**ยังติดคูลดาวน์อยู่** และ
  /// `sinceLastPostedMs` ที่คืนมา**น้อยกว่าเวลาจริงที่ผ่านไปจริง**เท่ากับขนาดที่ปรับ
  /// ย้อนหลัง
  ///
  /// ⚠️ **นี่คือ fail-closed ที่ ADR-25 §4.3.1 ยอมรับไว้โดยตั้งใจ ไม่ใช่พฤติกรรมที่
  /// ถูกต้องสมบูรณ์และไม่ใช่บั๊ก** — ขนาดที่ยืดออกเท่ากับ**ผลต่างสุทธิสะสมของการปรับ
  /// นาฬิกาย้อนหลังในหน้าต่างนั้น (`D`)** คือหมดอายุเมื่อเวลาจริงผ่านไป `1800 + D`
  /// วินาที ไม่ใช่ "ขนาดของการปรับครั้งนั้น" (แก้ถ้อยคำ 17 ก.ย. 2026 ตามรอบรีวิว —
  /// ฟังก์ชันเทียบแค่สองค่า ณ จุดที่ตรวจ ไม่ได้นับจำนวนครั้งที่ปรับ) ต่างจากบั๊ก
  /// `systemUptime` เดิมที่ §4.3 กำลังแก้ ตรงที่**ความถี่ของทริกเกอร์** — การปรับ
  /// นาฬิกาย้อนหลังเกิดนาน ๆ ครั้ง ส่วนการหลับของเครื่องเกิดทุกคืน (~2.7-2.8 เท่า)
  /// เทสต์นี้มีหน้าที่**ตรึงพฤติกรรมที่ยอมรับไว้ให้เป็นเอกสารที่รันได้** เท่านั้น
  /// ไม่ใช่ยืนยันว่าถูกต้อง 100% · เคส "คูลดาวน์ที่หมดอายุแล้วกลับมาติดใหม่หลังปรับ
  /// นาฬิกาย้อนหลัง" ยังไม่มีเทสครอบคลุม (บันทึกไว้ใน §4.3.1)
  ///
  /// ตัวอย่างตรงจาก ADR-25 §4.3.1: โพสต์สำเร็จตอน 10:00 · เวลาจริงผ่านไป 20 นาที
  /// (จริง ๆ คือ 10:20) · นาฬิกาเครื่องถูกปรับย้อนหลัง 10 นาทีระหว่างนั้น → `now` ที่
  /// อ่านได้จากเครื่องคือ 10:10 → `since` ที่คำนวณได้ = 10 นาที (ไม่ใช่ 20 นาทีจริง)
  /// < 30 นาที → ยังติดคูลดาวน์ (จะหมดอายุตอนนาฬิกาอ่านได้ 10:30 ซึ่งคือเวลาจริง
  /// 10:40 — คูลดาวน์กินเวลาจริง 40 นาที ยาวกว่าที่ตั้งไว้ 10 นาที เท่ากับขนาดที่
  /// ปรับย้อนหลังพอดี)
  func testLongCooldownRemainsBlockedWithUnderstatedElapsedWhenClockWasSetBackwardsLessThanElapsed() {
    let lastPostedEpochSeconds: TimeInterval = 10 * 60 * 60 // สมมติแทน "10:00" — ค่าฐานสัมบูรณ์ไม่มีผล ฟังก์ชันสนใจแค่ผลต่าง
    let realElapsedSeconds: TimeInterval = 20 * 60 // เวลาจริงที่ผ่านไปตั้งแต่โพสต์สำเร็จ (10:00 -> 10:20 จริง)
    let clockSetBackSeconds: TimeInterval = 10 * 60 // ขนาดที่นาฬิกาเครื่องถูกปรับย้อนหลังระหว่างนั้น
    let nowEpochSeconds = lastPostedEpochSeconds + realElapsedSeconds - clockSetBackSeconds // เครื่องอ่านได้ "10:10" ไม่ใช่ "10:20"

    let result = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPostedEpochSeconds,
      nowEpochSeconds: nowEpochSeconds
    )

    XCTAssertNotNil(
      result,
      "guard จับเคส (ก2) นี้ไม่ได้ (ADR-25 §4.3.1) — ยังติดคูลดาวน์ทั้งที่เวลาจริงผ่านไปแล้ว 20 นาที ไม่ใช่บั๊ก แต่เป็นความเสี่ยงที่ยอมรับไว้โดยตั้งใจ"
    )
    XCTAssertEqual(
      result,
      Int64((realElapsedSeconds - clockSetBackSeconds) * 1000),
      "sinceLastPostedMs ที่คืนมาต้องน้อยกว่าเวลาจริงที่ผ่านไป (20 นาที) อยู่พอดีเท่ากับขนาดที่ปรับย้อนหลัง (10 นาที) เหลือ 10 นาที ตามตัวอย่างใน ADR-25 §4.3.1"
    )
  }

  /// เคส 9 (เดิมกำกับเป็นเคส 7 — เลื่อนเลขให้ต่อเนื่องหลังเพิ่มเคส 8 ด้านบน
  /// 17 ก.ย. 2026, ADR-25 §4.3) — เคสหลักของ ADR-20 §12.6: "stale แล้ว near ใหม่
  /// ภายในคูลดาวน์ → ไม่ยิง" **สิ่งที่เทสต์นี้พิสูจน์ได้จริง:** ฟังก์ชันนี้ไม่รับ
  /// `BeaconKitProximityChangedEvent`/reason ใด ๆ เป็นพารามิเตอร์เลย — ผลลัพธ์
  /// ขึ้นกับ`เวลาที่ผ่านไป`เท่านั้น เรียกซ้ำด้วยพารามิเตอร์เวลาเดียวกันต้องได้ผล
  /// เดียวกันเสมอไม่ว่าผู้เรียกจะอยู่ในเส้นทางไหน (ล้าง state จาก stale/reconcile/
  /// นาฬิกาปลุก หรือเดินข้ามขอบจริง — ทุกเส้นทางเรียกฟังก์ชันเดียวกันด้วย
  /// พารามิเตอร์เวลาล้วน ๆ)
  ///
  /// ⚠️ **ข้ออ้าง "stale ไม่ล้างคูลดาวน์นี้" ไม่ได้ถูกยืนยันโดยเทสต์นี้ (หรือ
  /// เทสต์ใดในไฟล์นี้)** — เป็นข้อสรุปเชิงโครงสร้างจากการที่คูลดาวน์ 30 นาทีนี้
  /// เก็บอยู่ใน `UserDefaults(suiteName: "beacon_kit_example.notification_cooldown_v2")`
  /// (⚠️ แก้ชื่อ suite 17 ก.ย. 2026 — เดิมคอมเมนต์นี้อ้าง `..._v1` ซึ่งเป็นชื่อก่อน
  /// ADR-25 §4.3.3 เปลี่ยนเป็น `..._v2` ตอนย้ายฐานเวลาเป็น wall clock ตัวชื่อ suite
  /// เปลี่ยนไปแล้วในโค้ดจริง แต่คอมเมนต์นี้ไม่เคยถูกอัปเดตตาม)
  /// ซึ่งเป็น suite คนละอันจาก `ProximityGateStore.swift`/`ProximityGate.swift`
  /// ที่เส้นทาง `stale` แก้ไข — ไม่มีโค้ดจุดใดใน `AppDelegate.swift` เรียก
  /// `.removePersistentDomain`/ล้าง suite นี้เลย (อ่านจากซอร์สโดยตรง ไม่ได้พิสูจน์
  /// ด้วยการรันเทสต์) ยืนยันเชิง behavior เต็มรูปแบบทำได้แค่บนอุปกรณ์จริงเท่านั้น
  func testLongCooldownTimingIsIndependentOfTransitionReason() {
    let lastPosted: TimeInterval = 1_000
    let elapsed: TimeInterval = 10 * 60 // 10 นาที — ยังอยู่ในคูลดาวน์
    let now = lastPosted + elapsed

    let resultA = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPosted,
      nowEpochSeconds: now
    )
    let resultB = AppDelegate.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: lastPosted,
      nowEpochSeconds: now
    )

    XCTAssertEqual(resultA, Int64(elapsed * 1000))
    XCTAssertEqual(
      resultA,
      resultB,
      "เวลาที่ผ่านไปเท่ากันต้องได้ผลเดียวกันเสมอ ไม่ขึ้นกับ transition ใด ๆ"
    )
  }
}
