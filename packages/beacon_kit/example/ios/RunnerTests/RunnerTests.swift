import CoreLocation
import Flutter
import UIKit
import XCTest

@testable import beacon_kit_ios

/// XCTest ที่รันได้บน **simulator** โดยไม่ต้องมี iPhone หรือ beacon จริง
///
/// ครอบคลุมอะไร: ตารางการตัดสินใจ `IBeaconRangingManager.authorizationDecision(for:)`
/// ซึ่งเป็นจุดที่บั๊กจากการทดสอบเครื่องจริงรอบ 2 เกิด — ถ้ามีใครแก้ให้ `.denied`
/// ไหลไปเข้าทาง "พักรอ callback" อีก เทสต์ชุดนี้จะแดงทันที
///
/// **ไม่ครอบคลุมอะไร (อ่านก่อนเชื่อ):** ไม่ได้รัน `CLLocationManager` จริง ไม่ได้
/// จำลอง system permission prompt และไม่ได้พิสูจน์ว่า CoreLocation เรียก delegate
/// ตามที่เราคาด — การยืนยันระดับนั้นยังต้องทำบนเครื่องจริงตาม
/// `docs/test-checklists/ios_broadcast_scanning.md`
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
}
