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
///
/// **ตั้งแต่ ADR-6 (28 ส.ค. 2026):** นอกจาก ranging แล้ว คลาสนี้ยังรับผิดชอบ
/// region monitoring แบบเต็มรูป (`didEnterRegion`/`didExitRegion`/
/// `didDetermineState`) และยิง event ผ่าน channel ที่สองแยกต่างหาก
/// (`beacon_kit_ios/region_state_events`, ดู [regionStateStreamHandler]) —
/// อยู่ในคลาสเดียวกับ ranging เพราะทั้งคู่เป็น `CLLocationManagerDelegate`
/// callback ของ `CLLocationManager` instance เดียวกัน ไม่มีเหตุผลให้แยกคลาส
final class IBeaconRangingManager: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
  private let locationManager = CLLocationManager()
  private var eventSink: FlutterEventSink?

  /// stream handler ของ event channel ที่สอง (region state) — เป็นคลาสแยกเพราะ
  /// `FlutterEventChannel.setStreamHandler(_:)` รับ 1 handler ต่อ 1 channel และ
  /// handler หนึ่งตัวมี `onListen`/`onCancel` ได้แค่ชุดเดียว ผูก `eventSink` ของ
  /// ranging channel ปนกับของ region-state channel ในเมธอดเดียวกันไม่ได้ — ดู
  /// [RegionStateEventStreamHandler] ท้ายไฟล์นี้
  let regionStateStreamHandler = RegionStateEventStreamHandler()

  /// region ที่กำลัง monitor+range อยู่ตอนนี้ keyed ด้วย identifier ที่แอปกำหนดมา —
  /// ใช้ทั้งตอน stop แบบเจาะจง และตอนหา regionIdentifier กลับจาก
  /// `CLBeaconIdentityConstraint` ที่ `didRange` ส่งมา (ดู ค.ห. ท้ายไฟล์) รวมถึงหา
  /// uuid/major/minor กลับจาก `region.identifier` ที่ `didEnterRegion`/
  /// `didExitRegion`/`didDetermineState` ส่งมา (ต่างจาก `didRange` ตรงที่
  /// `CLRegion` มี `identifier` ตรงตัวอยู่แล้ว ไม่ต้องเทียบ constraint)
  private var constraintsByIdentifier: [String: CLBeaconIdentityConstraint] = [:]

  /// state ล่าสุดที่รู้ต่อ region identifier หนึ่งตัว — ใช้ dedupe ระหว่าง
  /// `didDetermineState` (ตอน `requestState(for:)` ตอบกลับ) กับ
  /// `didEnterRegion`/`didExitRegion` (ตอน boundary transition จริง) ดูเหตุผล
  /// เต็มที่ [emitRegionStateIfChanged(_:for:)]
  private var lastKnownRegionState: [String: RegionMonitoringState] = [:]

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

  /// hook ให้ **โค้ด native ของ host app** รับ region event ได้ตรง ๆ โดยไม่ผ่าน
  /// Flutter engine เลย
  ///
  /// **ทำไมต้องมี:** เส้นทางปกติของ event คือ `FlutterEventSink` -> Dart ซึ่ง
  /// ใช้ได้ก็ต่อเมื่อ Flutter engine ถูกสร้างและ Dart subscribe แล้ว แต่ตอน iOS
  /// ปลุก process ที่ถูกฆ่าขึ้นมาเบื้องหลังเพื่อส่ง region event (B5) engine อาจ
  /// ยังไม่ถูกสร้างเลย (ดูเหตุผลเต็มใน ARCHITECTURE.md ADR-10) — ถ้าไม่มีทาง
  /// ออกที่เป็นอิสระจาก Dart แอปจะตื่นจริงแต่ไม่มีใครเห็นและไม่มีหลักฐานเหลือไว้
  ///
  /// SDK **ไม่** ตัดสินใจแทนว่า host จะทำอะไรกับ event (เขียน log/ยิง
  /// notification/ส่งขึ้น server) — เป็นแค่ hook เปล่า ๆ ตามหลักที่ว่า SDK ไม่ควร
  /// บังคับให้ผู้ใช้พึ่ง framework ใด framework หนึ่ง
  var onRegionStateEvent: ((BeaconKitRegionStateEvent) -> Void)?

  /// instance เดียวที่ทั้งแอปใช้ร่วมกัน
  ///
  /// **จำเป็นต้องเป็น singleton** เพราะตั้งแต่ ADR-10 มีผู้สร้างสองทางที่ต้องได้
  /// ตัวเดียวกัน: (1) `BeaconKitIosPlugin.startBackgroundRegionMonitoring()` ที่
  /// host app เรียกจาก `didFinishLaunchingWithOptions` และ (2)
  /// `BeaconKitIosPlugin.register(with:)` ที่เกิดทีหลังตอน Flutter engine พร้อม
  /// ถ้าเป็นคนละ instance จะมี `CLLocationManager` สองตัวที่ `constraintsByIdentifier`
  /// และ `lastKnownRegionState` แยกกัน — และตาม Apple docs ของ `didEnterRegion`
  /// ("every active location manager object delivers this message to its
  /// associated delegate") ทั้งคู่จะได้ callback เดียวกัน กลายเป็น event ซ้ำสองชุด
  static let shared = IBeaconRangingManager()

  /// identifier ของ region ที่ระบบกำลัง monitor อยู่จริง ณ ตอนนี้
  ///
  /// อ่านจาก `locationManager.monitoredRegions` โดยตรง ไม่ใช่จาก state ในหน่วย
  /// ความจำของเรา เพื่อให้ใช้เป็นหลักฐานได้ว่า "region รอดข้าม process มาจริง"
  var monitoredRegionIdentifiers: [String] {
    locationManager.monitoredRegions.map(\.identifier).sorted()
  }

  override init() {
    super.init()
    locationManager.delegate = self

    // **ห้ามเรียก stopMonitoring/stopMonitoringForRegion: ใด ๆ ในเส้นทางนี้เด็ดขาด**
    // (ADR-10) — region ที่ระบบเก็บไว้ให้คือสิ่งเดียวที่ทำให้ iOS ปลุกแอปขึ้นมา
    // ตอนถูกฆ่า ถ้าโค้ด init ของเราไปล้างทิ้ง แอปจะไม่มีวันถูกปลุกอีกเลยและ
    // อาการจะออกมาเหมือน "ไม่รองรับ background" ทั้งที่จริงเราลบมันเอง
    // ตรงนี้ทำแค่ **อ่าน** ชุด region ที่ระบบเก็บไว้กลับเข้ามาเป็น state ของเรา
    adoptSystemMonitoredRegions()
  }

  /// อ่าน region ที่ระบบเก็บไว้ข้าม launch กลับเข้ามาใส่ `constraintsByIdentifier`
  ///
  /// **ทำไมต้องทำ:** header ของ `monitoredRegions` ระบุว่า "If any location manager
  /// has been instructed to monitor a region, **during this or previous launches
  /// of your application**, it will be present in this set."
  /// (CLLocationManager.h:420-422, iPhoneOS26.5.sdk) — แปลว่าตอน process ใหม่ถูก
  /// ปลุกขึ้นมา region ยังลงทะเบียนอยู่กับระบบครบ แต่ `constraintsByIdentifier`
  /// ของเราเป็น dictionary ในหน่วยความจำที่ **ว่างเปล่า** เสมอใน process ใหม่
  /// เพราะมีแต่ `applyParsedRegions` (ซึ่งวิ่งได้ต่อเมื่อ Dart เรียกเข้ามา)
  /// เท่านั้นที่เติมค่าให้ ผลคือ `emitRegionStateIfChanged` มองไม่เห็น constraint
  /// แล้วทิ้ง event เงียบ ๆ — event มาถึงจริงแต่ไม่มีใครรู้
  private func adoptSystemMonitoredRegions() {
    for (identifier, constraint) in Self.constraints(
      fromMonitoredRegions: locationManager.monitoredRegions
    ) where constraintsByIdentifier[identifier] == nil {
      constraintsByIdentifier[identifier] = constraint
    }
  }

  /// ส่วนที่เป็น pure function ของ [adoptSystemMonitoredRegions] — แยกออกมาเพื่อให้
  /// XCTest ตรวจได้โดยไม่ต้องมี `CLLocationManager` จริง
  ///
  /// ข้าม region ที่ไม่ใช่ `CLBeaconRegion` ทิ้ง (เช่น `CLCircularRegion` ที่ SDK
  /// อื่นในแอปเดียวกันลงทะเบียนไว้) เพราะ payload ของ ADR-6 ต้องการ
  /// uuid/major/minor ซึ่ง region ประเภทอื่นไม่มี — และ**ไม่**หยุด monitor
  /// region เหล่านั้นด้วย มันไม่ใช่ของเรา
  static func constraints(
    fromMonitoredRegions regions: Set<CLRegion>
  ) -> [String: CLBeaconIdentityConstraint] {
    var result: [String: CLBeaconIdentityConstraint] = [:]
    for region in regions {
      guard let beaconRegion = region as? CLBeaconRegion else { continue }
      result[beaconRegion.identifier] = beaconRegion.beaconIdentityConstraint
    }
    return result
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
      // ranging/monitoring เริ่มได้ทั้ง whenInUse และ always ตัวโค้ดนี้เอง
      // ไม่ต้องแยก branch ตามระดับสิทธิ์ — ต่างกันแค่เรื่อง background wake
      // หลังแอปโดน terminate (Always เท่านั้น ตาม ADR-6 หัวข้อ 3) ซึ่งเป็นเรื่อง
      // ที่ Dart layer ต้อง "รู้" ไม่ใช่เรื่องที่ native ต้องบล็อกการทำงาน — ดู
      // ADR-6 หัวข้อ 5 (B6): `.authorizedWhenInUse` ไม่ได้แปลว่า background
      // monitoring จะทำงานเต็มรูปเสมอไป (อาจเป็นแค่ "Allow Once" ชั่วคราว หรือ
      // "When In Use" ถาวรที่ผู้ใช้ตั้งใจเลือก — แยกไม่ออกจากค่า status อย่าง
      // เดียว) เพื่อไม่ให้ caller เข้าใจผิดว่า background wake ทำงานได้เต็มรูปทั้ง
      // ที่จริงจะไม่ปลุกแอปที่ถูก kill จึงเพิ่ม `getIBeaconAuthorizationLevel`
      // เป็น method แยกให้ Dart query ระดับสิทธิ์จริงได้ทุกเมื่อ (ไม่ผูกกับผลลัพธ์
      // ของ startIBeaconMonitoring โดยตรง เพื่อไม่แตะ signature ของ
      // startIBeaconMonitoring ตามที่ ADR-6 หัวข้อ 2 ล็อกไว้แล้วว่า "ไม่เปลี่ยน
      // ชื่อ/signature") — ดู `authorizationLevel(for:)` ด้านล่าง
      applyParsedRegions(parsedRegions)
      result(nil)
    }
  }

  /// การตัดสินใจว่าจะทำอะไรต่อ เมื่อรู้ `CLAuthorizationStatus` ปัจจุบัน
  ///
  /// แยกออกมาเป็น pure function เพื่อให้ทดสอบด้วย XCTest บน simulator ได้โดยไม่
  /// ต้องมี `CLLocationManager` จริงหรืออุปกรณ์จริง — ดู
  /// `example/ios/RunnerTests/RunnerTests.swift`
  ///
  /// **B6 — พฤติกรรมของ `.notDetermined` ที่เกิดจาก "Allow Once" หมดอายุ (ไม่ใช่
  /// การกระทำของผู้ใช้ที่มองเห็นชัดเจน):** ยืนยันจาก Apple docs ว่า "Allow Once"
  /// ไม่มีสถานะแยกใน `CLAuthorizationStatus` — รายงานเป็น `.authorizedWhenInUse`
  /// ชั่วคราวแล้ว **เปลี่ยนกลับเป็น `.notDetermined` เอง** เมื่อ "app is no longer
  /// in use" (ดู ARCHITECTURE.md ADR-6 หัวข้อ 5 คำพูดต้นฉบับจากหน้า
  /// `requestAlwaysAuthorization()`) ฟังก์ชันนี้เป็น **pure function ของค่า status
  /// ปัจจุบันเท่านั้น** (ไม่มี state/history) จึงจัดการเคสนี้ได้ถูกต้องโดยไม่ต้อง
  /// แก้อะไรเพิ่ม: ไม่ว่า `.notDetermined` จะมาจาก "ยังไม่เคยถามเลย" หรือมาจาก
  /// "เคยเป็น .authorizedWhenInUse แบบ Allow Once แล้วหมดอายุ" ผลลัพธ์เหมือนกัน
  /// เป๊ะคือ `.deferUntilAuthorizationCallback` — ถ้าแอปเรียก
  /// `startIBeaconMonitoring` ใหม่ตอนนี้ จะขอสิทธิ์ใหม่ตามปกติ (defer + prompt)
  /// ไม่ error/ไม่ค้าง ยืนยันด้วย XCTest `testAllowOnceExpiryReturnsToDefer...`
  /// ใน `RunnerTests.swift`
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

  /// B6: ระดับสิทธิ์ location ปัจจุบัน "แปลตรง ๆ" เป็นชื่อที่ Dart layer อ่านแล้ว
  /// ตัดสินใจต่อได้ทันทีว่า background wake หลังแอปโดน terminate จะทำงานหรือไม่ —
  /// ตาม ARCHITECTURE.md ADR-6 หัวข้อ 3 มีแค่ `.authorizedAlways` เท่านั้นที่
  /// รับประกัน background wake ("region monitoring services" ถูกระบุชื่อตรง ๆ ว่า
  /// ต้องมี Always) ส่วน `.authorizedWhenInUse` ทำงานได้แค่ตอนแอปยัง
  /// foreground/suspended ไม่ terminate (ไม่ว่าจะเป็น Allow Once หรือ When In Use
  /// ถาวร — แยกไม่ออกจากค่า status เพียงอย่างเดียวตามที่ยืนยันใน ADR-6 หัวข้อ 5
  /// จึงตั้งใจใช้ชื่อ `whenInUse` เฉย ๆ ไม่แยกย่อยเป็น "allowOnce"/"whenInUsePermanent"
  /// เพราะ native เองก็แยกไม่ได้จริง การตั้งชื่อแยกจะสร้างภาพลวงว่าระบบรู้ในสิ่งที่
  /// ไม่รู้)
  ///
  /// แยกเป็น pure function เหมือน `authorizationDecision(for:)` เพื่อทดสอบด้วย
  /// XCTest ได้โดยไม่ต้องมี `CLLocationManager` จริง
  enum AuthorizationLevel: String {
    /// Always — background wake หลังแอปโดน terminate ทำงานได้ (ranging +
    /// region monitoring ครบ)
    case always
    /// When In Use (permanent หรือ Allow Once ชั่วคราว แยกไม่ออก) — ทำงานได้
    /// เฉพาะตอนแอปยัง foreground/suspended เท่านั้น ไม่ปลุกแอปที่ถูก terminate
    case whenInUse
    /// notDetermined/denied/restricted — ไม่มีการ monitor ใด ๆ เกิดขึ้นเลย
    case insufficient
  }

  static func authorizationLevel(for status: CLAuthorizationStatus) -> AuthorizationLevel {
    switch status {
    case .authorizedAlways:
      return .always
    case .authorizedWhenInUse:
      return .whenInUse
    case .notDetermined, .denied, .restricted:
      return .insufficient
    @unknown default:
      return .insufficient
    }
  }

  /// Method channel entry point ของ `getIBeaconAuthorizationLevel` —
  /// คืนค่า `"always" | "whenInUse" | "insufficient"` เสมอ (ไม่ throw) เพราะการ
  /// query สถานะปัจจุบันไม่มีทาง fail แบบที่ต้องรายงาน error กลับ ต่างจาก
  /// `startIBeaconMonitoring` ที่ต้องรอ system prompt
  func currentAuthorizationLevel(result: @escaping FlutterResult) {
    result(Self.authorizationLevel(for: locationManager.authorizationStatus).rawValue)
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

      // ADR-6 หัวข้อ 1: startMonitoring(for:) ยิง didEnterRegion/didExitRegion
      // เฉพาะตอนมี "boundary crossing" ในอนาคตเท่านั้น — ถ้าอุปกรณ์อยู่ในโซนอยู่
      // แล้วตั้งแต่ก่อนเรียก startMonitoring จะไม่มี event ใดยิงออกมาเลยจนกว่าจะ
      // มีการออก-แล้วเข้าใหม่จริง ๆ requestState(for:) เป็นกลไกทางการเดียวที่
      // Apple ให้มาเพื่อ query initial state ทันทีโดยไม่ต้องรอ boundary crossing
      // จริง (ยืนยันจาก docs — ดู ARCHITECTURE.md ADR-6 หัวข้อ 1) ผลจะย้อนกลับมา
      // ทาง didDetermineState(_:for:) แบบ async เช่นกัน
      locationManager.requestState(for: region)
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
      // เคลียร์ dedupe state ทิ้งด้วย — ถ้า region เดิมถูก monitor ใหม่ในอนาคต
      // (identifier เดิมถูกส่งมาอีกครั้งใน startIBeaconMonitoring) ต้องถือว่าเป็น
      // การเริ่มต้นใหม่ ไม่ใช่ dedupe กับ state เก่าก่อนหยุดไปแล้ว
      lastKnownRegionState.removeValue(forKey: identifier)
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

  // MARK: - CLLocationManagerDelegate: region state (ADR-6, เพิ่ม 28 ส.ค. 2026)

  /// เรียกเมื่อ CoreLocation ยืนยันว่าอุปกรณ์ "เข้า" โซนของ region — semantic
  /// ยืนยันจาก Apple docs: "every active location manager object delivers this
  /// message to its associated delegate ... use the region's identifier string"
  /// (ดู ARCHITECTURE.md ADR-6 หัวข้อ 1) — ใช้ `region.identifier` ตรง ๆ ได้เลย
  /// (ไม่ต้องเทียบ constraint แบบ `didRange` เพราะ `CLRegion` มี `identifier`
  /// ตรงตัวอยู่แล้ว เป็นค่าเดียวกับที่ `applyParsedRegions` ตั้งตอนสร้าง region)
  func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
    emitRegionStateIfChanged(.enter, for: region)
  }

  /// เช่นเดียวกับ `didEnterRegion` แต่ตอน "ออก" จากโซน
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    emitRegionStateIfChanged(.exit, for: region)
  }

  /// เรียกทั้งตอนมี boundary transition จริง (คู่กับ `didEnterRegion`/
  /// `didExitRegion`) และตอนตอบกลับ `requestState(for:)` ที่ `applyParsedRegions`
  /// เรียกทันทีหลัง `startMonitoring(for:)` สำเร็จ — นี่คือทางเดียวที่รู้ initial
  /// state ของ region ได้โดยไม่ต้องรอ boundary crossing จริง (ดู ARCHITECTURE.md
  /// ADR-6 หัวข้อ 1 คำพูดต้นฉบับจาก Apple docs) `.inside`/`.outside` map เป็น
  /// enter/exit เดียวกับสองเมธอดข้างบนตาม payload contract ของ ADR-6 หัวข้อ 2
  func locationManager(
    _ manager: CLLocationManager,
    didDetermineState state: CLRegionState,
    for region: CLRegion
  ) {
    let mapped: RegionMonitoringState
    switch state {
    case .inside:
      mapped = .enter
    case .outside:
      mapped = .exit
    case .unknown:
      mapped = .unknown
    @unknown default:
      mapped = .unknown
    }
    emitRegionStateIfChanged(mapped, for: region)
  }

  /// state ของ region หนึ่งตัวตามที่ ADR-6 หัวข้อ 2 กำหนด (`"enter"|"exit"|"unknown"`)
  private enum RegionMonitoringState: String {
    case enter
    case exit
    case unknown
  }

  /// **กลไก dedupe ระหว่าง `didDetermineState` กับ `didEnterRegion`/`didExitRegion`**
  /// (จุดที่ ARCHITECTURE.md ADR-6 หัวข้อ 2-3 ตั้งใจปล่อยให้ตัดสินใจตอน implement):
  ///
  /// ปัญหา: `applyParsedRegions` เรียก `requestState(for:)` ทันทีหลัง
  /// `startMonitoring(for:)` — ถ้าจังหวะนั้นบังเอิญมี boundary transition จริงเกิด
  /// ขึ้นพอดี (เช่นผู้ใช้เพิ่งเดินเข้าโซนตอนแอปกำลังเริ่ม monitor) CoreLocation
  /// อาจเรียกทั้ง `didDetermineState` (จาก requestState) และ `didEnterRegion`
  /// (จาก boundary crossing จริง) ด้วย state เดียวกัน (`.inside`/enter) ถ้าไม่
  /// dedupe จะมี event "enter" ซ้ำสองรอบให้ Dart layer ทั้งที่ state จริงเปลี่ยน
  /// แค่ครั้งเดียว
  ///
  /// ทางแก้: เก็บ state ล่าสุดที่รู้ต่อ region ([lastKnownRegionState]) แล้วยิง
  /// event ออกไปเฉพาะตอนที่ state ใหม่ต่างจากที่เก็บไว้ล่าสุดเท่านั้น — ใช้กฎ
  /// เดียวกันไม่ว่า event จะมาจาก `didDetermineState` หรือ
  /// `didEnterRegion`/`didExitRegion` ก็ตาม (ไม่แยก logic ตามแหล่งที่มา) เพราะทั้ง
  /// สองแหล่งรายงาน "state จริงของ region ณ ตอนนี้" เหมือนกัน ต่างกันแค่ทริกเกอร์
  /// ที่ทำให้ CoreLocation เรียก ไม่ใช่ความหมายของ state เอง — Dart layer ที่ฟัง
  /// `beacon_kit_ios/region_state_events` จึงเห็นแค่ "การเปลี่ยนแปลงจริง" เท่านั้น
  /// ไม่ต้อง dedupe เองอีกชั้น
  private func emitRegionStateIfChanged(_ state: RegionMonitoringState, for region: CLRegion) {
    let identifier = region.identifier
    let constraint: CLBeaconIdentityConstraint
    if let cached = constraintsByIdentifier[identifier] {
      constraint = cached
    } else if let beaconRegion = region as? CLBeaconRegion {
      // **ADR-10:** ไม่รู้จัก identifier นี้ แต่ตัว `CLRegion` ที่ CoreLocation ส่ง
      // มาเองเป็น `CLBeaconRegion` อยู่แล้ว จึงถอด constraint จากมันได้ตรง ๆ ไม่
      // ต้องพึ่ง dictionary ในหน่วยความจำเลย
      //
      // เคสที่ทางนี้ช่วยชีวิต: process ถูกปลุกขึ้นมาใหม่แล้ว `didEnterRegion` มา
      // ถึง**ก่อน**ที่ `monitoredRegions` จะสะท้อนค่าครบ (header เตือนไว้เองว่า
      // การลงทะเบียน region เป็น asynchronous "and may not be immediately
      // reflected in monitoredRegions" — CLLocationManager.h:720) ถ้ายัง guard
      // แบบเดิม event ที่รอมาทั้งรอบทดสอบจะหายไปเพราะเรื่องจังหวะล้วน ๆ
      constraint = beaconRegion.beaconIdentityConstraint
      constraintsByIdentifier[identifier] = constraint
    } else {
      // ไม่ใช่ beacon region (เช่น `CLCircularRegion` ของโค้ดส่วนอื่นในแอปเดียวกัน)
      // — ไม่มี uuid/major/minor ให้ประกอบ payload ตาม ADR-6 ทิ้งไปเงียบ ๆ
      return
    }
    guard lastKnownRegionState[identifier] != state else {
      // state ไม่เปลี่ยนจากที่รู้ล่าสุด — นี่คือจุด dedupe จริง (ดูคอมเมนต์ข้างบน)
      return
    }
    lastKnownRegionState[identifier] = state

    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let payload: [String: Any] = [
      "regionIdentifier": identifier,
      "uuid": constraint.uuid.uuidString.lowercased(),
      // constraint.major/minor เป็น UInt16? (ยืนยันจาก Apple docs:
      // https://developer.apple.com/documentation/corelocation/clbeaconidentityconstraint/major
      // "var major: UInt16? { get }") — nil = wildcard ตาม ADR-5, ส่งเป็น
      // NSNull() ผ่าน StandardMethodCodec เพื่อให้ฝั่ง Dart ได้ `int?` ตรง ๆ
      "major": constraint.major.map { NSNumber(value: $0) } ?? NSNull(),
      "minor": constraint.minor.map { NSNumber(value: $0) } ?? NSNull(),
      "state": state.rawValue,
      "timestamp": timestamp,
    ]
    // ยิงออกสองทางที่**เป็นอิสระจากกัน** ทางไหนพร้อมก็ได้ผลของทางนั้น:
    //   1. native hook  — ใช้ได้แม้ Flutter engine ยังไม่ถูกสร้าง (B5 cold launch)
    //   2. event channel — ต้องมี engine + Dart subscribe แล้ว (buffer ให้ถ้ายัง)
    // ห้ามให้ทางหนึ่งล้มแล้วอีกทางไม่ได้ทำงาน จึงเรียก hook ก่อนเสมอ
    onRegionStateEvent?(
      BeaconKitRegionStateEvent(
        regionIdentifier: identifier,
        uuid: constraint.uuid,
        major: constraint.major,
        minor: constraint.minor,
        state: state.rawValue,
        timestamp: Date(timeIntervalSince1970: Double(timestamp) / 1000)
      )
    )
    regionStateStreamHandler.send(payload)
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

/// Stream handler ของ event channel ที่สอง `beacon_kit_ios/region_state_events`
/// (ADR-6) — เป็นคลาสแยกจาก `IBeaconRangingManager` (ซึ่งเป็น stream handler ของ
/// `beacon_kit_ios/ibeacon_ranging_events` อยู่แล้ว) เพราะ
/// `FlutterEventChannel.setStreamHandler(_:)` ผูก handler หนึ่งตัวกับหนึ่ง
/// channel เท่านั้น และ `onListen`/`onCancel` ของ `FlutterStreamHandler` ไม่มี
/// พารามิเตอร์บอกว่ามาจาก channel ไหน — ถ้าให้ `IBeaconRangingManager` implement
/// `FlutterStreamHandler` ครั้งเดียวแล้วเอาไปผูกทั้งสอง channel จะไม่มีทางแยกได้
/// ว่า `eventSink` ที่ได้มาเป็นของ ranging หรือ region-state channel
///
/// `IBeaconRangingManager` เป็นเจ้าของ instance นี้ (`regionStateStreamHandler`)
/// และเรียก `regionStateEventSink` ตรง ๆ จาก `emitRegionStateIfChanged` —
/// `BeaconKitIosPlugin.swift` เป็นคน register instance นี้เป็น stream handler
/// ของ channel `beacon_kit_ios/region_state_events` ตอน `register(with:)`
final class RegionStateEventStreamHandler: NSObject, FlutterStreamHandler {
  private var regionStateEventSink: FlutterEventSink?

  /// event ที่เกิดขึ้น**ก่อน**ฝั่ง Dart จะ subscribe — เก็บไว้ก่อนแล้วส่งให้ทีเดียว
  /// ตอน `onListen`
  ///
  /// **ทำไมต้องมี (ADR-10):** ตอน iOS ปลุก process ที่ถูกฆ่าขึ้นมาส่ง region event
  /// ลำดับเวลาคือ CoreLocation เรียก delegate ได้ทันทีที่ `CLLocationManager` ถูก
  /// สร้าง แต่กว่า Flutter engine จะ start และ Dart จะ subscribe ได้ต้องผ่านอีกหลาย
  /// ขั้น ถ้า sink ยังเป็น nil ตอนนั้นแล้วเราทิ้ง event ไปเลย ฝั่ง Dart จะไม่มีวัน
  /// ได้เห็น event ที่เป็นเหตุผลเดียวที่แอปถูกปลุกขึ้นมาตั้งแต่แรก
  private var bufferedEvents: [[String: Any]] = []

  /// เพดาน buffer — ตัดจากตัวเก่าสุดเมื่อเต็ม
  ///
  /// จำกัดไว้เพราะถ้า Dart ไม่มีวัน subscribe (เช่นแอปถูกปลุกเบื้องหลังซ้ำ ๆ โดย
  /// ผู้ใช้ไม่เคยเปิดหน้าจอเลย) buffer จะโตไม่มีที่สิ้นสุด ทิ้งตัวเก่าสุดเพราะ
  /// state ล่าสุดของ region มีค่ากับผู้ใช้มากกว่าประวัติเก่า — และหลักฐานฉบับที่
  /// ครบถ้วนอยู่ในไฟล์ log ที่ native เขียนไว้แล้ว ไม่ได้พึ่ง buffer นี้
  private static let maxBufferedEvents = 50

  fileprivate func send(_ payload: [String: Any]) {
    guard let sink = regionStateEventSink else {
      bufferedEvents.append(payload)
      if bufferedEvents.count > Self.maxBufferedEvents {
        bufferedEvents.removeFirst(bufferedEvents.count - Self.maxBufferedEvents)
      }
      return
    }
    sink(payload)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    regionStateEventSink = events
    let pending = bufferedEvents
    bufferedEvents = []
    for payload in pending {
      events(payload)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    regionStateEventSink = nil
    return nil
  }
}
