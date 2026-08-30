import Flutter
import UIKit
import UserNotifications
import beacon_kit_ios

/// AppDelegate ของ **example app เท่านั้น** — โค้ดในไฟล์นี้จงใจไม่อยู่ใน `beacon_kit`
/// เพราะ SDK ไม่ควรบังคับให้ผู้ใช้ต้องพึ่ง UserNotifications หรือรูปแบบการเก็บ log
/// แบบใดแบบหนึ่ง นี่เป็นเครื่องมือสำหรับ **พิสูจน์ B5/B6 บนอุปกรณ์จริง** ล้วน ๆ
///
/// ให้บริการผ่าน method channel `beacon_kit_example/diagnostics`:
///   - `getLaunchDiagnostics` : สัญญาณดิบสำหรับแยกว่าแอป "ถูกปลุกจากสถานะถูกฆ่า"
///                              หรือ "รันอยู่เบื้องหลังอยู่แล้ว"
///   - `getLogDirectory`      : path ของ Application Support (ไม่ต้องพึ่ง path_provider)
///   - `requestNotificationAuthorization` / `postNotification`
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// เวลาที่ **process นี้** เริ่ม — ใช้คำนวณว่า event เกิดขึ้นกี่วินาทีหลังแอปเปิด
  /// (event ที่เกิดไม่กี่วินาทีหลัง process เริ่ม + แอปไม่เคย active = สัญญาณของ
  /// การถูกปลุกจากสถานะถูกฆ่า)
  private let processStartedAt = Date()

  /// `true` ถ้า iOS ส่ง `UIApplication.LaunchOptionsKey.location` มาตอน launch
  ///
  /// ความหมายตามเอกสาร Apple: "A key indicating that the app was launched to
  /// handle an incoming location event" และคอมเมนต์ใน UIKit header:
  /// "The app was launched in response to a CoreLocation event"
  ///
  /// ⚠️ key นี้ถูก deprecate แล้วใน iOS 26.0 (`API_DEPRECATED(..., ios(4.0, 26.0))`
  /// ข้อความ: "Adopt CLLocationUpdate or CLMonitor, or use CLLocationManagerDelegate
  /// from CoreLocation to handle expected location events after scene connection.")
  /// — ยังใช้ได้อยู่ ไม่ได้ถูกถอดออก และทางเลือกที่ Apple แนะนำคือ `CLMonitor`
  /// ซึ่ง ADR-6 หัวข้อ 4 ตัดสินแล้วว่ายังไม่ย้ายในรอบนี้ จึงยังใช้ key นี้ต่อ
  /// **แต่ไม่พึ่งมันตัวเดียว** — ดู `hasEverBecomeActive` ประกอบ
  private var launchedByLocationKey = false

  /// `true` เมื่อแอปเคยขึ้นมาอยู่ foreground อย่างน้อยหนึ่งครั้งใน process นี้
  ///
  /// เป็นสัญญาณอิสระที่**ไม่พึ่ง API ที่ deprecated เลย**: process ที่ผู้ใช้เปิดเอง
  /// จะผ่าน active เสมอ ส่วน process ที่ iOS ปลุกขึ้นมาเบื้องหลังเพื่อส่ง location
  /// event จะไม่เคย active จนกว่าผู้ใช้จะกดเปิดแอปเอง
  private var hasEverBecomeActive = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    launchedByLocationKey = launchOptions?[.location] != nil

    // ต้องตั้ง delegate ตรงนี้ ไม่งั้น `userNotificationCenter(_:willPresent:...)`
    // จะไม่ถูกเรียกเลย และ **notification จะไม่แสดงตอนแอปอยู่ foreground**
    // (ดูเหตุผลเต็มที่เมธอดนั้น) — ตั้งใน didFinishLaunching ตามที่ header ระบุว่า
    // "The delegate must be set before the application returns from
    //  application:didFinishLaunchingWithOptions:"
    UNUserNotificationCenter.current().delegate = self

    // **ADR-10 — จุดที่ทำให้ B5 รอบ 30 ส.ค. 2026 ไม่ผ่าน:**
    // เดิม `CLLocationManager` ถูกสร้างตอน `BeaconKitIosPlugin.register(with:)`
    // ซึ่งวิ่งใน `didInitializeImplicitFlutterEngine` — ผูกกับการที่
    // `FlutterViewController` ถูกสร้างจาก storyboard ตอน scene connect
    // ตอน iOS ปลุก process ที่ถูกฆ่าขึ้นมาเบื้องหลังเพื่อส่ง region event ไม่มี
    // scene ถูก connect จึงไม่มีใครสร้าง location manager และไม่มี delegate ให้
    // CoreLocation เรียก — แอปถูกปลุกจริงแต่ event ตกหายทั้งหมด
    //
    // เรียกตรงนี้เพื่อให้ manager + delegate มีตัวตนตั้งแต่รอบ launch เสมอ
    // ไม่ว่ารอบนั้นจะมี UI หรือไม่ และไม่ต้องรอ Dart เรียกเข้ามา
    //
    // ⚠️ ห้ามใส่ `stopMonitoring` ใด ๆ ในเส้นทางนี้ (ดูคอมเมนต์ใน
    // `IBeaconRangingManager.init()`) — การเรียกเองจะล้าง region ที่เป็นเหตุผล
    // เดียวที่ทำให้ iOS ปลุกแอปขึ้นมา
    let restoredRegionIdentifiers = BeaconKitIosPlugin.startBackgroundRegionMonitoring {
      [weak self] event in
      self?.recordRegionEvent(event)
    }

    // เขียนบรรทัด launch **ทุกครั้ง** ไม่ว่ารอบนั้นจะมี event หรือไม่ — นี่คือจุดที่
    // แยก "iOS ไม่ได้ปลุกแอปเลย" (ไม่มีบรรทัด launch ใหม่) ออกจาก "ปลุกแล้วแต่
    // event ไม่ถึง handler" (มีบรรทัด launch แต่ไม่มี enter/exit ตามมา) ซึ่งรอบ
    // ทดสอบก่อนหน้าแยกไม่ออกเลยเพราะไม่มีบรรทัดอะไรทั้งสิ้นให้ดู
    logLaunch(restoredRegionIdentifiers: restoredRegionIdentifiers)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - หลักฐาน B5 ฝั่ง native (ไม่พึ่ง Flutter engine)

  /// เขียนหนึ่งบรรทัดทุกครั้งที่ process เริ่มทำงาน
  ///
  /// `monitoredRegions` ในบรรทัดนี้สำคัญที่สุด — เป็นหลักฐานว่า region **รอดข้าม
  /// process** มาจริง (header ของ `monitoredRegions` ระบุว่า region ที่ลงทะเบียนไว้
  /// "during this or previous launches of your application" จะอยู่ในเซ็ตนี้)
  /// ถ้าบรรทัด launch แสดง `monitoredRegions=[]` แปลว่าไม่มีอะไรให้ iOS ปลุกแอป
  /// ตั้งแต่แรก ซึ่งเป็นคนละสาเหตุกับ "ปลุกแล้วแต่ event หาย" โดยสิ้นเชิง
  private func logLaunch(restoredRegionIdentifiers: [String]) {
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: processStartedAt,
        event: "launch",
        regionIdentifier: "-",
        conclusion: currentRunContext(),
        rawSignals:
          "\(rawSignalSummary()) monitoredRegions=[\(restoredRegionIdentifiers.joined(separator: ","))]"
      )
    )
  }

  /// เขียน log + ยิง notification จาก **โค้ด native ล้วน**
  ///
  /// ทั้งสองอย่างเคยอยู่ฝั่ง Dart (`_onRegionEvent` ใน `main.dart`) ซึ่งใช้ได้ก็
  /// ต่อเมื่อ Flutter engine ทำงานอยู่ — เงื่อนไขที่ไม่เป็นจริงในเคสที่ B5 ต้องการ
  /// พิสูจน์พอดี ย้ายมาทางนี้เพื่อให้ทำงานได้ทุกบริบท และเพื่อให้มี **ผู้เขียน log
  /// เพียงรายเดียว** ไม่งั้นตอน foreground จะได้บรรทัดซ้ำสองชุดต่อหนึ่ง event
  private func recordRegionEvent(_ event: BeaconKitRegionStateEvent) {
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: event.timestamp,
        event: event.state,
        regionIdentifier: event.regionIdentifier,
        conclusion: currentRunContext(),
        rawSignals: rawSignalSummary()
      )
    )

    // ยิง notification **หลัง**เขียน log เสมอ — log คือหลักฐานที่ต้องรอด ส่วน
    // notification เป็นแค่สัญญาณให้คนเห็น ถ้าเวลาที่ระบบให้หมดก่อน อย่างน้อย
    // หลักฐานต้องลงดิสก์แล้ว
    postNotification(
      title: "Region \(event.state): \(event.regionIdentifier)",
      body: "สถานะแอป: \(currentRunContext())"
    )
  }

  /// ข้อสรุปว่ารอบนี้แอปอยู่ในบริบทไหน — ใช้ตรรกะเดียวกับ `AppRunContext` ฝั่ง Dart
  ///
  /// `relaunchedFromTerminated` คือค่าที่ B5 ต้องเห็นในไฟล์ log จึงจะถือว่าผ่าน:
  /// process อยู่เบื้องหลัง **และ** ไม่เคยขึ้น foreground เลยตั้งแต่เริ่ม แปลว่า
  /// ไม่ใช่ผู้ใช้เปิดแอปเอง
  private func currentRunContext() -> String {
    switch UIApplication.shared.applicationState {
    case .active:
      return "foreground"
    case .background, .inactive:
      return hasEverBecomeActive ? "background" : "relaunchedFromTerminated"
    @unknown default:
      return "unknown"
    }
  }

  /// สัญญาณดิบชุดเดียวกับที่ `getLaunchDiagnostics` คืนให้ Dart — เก็บลง log ด้วย
  /// เพื่อให้ตรวจย้อนกลับได้ว่าข้อสรุปข้างต้นมาจากอะไร ถ้าวันหนึ่งพบว่าวิธีสรุป
  /// ของเราผิด ข้อมูลดิบยังอยู่
  private func rawSignalSummary() -> String {
    let uptime = Date().timeIntervalSince(processStartedAt)
    return
      "launchKey=\(launchedByLocationKey) everActive=\(hasEverBecomeActive) "
      + "state=\(Self.stateString(UIApplication.shared.applicationState)) "
      + "uptime=\(String(format: "%.1f", uptime))s"
  }

  private func postNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    // trigger เป็น nil = ยิงทันที สำคัญมากสำหรับเคสที่แอปถูกปลุกเบื้องหลัง
    // เพราะเวลาที่ระบบให้มาสั้น อาจถูก suspend ก่อนถ้าหน่วงเวลา
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
      )
    )
  }

  /// แสดง notification แม้ตอนแอปอยู่ **foreground**
  ///
  /// **ทำไมต้องมีเมธอดนี้ — จากคอมเมนต์ใน header จริง**
  /// (`UserNotifications.framework/Headers/UNUserNotificationCenter.h:96`,
  /// iPhoneOS26.5.sdk):
  ///
  /// > "The method will be called on the delegate only if the application is in
  /// > the foreground. **If the method is not implemented or the handler is not
  /// > called in a timely manner then the notification will not be presented.**"
  ///
  /// นี่คือสาเหตุที่การทดสอบข้อ 1 (foreground) ไม่เห็นอะไรเลย ทั้งที่ข้อ 2
  /// (background) ได้ notification ปกติ — ไม่ใช่ปัญหาของ CoreLocation/region
  /// แต่เป็นเพราะ iOS ไม่แสดง notification ให้แอปที่กำลังเปิดอยู่ ถ้าแอปไม่บอกว่า
  /// ต้องการให้แสดง
  ///
  /// ใช้ `[.banner, .list, .sound]` ไม่ใช่ `.alert` เพราะ
  /// `UNNotificationPresentationOptionAlert` ถูก deprecate ตั้งแต่ iOS 14
  /// (`API_DEPRECATED_WITH_REPLACEMENT("UNNotificationPresentationOptionList | `
  /// `UNNotificationPresentationOptionBanner", ..., ios(10.0, 14.0), ...)`
  /// ที่ `UNUserNotificationCenter.h:84`) — deployment target ของโปรเจกต์นี้คือ
  /// iOS 15 จึงใช้ตัวใหม่ได้เลย
  /// `.banner` = เด้งขึ้นมาให้เห็นทันที, `.list` = ค้างไว้ใน Notification Center
  /// ให้ย้อนดูได้
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // ส่งต่อให้ FlutterAppDelegate ก่อน เพื่อไม่ให้ plugin ที่พึ่ง callback นี้เสียหาย
    // (FlutterAppDelegate conform UNUserNotificationCenterDelegate ผ่าน
    //  FlutterAppLifeCycleProvider อยู่แล้ว — ดู FlutterPlugin.h:521)
    // ใช้ completion handler ของตัวเองเป็นตัวตอบสุดท้าย เพราะ contract ของ iOS คือ
    // ต้องเรียก handler ครั้งเดียวเสมอ
    super.userNotificationCenter(
      center,
      willPresent: notification,
      withCompletionHandler: { _ in }
    )
    completionHandler([.banner, .list, .sound])
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    hasEverBecomeActive = true
    super.applicationDidBecomeActive(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "beacon_kit_example/diagnostics",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getLaunchDiagnostics":
      // คืน**สัญญาณดิบทั้งหมด** ไม่ตัดสินใจแทนฝั่ง Dart — เพื่อให้ log เก็บข้อเท็จจริง
      // ไว้ด้วย ถ้าภายหลังพบว่าวิธีสรุปของเราผิด ข้อมูลดิบยังตรวจย้อนกลับได้
      result([
        "launchedByLocationKey": launchedByLocationKey,
        "hasEverBecomeActive": hasEverBecomeActive,
        "applicationState": Self.stateString(UIApplication.shared.applicationState),
        "processUptimeSeconds": Date().timeIntervalSince(processStartedAt),
      ])

    case "prepareLogFile":
      guard let args = call.arguments as? [String: Any],
        let fileName = args["fileName"] as? String
      else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "ต้องมี fileName เป็น String",
            details: nil
          )
        )
        return
      }
      do {
        result(try BackgroundEvidenceLog.prepareLogFile(named: fileName))
      } catch {
        result(
          FlutterError(
            code: "PREPARE_LOG_FAILED",
            message: error.localizedDescription,
            details: nil
          )
        )
      }

    case "getLogFileProtection":
      // ให้ Dart/เทสต์อ่านค่าจริงที่ไฟล์ได้รับกลับไปตรวจได้ ไม่ต้องเชื่อว่าเราตั้งสำเร็จ
      guard let args = call.arguments as? [String: Any],
        let fileName = args["fileName"] as? String
      else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "ต้องมี fileName เป็น String",
            details: nil
          )
        )
        return
      }
      result(BackgroundEvidenceLog.protectionOfLogFile(named: fileName))

    case "requestNotificationAuthorization":
      UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          DispatchQueue.main.async { result(granted) }
        }

    case "postNotification":
      guard let args = call.arguments as? [String: Any],
        let title = args["title"] as? String,
        let body = args["body"] as? String
      else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "ต้องมี title และ body เป็น String",
            details: nil
          )
        )
        return
      }
      // ใช้ตัวเดียวกับเส้นทาง native (`recordRegionEvent`) เพื่อไม่ให้รูปแบบ
      // notification ของสองเส้นทางต่างกัน
      postNotification(title: title, body: body)
      result(nil)

    case "getLogWriteError":
      // ให้ฝั่ง Dart ดึง error ของการเขียน log ฝั่ง native มาแสดงได้ — ตอนถูกปลุก
      // เบื้องหลังไม่มีใครเห็น error ตรงนั้น ถ้าไม่เก็บไว้จะกลายเป็น "ไม่มีบรรทัด
      // ใน log" แบบไม่มีคำอธิบาย ซึ่งแยกไม่ออกจากการที่แอปไม่ถูกปลุกเลย
      result(BackgroundEvidenceLog.shared.lastError)

    default:
      result(FlutterMethodNotImplemented)
    }
  }


  // MARK: - Log file + Data Protection

  /// ทั้งสองเมธอดนี้เป็นแค่ทางผ่านไปยัง `BackgroundEvidenceLog` — เจตนาคือให้มี
  /// **ที่เดียว**ที่รู้ว่าไฟล์ log อยู่ไหนและต้องได้ protection class อะไร
  /// ถ้าปล่อยให้เส้นทาง native กับเส้นทาง Dart เตรียมไฟล์กันคนละชุด วันหนึ่งค่า
  /// จะ drift แล้วบรรทัดที่หายไปจะถูกโทษว่าเป็นบั๊กของ CoreLocation แทน
  static func prepareLogFileForTesting(named fileName: String) throws -> String {
    try BackgroundEvidenceLog.prepareLogFile(named: fileName)
  }

  static func protectionOfLogFile(named fileName: String) -> String? {
    BackgroundEvidenceLog.protectionOfLogFile(named: fileName)
  }

  private static func stateString(_ state: UIApplication.State) -> String {
    switch state {
    case .active: return "active"
    case .inactive: return "inactive"
    case .background: return "background"
    @unknown default: return "unknown"
    }
  }
}
