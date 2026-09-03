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
  ///
  /// **ADR-16 §1.3:** ตั้งค่าจากสองเส้นทาง — observer ของ
  /// `UIApplication.didBecomeActiveNotification` (ทางหลัก ทำงานได้ทั้งกรณีแอปใช้
  /// scene และไม่ใช้) กับ `override applicationDidBecomeActive` ด้านล่าง (fallback
  /// เดิม ที่ตายเมื่อแอปใช้ scene ตามเอกสาร Apple — ดูคอมเมนต์ที่จุดลงทะเบียน
  /// observer ใน `didFinishLaunchingWithOptions`) ทั้งสองเส้นทางตั้งค่าเดียวกันแบบ
  /// idempotent จึงเรียกซ้ำหรือเรียกทั้งคู่ได้อย่างปลอดภัย
  private var hasEverBecomeActive = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    launchedByLocationKey = launchOptions?[.location] != nil

    // **ADR-16 §1.3 — แหล่งความจริงใหม่ของ `hasEverBecomeActive` ภายใต้ UIScene
    // lifecycle:** แอปนี้ประกาศ `UIApplicationSceneManifest` (Info.plist:40-60)
    // ตามเอกสาร Apple ของ `applicationDidBecomeActive(_:)`
    // (https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationdidbecomeactive(_:)):
    // "If you're using scenes ... UIKit will not call this method" — override
    // เดิมด้านล่างจึงเป็น dead code ตลอดชีพ process ทุกกรณีที่แอปยังใช้ scene
    // เอกสารหน้าเดียวกันยืนยันด้วยว่า "UIKit posts a didBecomeActiveNotification
    // regardless of whether your app uses scenes" — สังเกตสัญญาณนี้แทนจึงทำงานได้
    // ไม่ว่าแอปจะใช้ scene หรือไม่
    //
    // ลงทะเบียนที่ต้นเมธอดนี้ (ก่อน scene ใด ๆ ถูก connect เสมอ) เพราะเอกสาร Apple
    // ของ `didFinishLaunchingWithOptions` เองระบุลำดับเหตุการณ์ไว้ตรง ๆ ว่า
    // "The system calls this method as soon as the process is done launching.
    // The system then creates the scene(s) that you configured for your app.
    // The system calls scene life-cycle methods, such as
    // scene(_:willConnectTo:options:)." — observer จึงมีตัวตนก่อนโอกาสแรกที่
    // `didBecomeActiveNotification` จะถูก post ได้เสมอ ไม่มีช่องให้ race
    //
    // ใช้ `[weak self]` กัน retain cycle — `NotificationCenter` ถือ closure นี้ไว้
    // เอง ไม่ใช่ผูกกับ observer token ที่เราทิ้งไว้โดยไม่เก็บ reference คืน
    //
    // ไม่ removeObserver เพราะ `AppDelegate` (`@main`) มีอายุเท่ากับ process เอง
    // ไม่มีจังหวะใดที่ instance นี้จะถูกทำลายก่อน process จบแล้วต้องเลิกฟังก่อน
    //
    // ปลอดภัยต่อการเรียกซ้ำ/เรียกคู่กับ `override applicationDidBecomeActive`
    // ด้านล่าง (คงไว้เป็น defensive fallback ตาม ADR-16 §1.3 เผื่อวันหนึ่งแอปเลิก
    // ใช้ scene): ทั้งสองเส้นทางแค่ตั้ง `Bool` เดียวกันเป็น `true` ซึ่ง idempotent
    // อยู่แล้ว — ยิงกี่ครั้ง ยิงพร้อมกัน หรือยิงจากคนละเส้นทาง ผลลัพธ์เหมือนเดิมเป๊ะ
    //
    // **ทำไมต้องเป็น `queue: nil`** — เอกสาร Apple ของพารามิเตอร์ `queue` ของ
    // เมธอดนี้ (`NotificationCenter.addObserver(forName:object:queue:using:)`,
    // https://developer.apple.com/documentation/foundation/notificationcenter/addobserver(forname:object:queue:using:))
    // ระบุตรง ๆ ว่า: "The operation queue where the block runs." และ "When nil,
    // the block runs synchronously on the posting thread." — `nil` จึงแปลว่า
    // block นี้รันทันทีบนเธรดเดียวกับที่ UIKit post notification (main thread
    // สำหรับ lifecycle notification นี้) ไม่มีการเลื่อนคิวใด ๆ
    //
    // ⚠️ **ถ้ามีคนเปลี่ยนเป็น `.main` ในอนาคต:** ผลจะเปลี่ยนจาก "รันทันทีแบบ
    // synchronous" เป็น "ถูก schedule เข้าคิวของ `OperationQueue.main` แบบ
    // asynchronous" — เปิดช่องให้มีจังหวะสั้น ๆ ที่ notification ถูก post ไปแล้ว
    // จริง แต่ `hasEverBecomeActive` ยังไม่ทันถูกตั้งเป็น `true` (โค้ดอื่นที่อ่าน
    // ค่านี้ในช่วงนั้นจะเห็นค่าเก่า) ทั้งที่ block ในตัวนี้ไม่ได้ทำงานหนักอะไรเลย
    // (แค่ตั้ง `Bool` ตัวเดียว) จึงไม่มีเหตุผลด้านประสิทธิภาพที่ต้องเลื่อนออกจาก
    // เธรดเดิม — คงไว้เป็น `nil` ตราบใดที่ closure ยังทำแค่สิ่งนี้
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.hasEverBecomeActive = true
    }

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
        // receiverEntry = false เสมอ **แม้ process นี้จะถูก iOS ปลุกขึ้นมาเพื่อส่ง
        // location event ก็ตาม** — บรรทัดนี้เขียนใน
        // `didFinishLaunchingWithOptions` ซึ่งจบก่อน CoreLocation จะเรียก delegate
        //
        // อ่านคู่กับคอลัมน์ `conclusion`: บรรทัด launch ที่เป็น
        // `relaunchedFromTerminated` แล้วตามด้วยบรรทัดที่มี `receiverEntry=true`
        // และ `procUuid` เดียวกัน = iOS สร้าง process ขึ้นมาเพื่อส่ง event นั้น
        // โดยเฉพาะ ซึ่งคือสิ่งที่ B5 ต้องพิสูจน์
        rawSignals:
          "\(rawSignalSummary(receiverEntry: false)) "
          + "monitoredRegions=[\(restoredRegionIdentifiers.joined(separator: ","))]"
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
        // receiverEntry = true เป็น **ข้อเท็จจริงของเส้นทางเรียก ไม่ใช่การเดา**:
        // hook นี้ถูกเรียกจาก `IBeaconRangingManager.emitRegionStateIfChanged`
        // จุดเดียว และเมธอดนั้นมีผู้เรียกแค่สามตัว ซึ่งทั้งสามเป็น
        // `CLLocationManagerDelegate` ที่ระบบเรียกเข้ามาทั้งหมด:
        // `didEnterRegion` / `didExitRegion` / `didDetermineState`
        //
        // ถ้าวันหนึ่งมีเส้นทางที่ยิง event จากที่อื่น **ต้องแยกค่าตรงนี้**
        // ไม่ใช่ปล่อยให้บรรทัดนั้นอ้างว่ามาจาก callback ของระบบ
        rawSignals: rawSignalSummary(receiverEntry: true)
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

  /// **ตรรกะการตัดสินล้วน (pure)** — แยกออกจาก `currentRunContext()` เพื่อให้
  /// XCTest คลุมได้จริงโดยไม่ต้องพึ่งค่า `UIApplication.shared.applicationState`
  /// ของจริง (ซึ่งอ่านได้แค่ตอนแอปรันอยู่ ไม่ใช่ค่าที่ทดสอบตั้งเองได้) — pattern
  /// เดียวกับที่ `BackgroundEvidenceLog.line`/`processMarker` ฝั่ง Android แยก
  /// pure function ออกมาให้ unit test คลุมได้ (ดู `BackgroundEvidenceLog.kt`)
  ///
  /// รับพารามิเตอร์แทนการอ่าน property ของ `self` ตรง ๆ เพื่อให้เป็น pure
  /// function จริง (input เดียวกัน -> output เดียวกันเสมอ ไม่มี side effect
  /// และไม่ต้องสร้าง `AppDelegate` instance เพื่อเรียก) — ดู ADR-16 หัวข้อ 1
  ///
  /// ⚠️ **ห้ามเปลี่ยนสตริงที่คืนกลับแม้แต่ตัวเดียว** (`foreground` / `background` /
  /// `relaunchedFromTerminated` / `unknown`) — ค่าเหล่านี้ใช้ร่วมกับ
  /// `ProcessState.conclusion` ฝั่ง Android และ `AppRunContext` ใน
  /// `example/lib/diagnostics/launch_context.dart` ถ้าเปลี่ยนชื่อค่าที่นี่โดยไม่
  /// เปลี่ยนอีกสองฝั่ง เครื่องมือเทียบ log ข้ามแพลตฟอร์ม
  /// (`tool/analyze_region_log.dart`) จะอ่านไม่ตรงกันทันที
  static func runContext(
    applicationState: UIApplication.State,
    hasEverBecomeActive: Bool
  ) -> String {
    switch applicationState {
    case .active:
      return "foreground"
    case .background, .inactive:
      return hasEverBecomeActive ? "background" : "relaunchedFromTerminated"
    @unknown default:
      return "unknown"
    }
  }

  /// ข้อสรุปว่ารอบนี้แอปอยู่ในบริบทไหน — ใช้ตรรกะเดียวกับ `AppRunContext` ฝั่ง Dart
  ///
  /// `relaunchedFromTerminated` คือค่าที่ B5 ต้องเห็นในไฟล์ log จึงจะถือว่าผ่าน:
  /// process อยู่เบื้องหลัง **และ** ไม่เคยขึ้น foreground เลยตั้งแต่เริ่ม แปลว่า
  /// ไม่ใช่ผู้ใช้เปิดแอปเอง
  ///
  /// แค่ทางผ่านไปยัง [runContext] พร้อมค่าจริงของ process นี้ — ตัวตรรกะเองอยู่ที่
  /// [runContext] ทั้งหมด (ADR-16 หัวข้อ 1)
  private func currentRunContext() -> String {
    Self.runContext(
      applicationState: UIApplication.shared.applicationState,
      hasEverBecomeActive: hasEverBecomeActive
    )
  }

  /// สัญญาณดิบชุดเดียวกับที่ `getLaunchDiagnostics` คืนให้ Dart — เก็บลง log ด้วย
  /// เพื่อให้ตรวจย้อนกลับได้ว่าข้อสรุปข้างต้นมาจากอะไร ถ้าวันหนึ่งพบว่าวิธีสรุป
  /// ของเราผิด ข้อมูลดิบยังอยู่
  ///
  /// ขึ้นต้นด้วย `BackgroundEvidenceLog.processMarker` เสมอ (รูปแบบเดียวกับฝั่ง
  /// Android เป๊ะ) ตามด้วยสัญญาณที่มีเฉพาะฝั่ง iOS
  ///
  /// [receiverEntry] ไม่มีค่า default **โดยตั้งใจ** — ผู้เรียกต้องตอบทุกครั้งว่า
  /// บรรทัดนี้เขียนจาก callback ที่ระบบเรียกเข้ามาหรือไม่ ถ้าให้ default ไว้
  /// บรรทัดที่ผู้เรียกใหม่ลืมส่งจะได้ค่าที่ดู "ปกติ" แต่ไม่จริง ซึ่งแย่กว่า
  /// คอมไพล์ไม่ผ่าน
  ///
  /// ⚠️ `uptimeMs` ฝั่งนี้วัดด้วย **นาฬิกาเวลาจริง** (`Date`) ต่างจากฝั่ง Android
  /// ที่ใช้ `SystemClock.elapsedRealtime()` ซึ่งไม่กระโดด — ถ้าเครื่องซิงก์เวลา
  /// กับเครือข่ายกลางรอบทดสอบ ค่านี้ฝั่ง iOS จะกระโดดตาม เก็บรูปแบบเดิมไว้เพราะ
  /// ทางเลือกฝั่ง iOS (`ProcessInfo.systemUptime`) **ไม่นับเวลาที่เครื่องหลับ**
  /// ซึ่งเพี้ยนหนักกว่ามากในรอบทดสอบข้ามคืนที่เครื่องหลับเป็นส่วนใหญ่
  private func rawSignalSummary(receiverEntry: Bool) -> String {
    let uptimeMillis = Int(Date().timeIntervalSince(processStartedAt) * 1000)
    return
      BackgroundEvidenceLog.processMarker(
        uptimeMillis: uptimeMillis,
        receiverEntry: receiverEntry
      )
      + " launchKey=\(launchedByLocationKey) everActive=\(hasEverBecomeActive) "
      + "state=\(Self.stateString(UIApplication.shared.applicationState))"
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

  /// **ADR-16 §1.3 — เก็บไว้เป็น defensive fallback เท่านั้น ห้ามลบ**
  ///
  /// ตราบใดที่แอปประกาศ `UIApplicationSceneManifest` (Info.plist:40-60) เมธอดนี้
  /// **ไม่ถูก UIKit เรียกเลย** ตามเอกสาร Apple ที่ observer ใน
  /// `didFinishLaunchingWithOptions` อ้างถึงข้างบน — สัญญาณตัวจริงในวันนี้คือ
  /// `UIApplication.didBecomeActiveNotification` observer เท่านั้น เมธอดนี้จึง
  /// เป็น dead code ในทางปฏิบัติ *แต่ยังคุ้มค่าเก็บไว้*: ถ้าวันหนึ่งแอปเลิกใช้ scene
  /// เส้นทางนี้จะกลับมาทำงานได้เองทันทีโดยไม่ต้องแก้โค้ดเพิ่ม และเพราะการตั้ง
  /// `hasEverBecomeActive = true` เป็น idempotent การเรียกซ้ำกับ observer (ถ้าวัน
  /// หนึ่งทั้งสองเส้นทางทำงานพร้อมกันจริง) จึงไม่มีผลข้างเคียงใด ๆ
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
        // ตัวระบุ process เดียวกับที่เขียนลงคอลัมน์ที่ 2 ของทุกบรรทัด log —
        // ให้หน้าจอบอกได้ว่าบรรทัดที่เห็นมาจาก process ที่กำลังรันอยู่หรือไม่
        "processId": BackgroundEvidenceLog.processId,
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

    case "runEvidenceLogSelfTest":
      result(evidenceLogSelfTest())

    default:
      result(FlutterMethodNotImplemented)
    }
  }


  // MARK: - self-test ของเครื่องมือวัด

  /// **พิสูจน์ว่าเครื่องมือวัดทำงานได้ โดยไม่ต้องพึ่ง beacon เลย**
  ///
  /// คู่แฝดของ `MainActivity.evidenceLogSelfTest()` ฝั่ง Android — คืน key ชุด
  /// เดียวกันเป๊ะ เพื่อให้หน้าจอฝั่ง Dart ตัวเดียวแสดงผลได้ทั้งสองแพลตฟอร์ม
  ///
  /// เขียนหนึ่งบรรทัดผ่าน `BackgroundEvidenceLog.shared.append` **ตัวเดียวกับที่
  /// เส้นทางเบื้องหลังใช้** แล้วอ่านไฟล์กลับขึ้นมาจริง ๆ เทียบว่าลงดิสก์แล้ว
  ///
  /// **ทำไมต้องมี:** `append` ห้าม throw (ตอนถูกปลุกเบื้องหลังไม่มีใครดู error)
  /// มันจึงเก็บ error ไว้ใน `lastError` เงียบ ๆ ผลคือ "เขียนไฟล์ไม่ได้" กับ
  /// "ระบบไม่เคยส่ง event" **จบที่อาการเดียวกันเป๊ะ: ไฟล์ log ว่าง**
  ///
  /// **ทำไมต้องอ่าน `lastError` ก่อนเขียน:** `append` ที่สำเร็จจะตั้งค่ากลับเป็น
  /// `nil` — ถ้าอ่านหลังเขียนอย่างเดียว error ที่สะสมมาจากรอบเบื้องหลังจะถูกลบ
  /// ทิ้งพร้อมกับหลักฐานว่ามันเคยเกิด
  ///
  /// ⚠️ **ฝั่งนี้มีโหมดล้มเหลวที่ Android ไม่มี:** ถ้าเครื่องรีบูตแล้วยังไม่เคย
  /// ปลดล็อก ไฟล์ระดับ `completeUntilFirstUserAuthentication` จะอ่าน/เขียนไม่ได้
  /// — จะโผล่ที่ `errorAfterWrite`/`readError` ซึ่งเป็นผลที่**ถูกต้อง** ไม่ใช่บั๊ก
  private func evidenceLogSelfTest() -> [String: Any] {
    // ต้องอ่าน**ก่อน** append เสมอ — ดูเหตุผลข้างบน
    let errorBeforeWrite = BackgroundEvidenceLog.shared.lastError

    let line = BackgroundEvidenceLog.line(
      timestamp: Date(),
      event: "selftest",
      regionIdentifier: "-",
      conclusion: currentRunContext(),
      // receiverEntry = false — บรรทัดนี้เขียนจากปุ่มบน UI ไม่ใช่จาก callback
      // ของ CoreLocation การใส่ true จะเป็นการโกหกในไฟล์หลักฐาน
      rawSignals: rawSignalSummary(receiverEntry: false)
    )
    BackgroundEvidenceLog.shared.append(line: line)
    let errorAfterWrite = BackgroundEvidenceLog.shared.lastError

    var path = ""
    var readError: String?
    var lines: [String] = []
    do {
      path = try BackgroundEvidenceLog.prepareLogFile(named: BackgroundEvidenceLog.fileName)
      let contents = try String(contentsOfFile: path, encoding: .utf8)
      lines = contents.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    } catch {
      // อ่านไม่ได้เป็นคนละความล้มเหลวกับเขียนไม่ได้ — ต้องรายงานแยกกัน
      readError = error.localizedDescription
    }

    let fm = FileManager.default
    let exists = !path.isEmpty && fm.fileExists(atPath: path)
    let size = (try? fm.attributesOfItem(atPath: path)[.size] as? NSNumber)??.intValue ?? 0

    return [
      "path": path,
      "errorBeforeWrite": errorBeforeWrite ?? NSNull(),
      "writtenLine": line,
      "errorAfterWrite": errorAfterWrite ?? NSNull(),
      "fileExists": exists,
      "fileSizeBytes": size,
      "lineCount": lines.count,
      "readBackLine": lines.last ?? NSNull(),
      "readBackMatches": lines.last == line,
      "readError": readError ?? NSNull(),
    ]
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

  /// **สำหรับ XCTest เท่านั้น — ADR-16** อ่านค่า `hasEverBecomeActive` ปัจจุบันของ
  /// `AppDelegate` instance ที่กำลังรันอยู่จริงใน process นี้
  ///
  /// เหตุผลที่ต้องมีทางผ่านนี้: `RunnerTests` เป็น **hosted test bundle**
  /// (`TEST_HOST`/`BUNDLE_LOADER` ชี้ไปที่ `Runner.app` ใน `project.pbxproj`) จึง
  /// รันอยู่**ข้างในแอปจริงที่ launch เต็มรูปแบบ** บน simulator ไม่ใช่รันแยกเดี่ยว
  /// ๆ — นี่คือสภาพแวดล้อมเดียวที่ทำให้ตรวจสอบได้จริงว่า observer ของ
  /// `UIApplication.didBecomeActiveNotification` ที่ลงทะเบียนใน
  /// `didFinishLaunchingWithOptions` ทำงานหรือไม่ (ดู
  /// `testDidBecomeActiveObserverFiresOnRealAppLifecycle` ใน `RunnerTests.swift`)
  ///
  /// **ไม่ใช่การเปลี่ยน access level ของ `hasEverBecomeActive` เอง** — ตัวแปรยัง
  /// เป็น `private` เหมือนเดิมทุกประการ นี่เป็นทางผ่านเดียวที่เปิดให้
  /// `@testable import` อ่านค่าออกไปได้ ตามรูปแบบเดียวกับ
  /// `prepareLogFileForTesting`/`protectionOfLogFile` ด้านบน
  static var hasEverBecomeActiveForTesting: Bool {
    (UIApplication.shared.delegate as? AppDelegate)?.hasEverBecomeActive ?? false
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
