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
}
