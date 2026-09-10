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
    // `clearProximityState: false` — **จุดเดียวในโค้ดทั้งหมดที่ส่งค่านี้**
    //
    // เส้นทางนี้คือ "แทนที่ชุด region" ไม่ใช่ "เลิกสนใจ region นั้นแล้ว" และมันคือ
    // **เส้นทางเดียวที่เริ่ม `startRangingBeacons` ในรอบ launch ใหม่** ด้วย
    // (ranging ไม่รอดข้าม process ต่างจาก monitoring ที่ระบบเก็บไว้ให้) แปลว่าตอน
    // iOS ปลุก process ที่ถูกฆ่าขึ้นมา ลำดับจริงคือ: ถูกปลุก → Dart เรียก
    // `startIBeaconMonitoring` → ที่นี่ → ranging เริ่มเดิน → `didRange` ตัวแรกมาถึง
    // ถ้าเส้นทางนี้ล้างสถานะชั้น 2 ด้วย **หน้าต่าง/dwell ที่อุตส่าห์เก็บลง
    // `UserDefaults` เพื่อให้รอดข้าม process (ADR-21 หัวข้อ 3) จะถูกลบทิ้งพอดี
    // ในวินาทีที่มันกำลังจะถูกใช้** — กลไกทั้งข้อจะตายโดยไม่มีอะไรฟ้อง
    //
    // การล้างสถานะยังคงเกิดตามปกติในเส้นทาง `stopIBeaconMonitoring` ที่แอปเรียกเอง
    // ซึ่งเป็นความหมายที่ ADR-21 หัวข้อ 7 ข้อ 2 พูดถึงจริง ๆ
    stopMonitoring(identifiers: nil, clearProximityState: false)

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
  ///
  /// - Parameter clearProximityState: ล้างสถานะของ**ชั้นที่ 2** (ADR-21) ของ region
  ///   เหล่านั้นด้วยหรือไม่ — `true` เสมอสำหรับผู้เรียกทุกรายยกเว้น
  ///   [applyParsedRegions] ซึ่งอธิบายเหตุผลไว้ที่จุดเรียกของมันเอง
  ///   (ค่า default เป็น `true` เพื่อให้ผู้เรียกที่ไม่รู้เรื่องชั้น 2 ได้พฤติกรรม
  ///   ที่ปลอดภัยกว่าโดยไม่ต้องตัดสินใจ)
  func stopMonitoring(identifiers: [String]?, clearProximityState: Bool = true) {
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

      // **ADR-21 หัวข้อ 7 ข้อ 2** — ล้าง state ของ**ชั้นที่ 2** ด้วยเหตุผลเดียวกับ
      // บรรทัดข้างบนเป๊ะ: หน้าต่าง/ตัวนับ dwell ของ region ที่เลิกเฝ้าไปแล้วต้องไม่
      // ถูกนำมาสานต่อถ้า identifier เดิมถูกลงทะเบียนใหม่วันหลัง (sample ที่นับ dwell
      // "ติดกัน" ต้องติดกันจริงตามเวลา — ADR-19 หัวข้อ 6(ฉ))
      //
      // ฝั่ง Android เรื่องนี้ยังเป็นหนี้ค้างเพราะต้องไปแก้ที่ example app —
      // **iOS ทำตั้งแต่คอมมิตแรกเพื่อไม่ให้ทำซ้ำรอยเดิม**
      //
      // ล้างทั้งสองที่: ในหน่วยความจำ (gate ที่ยังมีชีวิตอยู่ใน process นี้) และบน
      // ดิสก์ (สถานะที่รอดข้าม process มา ซึ่งอาจมีอยู่แม้ gate ยังไม่ถูกสร้างเลย
      // ในรอบ launch นี้)
      if clearProximityState {
        let keyPrefix = "\(identifier)\(ProximityKeyCodec.separator)"
        proximityGate?.removeStates(matchingPrefix: keyPrefix)
        proximityStore.removeStates(matchingPrefix: keyPrefix)
      }
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
    // CLBeaconIdentityConstraint เทียบค่าได้ (Apple ออกแบบมาให้เทียบกับ constraint
    // ที่ใช้ตอนเรียก startRangingBeacons(satisfying:) ได้โดยตรงใน callback นี้)
    guard
      let regionIdentifier = constraintsByIdentifier.first(where: { $0.value == beaconConstraint }
      )?.key
    else {
      return
    }

    // **ADR-21 หัวข้อ 5 — ทำไม `guard let eventSink` ถึงถูกย้ายมาไว้ตรงนี้:**
    // เดิมบรรทัดนี้อยู่ที่ต้นเมธอด ซึ่งแปลว่าเมื่อ**ไม่มีผู้ฟังฝั่ง Dart** (engine
    // ยังไม่ถูกสร้าง หรือไม่มีใคร subscribe) เมธอดนี้จะ `return` ออกไปทั้งตัว —
    // นั่นคือ**เคสหลักที่ ADR-21 ทั้งฉบับมีอยู่เพื่อรองรับ** (แอปถูกปลุกด้วย region
    // event แล้ว ranging เดินอยู่เบื้องหลังโดยยังไม่มี UI) ถ้าไม่ย้าย ชั้นที่ 2
    // จะตายตั้งแต่บรรทัดแรกโดยไม่มีอะไรฟ้อง
    //
    // **พฤติกรรมของบล็อกนี้เหมือนเดิมเป๊ะ** — ย้ายขอบเขตของ guard อย่างเดียว ไม่แก้
    // payload ไม่แก้ลำดับ ไม่แก้เงื่อนไขใด ๆ ของเส้นทางเดิม
    if let eventSink = eventSink {
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

    // ---- ชั้นที่ 2 ของ ADR-21: proximity ----
    //
    // **อยู่หลังตรรกะเดิมทั้งหมดเสมอ ห้ามขยับขึ้นก่อน** (ADR-21 หัวข้อ 5) และ
    // ครอบทั้งก้อนด้วย do/catch ที่ **กลืน** error โดยตั้งใจ — ไม่ใช่ความมักง่าย:
    // เส้นทางเดิม (ranging -> Dart) กับชั้น 1 (region enter/exit) มีหลักฐานจาก
    // อุปกรณ์จริงแล้ว ส่วนชั้นนี้ยังไม่เคยรันบนเครื่องจริงเลยแม้แต่ครั้งเดียว และ
    // ต้องอ่านค่าที่เก็บไว้บน `UserDefaults` (ถอด JSON ได้ไม่ครบ) ถ้าปล่อยให้
    // exception ลอยขึ้นไป callback ของ CoreLocation จะพังทั้งเมธอด ทั้งที่งานของ
    // เส้นทางเดิมข้างบนทำเสร็จไปแล้ว — ได้ crash โดยไม่ได้อะไรกลับมา และรอบถัดไป
    // ก็จะ crash ซ้ำแบบเดิม (หลักการเดียวกับ ADR-20 หัวข้อ 1)
    //
    // ร่องรอยของความล้มเหลวไม่ได้หายไปพร้อม error ที่ถูกกลืน — เส้นทางที่ล้มบ่อย
    // ที่สุด (ที่เก็บ state) รายงานผ่าน `store=` ในบรรทัดหลักฐานทุกบรรทัดอยู่แล้ว
    // (ADR-21 หัวข้อ 7 ข้อ 2)
    do {
      try runProximityLayer(
        regionIdentifier: regionIdentifier,
        beacons: beacons,
        fromRangeCallback: true
      )
    } catch {
      BackgroundProximityMonitor.recordBackgroundLocationUpdatesTrace(
        "proximity-layer-failed:\(error)"
      )
    }
  }

  /// **⚠️ ไม่ใช่สัญญาณว่าบีคอนหาย — พิสูจน์แล้วจากรอบเดินจริง 10 ก.ย. 2026**
  ///
  /// สมมติฐานเดิมของ ADR-21 หัวข้อ 4 คือ "เคส *ไม่เจอ beacon เลย* ของ API รุ่น
  /// `satisfying:` มาทาง callback นี้ ไม่ใช่ `didRange` ที่มี array ว่าง" (อ่านจาก
  /// abstract ของ Apple: "couldn't detect any beacons that satisfy the provided
  /// constraint") — **รอบเดินจริงหักล้างข้อนี้แล้ว**:
  /// `docs/test-data/2026-09-10_ios_proximity_walk.log` มี `event=rangefail`
  /// **0 บรรทัด** ทั้งไฟล์ ทั้งที่ผู้ทดสอบเดินพ้นสัญญาณสองนาทีและ iOS ประกาศ `exit`
  /// จริงในรอบเดียวกัน
  ///
  /// ความหมายที่เหลืออยู่จริงคือ **"ranging เองล้มเหลว"** (Bluetooth ถูกปิด สิทธิ์ถูก
  /// ถอน ฯลฯ) — **ห้ามพึ่ง callback นี้เป็นจุด sweep** จุด sweep ที่เชื่อถือได้คือ
  /// ท้าย `didRange` (เรียก `sweepStale()` เสมอแม้ array ว่าง) และ `didExitRegion`
  ///
  /// **ยังเก็บ hook นี้ไว้** เพราะเคส Bluetooth ปิดยังต้องมีร่องรอย และการ sweep ที่นี่
  /// ไม่ได้ทำอันตรายอะไร (เป็น superset ของจุดอื่น) — ดู kdoc ของ
  /// `BackgroundProximityMonitor.setRangingFailureObserver`
  func locationManager(
    _ manager: CLLocationManager,
    didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint,
    error: Error
  ) {
    guard
      let regionIdentifier = constraintsByIdentifier.first(where: { $0.value == beaconConstraint }
      )?.key
    else {
      return
    }

    // **นับให้เห็นเป็นบรรทัดจริง ก่อน sweep** — ดู kdoc ของ
    // `BackgroundProximityMonitor.setRangingFailureObserver` ว่าทำไมการไม่มีบรรทัด
    // ถึงตอบคำถามของ ADR-21 หัวข้อ 4 ไม่ได้เลย
    BackgroundProximityMonitor.emitRangingFailure(regionIdentifier: regionIdentifier)

    // กลืน error ด้วยเหตุผลเดียวกับใน didRange (ดูคอมเมนต์ที่นั่น)
    //
    // `fromRangeCallback: false` — **ตัวนับ `rangeCb` ต้องนับเฉพาะ `didRange` เท่านั้น**
    // (ADR-21 หัวข้อ 9) ถ้านับที่นี่ด้วย ตัวเลขจะตอบคำถาม "ranging เดินอยู่จริงไหม"
    // ไม่ได้อีกต่อไปเพราะปนกับ callback ที่แปลว่า ranging ล้มเหลว
    do {
      try runProximityLayer(
        regionIdentifier: regionIdentifier,
        beacons: [],
        fromRangeCallback: false
      )
    } catch {
      BackgroundProximityMonitor.recordBackgroundLocationUpdatesTrace(
        "proximity-layer-failed:\(error)"
      )
    }
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
    // **ชั้นที่ 1 ต้องมาก่อนเสมอ** — บรรทัดนี้คือของเดิม ไม่ถูกแก้แม้แต่ตัวอักษรเดียว
    emitRegionStateIfChanged(.enter, for: region)

    // ---- ADR-21 หัวข้อ 1(ข): เริ่ม ranging บนเส้นทางที่ถูกปลุกโดยไม่มี UI ----
    //
    // เพิ่ม **หลัง** ชั้นที่ 1 เสมอ ด้วยหลักการเดียวกับที่ ADR-20 ใช้กับ
    // `BeaconScanReceiver` ฝั่ง Android: ชั้นที่ 2 ห้ามอยู่ในเส้นทางที่ทำให้ชั้นที่ 1
    // พลาด และห้ามแก้ผลของมัน
    ensureRangingStarted(for: region)
  }

  /// เริ่ม ranging ให้ region ที่เพิ่งเข้า — **เส้นทางกู้สำหรับรอบที่ระบบปลุกแอป
  /// ขึ้นมาโดยไม่มี UI**
  ///
  /// ## ทำไมต้องมี ทั้งที่ `applyParsedRegions()` เริ่ม ranging ให้อยู่แล้ว
  ///
  /// **region monitoring รอดข้าม process ให้เอง แต่ ranging ไม่รอด** — เมื่อระบบ
  /// ปลุกแอปที่ถูกฆ่าไปแล้วด้วย region event `applyParsedRegions()` จะยังไม่เคยถูก
  /// เรียกในรอบนั้น (มันถูกเรียกจากฝั่ง Dart ผ่าน `startIBeaconMonitoring` เท่านั้น
  /// ซึ่งต้องมี Flutter engine) ผลคือไม่มีใครเริ่ม ranging เลย → `didRange` ไม่ยิง
  /// → **ชั้นที่ 2 ไม่มี sample แม้แต่ตัวเดียวในเคสที่ ADR-21 ทั้งฉบับมีอยู่เพื่อรองรับ**
  ///
  /// ## ทำไมต้องเติม `constraintsByIdentifier` ด้วย ไม่ใช่แค่เรียก `startRanging`
  ///
  /// `didRange` แปลง `CLBeaconIdentityConstraint` กลับเป็น `regionIdentifier` ผ่าน
  /// ตารางนี้ตัวเดียว — ในรอบที่ถูกปลุก ตารางจะ**ว่างเปล่า** เพราะไม่มีใครเรียก
  /// `applyParsedRegions()` ถ้าไม่เติม `didRange` จะ `return` ที่ `guard` ตัวแรก
  /// แล้วชั้นที่ 2 ก็ตายเงียบอยู่ดี ทั้งที่ ranging เดินอยู่จริง
  ///
  /// ค่าที่เติมมาจาก `CLBeaconRegion.beaconIdentityConstraint` ของ region ที่ระบบ
  /// ส่งมาเอง — **ไม่ใช่การเดา** เป็นค่าเดียวกับที่ใช้ตอนลงทะเบียน monitoring ไว้
  ///
  /// ## สิ่งที่ยังไม่ได้ทำและต้องรู้
  ///
  /// **ไม่มีการเรียก `stopRangingBeacons` คู่กันใน `didExitRegion`** — ตั้งแต่ 10 ก.ย. 2026
  /// เมธอดนั้นไม่ได้อยู่ในรายการห้ามแตะแล้ว (ADR-21 หัวข้อ 8(ข) เพิ่มการล้างสถานะชั้นที่ 2
  /// ต่อท้ายที่นั่น) แต่ **ยังจงใจไม่เพิ่ม `stopRangingBeacons`** เพราะกระทบทั้งอายุแบตและ
  /// โอกาสได้ sample ในหน้าต่างที่ถูกปลุก ซึ่งต้องมีการวัดผลจริงก่อน · ในทางปฏิบัติสถานะ
  /// ปัจจุบันไม่แย่ลงกว่าเดิม เพราะ
  /// `applyParsedRegions()` ก็เปิด ranging ค้างไว้ตลอดอยู่แล้วตั้งแต่ก่อนรอบนี้
  /// แต่ **Apple แนะนำให้หยุด ranging เมื่อออกจาก region** (`apple_proximity_ranging.md`
  /// หัวข้อ 9) จึงเป็นหนี้ที่ต้องใช้คืนใน ADR รอบถัดไปพร้อมกับการวัดผลแบตเตอรี่จริง
  private func ensureRangingStarted(for region: CLRegion) {
    guard let beaconRegion = region as? CLBeaconRegion else { return }

    let constraint = beaconRegion.beaconIdentityConstraint
    if constraintsByIdentifier[region.identifier] == nil {
      constraintsByIdentifier[region.identifier] = constraint
    }
    locationManager.startRangingBeacons(satisfying: constraint)
  }

  /// เช่นเดียวกับ `didEnterRegion` แต่ตอน "ออก" จากโซน
  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    // **ชั้นที่ 1 ต้องมาก่อนเสมอ** — บรรทัดนี้คือของเดิม ไม่ถูกแก้แม้แต่ตัวอักษรเดียว
    emitRegionStateIfChanged(.exit, for: region)

    // ---- ADR-21 หัวข้อ 8: ล้างสถานะชั้นที่ 2 ของ region ที่เพิ่งออก ----
    //
    // เพิ่ม **หลัง** ชั้นที่ 1 เสมอ และครอบด้วย do/catch ที่กลืน error ด้วยหลักการ
    // เดียวกับ `didEnterRegion`/`didRange` เป๊ะ: ชั้นที่ 2 ห้ามทำให้ enter/exit ของ
    // ชั้นที่ 1 (ซึ่งมีหลักฐานระดับ `observed` แล้ว) พลาดหรือพังได้
    //
    // **ทำไมต้องมี:** รอบเดินจริง 10 ก.ย. 2026 พิสูจน์ว่า `didFailRangingFor` ไม่เคย
    // ยิงเลย (0 บรรทัด) ทั้งที่ iOS ประกาศ `exit` จริง — `didExitRegion` จึงเป็น
    // **สัญญาณ "หายจริง" ที่เชื่อถือได้ที่สุดที่ iOS มีให้** และเป็นสัญญาณเดียวที่
    // มาถึงแม้ `didRange` จะเลิกยิงไปแล้ว (ตอนนั้นไม่มีใครเรียก `sweepStale()` ได้อีก)
    do {
      try runProximityRegionExit(regionIdentifier: region.identifier)
    } catch {
      BackgroundProximityMonitor.recordBackgroundLocationUpdatesTrace(
        "proximity-region-exit-failed:\(error)"
      )
    }
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

  // MARK: - ชั้นที่ 2: proximity (ADR-21, เพิ่ม 10 ก.ย. 2026)

  /// gate ของชั้น 2 — สร้างครั้งเดียวต่อ process แล้วกู้สถานะจากดิสก์ทันที
  ///
  /// ต่างจากฝั่ง Android ที่สร้าง gate ใหม่ทุก `onReceive` (receiver มีชีวิตแค่ช่วง
  /// นั้น) — ฝั่ง iOS `IBeaconRangingManager.shared` มีอายุเท่ากับ process จึงถือ
  /// instance เดียวไว้ได้ ประหยัดการอ่านดิสก์ทุก callback (ซึ่งอาจถี่ระดับวินาที
  /// ตอน foreground) **แต่ยังเขียนลงดิสก์ทุก batch เหมือนเดิม** เพราะ process ถูก
  /// ฆ่าได้ตลอดเวลาและนั่นคือเหตุผลทั้งหมดที่ store มีตัวตน (ADR-21 หัวข้อ 3)
  private var proximityGate: ProximityGate?

  private let proximityStore = ProximityGateStore()

  /// ตัวนับ 3 ตัวของ **ADR-21 หัวข้อ 9** (เพิ่มหลังรอบเดินจริง 10 ก.ย. 2026)
  ///
  /// **ทำไมไม่เก็บใน `ProximityKeyState`:** ADR-21 หมายเหตุข้อ 1 ห้ามใส่ counter ใด ๆ
  /// ลง state ของ gate เพราะจะเบี่ยงจาก reference (`proximity_gate.dart`) ทั้งที่ไม่
  /// จำเป็น — ตัวนับชุดนี้เป็น **เครื่องมือวัดของ process นี้** ไม่ใช่สถานะที่ gate ใช้
  /// ตัดสินใจ จึงอยู่ที่นี่ ไม่ลงดิสก์ และรีเซ็ตเองทุกครั้งที่ process เกิดใหม่
  /// (ซึ่งตรงกับความหมายของ `rangeCb` ที่เป็นค่าระดับ process อยู่แล้ว)
  ///
  /// `internal` ไม่ใช่ `private` เพราะ **กฎการนับต้องมี XCTest ล็อกไว้** — ดู
  /// [ProximitySampleCounters.counting(bucket:)] ซึ่งเป็น pure function ที่เทสต์เรียก
  /// ได้ตรง ๆ โดยไม่ต้องมี `CLLocationManager` (หลักการเดียวกับ
  /// `allowsBackgroundLocationUpdates(backgroundModes:)`)
  struct ProximitySampleCounters: Equatable {
    var inArray = 0
    var unknown = 0

    /// นับ sample หนึ่งตัวที่อยู่ใน array ของ `didRange` — **pure**
    ///
    /// **`unknown` นับรวมอยู่ใน `inArray` ด้วย** (ไม่แยกขาดจากกัน) — สองตัวตอบคนละ
    /// คำถาม: `inArray` = "Apple ยังเห็นบีคอนตัวนี้อยู่ไหม" · `unknown` = "เห็นแล้ว
    /// แต่ตอบไม่ได้ว่าใกล้แค่ไหน บ่อยแค่ไหน" ถ้าแยกขาด อัตราส่วน `unknown/inArray`
    /// ที่สมมติฐาน B ของ ADR-21 หัวข้อ 9 ต้องใช้จะคำนวณจากบรรทัดเดียวไม่ได้
    func counting(bucket: ProximityBucket?) -> ProximitySampleCounters {
      return ProximitySampleCounters(
        inArray: inArray + 1,
        unknown: unknown + (bucket == nil ? 1 : 0)
      )
    }
  }

  /// จำนวนครั้งที่ `didRange` ถูกเรียกใน process นี้ — **ไม่นับ `didFailRangingFor`**
  private var rangeCallbackCount = 0

  /// ตัวนับต่อ key — **ไม่ถูกล้างตอน `regionExit`/`stopMonitoring`** โดยตั้งใจ:
  /// มันวัดพฤติกรรมของ CoreLocation ใน process นี้ ไม่ใช่สถานะความใกล้ ถ้าล้างพร้อม
  /// gate ตัวเลขจะตอบคำถาม "Apple ถอดบีคอนออกจาก array บ่อยไหม" ไม่ได้อีก
  ///
  /// ⚠️ โตไม่มีเพดานถ้าเจอบีคอนแปลกหน้าจำนวนมาก — หนี้ก้อนเดียวกับที่ ADR-21 หัวข้อ 6
  /// บันทึกไว้เรื่อง eviction ของ `UserDefaults` แต่ **หนักน้อยกว่า** เพราะตายพร้อม
  /// process ไม่สะสมข้ามรอบ
  private var sampleCountersByKey: [String: ProximitySampleCounters] = [:]

  /// เวลาที่ยิงบรรทัด `rangetick` ล่าสุด — `nil` = ยังไม่เคยยิงใน process นี้
  private var lastRangeTickAtMillis: Int64?

  /// เพดานความถี่ของบรรทัด `rangetick` — **อย่างมากทุก 30 วินาทีต่อ process**
  private static let rangeTickIntervalMillis: Int64 = 30_000

  /// ตั้งค่า `allowsBackgroundLocationUpdates` ไปแล้วหรือยังใน process นี้ —
  /// ตัดสินครั้งเดียวพอ ค่าใน `Info.plist` เปลี่ยนระหว่างรันไม่ได้อยู่แล้ว
  private var didDecideBackgroundLocationUpdates = false

  /// นาฬิกาที่ฉีดให้ [ProximityGate] — **จุดเดียวในเส้นทางนี้ที่เรียก `Date()`**
  /// เพราะ `ProximityGate.swift` ห้ามแตะนาฬิกาของระบบเอง (ADR-21 หัวข้อ 2)
  private static func epochMillisNow() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }

  private func proximityGateRestoringIfNeeded() -> ProximityGate {
    if let gate = proximityGate { return gate }
    let gate = ProximityGate(clock: Self.epochMillisNow)
    // ต้องกู้สถานะก่อน push แรกเสมอ ไม่งั้น dwell เริ่มนับหนึ่งใหม่ทุกครั้งที่ระบบ
    // สร้าง process ใหม่ แล้ว `dwellSamples = 3` จะไม่มีวันครบ (ADR-21 หัวข้อ 3)
    gate.restoreStates(proximityStore.load())
    proximityGate = gate
    return gate
  }

  /// เดิน gate ให้ครบหนึ่ง batch แล้วบันทึกลงดิสก์ก่อนแจ้ง observer
  ///
  /// ลำดับสำคัญและห้ามสลับ:
  /// 1. กู้สถานะจากดิสก์ (ครั้งแรกของ process)
  /// 2. ป้อนทุก `CLBeacon` ที่อยู่ใน array ตามลำดับที่ระบบส่งมา ("ordered by
  ///    approximate distance from the device, with the closest beacon at the
  ///    beginning" — Apple)
  /// 3. [ProximityGate.sweepStale] **หลัง** push และ **เรียกเสมอแม้ array ว่าง**
  ///    (ดูหัวข้อถัดไปว่าทำไมลำดับกลับด้านจากรอบแรก)
  /// 4. **บันทึกลงดิสก์ก่อนแจ้ง observer** — หลักการเดียวกับที่ example app เขียน
  ///    หลักฐานก่อนยิง notification: ถ้าระบบ suspend/ฆ่า process คั่นกลาง อย่างน้อย
  ///    สถานะที่นับมาได้ต้องไม่หาย
  ///
  /// ## ทำไม `sweepStale()` ย้ายจาก "ก่อน push" มาเป็น "หลัง push" (ADR-21 หัวข้อ 8)
  ///
  /// รอบแรกเรียก sweep **ก่อน** loop ด้วยเหตุผลว่า "ตรวจความเงียบที่ผ่านมาก่อนที่
  /// sample ของรอบนี้จะไปต่ออายุ key" — ซึ่งอ่านดูสมเหตุสมผลแต่**แก้เคสหลักไม่ได้**
  /// และรอบเดินจริง 10 ก.ย. 2026 พิสูจน์แล้วว่าเคสหลักคือเคสที่เกิดจริง:
  /// `docs/test-data/2026-09-10_ios_proximity_walk.log` มี `event=rangefail`
  /// **0 บรรทัด** ทั้งไฟล์ แปลว่า **จุด sweep ที่สองของ ADR-21 หัวข้อ 4 ไม่เคยทำงาน
  /// เลยแม้แต่ครั้งเดียว** — เมื่อบีคอนหายไปจาก array แต่ `didRange` ยังยิงอยู่
  /// (เพราะบีคอนตัวอื่นใน constraint เดียวกันยังอยู่ หรือ array ว่างเปล่า) ลำดับเดิม
  /// จะกวาดด้วยเวลาของรอบก่อนหน้าเสมอ
  ///
  /// ลำดับใหม่ให้ผลที่ต้องการพอดีโดยไม่ต้องมี `Timer`:
  /// - key ที่ **เพิ่งรายงานในรอบนี้** มี `lastSampleAt` สดจาก [ProximityGate.push]
  ///   ไปแล้ว จึงรอด sweep แน่นอน (ไม่มีเคสกวาดของสด)
  /// - key ที่ **หายไปจาก array** ไม่มีอะไรมาต่ออายุ จึงถูกจับได้ใน**รอบเดียวกัน**
  ///   ที่มันหาย ไม่ต้องรอ callback ถัดไป
  /// - sample ที่เป็น `unknown` ยังไม่ต่ออายุ `lastSampleAt` ตาม ADR-19 6(ง) เหมือน
  ///   เดิมทุกประการ (`push` เป็นคนบังคับ ไม่ใช่ลำดับตรงนี้)
  ///
  /// **และต้องเรียกเสมอแม้ `beacons` ว่าง** — ถ้า `guard` ทิ้งไปตอน array ว่าง เคส
  /// "ผู้ใช้เดินออกไปแล้ว CoreLocation ยังยิง `didRange` ที่มี array ว่างอยู่" จะไม่มี
  /// ใครค้นพบเลย ซึ่งเป็นเคสเดียวกับที่รอบเดินจริงหวังพึ่ง `didFailRangingFor` แล้วพบ
  /// ว่าพึ่งไม่ได้
  ///
  /// ประกาศ `throws` เพื่อ**บังคับให้ผู้เรียกครอบด้วย do/catch ตั้งแต่วันนี้** ตาม
  /// ADR-21 หัวข้อ 5 แม้เส้นทางปัจจุบันจะยังไม่มีจุดที่ throw จริง — ถ้าวันหนึ่งมี
  /// ใครเพิ่มโค้ดที่ throw เข้ามาในนี้ ชั้น 1 จะยังปลอดภัยอยู่โดยไม่ต้องแก้ผู้เรียก
  ///
  /// - Parameter fromRangeCallback: `true` เฉพาะเมื่อผู้เรียกคือ `didRange` —
  ///   ใช้คุมทั้ง `rangeCb` และบรรทัด `rangetick` (ADR-21 หัวข้อ 9)
  private func runProximityLayer(
    regionIdentifier: String,
    beacons: [CLBeacon],
    fromRangeCallback: Bool
  ) throws {
    decideBackgroundLocationUpdatesIfNeeded()

    if fromRangeCallback {
      rangeCallbackCount += 1
    }

    proximityStore.resetLastError()
    let gate = proximityGateRestoringIfNeeded()

    var pending: [ProximityTransition] = []

    for beacon in beacons {
      let key = ProximityKeyCodec.key(
        regionIdentifier: regionIdentifier,
        uuid: beacon.uuid.uuidString.lowercased(),
        major: beacon.major.uint16Value,
        minor: beacon.minor.uint16Value
      )
      // ส่ง `nil` ตามจริงเมื่อ OS ตอบว่า `unknown` — **ห้ามแปลงเป็น `.far`**
      // ("วัดไม่ได้" ไม่เท่ากับ "ไกล" — ADR-19 หัวข้อ 6(ง))
      let bucket = Self.proximityBucket(beacon.proximity)

      // นับ **ก่อน** push เสมอ: `push` ทิ้ง sample ที่เป็น `unknown` ไปเงียบ ๆ ตาม
      // ADR-19 6(ง) ถ้านับหลังจากผลของ push ตัวเลข `unknown` จะเป็น 0 ตลอดกาลและ
      // สมมติฐาน B ของ ADR-21 หัวข้อ 9 จะทดสอบไม่ได้เลย
      countSample(key: key, bucket: bucket)

      if let transition = gate.push(key: key, bucket: bucket) {
        pending.append(transition)
      }
    }

    // ---- sweep ท้ายสุด และ "เสมอ" แม้ array ว่าง (ดูเหตุผลใน kdoc ข้างบน) ----
    pending.append(contentsOf: gate.sweepStale())

    proximityStore.save(gate.snapshotStates())
    // อ่านหลัง save เพื่อให้ครอบทั้งความล้มเหลวของ load และ save ในรอบเดียวกัน
    let storeError = proximityStore.lastError

    emitProximityTransitions(
      pending,
      fallbackRegionIdentifier: regionIdentifier,
      storeError: storeError
    )

    if fromRangeCallback {
      emitRangeTickIfDue(regionIdentifier: regionIdentifier)
    }
  }

  /// ล้างสถานะชั้นที่ 2 ของ **ทุก key ใน region ที่เพิ่งออก** แล้วประกาศ transition
  /// ด้วย [ProximityTransitionReason.regionExit]
  ///
  /// key ที่ยังค้าง dwell (ไม่เคย confirm bucket ใดเลย) ถูกล้าง **เงียบ ๆ ไม่ emit**
  /// — หลักการเดียวกับ [ProximityGate.sweepStale] เป๊ะ: ไม่เคยประกาศว่า "ใกล้" ก็ไม่มี
  /// อะไรให้ประกาศว่า "หลุด"
  ///
  /// ⚠️ `regionExit` **ไม่ใช่ parity กับ Android** — ฝั่งนั้นไม่มี reason นี้จริง ๆ
  /// (ล้าง store ตอน `monitorStop` ของ example app ไม่ใช่ตอน region exit) และ
  /// `proximity_gate.dart` ก็ไม่มี · เป็นการเบี่ยงจาก reference **โดยตั้งใจ** และเป็น
  /// **หนี้ที่ต้องยกขึ้นไป Dart แล้วไหลลงทั้งสอง port** ในรอบถัดไป (ADR-21 หัวข้อ 8)
  ///
  /// `throws` ด้วยเหตุผลเดียวกับ [runProximityLayer] — บังคับให้ผู้เรียกครอบ do/catch
  private func runProximityRegionExit(regionIdentifier: String) throws {
    proximityStore.resetLastError()
    let gate = proximityGateRestoringIfNeeded()

    let keyPrefix = "\(regionIdentifier)\(ProximityKeyCodec.separator)"
    let transitions = gate.clearStates(matchingPrefix: keyPrefix, emitting: .regionExit)

    // เขียนดิสก์ก่อนแจ้ง observer เสมอ (เหตุผลเดียวกับ runProximityLayer) — และต้อง
    // เขียนแม้ไม่มี transition เพราะ key ที่ยัง pending ก็หายไปจากหน่วยความจำแล้ว
    // ถ้าไม่เขียน สถานะบนดิสก์จะฟื้นมันกลับมาในรอบ launch ถัดไปราวกับไม่เคยออกจาก region
    proximityStore.save(gate.snapshotStates())
    let storeError = proximityStore.lastError

    emitProximityTransitions(
      transitions,
      fallbackRegionIdentifier: regionIdentifier,
      storeError: storeError
    )
  }

  /// แจ้ง observer ทีละ transition พร้อมแนบตัวนับของ key นั้น — จุดเดียวที่สร้าง
  /// [BeaconKitProximityChangedEvent] ในไฟล์นี้
  private func emitProximityTransitions(
    _ transitions: [ProximityTransition],
    fallbackRegionIdentifier: String,
    storeError: String?
  ) {
    guard !transitions.isEmpty else { return }

    let timestampMillis = Self.epochMillisNow()
    for transition in transitions {
      let parsed = ProximityKeyCodec.parse(transition.key)
      let counters = sampleCountersByKey[transition.key] ?? ProximitySampleCounters()
      BackgroundProximityMonitor.emit(
        BeaconKitProximityChangedEvent(
          // ถ้าถอด key ไม่ได้ (ไม่ควรเกิด) ยังต้องรายงาน region ตามที่รู้จริงจาก
          // callback แทนการทิ้ง event ทั้งใบ — ความเงียบคือสิ่งที่ ADR-21 หัวข้อ 7
          // ทั้งข้อพยายามกำจัด
          regionIdentifier: parsed?.regionIdentifier ?? fallbackRegionIdentifier,
          uuid: parsed?.uuid,
          major: parsed?.major,
          minor: parsed?.minor,
          from: transition.from,
          to: transition.to,
          reason: transition.reason,
          medianMeters: transition.medianMeters,
          timestampMillis: timestampMillis,
          storeError: storeError,
          rangeCallbackCount: rangeCallbackCount,
          inArrayCount: counters.inArray,
          unknownCount: counters.unknown
        )
      )
    }
  }

  /// นับว่าบีคอนตัวนี้อยู่ใน array ของ `didRange` รอบนี้ (และเป็น `unknown` หรือไม่)
  ///
  /// **`unknown` นับรวมอยู่ใน `inArray` ด้วย** — สองตัวนี้ตอบคนละคำถาม: `inArray`
  /// ตอบว่า "Apple ยังเห็นบีคอนตัวนี้อยู่ไหม" · `unknown` ตอบว่า "เห็นแล้วแต่ตอบไม่ได้
  /// ว่าใกล้แค่ไหน บ่อยแค่ไหน" ถ้าแยกกันเด็ดขาด (`inArray` ไม่รวม `unknown`) อัตราส่วน
  /// `unknown/inArray` ที่สมมติฐาน B ต้องใช้จะคำนวณไม่ได้จากบรรทัดเดียว
  private func countSample(key: String, bucket: ProximityBucket?) {
    let counters = sampleCountersByKey[key] ?? ProximitySampleCounters()
    sampleCountersByKey[key] = counters.counting(bucket: bucket)
  }

  /// ยิงบรรทัด `rangetick` ถ้าครบรอบ — **อย่างมากทุก 30 วินาทีต่อ process**
  ///
  /// ครั้งแรกของ process ยิงทันที (`lastRangeTickAtMillis == nil`) โดยตั้งใจ: บรรทัด
  /// แรกคือหลักฐานว่า **ranging เริ่มเดินจริงในรอบที่ถูกปลุก** ซึ่งเป็นข้อที่ ADR-21
  /// หัวข้อ 2.1 เพิ่งเพิ่มเข้ามาและยังไม่มีหลักฐานตรง ๆ ของตัวเอง
  ///
  /// `inArray`/`unknown` ที่แนบไปเป็น **ผลรวมของทุก key** ไม่ใช่ของ key ใด key หนึ่ง
  /// (บรรทัดนี้ไม่ได้พูดถึงบีคอนตัวใดตัวหนึ่ง) — ดู kdoc ของ [BeaconKitRangeTickEvent]
  private func emitRangeTickIfDue(regionIdentifier: String) {
    let now = Self.epochMillisNow()
    if let last = lastRangeTickAtMillis, now - last < Self.rangeTickIntervalMillis {
      return
    }
    lastRangeTickAtMillis = now

    var inArrayTotal = 0
    var unknownTotal = 0
    for counters in sampleCountersByKey.values {
      inArrayTotal += counters.inArray
      unknownTotal += counters.unknown
    }

    BackgroundProximityMonitor.emitRangeTick(
      BeaconKitRangeTickEvent(
        regionIdentifier: regionIdentifier,
        rangeCallbackCount: rangeCallbackCount,
        inArrayCount: inArrayTotal,
        unknownCount: unknownTotal,
        timestampMillis: now
      )
    )
  }

  /// ตั้ง `allowsBackgroundLocationUpdates` **ก็ต่อเมื่อ `Info.plist` ของ host app
  /// ประกาศ `UIBackgroundModes` ที่มี `location` จริงเท่านั้น**
  ///
  /// ⚠️ **ห้ามตั้งแบบไม่มีเงื่อนไขเด็ดขาด** — Apple ระบุคำต่อคำว่า "Setting the
  /// value to `true` but omitting the `UIBackgroundModes` key and `location` value
  /// in your app's `Info.plist` file is **a fatal error that terminates the app**"
  /// (`docs/sources/apple_proximity_ranging.md` หัวข้อ 6) `beacon_kit` เป็นไลบรารี
  /// ที่รันอยู่ในแอปของคนอื่น การตั้งดื้อ ๆ = **SDK ฆ่าแอปของ host app เพราะเขา
  /// ลืมใส่ plist** ซึ่งยอมไม่ได้ (ADR-21 หัวข้อ 1)
  ///
  /// เมื่อไม่ตั้ง **ต้องมีร่องรอย ห้ามเงียบ** — ดู
  /// [BackgroundProximityMonitor.backgroundLocationUpdatesTrace]
  ///
  /// ⚠️ **ยังไม่มีเอกสาร Apple ยืนยันว่าแฟล็กนี้มีผลกับ *ranging*** ทุกประโยคในหน้า
  /// นั้นพูดถึง "location updates" ล้วน ๆ (บันทึกไว้แล้วใน sources หัวข้อ
  /// "ไม่พบ/ไม่ยืนยัน (รอบที่ 2)") — ตั้งเพราะเป็นตัวเลือกเดียวที่มี **ต้องพิสูจน์
  /// ด้วยเครื่องจริงเท่านั้น**
  private func decideBackgroundLocationUpdatesIfNeeded() {
    guard !didDecideBackgroundLocationUpdates else { return }
    didDecideBackgroundLocationUpdates = true

    let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
    if Self.allowsBackgroundLocationUpdates(backgroundModes: modes) {
      locationManager.allowsBackgroundLocationUpdates = true
      BackgroundProximityMonitor.recordBackgroundLocationUpdatesTrace(
        "allowsBackgroundLocationUpdates=true"
      )
    } else {
      BackgroundProximityMonitor.recordBackgroundLocationUpdatesTrace(
        "allowsBackgroundLocationUpdates=skipped"
          + " reason=no-location-in-UIBackgroundModes"
          + " modes=[\((modes ?? []).joined(separator: ","))]"
      )
    }
  }

  /// ส่วนที่เป็น **pure function** ของ [decideBackgroundLocationUpdatesIfNeeded] —
  /// แยกออกมาเพื่อให้ XCTest ตรวจตารางการตัดสินนี้ได้โดยไม่ต้องแก้ `Info.plist`
  /// ของแอปทดสอบ (pattern เดียวกับ `authorizationDecision(for:)`)
  static func allowsBackgroundLocationUpdates(backgroundModes: [String]?) -> Bool {
    return (backgroundModes ?? []).contains("location")
  }

  /// แปลง `CLProximity` -> [ProximityBucket] — **`nil` เมื่อ `unknown`**
  ///
  /// การแปลงอยู่ที่ไฟล์นี้ (ซึ่ง import CoreLocation อยู่แล้ว) ไม่ใช่ใน
  /// `ProximityGate.swift` ที่ห้าม import CoreLocation ตาม ADR-21 หัวข้อ 2
  ///
  /// `unknown` แปลงเป็น `nil` **ไม่ใช่ `.far`** — Apple นิยามไว้ว่า "The proximity
  /// of the beacon could not be determined" ซึ่งคือ "วัดไม่ได้" คนละเรื่องกับ
  /// "วัดได้แล้วไกล" (ADR-19 หัวข้อ 6(ง)) `@unknown default` ก็เป็น `nil` ด้วย
  /// เหตุผลเดียวกัน: case ที่เราไม่รู้จัก = ตอบไม่ได้ ห้ามเดา
  static func proximityBucket(_ proximity: CLProximity) -> ProximityBucket? {
    switch proximity {
    case .immediate:
      return .immediate
    case .near:
      return .near
    case .far:
      return .far
    case .unknown:
      return nil
    @unknown default:
      return nil
    }
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
