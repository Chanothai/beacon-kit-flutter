import Flutter
import UIKit
import UserNotifications

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
        result(try Self.prepareLogFile(named: fileName))
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
      result(Self.protectionOfLogFile(named: fileName))

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
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      // trigger เป็น nil = ยิงทันที สำคัญมากสำหรับเคสที่แอปถูกปลุกเบื้องหลัง
      // เพราะเวลาที่ระบบให้มาสั้น อาจถูก suspend ก่อนถ้าหน่วงเวลา
      let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
      )
      UNUserNotificationCenter.current().add(request) { error in
        DispatchQueue.main.async {
          if let error = error {
            result(
              FlutterError(
                code: "NOTIFICATION_FAILED",
                message: error.localizedDescription,
                details: nil
              )
            )
          } else {
            result(nil)
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }


  // MARK: - Log file + Data Protection

  /// protection class ที่ไฟล์ log **ต้อง**ได้รับ
  ///
  /// **ทำไมต้องตั้งเอง ทั้งที่นี่เป็นค่า default ของ iOS อยู่แล้ว:**
  /// เอกสาร Apple ("Encrypting your app's files") ระบุว่า "If you do not specify
  /// a protection level when creating a file, iOS applies the default protection
  /// level automatically" และอธิบายระดับนี้ว่า "(Default) The file is inaccessible
  /// until the first time the user unlocks the device. After the first unlocking of
  /// the device, the file remains accessible until the device shuts down or reboots."
  ///
  /// นั่นแปลว่าค่า default **ตรงกับที่เราต้องการอยู่แล้ว** แต่การพึ่ง default คือการ
  /// พึ่งสิ่งที่เราไม่ได้ควบคุมและอาจเปลี่ยนได้ตาม entitlement/เวอร์ชัน iOS —
  /// ถ้าวันหนึ่งกลายเป็น `.complete` การเขียน log ตอนเครื่องล็อกจะล้มเหลว
  /// ซึ่งแปลว่า **แอปตื่นจริงแต่ไม่มีหลักฐาน** แล้วเราจะสรุปผิดว่า B5 ไม่ผ่าน
  /// การตั้งค่าให้ชัดจึงเป็นการล็อกสมมติฐานที่การทดสอบทั้งหมดตั้งอยู่บนมัน
  ///
  /// **ยังมีเคสที่เขียนไม่ได้อยู่ดี:** ถ้าเครื่องรีบูตแล้ว**ยังไม่เคยปลดล็อกเลย**
  /// สักครั้ง ไฟล์ระดับนี้ยังเข้าถึงไม่ได้ — เป็นข้อจำกัดที่ยอมรับ เพราะระดับที่ต่ำ
  /// กว่านี้ (`.none`) แปลว่าไม่เข้ารหัสเลย ซึ่งไม่เหมาะกับไฟล์ที่บันทึกว่าผู้ใช้
  /// อยู่สาขาไหนเวลาใด
  private static let logFileProtection = FileProtectionType.completeUntilFirstUserAuthentication

  /// สร้าง (ถ้ายังไม่มี) ไฟล์ log พร้อมตั้ง protection class ให้ชัดเจน แล้วคืน path
  ///
  /// ตั้ง protection ทั้งที่ **directory** และ **ไฟล์**: directory เพื่อให้ไฟล์ใหม่
  /// ที่ถูกสร้างในนั้นภายหลังได้ค่าเดียวกัน และไฟล์เพื่อให้ไฟล์ที่มีอยู่แล้วจากการ
  /// ติดตั้งเวอร์ชันก่อนหน้าถูกอัปเดตด้วย
  private static func prepareLogFile(named fileName: String) throws -> String {
    let fm = FileManager.default
    guard
      let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else {
      throw NSError(
        domain: "beacon_kit_example",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "หา Application Support directory ไม่เจอ"]
      )
    }

    // Application Support ไม่ได้ถูกสร้างมาให้อัตโนมัติเหมือน Documents
    try fm.createDirectory(
      at: dir,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: logFileProtection]
    )
    try fm.setAttributes([.protectionKey: logFileProtection], ofItemAtPath: dir.path)

    let fileURL = dir.appendingPathComponent(fileName)
    if !fm.fileExists(atPath: fileURL.path) {
      fm.createFile(
        atPath: fileURL.path,
        contents: nil,
        attributes: [.protectionKey: logFileProtection]
      )
    } else {
      try fm.setAttributes([.protectionKey: logFileProtection], ofItemAtPath: fileURL.path)
    }

    return fileURL.path
  }

  /// อ่าน protection class จริงของไฟล์ log กลับมา (`nil` ถ้ายังไม่มีไฟล์)
  static func protectionOfLogFile(named fileName: String) -> String? {
    let fm = FileManager.default
    guard
      let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return nil }
    let path = dir.appendingPathComponent(fileName).path
    guard let attrs = try? fm.attributesOfItem(atPath: path),
      let protection = attrs[.protectionKey] as? FileProtectionType
    else { return nil }
    return protection.rawValue
  }

  /// เปิดให้ XCTest เรียกได้โดยไม่ต้องผ่าน method channel
  static func prepareLogFileForTesting(named fileName: String) throws -> String {
    try prepareLogFile(named: fileName)
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
