import CoreLocation
import Flutter

/// จัดการ path ของ iBeacon บน iOS ผ่าน **CoreLocation** (`CLLocationManager`) — ไม่ใช่
/// CoreBluetooth เพราะ iOS mask ข้อมูล iBeacon ทิ้งที่ระดับ CoreBluetooth ทั้งหมด
/// (เห็นได้แค่ peripheral identifier + RSSI) CoreLocation เป็นทางเดียวที่ได้
/// uuid/major/minor/proximity แบบถอดมาให้แล้ว — ดู ARCHITECTURE.md หัวข้อ
/// "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android"
///
/// ยิง event ผ่าน `FlutterEventSink` ทุกครั้งที่ CoreLocation เรียก
/// `locationManager(_:didRange:satisfying:)` — เป็น batch ตามที่ OS ให้มา 1:1 กับ
/// callback (ฝั่ง Dart เป็นคน flatten เป็น `BeaconAdvertisement` ทีละตัวตาม ADR-4)
final class IBeaconRangingManager: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
  private let locationManager = CLLocationManager()
  private var eventSink: FlutterEventSink?

  /// region ที่กำลัง monitor+range อยู่ตอนนี้ keyed ด้วย identifier ที่แอปกำหนดมา —
  /// ใช้ทั้งตอน stop แบบเจาะจง และตอนหา regionIdentifier กลับจาก
  /// `CLBeaconIdentityConstraint` ที่ `didRange` ส่งมา (ดู ค.ห. ท้ายไฟล์)
  private var constraintsByIdentifier: [String: CLBeaconIdentityConstraint] = [:]

  /// เพดาน region ที่ `CLLocationManager` รองรับพร้อมกันบน iOS
  private static let maxMonitoredRegions = 20

  /// region ที่ parse ผ่านแล้วแต่ยังเริ่ม range ไม่ได้ เพราะ authorization ยังเป็น
  /// `.notDetermined` (system prompt ค้างอยู่บนจอ) — จะถูกนำไปใช้จริงใน
  /// `locationManagerDidChangeAuthorization(_:)` เมื่อผู้ใช้ตอบ prompt แล้ว
  ///
  /// `results` เป็น array เพราะแอปอาจเรียก `startMonitoring` ซ้ำได้ก่อนผู้ใช้จะกด
  /// ตอบ prompt — ชุด region เอาครั้งล่าสุด (สอดคล้องกับ semantic "แทนที่ ไม่ merge")
  /// แต่ทุก `FlutterResult` ที่ค้างอยู่ต้องถูกเรียกให้ครบพอดีครั้งเดียว ไม่งั้นฝั่ง
  /// Dart จะมี Future ที่ไม่ complete ตลอดไป
  private struct PendingStart {
    var parsedRegions: [(identifier: String, constraint: CLBeaconIdentityConstraint)]
    var results: [FlutterResult]
  }
  private var pendingStart: PendingStart?

  override init() {
    super.init()
    locationManager.delegate = self
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Method channel entry points

  /// เริ่ม monitor+range iBeacon ตาม [regions] — **แทนที่**ชุดที่ monitor อยู่เดิม
  /// ทั้งหมด (ไม่ merge) แบบ all-or-nothing ต่อการเรียกแต่ละครั้ง: ถ้า region ใด
  /// region หนึ่ง parse ไม่ผ่าน จะไม่มี region ไหนถูกสร้าง/แทนที่เลย
  ///
  /// **ลำดับการตรวจ: เพดาน region -> parse/validate -> authorization**
  /// (เดิม authorization มาก่อน) เหตุผล: argument ที่ผิดรูปแบบเป็นบั๊กของผู้เรียก
  /// ควรโผล่ทันทีไม่ว่าสิทธิ์จะเป็นสถานะไหน และการจะ "พัก" คำขอไว้รอ prompt ได้
  /// ต้อง parse ให้เสร็จก่อนอยู่แล้ว
  ///
  /// **เมื่อ authorization เป็น `.notDetermined`** จะ **ไม่** เรียก [result] ทันที
  /// แต่พักคำขอไว้ใน `pendingStart` แล้วรอ `locationManagerDidChangeAuthorization(_:)`
  /// เป็นคนสรุปผล — ดูเหตุผลที่ห้ามเช็คสถานะแบบ synchronous ทันทีหลังขอสิทธิ์
  /// ที่คอมเมนต์ในตัว case เอง
  func startMonitoring(regions: [[String: Any]], result: @escaping FlutterResult) {
    // เช็คเพดาน 20 regions ก่อนสร้าง CLBeaconRegion ใด ๆ ทั้งสิ้น (ตาม ADR-4:
    // regions.count + currentlyMonitoredCount > 20)
    let currentlyMonitoredCount = locationManager.monitoredRegions.count
    if regions.count + currentlyMonitoredCount > Self.maxMonitoredRegions {
      result(
        FlutterError(
          code: "TOO_MANY_REGIONS",
          message:
            "ขอ \(regions.count) region เพิ่ม บวกกับที่ monitor อยู่แล้ว \(currentlyMonitoredCount) เกินเพดาน \(Self.maxMonitoredRegions) ของ iOS",
          details: nil
        )
      )
      return
    }

    // Parse + validate ทุก region ก่อน แล้วค่อยเริ่ม stop ของเดิม/สร้างของใหม่จริง
    // (all-or-nothing — ถ้า region ใดพัง ไม่มีการเปลี่ยนแปลง state เดิมเลย)
    var parsedRegions: [(identifier: String, constraint: CLBeaconIdentityConstraint)] = []
    for rawRegion in regions {
      guard let identifier = rawRegion["identifier"] as? String,
        let uuidString = rawRegion["uuid"] as? String
      else {
        // ขาด key ไปเลย = argument ผิดรูปแบบ ไม่ใช่ UUID พัง (INVALID_REGION_UUID
        // สงวนไว้ให้ guard ถัดไปที่ UUID(uuidString:) คืน nil เท่านั้น)
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "region ขาด identifier หรือ uuid",
            details: nil
          )
        )
        return
      }
      guard let uuid = UUID(uuidString: uuidString) else {
        result(
          FlutterError(
            code: "INVALID_REGION_UUID",
            message: "uuid '\(uuidString)' ไม่ใช่ NSUUID ที่ถูกต้อง",
            details: nil
          )
        )
        return
      }

      let major = (rawRegion["major"] as? NSNumber)?.uint16Value
      let minor = (rawRegion["minor"] as? NSNumber)?.uint16Value

      let constraint: CLBeaconIdentityConstraint
      if let major = major, let minor = minor {
        constraint = CLBeaconIdentityConstraint(uuid: uuid, major: major, minor: minor)
      } else if let major = major {
        constraint = CLBeaconIdentityConstraint(uuid: uuid, major: major)
      } else {
        constraint = CLBeaconIdentityConstraint(uuid: uuid)
      }
      parsedRegions.append((identifier: identifier, constraint: constraint))
    }

    // ใช้ instance property (`locationManager.authorizationStatus`) ไม่ใช่ class
    // method `CLLocationManager.authorizationStatus()` ที่ deprecated ตั้งแต่ iOS 14
    //
    // แปลง status -> การตัดสินใจ ผ่าน pure function ตัวเดียว (ดู
    // `authorizationDecision(for:)`) เพื่อให้ XCTest ตรวจตารางการตัดสินใจนี้ได้บน
    // simulator โดยไม่ต้องมี CLLocationManager จริง — ห้ามเขียน logic ซ้ำที่อื่น
    switch Self.authorizationDecision(for: locationManager.authorizationStatus) {
    case .denyImmediately:
      // (ก) branch แยกชัดเจน — คืน error ทันทีเสมอ **ห้าม**ไหลไปฝาก pendingStart
      // รอ delegate callback เด็ดขาด เพราะเมื่อสถานะเป็น .denied อยู่แล้ว การเรียก
      // requestAlwaysAuthorization() เป็น no-op ของ CoreLocation (ไม่มี prompt ขึ้น
      // ไม่มีการเปลี่ยนสถานะ) callback จึงไม่มีวันมา = คำขอค้างตลอดกาล
      //
      // (ข) ถ้ามีคำขอเก่าค้างอยู่ ต้องปลดให้หมดตรงนี้ด้วย ไม่ปล่อยข้ามไปครั้งถัดไป
      failPendingStart(
        message: "สิทธิ์ location ถูกปฏิเสธ/ถูกจำกัดระหว่างที่คำขอก่อนหน้ายังค้างอยู่"
      )
      result(
        FlutterError(
          code: "LOCATION_PERMISSION_DENIED",
          message: "Location permission denied/restricted",
          details: nil
        )
      )

    case .deferUntilAuthorizationCallback:
      // บั๊กที่เจอจากการทดสอบบน iPhone จริง (27 ส.ค. 2026): เดิมโค้ดตรงนี้เรียกขอ
      // สิทธิ์แล้วอ่าน authorization status ต่อทันทีแบบ synchronous ซึ่ง**ยังเป็น
      // .notDetermined อยู่เสมอ** เพราะ system prompt เพิ่งขึ้นบนจอ ผู้ใช้ยังไม่ทัน
      // กดตอบด้วยซ้ำ ผลคือการเปิดแอปครั้งแรกจะคืน error และไม่เริ่ม ranging เลย
      // แม้ผู้ใช้จะกด Allow ก็ตาม (ต้องกด start ซ้ำเองรอบสอง)
      //
      // CoreLocation คืนผลของ prompt ผ่าน delegate เท่านั้น จึงพักคำขอไว้แล้วให้
      // locationManagerDidChangeAuthorization(_:) เป็นคนเรียก result ให้ครั้งเดียว
      if pendingStart == nil {
        pendingStart = PendingStart(parsedRegions: parsedRegions, results: [result])
      } else {
        // เรียกซ้ำระหว่าง prompt ค้างอยู่ — ชุด region เอาครั้งล่าสุด แต่เก็บ result
        // ของทุกคำขอไว้ให้ครบ เพื่อไม่ให้มี Future ฝั่ง Dart ค้างไม่ complete
        pendingStart?.parsedRegions = parsedRegions
        pendingStart?.results.append(result)
      }
      locationManager.requestAlwaysAuthorization()

    case .proceed:
      // ranging ใช้ได้ทั้ง whenInUse และ always — ต่างกันแค่เรื่อง background
      applyParsedRegions(parsedRegions)
      result(nil)
    }
  }

  /// การตัดสินใจว่าจะทำอะไรต่อ เมื่อรู้ `CLAuthorizationStatus` ปัจจุบัน
  ///
  /// แยกออกมาเป็น pure function เพื่อให้ทดสอบด้วย XCTest บน simulator ได้โดยไม่
  /// ต้องมี `CLLocationManager` จริงหรืออุปกรณ์จริง — ดู
  /// `example/ios/RunnerTests/RunnerTests.swift`
  enum AuthorizationDecision: Equatable {
    /// สิทธิ์ผ่านแล้ว เริ่ม monitor+range ได้ทันที
    case proceed
    /// ยังไม่เคยถาม — ขอสิทธิ์แล้วพักคำขอไว้รอ delegate callback
    case deferUntilAuthorizationCallback
    /// ถูกปฏิเสธ/จำกัด — คืน error ทันที **ห้ามพักรอ callback** เพราะเมื่อสถานะ
    /// เป็น .denied อยู่แล้ว `requestAlwaysAuthorization()` เป็น no-op ของ
    /// CoreLocation callback จึงไม่มีวันมา (บั๊กที่เจอจากทดสอบเครื่องจริงรอบ 2)
    case denyImmediately
  }

  static func authorizationDecision(for status: CLAuthorizationStatus)
    -> AuthorizationDecision
  {
    switch status {
    case .authorizedAlways, .authorizedWhenInUse:
      return .proceed
    case .notDetermined:
      return .deferUntilAuthorizationCallback
    case .denied, .restricted:
      return .denyImmediately
    @unknown default:
      // สถานะที่เราไม่รู้จัก = ไม่รับประกันว่า callback จะมา ถือว่าไม่ได้รับสิทธิ์
      return .denyImmediately
    }
  }

  /// ปลดคำขอที่ค้างรอ prompt อยู่ทั้งหมดด้วย `LOCATION_PERMISSION_DENIED` แล้ว
  /// เคลียร์ `pendingStart` ทิ้ง — no-op ถ้าไม่มีอะไรค้าง
  ///
  /// เรียกเฉพาะตอนที่ **รู้แน่ว่า callback จะไม่มีวันมา** (สิทธิ์ถูกปฏิเสธไปแล้ว)
  /// เท่านั้น — ไม่เรียกในเคส argument ผิดรูปแบบหรือเกินเพดาน region เพราะเคส
  /// เหล่านั้นคำขอเก่ายังรอ prompt อยู่อย่างถูกต้อง delegate ยังจะมาตามปกติ
  private func failPendingStart(message: String) {
    guard let pending = pendingStart else { return }
    pendingStart = nil
    for pendingResult in pending.results {
      pendingResult(
        FlutterError(
          code: "LOCATION_PERMISSION_DENIED",
          message: message,
          details: nil
        )
      )
    }
  }

  /// แทนที่ region ที่ monitor อยู่เดิมทั้งหมดด้วย [parsedRegions] แล้วเริ่ม
  /// monitor+range ใหม่ — เรียกได้เฉพาะตอนที่ authorization ผ่านแล้วเท่านั้น
  private func applyParsedRegions(
    _ parsedRegions: [(identifier: String, constraint: CLBeaconIdentityConstraint)]
  ) {
    stopMonitoring(identifiers: nil)

    for parsedRegion in parsedRegions {
      let region = CLBeaconRegion(
        beaconIdentityConstraint: parsedRegion.constraint,
        identifier: parsedRegion.identifier
      )
      region.notifyEntryStateOnDisplay = false
      constraintsByIdentifier[parsedRegion.identifier] = parsedRegion.constraint
      locationManager.startMonitoring(for: region)
      locationManager.startRangingBeacons(satisfying: parsedRegion.constraint)
    }
  }

  /// หยุด monitor+range ตาม [identifiers] — nil = หยุดทั้งหมดที่กำลัง monitor อยู่
  func stopMonitoring(identifiers: [String]?) {
    let targetIdentifiers = identifiers ?? Array(constraintsByIdentifier.keys)
    for identifier in targetIdentifiers {
      guard let constraint = constraintsByIdentifier[identifier] else { continue }
      let region = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: identifier)
      locationManager.stopMonitoring(for: region)
      locationManager.stopRangingBeacons(satisfying: constraint)
      constraintsByIdentifier.removeValue(forKey: identifier)
    }
  }

  // MARK: - CLLocationManagerDelegate

  /// จุดที่ CoreLocation คืนผลของ system permission prompt — เป็นทางเดียวที่รู้ผล
  /// ได้จริง (อ่าน status แบบ synchronous ทันทีหลังขอสิทธิ์จะได้ .notDetermined เสมอ)
  ///
  /// callback นี้ยิงหนึ่งครั้งทันทีที่ตั้ง `locationManager.delegate` ด้วย จึงต้อง
  /// guard ว่ามีคำขอค้างอยู่จริงก่อนเสมอ
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let pending = pendingStart else { return }

    // ใช้ตารางการตัดสินใจตัวเดียวกับ startMonitoring() เพื่อไม่ให้ logic แตกเป็น
    // สองชุดที่ drift จากกันได้
    switch Self.authorizationDecision(for: manager.authorizationStatus) {
    case .deferUntilAuthorizationCallback:
      // ผู้ใช้ยังไม่ตอบ prompt — ยังไม่สรุปผล รอ callback รอบถัดไป
      return

    case .proceed:
      pendingStart = nil
      applyParsedRegions(pending.parsedRegions)
      for pendingResult in pending.results {
        pendingResult(nil)
      }

    case .denyImmediately:
      failPendingStart(message: "ผู้ใช้ปฏิเสธสิทธิ์ location จาก system prompt")
    }
  }

  func locationManager(
    _ manager: CLLocationManager,
    didRange beacons: [CLBeacon],
    satisfying beaconConstraint: CLBeaconIdentityConstraint
  ) {
    guard let eventSink = eventSink else { return }

    // CLBeaconIdentityConstraint เทียบค่าได้ (Apple ออกแบบมาให้เทียบกับ constraint
    // ที่ใช้ตอนเรียก startRangingBeacons(satisfying:) ได้โดยตรงใน callback นี้)
    guard
      let regionIdentifier = constraintsByIdentifier.first(where: { $0.value == beaconConstraint }
      )?.key
    else {
      return
    }

    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let payload: [[String: Any]] = beacons.map { beacon in
      [
        "regionIdentifier": regionIdentifier,
        "uuid": beacon.uuid.uuidString.lowercased(),
        "major": beacon.major.intValue,
        "minor": beacon.minor.intValue,
        "rssi": beacon.rssi,
        "proximity": Self.proximityString(beacon.proximity),
        "timestamp": timestamp,
      ]
    }
    eventSink(payload)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // ADR-4 ไม่ได้กำหนด error channel แยกสำหรับ ranging error รายครั้ง — ไม่มีที่ให้
    // forward ต่อไป Dart ได้ในสโคปสปรินต์นี้
  }

  private static func proximityString(_ proximity: CLProximity) -> String {
    switch proximity {
    case .immediate:
      return "immediate"
    case .near:
      return "near"
    case .far:
      return "far"
    case .unknown:
      return "unknown"
    @unknown default:
      return "unknown"
    }
  }
}
