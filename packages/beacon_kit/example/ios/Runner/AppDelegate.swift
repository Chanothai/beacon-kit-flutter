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

  /// ค่าที่ใช้งานจริง ณ runtime — **instance property** (ไม่ใช่ `static let`) เพราะ
  /// จุดประกอบจริงของไฟล์นี้คือ `didFinishLaunchingWithOptions` ซึ่งเป็น **instance
  /// method** (`didFinishLaunchingWithOptions` ด้านล่าง) — แพทเทิร์นเดียวกับ
  /// `launchedByLocationKey`/`hasEverBecomeActive` ที่มีอยู่แล้วในไฟล์นี้ ตั้ง default
  /// เป็นค่าสินค้าไว้ก่อน แล้ว override อย่างชัดเจนตอน launch (ดูโค้ดใน
  /// `didFinishLaunchingWithOptions`) — สมมาตรกับ Android ที่ override ค่าจริงที่จุด
  /// ประกอบ (`ExampleProximityWatcher.install()`, ADR-25 §8.4)
  ///
  /// ⚠️ **ส่วนต่างจาก ADR-25 §8.4:** ตัวอย่างโค้ดของ ADR เขียน
  /// `= Self.productDefaultLongCooldownSeconds` แต่ตรวจจริงแล้ว **compile ไม่ผ่าน**
  /// (`error: covariant 'Self' type cannot be referenced from a stored property
  /// initializer`) เพราะ `AppDelegate` ไม่ใช่ `final class` — Swift ห้ามใช้ `Self`
  /// ใน initializer ของ stored property เพราะ subclass ที่ยังไม่มีตัวตน ณ จุดนั้น
  /// อาจ override ค่า static นี้ได้ในทางทฤษฎี ใช้ชื่อ type ตรง ๆ (`AppDelegate.`)
  /// แทน ซึ่งให้ผลเหมือนกันทุกประการเพราะไม่มี subclass จริงของ `AppDelegate`
  ///
  /// **`internal` ไม่ใช่ `private`** (เปิดหลังรอบตรวจ QA — พิสูจน์จากคอมไพเลอร์จริง
  /// ว่า `private var` เข้าถึงไม่ได้แม้ผ่าน `@testable import`: `error:
  /// 'longCooldownSeconds' is inaccessible due to 'private' protection level` —
  /// `private` ของ Swift จำกัดแค่ไฟล์เดียวกันเท่านั้น `@testable import` ยกระดับ
  /// แค่ `internal` เป็นสูงสุด ไม่ทะลุ `private`/`fileprivate`) — เปิด access ให้
  /// แคบที่สุดเท่าที่ §8.8 ต้องใช้เพื่อตรวจว่า `AppDelegate()` ใหม่มีค่าเริ่มต้นเป็น
  /// ค่าสินค้าจริง ไม่ใช่เปิดเป็น `public` (ยัง**ไม่มี** access modifier แปลว่า
  /// `internal` ตาม default ของ Swift — มองเห็นได้แค่ในโมดูลนี้ ข้ามโมดูลไม่ได้)
  /// — precedent เดียวกับที่ commit `6e3470d` เปิด `proximityCooldownKey(for:)`
  /// กับ `proximityLongNotificationCooldownSeconds` จาก `private` เป็น `internal`
  /// ด้วยเหตุผลเดียวกันเป๊ะ (ดู MARK header ของ `RunnerTests.swift`)
  var longCooldownSeconds: TimeInterval = AppDelegate.productDefaultLongCooldownSeconds

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
    // เอง ไม่ใช่ผูกกับ observer token ที่เราทิ้งไว้โดยไม่เก็บ reference คืน — นี่คือ
    // สิ่งที่ทำให้ "ทิ้ง token ได้โดยไม่กลายเป็น no-op" ทั้ง fix นี้แขวนอยู่ ยืนยัน
    // จากเอกสาร Apple ของหน้าเดียวกับที่คอมเมนต์ `queue: nil` ด้านล่างอ้างอิง
    // (`NotificationCenter.addObserver(forName:object:queue:using:)`) สองจุด:
    //
    // ส่วน **Return Value** ของหน้านั้น: "An opaque object to act as the
    // observer. Notification center strongly holds this return value until
    // you remove the observer registration." — คือ token ที่เราทิ้งไป (ไม่เก็บ
    // reference คืน)
    //
    // ส่วนพารามิเตอร์ **block**: "The notification center copies the block.
    // The notification center strongly holds the copied block until you
    // remove the observer registration." — คือ closure นี้เอง ซึ่งเป็นคนละ
    // object กับ token ข้างบน
    //
    // รวมสองประโยคนี้: notification center ถือทั้ง**block ที่ copy ไว้เอง**
    // (strong) จนกว่าจะ `removeObserver` ไม่ใช่ถือผ่าน token ที่เราคืนค่ามา — การ
    // ไม่เก็บ token ไว้จึงไม่ทำให้ observer ถูกปล่อยทิ้งหรือกลายเป็น no-op ตราบใด
    // ที่ยังไม่มีใครเรียก `removeObserver` (ดูเหตุผลข้อถัดไปว่าทำไมไม่ต้องเรียก)
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
    // ⚠️ ค่าทดสอบ 30 นาที ไม่ใช่ค่าสินค้า (ค่าสินค้า = 24 ชั่วโมง,
    // `productDefaultLongCooldownSeconds`, ADR-25 §8.1) — override สั้นลงเพื่อให้เห็น
    // ใบที่สองระหว่างรอบทดสอบภาคสนามได้จริงโดยไม่ต้องรอทั้งวัน (เหตุผลเต็มที่ §8.1)
    // ต้องตั้งค่านี้ **ก่อน** `startBackgroundRegionMonitoring` ด้านล่าง เพื่อให้ค่า
    // พร้อมก่อนมี event ใดเข้ามาถึง `longCooldownBlockedSinceMs`
    longCooldownSeconds = Self.testingLongCooldownSeconds

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

    // **ชั้นที่ 2 (ADR-21) — ต่อจากของเดิม ไม่แตะตรรกะข้างบนเลยแม้แต่บรรทัดเดียว**
    //
    // ตั้งที่นี่ด้วยเหตุผลเดียวกับที่ชั้น 1 ตั้ง hook ที่นี่: นี่คือจุดเดียวที่
    // ทำงานเสมอไม่ว่า process จะเกิดด้วยเหตุใด (ผู้ใช้เปิดเอง / iOS ปลุกขึ้นมา
    // เบื้องหลัง) และจบก่อนที่ CoreLocation จะเรียก delegate ได้เสมอ — SDK ไม่มี
    // คิว event ให้ (ADR-21 หัวข้อ 6) ถ้าตั้ง observer ช้ากว่านี้ event จะหายจริง ๆ
    BackgroundProximityMonitor.setProximityObserver { [weak self] event in
      self?.recordProximityEvent(event)
    }

    // นับ `didFailRangingFor` ให้เห็นเป็นบรรทัดจริง — **ห้ามอนุมานจากการไม่มีบรรทัด**
    // (รอบเดินจริง 10 ก.ย. 2026 ได้ 0 บรรทัด ซึ่งเป็น**ผลลัพธ์** ไม่ใช่ความว่างเปล่า:
    // พิสูจน์ว่า `didFailRangingFor` ไม่ใช่สัญญาณว่าบีคอนหาย — ADR-21 หัวข้อ 8)
    BackgroundProximityMonitor.setRangingFailureObserver { [weak self] regionIdentifier in
      self?.recordRangingFailure(regionIdentifier: regionIdentifier)
    }

    // ชีพจรของ ranging (ADR-21 หัวข้อ 9 "ของเพิ่ม") — บรรทัด `rangetick` อย่างมากทุก
    // 30 วินาทีต่อ process **ไม่ยิง notification** ถ้าไม่ต้องการแล้วลบทั้งบล็อกนี้ได้
    BackgroundProximityMonitor.setRangeTickObserver { [weak self] event in
      self?.recordRangeTick(event)
    }

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
  /// git short SHA ของซอร์สที่ build บิลด์นี้ — ประทับลง `Info.plist` ตอน build
  /// ด้วย build phase "Stamp git SHA" (`Runner.xcodeproj`)
  ///
  /// ## ทำไมไฟล์หลักฐานต้องบอกเองว่ามาจากบิลด์ไหน
  ///
  /// รอบทดสอบฝั่ง Android เมื่อ 9 ก.ย. 2026 เสียเวลาไปทั้งช่วงเพราะ **แฮชของ APK
  /// ที่ติดตั้งอยู่บนเครื่องไม่ตรงกับบิลด์ใดที่สร้างในเซสชันนั้นเลย** ต้องไล่ย้อนจาก
  /// เนื้อ log ("มีบรรทัด `event=notification` ไหม") เพื่ออนุมานว่าเป็นบิลด์หลังคอมมิต
  /// ไหน — เป็นการอนุมาน ไม่ใช่หลักฐาน
  ///
  /// บรรทัด `launch` เป็นที่ที่ถูกต้องเพราะเขียนทุกครั้งที่ process เกิด และค่านี้คงที่
  /// ตลอดอายุ process (เหตุผลเดียวกับที่ฝั่ง Android วาง `model`/`os` ไว้ที่บรรทัดนี้
  /// บรรทัดเดียว ไม่ใช่ทุกบรรทัด)
  ///
  /// `unknown` = build จากที่ที่ไม่มี git · **`-dirty` ต่อท้าย = ตอน build มีไฟล์ที่ยัง
  /// ไม่ commit ห้ามอ้างผลรอบนั้นว่าตรงกับคอมมิตใด**
  ///
  /// ⚠️ **ฝั่ง Android ยังไม่มีฟิลด์นี้** — เป็นหนี้ที่ต้องใช้คืน ไม่ใช่ความตั้งใจให้ต่างกัน
  static let gitShortSHA: String =
    (Bundle.main.object(forInfoDictionaryKey: "GitShortSHA") as? String) ?? "unknown"

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
          + "monitoredRegions=[\(restoredRegionIdentifiers.joined(separator: ","))] "
          + "build=\(Self.gitShortSHA)"
          // `rangeCb=0` เป็น **ข้อเท็จจริงเชิงโครงสร้าง ไม่ใช่ค่าที่อ่านมา**: บรรทัดนี้
          // เขียนใน `didFinishLaunchingWithOptions` ซึ่งจบก่อน CoreLocation จะเรียก
          // `didRange` ได้เสมอ — มีไว้เป็น **เส้นฐานของ process** ให้บรรทัด
          // `rangetick`/`proximity` ที่ตามมาถูกอ่านเป็น "เพิ่มจาก 0" ได้โดยไม่ต้องเดา
          // และเป็นตัวบอกว่าบิลด์นี้มีคอลัมน์ตัวนับแล้ว (ต่างจาก log รุ่นก่อน 10 ก.ย.)
          //
          // `inArray`/`unknown` เป็น `n/a` เพราะบรรทัด launch **ไม่ได้พูดถึง key ใด**
          // — `n/a` ไม่ใช่ค่าว่าง: อ่านออกได้ว่า "ตอบไม่ได้ที่บรรทัดนี้"
          + Self.rangeCounterSuffix(rangeCb: 0, inArray: nil, unknown: nil)
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
    if Self.layer1NotificationsEnabled {
      postNotification(  // เนื้อหาเดิมทุกบรรทัด ไม่แก้
        title: "Region \(event.state): \(event.regionIdentifier)",
        body: "สถานะแอป: \(currentRunContext())"
      )
    } else {
      recordRegionNotificationDisabled(event)
    }
  }

  /// เปิด/ปิด notification ชั้นที่ 1 (enter/exit) — ปิดโดย default (ADR-25 §9) —
  /// บรรทัดหลักฐาน `event=notification` ยังเขียนเสมอไม่ว่าค่านี้จะเป็นอะไร
  ///
  /// **`internal` ไม่ใช่ `private`** (เปิดหลังรอบตรวจ QA ยืนยันจากคอมไพเลอร์จริงว่า
  /// `private static let` เข้าถึงไม่ได้แม้ผ่าน `@testable import` — `private`
  /// จำกัดแค่ไฟล์เดียวกัน ส่วน `@testable import` ยกระดับได้สูงสุดแค่ `internal`)
  /// เปิด access ให้แคบที่สุดเท่าที่ §9.7 ต้องใช้เพื่อตรวจว่าค่าเริ่มต้นคือปิดจริง
  /// ไม่ใช่เปิดเป็น `public`/API สาธารณะของแอป — ไม่ระบุ access modifier แปลว่า
  /// `internal` ตาม default ของ Swift (มองเห็นได้แค่ในโมดูลนี้ ข้ามโมดูลไม่ได้) —
  /// precedent เดียวกับที่ commit `6e3470d` เปิด `proximityCooldownKey(for:)` กับ
  /// `proximityLongNotificationCooldownSeconds` จาก `private` เป็น `internal`
  /// ด้วยเหตุผลเดียวกันเป๊ะ (ดู MARK header ของ `RunnerTests.swift`)
  static let layer1NotificationsEnabled: Bool = false

  /// เขียนบรรทัดหลักฐานตอน notification ชั้นที่ 1 ถูกปิดไว้ (ADR-25 §9) — **ต้องเขียน
  /// เสมอ ห้ามเงียบหาย** (ADR-20 §12.2/§12.5.3) ใช้ `event.regionIdentifier` จริง
  /// ไม่ใช่ `"-"` แบบที่ [postNotification] เขียนตอนล้มเหลว เพราะที่นี่รู้ region แน่นอน
  private func recordRegionNotificationDisabled(_ event: BeaconKitRegionStateEvent) {
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: event.timestamp,
        event: "notification",
        regionIdentifier: event.regionIdentifier,
        conclusion: currentRunContext(),
        rawSignals: rawSignalSummary(receiverEntry: true)
          + " posted=false reason=disabled"
      )
    )
  }

  // MARK: - หลักฐานของชั้นที่ 2 (proximity — ADR-21)

  /// เว้นช่วง notification ต่อหนึ่งบีคอนอย่างน้อย 60 วินาที
  ///
  /// **เป็นค่าสำหรับ demo ล้วน ๆ ไม่ใช่ค่าที่ calibrate อะไร** — และเป็น**บทเรียน
  /// ตรง ๆ จากรอบทดสอบ Android 9 ก.ย. 2026 ที่ผู้ทดสอบได้ notification 13 ใบใน 15
  /// นาทีทั้งที่ยืนอยู่กับที่** (bucket แกว่ง near ⇄ immediate เพราะขอบนั้นไม่มี
  /// hysteresis ตาม ADR-19 หัวข้อ 6(ข) — ADR-21 หัวข้อ 7 ข้อ 3 สั่งไว้ว่า iOS ต้อง
  /// ไม่ทำซ้ำ)
  private static let proximityNotificationCooldownMillis: Int64 = 60_000

  /// suite แยกของ cooldown — **ต้องรอดข้าม process** (ดู [consumeProximityCooldown])
  private static let proximityCooldownSuiteName = "beacon_kit_example.proximity_cooldown"

  /// คูลดาวน์ **ที่สอง** ต่อ key ซ้อนอยู่**เหนือ** [proximityNotificationCooldownMillis]
  /// เดิม (ไม่ได้แทนที่) เก็บลง suite คนละไฟล์โดยตั้งใจ — ตอบปัญหาของ §12.6.1
  /// (ADR-25 §2): state ที่ถูกล้างทำให้ transition แรกดูเหมือนเดินข้ามขอบใหม่
  ///
  /// ค่าเริ่มต้นของสินค้า (product default) — 24 ชั่วโมง (ADR-25 §8.1) — ค่านี้ไม่ใช่
  /// SDK default เช่นเดียวกับฝั่ง Android เพราะ `beacon_kit_ios` ไม่มีแนวคิดคูลดาวน์นี้
  /// เลย — **แหล่งความจริงเดียวของค่าสินค้า** (`static let` เพราะเป็นค่าคงที่ระดับ
  /// สินค้า ไม่ใช่ค่าที่ override ได้ต่อ instance)
  static let productDefaultLongCooldownSeconds: TimeInterval = 24 * 60 * 60  // 86,400

  /// ค่า literal ที่ตั้งใจ override ค่าเริ่มต้นของสินค้าเพื่อการทดสอบเท่านั้น (ADR-25
  /// §8.1) — คงเป็น `static let` (ไม่ใช่ instance) เพราะเป็นแค่**ค่าคงที่ที่ทั้งจุด
  /// ประกอบและไฟล์เทสต้องอ้างอิงถึงได้โดยไม่ต้องมี `AppDelegate` instance** — เทียบเท่า
  /// `TESTING_LONG_COOLDOWN_MILLIS` ที่ฝั่ง Android เก็บไว้ใน `ExampleApplication.kt`
  /// ตัวมันเองไม่ใช่ค่าที่ใช้งานจริง — ต้อง override เข้า [longCooldownSeconds]
  /// ที่จุดประกอบก่อนถึงจะมีผล (ดู `didFinishLaunchingWithOptions`)
  ///
  /// **`internal` ไม่ใช่ `private`** (แก้ตามรอบรีวิว QA) — เพื่อให้ `RunnerTests`
  /// อ้างอิงค่าจริงนี้ตรง ๆ ผ่าน `@testable import Runner` ได้ ไม่ต้อง hardcode
  /// `30 * 60` ซ้ำในไฟล์เทส (ถ้าวันหนึ่งมีคนแก้ค่านี้ เทสที่ hardcode ไว้จะยังเขียว
  /// ทั้งที่ทดสอบคนละค่า) — เท่ากับที่ฝั่ง Android เปิด `TESTING_LONG_COOLDOWN_MILLIS`
  /// ไว้แล้ว
  static let testingLongCooldownSeconds: TimeInterval = 30 * 60

  /// suite ใหม่ของคูลดาวน์ 30 นาที — ชื่อนี้เลือกให้สมมาตรกับชื่อไฟล์ Android
  /// (`notification_cooldown_v1`) ไม่ใช่ข้อบังคับจากที่ไหน (ADR-25 §4 — เดิมชื่อ
  /// `notification_cooldown_v1`)
  ///
  /// ⚠️ **ขยับเป็น `_v2` (ADR-25 §4.3.3, เพิ่ม 17 ก.ย. 2026)** — ค่าที่เก็บอยู่เดิม
  /// ใน `_v1` เป็น `TimeInterval` แทน **วินาทีนับจาก boot** (`systemUptime`) ส่วน
  /// ค่าใหม่หลัง §4.3 เป็น **วินาทีนับจาก epoch 1970** (`Date().timeIntervalSince1970`)
  /// — หน่วยเดียวกัน (วินาที) แต่ฐานคนละอันโดยสิ้นเชิง เทียบกันตรง ๆ ไม่ได้ ถ้าไม่
  /// เปลี่ยนชื่อ suite เครื่องที่เคยติดตั้งเวอร์ชันก่อนหน้าจะมีค่า `systemUptime`
  /// เก่าค้างอยู่ในคีย์เดิม โค้ดใหม่จะอ่านมันเป็น epoch seconds ตรง ๆ (เช่น 45,000
  /// วินาทีหลัง epoch 1970 = ประมาณเที่ยงคืนวันที่ 2 ม.ค. 1970) ซึ่งเทียบกับ
  /// `nowEpochSeconds` ปี 2026 (~1.77×10⁹) แล้ว `lastPostedEpochSecondsOrZero >
  /// nowEpochSeconds` เป็นเท็จเสมอ ไหลไปคำนวณ `sinceSeconds ≈ nowEpochSeconds` ซึ่ง
  /// มากกว่า 1800 วินาทีมหาศาล → ฟังก์ชันคืน `nil` เสมอ = คูลดาวน์มองว่า "ไม่เคยติด"
  /// ทันทีหลังอัปเกรด ผลจริงคือ **ได้ notification เกินมาหนึ่งใบต่อบีคอนตอนอัปเกรด
  /// ครั้งเดียว** (ความเสี่ยงระดับเดียวกับที่ §4.2 เคยยอมรับไว้กับกรณี key เปลี่ยน
  /// รูปร่าง ไม่ใช่บั๊กร้ายแรง) แต่ยังต้องเปลี่ยนชื่อ suite อยู่ดี เพราะการพึ่งว่า
  /// "uptime เป็นเลขน้อยกว่า epoch เสมอ" เป็นข้อเท็จจริงเชิงตัวเลข ณ ตอนนี้ ไม่ใช่
  /// สัญญาที่โค้ดบังคับไว้ และการแยก suite ต่อ "ฐานเวลาที่เข้ากันไม่ได้" เป็น
  /// แพทเทิร์นเดียวกับที่ ADR นี้ใช้อยู่แล้วตอนแยกคูลดาวน์ 30 นาทีออกจากคูลดาวน์
  /// 60 วินาทีตั้งแต่ §2
  private static let proximityLongCooldownSuiteName = "beacon_kit_example.notification_cooldown_v2"

  /// เขียน log + ยิง notification ของ transition ชั้นที่ 2 จาก **โค้ด native ล้วน**
  ///
  /// เหตุผลเดียวกับ [recordRegionEvent] เป๊ะ: เส้นทางที่ ADR-21 มีอยู่เพื่อรองรับ
  /// คือช่วงที่ Flutter engine อาจยังไม่มีตัวตน — ถ้าเขียน log ฝั่ง Dart เครื่องมือ
  /// วัดจะตายพร้อมกับสิ่งที่มันควรวัด
  ///
  /// **ลำดับที่ห้ามสลับ: log ก่อน notification เสมอ** และ **cooldown มีผลกับ
  /// notification เท่านั้น บรรทัด log เขียนทุก transition** ไม่งั้นหลักฐานจะหายไป
  /// พร้อมกับการกันสแปม ซึ่งกลับหัวกลับหางกับเหตุผลข้างบน — บรรทัด `farther`/`stale`
  /// คือสิ่งเดียวที่ตอบได้ว่า `staleAfter = 10 วินาที` (ADR-19 หัวข้อ 8) ใช้ได้จริง
  /// กับอัตราการยิงของ `didRange` บน iOS หรือไม่ ซึ่งเป็นคำถามเปิดข้อใหญ่ที่สุดของ
  /// ADR-21 หัวข้อ 4
  /// เขียนบรรทัด `rangefail` ทุกครั้งที่ `didFailRangingFor` ยิง
  ///
  /// **ไม่ใช่การรายงาน error** — เป็นการ**นับความเงียบให้เป็นตัวเลข** เพื่อตอบคำถามเปิด
  /// ข้อใหญ่ที่สุดของ ADR-21 หัวข้อ 4: `didFailRangingFor` ยิงจริงไหม ยิงถี่แค่ไหน และ
  /// พึ่งเป็นจุด sweep ที่สองได้หรือไม่ (`apple_proximity_ranging.md` หัวข้อ 8 บันทึกว่า
  /// **เอกสาร Apple ไม่ระบุ** ว่ามันยิงซ้ำเป็นจังหวะหรือครั้งเดียว)
  ///
  /// ถ้าไม่มีบรรทัดนี้ ไฟล์หลักฐานจะแยกไม่ออกระหว่าง "callback ไม่เคยยิงเลย" กับ "ยิงแต่
  /// ไม่มีอะไรให้รายงาน" — ซึ่งเป็นความกำกวมชนิดเดียวกับที่ทำให้รอบสอบสวนฝั่ง Android
  /// (`android_background_scanning.md` ข้อ B) ตอบคำถามไม่ได้ทั้งรอบ
  ///
  /// **ไม่ยิง notification** — นี่เป็นข้อมูลของผู้ทดสอบ ไม่ใช่เหตุการณ์ที่ผู้ใช้ต้องรู้
  private func recordRangingFailure(regionIdentifier: String) {
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: Date(),
        event: "rangefail",
        regionIdentifier: regionIdentifier,
        conclusion: currentRunContext(),
        rawSignals: rawSignalSummary(receiverEntry: true)
      )
    )
  }

  private func recordProximityEvent(_ event: BeaconKitProximityChangedEvent) {
    // 1) หลักฐานก่อน — **schema 6 คอลัมน์เดิมทุกประการ ไม่เพิ่ม/ลด/สลับคอลัมน์**
    //    ข้อมูลใหม่ของ ADR-21 ทั้งหมดต่อท้ายอยู่ใน**คอลัมน์สัญญาณดิบ**เท่านั้น
    //    (ตัวอ่านที่มีอยู่ — หน้า "ดู log" ฝั่ง Dart และ `tool/analyze_region_log.dart`
    //    — จึงไม่พัง)
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: event.timestamp,
        event: "proximity",
        regionIdentifier: event.regionIdentifier,
        conclusion: currentRunContext(),
        // receiverEntry = true เป็น **ข้อเท็จจริงของเส้นทางเรียก ไม่ใช่การเดา**:
        // `BackgroundProximityMonitor.emit` ถูกเรียกจาก
        // `IBeaconRangingManager.runProximityLayer` ที่เดียว และเมธอดนั้นมีผู้เรียก
        // แค่สองตัวคือ `didRange` กับ `didFailRangingFor` ซึ่งเป็น
        // `CLLocationManagerDelegate` ที่ระบบเรียกเข้ามาทั้งคู่
        rawSignals: rawSignalSummary(receiverEntry: true)
          + Self.proximityRawSignalsSuffix(event)
      )
    )

    // 2) notification เฉพาะ transition ที่ยืนยันว่า "ใกล้" — **ตัวกรองอยู่ที่แอป
    //    ไม่ใช่ที่ SDK** (ADR-21 หัวข้อ 6 · ADR-11 หัวข้อ 7 เรื่องตำแหน่งของ
    //    debounce) ผู้ทดสอบไม่ควรถูกเด้งตอนเดินออกห่าง เพราะจะกลบสัญญาณที่กำลังจะ
    //    พิสูจน์
    guard event.to == .near || event.to == .immediate else { return }

    // 3) **ยิงเฉพาะตอน "เข้าสู่ความใกล้" เท่านั้น ไม่ใช่ทุกการขยับภายในความใกล้**
    //
    //    ขอบ `immediate`/`near` ไม่มี dead zone อะไรคั่นเลยบนเส้นทางนี้ (มีแค่ mode
    //    ของหน้าต่าง + dwell) — ผู้ที่ยืนนิ่งอยู่ราวหนึ่งเมตรจึงทำให้ candidate
    //    สลับไป-กลับได้เรื่อย ๆ และ **ทั้งสองทิศผ่านตัวกรองข้อ 2 ได้หมด** นี่คือ
    //    ช่องว่างของ ADR-19 หัวข้อ 6(ข) เอง (ใส่ hysteresis ไว้เฉพาะขอบ far/close)
    //    ซึ่ง **ห้ามแก้ที่ `ProximityGate` ฝั่ง Swift ฝ่ายเดียวเด็ดขาด** เพราะจะ
    //    drift จาก reference implementation ทันที (ADR-21 หัวข้อ 2/7 ข้อ 3) —
    //    รอบนี้จึงกันที่ชั้นนโยบายของแอปแทน เหมือนที่ ADR-20 ทำฝั่ง Android
    //
    //    **บรรทัดหลักฐานยังเขียนครบทุก flap** (ข้อ 1) ตัวเลข "สลับ near↔immediate
    //    กี่ครั้ง" ที่ ADR-21 หัวข้อ 7 ข้อ 3 สั่งให้เก็บจึงไม่หายไปไหน
    guard event.from == nil || event.from == .far else { return }

    // 3.5) คูลดาวน์ 30 นาทีที่สอง (ADR-25 §2/§4/§4.1/§4.3) — เช็ค**ก่อน**คูลดาวน์เดิม
    //    60 วินาทีเพราะนี่คือตัวที่ตอบปัญหาของ §12.6 จริง ๆ ใช้ [proximityCooldownKey]
    //    เดิมซ้ำ (key ของคูลดาวน์เดิมตรงกับ key ของ `ProximityGate` อยู่แล้ว)
    //
    //    **wall clock ไม่ใช่ `systemUptime` (ADR-25 §4.3)** — อ่านนาฬิกาครั้งเดียว
    //    ตอนต้นแล้วใช้ซ้ำทั้งตอนตรวจ (`longCooldownBlockedSinceMs`) และตอนจด
    //    (`recordLongCooldownPosted` ใน closure `onDelivered` ด้านล่าง) ห้ามอ่านซ้ำ
    //    ใน closure (หลักการเดิมของ §3.1/§4.1)
    let longKey = Self.proximityCooldownKey(for: event)
    let nowEpochSeconds = Date().timeIntervalSince1970
    if let sinceLastPostedMs = longCooldownBlockedSinceMs(key: longKey, nowEpochSeconds: nowEpochSeconds) {
      recordNotificationSuppressed(event, sinceLastPostedMs: sinceLastPostedMs)
      return
    }

    // 4) แล้วค่อย notification (ถ้าไม่ติด cooldown)
    //
    //    **cooldown เป็นระดับ key (บีคอนหนึ่งตัวในหนึ่ง region) 60 วินาที** เท่ากับ
    //    ฝั่ง Android เป๊ะ และ**รอดข้าม process** — จำเป็นบนเส้นทาง ADR-22 เพราะ
    //    โปรเซสที่ถูกปลุกเกิด/ตายได้หลายรอบในนาทีเดียว cooldown ที่อยู่ใน memory
    //    อย่างเดียวจะไม่กันอะไรเลย
    guard consumeProximityCooldown(key: Self.proximityCooldownKey(for: event), nowMillis: event.timestampMillis)
    else { return }

    // 5) **เขียนบรรทัด `notification` ก่อนยิงเสมอ** (ADR-20 หัวข้อ 7 / บทเรียนจาก
    //    รอบ MIUI 9 ก.ย. 2026) — ถ้าไม่มีบรรทัดนี้ "ระบบบล็อก notification" กับ
    //    "เงื่อนไขไม่เคยเข้า" จะจบที่อาการเดียวกันเป๊ะ: ไม่มีอะไรเด้ง · ฝั่ง iOS
    //    เพิ่งมีในรอบ ADR-22 เพราะข้อ 19.7 ของไฟล์สถานะต้องการหลักฐานตรงจุดนี้พอดี
    recordNotificationEvent(event)

    postNotification(
      title: "ใกล้ \(event.regionIdentifier) (\(event.to?.wireName ?? "n/a"))",
      body: "reason=\(event.reason.wireName) · beacon=\(event.beacon) · "
        + "mode=\(event.mode.rawValue) · procUuid=\(BackgroundEvidenceLog.processId)",
      onDelivered: { [weak self] in
        // จดเวลาคูลดาวน์ 30 นาทีเฉพาะตอนรู้ผลว่าไม่มี error เท่านั้น (ADR-25 §4.1)
        // ใช้ `nowEpochSeconds` ที่อ่านไว้ตอนต้นซ้ำ ไม่อ่านนาฬิกาใหม่ในนี้ (§4.3.2)
        self?.recordLongCooldownPosted(key: longKey, atEpochSeconds: nowEpochSeconds)
      }
    )
  }

  /// เขียนบรรทัดหลักฐานตอนติดคูลดาวน์ 30 นาที — **คอลัมน์ระบุบีคอนต้องตรงกับ
  /// เส้นทางสำเร็จ** ([recordNotificationEvent]) ไม่ใช่แค่ `posted=false
  /// reason=cooldown` ล้วน ๆ (แก้ตามรอบรีวิว 16 ก.ย. 2026) — ถ้าไม่มี `beacon=`
  /// บรรทัด `reason=cooldown` หลายบรรทัดติดกันของคนละบีคอนจะอ่านเหมือนบั๊กยิงซ้ำ
  /// เดียวกับที่ kdoc ของ [proximityRawSignalsSuffix] เตือนไว้ว่าเกิดจริงมาแล้ว
  /// (ADR-21 หัวข้อ 7 ข้อ 1) — ใช้ [notificationColumns] ตัวเดียวกับ
  /// [recordNotificationEvent] แทนการประกอบคอลัมน์ใหม่เอง ต่อท้ายด้วย
  /// `posted=false reason=cooldown sinceLastPostedMs=<n>` เหมือนเดิม (ADR-25 §4)
  private func recordNotificationSuppressed(
    _ event: BeaconKitProximityChangedEvent,
    sinceLastPostedMs: Int64
  ) {
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: event.timestamp,
        event: "notification",
        regionIdentifier: event.regionIdentifier,
        conclusion: currentRunContext(),
        rawSignals: rawSignalSummary(receiverEntry: true)
          + Self.notificationColumns(event)
          + " posted=false reason=cooldown sinceLastPostedMs=\(sinceLastPostedMs)"
      )
    )
  }

  /// บรรทัด `event=notification` — หลักฐานว่า**เงื่อนไขยิงเข้าเกิดขึ้นจริงเมื่อไร**
  ///
  /// ⚠️ **`posted=requested` ไม่ใช่ `posted=true`** และความต่างนี้สำคัญ: ฝั่ง iOS
  /// ถามสถานะสิทธิ์แบบ synchronous ไม่ได้ (`getNotificationSettings` เป็น async
  /// และโปรเซสที่ถูกปลุกอาจถูก suspend ก่อน callback มาถึง) — บรรทัดนี้จึงยืนยันได้
  /// แค่ว่า **แอปสั่งยิงแล้ว** ไม่ได้ยืนยันว่าผู้ใช้เห็น ต่างจากฝั่ง Android ที่
  /// `deliveryReason()` ตอบได้ทันทีก่อนยิง (`ExampleNotifications.kt`)
  ///
  /// ถ้า `UNUserNotificationCenter.add` คืน error กลับมา จะมีบรรทัดที่สอง
  /// `posted=false` ตามมา — **สองบรรทัด ไม่ใช่บรรทัดเดียวที่แก้ทีหลัง** เพราะไฟล์
  /// หลักฐานเป็น append-only และการมีบรรทัดแรกค้างไว้คือสิ่งที่พิสูจน์ว่าโปรเซสไป
  /// ถึงจุดนั้นจริงแม้จะถูกฆ่าต่อจากนั้น
  private func recordNotificationEvent(_ event: BeaconKitProximityChangedEvent) {
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: event.timestamp,
        event: "notification",
        regionIdentifier: event.regionIdentifier,
        conclusion: currentRunContext(),
        rawSignals: rawSignalSummary(receiverEntry: true)
          + Self.notificationColumns(event)
          + " posted=requested"
      )
    )
  }

  /// คอลัมน์ระบุบีคอนของบรรทัด `event=notification` — **แยกเป็น helper กลาง
  /// เพื่อให้ [recordNotificationEvent] (เส้นทางสำเร็จ) กับ
  /// [recordNotificationSuppressed] (เส้นทางติดคูลดาวน์) พิมพ์คอลัมน์เดียวกัน
  /// เป๊ะเสมอ** — กันไม่ให้สองเส้นทางค่อย ๆ drift กันในอนาคต (แก้ตามรอบรีวิว
  /// 16 ก.ย. 2026 ที่พบว่าบรรทัด `reason=cooldown` เดิมไม่มี `beacon=` เลย ทำให้
  /// พิสูจน์เกณฑ์รับงานแบบรายบีคอนของ §12.6 จากไฟล์ตรง ๆ ไม่ได้)
  ///
  /// รูปร่างเดียวกับที่ [recordNotificationEvent] เขียนมาแต่แรก:
  /// `bucket=<near|immediate|far|n/a> from=<bucket|none> beacon=<major>/<minor>
  /// mode=<fg|bg>` — **ไม่ใช้ [proximityRawSignalsSuffix]** เพราะฟังก์ชันนั้นมี
  /// `reason=`/`store=`/ตัวนับ range ที่เป็นคอลัมน์ของบรรทัด `event=proximity`
  /// เท่านั้น ไม่ใช่ของบรรทัด `event=notification`
  private static func notificationColumns(_ event: BeaconKitProximityChangedEvent) -> String {
    return " bucket=\(event.to?.wireName ?? "n/a")"
      + " from=\(event.from?.wireName ?? "none")"
      + " beacon=\(event.beacon)"
      + " mode=\(event.mode.rawValue)"
  }

  /// ส่วนต่อท้ายของคอลัมน์สัญญาณดิบสำหรับบรรทัด `event=proximity` — **pure function**
  /// จึงมี XCTest คลุมได้จริงโดยไม่ต้องมีอุปกรณ์ (เหตุผลเดียวกับ
  /// `BackgroundEvidenceLog.line`)
  ///
  /// ```
  ///  bucket=near from=none reason=closer beacon=1/42 store=ok mode=bg
  /// ```
  ///
  /// รูปแบบเดียวกับฝั่ง Android: ขึ้นต้นด้วยช่องว่าง และทุกค่าที่ไม่มีเขียนเป็น
  /// `n/a` **ห้ามปล่อยว่างและห้ามมีช่องว่างในค่า** เพราะคอลัมน์สัญญาณดิบคั่นค่าด้วย
  /// ช่องว่าง ถ้าค่าใดว่างหรือมีช่องว่างปน ตัวอ่านจะเห็นเป็นคนละ key โดยไม่มีอะไรฟ้อง
  ///
  /// - `from=none` (ไม่ใช่ `n/a`) เมื่อไม่เคยมี bucket ที่ยืนยันมาก่อน — คนละความ
  ///   หมายกัน: `none` = "ยืนยัน bucket แรกของบีคอนตัวนี้" ซึ่งเป็นข้อเท็จจริงที่รู้
  ///   แน่ ส่วน `n/a` = "ตอบไม่ได้"
  /// - `beacon=<major>/<minor>` — **ต้องมีตั้งแต่คอมมิตแรกตาม ADR-21 หัวข้อ 7 ข้อ 1**
  ///   ไม่งั้น `stale` หลายบรรทัดติดกันของคนละบีคอนจะอ่านเหมือนบั๊กยิงซ้ำ (เกิดจริง
  ///   รอบ Android 9 ก.ย. 2026)
  /// - `store=ok|<error>` — **ต้องมีตั้งแต่คอมมิตแรกตาม ADR-21 หัวข้อ 7 ข้อ 2**
  ///   `ok` ไม่ใช่ค่าว่าง: ต้องอ่านออกได้ว่า "ถามแล้วและไม่มี error" ต่างจาก "ไม่มี
  ///   คอลัมน์นี้เพราะเป็น log รุ่นเก่า"
  /// - `mode=fg|bg` — **ADR-22** gate ตัวไหนเป็นคนตัดสิน · ขาดไม่ได้เพราะสอง gate
  ///   มีค่า `dwellSamples`/`staleAfterMillis` คนละชุด ถ้าไม่มีคอลัมน์นี้ "dwell ครบ
  ///   เร็วผิดปกติ" กับ "ไม่มี `stale` เลยทั้งช่วง" จะอ่านเป็นบั๊กทั้งคู่
  static func proximityRawSignalsSuffix(_ event: BeaconKitProximityChangedEvent) -> String {
    var parts = ""
    parts += " bucket=\(event.to?.wireName ?? "n/a")"
    parts += " from=\(event.from?.wireName ?? "none")"
    parts += " reason=\(event.reason.wireName)"
    parts += " beacon=\(event.beacon)"
    parts += " store=\(event.storeError?.replacingOccurrences(of: " ", with: "_") ?? "ok")"
    parts += " mode=\(event.mode.rawValue)"
    parts += Self.rangeCounterSuffix(
      rangeCb: event.rangeCallbackCount,
      inArray: event.inArrayCount,
      unknown: event.unknownCount
    )
    return parts
  }

  /// ตัวนับ 3 ตัวของ **ADR-21 หัวข้อ 9** ในรูปคอลัมน์สัญญาณดิบ — **pure function**
  ///
  /// ```
  ///  rangeCb=41 inArray=12 unknown=3
  /// ```
  ///
  /// **ทั้งสามตัวต้องอยู่ด้วยกันและห้ามรวมเป็นตัวเดียว** เพราะบน iOS "ไม่มี sample"
  /// มีสองความหมายที่แก้คนละทางเลย:
  /// - `rangeCb` ไม่ขยับ = **ranging ไม่เดิน** (process ถูก suspend / ไม่มีใครเรียก
  ///   `startRangingBeacons` ในรอบที่ถูกปลุก) → แก้ที่ lifecycle
  /// - `rangeCb` ขยับถี่ ~1 Hz แต่ `inArray` ห่าง = **CoreLocation ถอดบีคอนออกจาก
  ///   array เอง** → `stale` 33% ของรอบ 10 ก.ย. คือพฤติกรรมของ OS ไม่ใช่การขาด callback
  /// - `unknown` สูง = คำตอบอยู่ที่กฎ "`unknown` ไม่ต่ออายุ `lastSampleAt`"
  ///   (ADR-19 6(ง)) **ไม่ใช่ที่ตัวเลข `staleAfter`** — ข้อนี้สำคัญกว่าการไปปรับ
  ///   `staleAfter` มั่ว ๆ (ADR-21 หัวข้อ 9 สมมติฐาน B)
  ///
  /// - Parameters:
  ///   - inArray: `nil` = บรรทัดนี้ไม่ได้พูดถึง key ใด (เช่นบรรทัด `launch`) เขียน
  ///     เป็น `n/a` **ห้ามเขียน `0`** ซึ่งแปลว่า "นับแล้วได้ศูนย์" คนละความหมายกัน
  ///   - unknown: เช่นเดียวกับ [inArray]
  static func rangeCounterSuffix(rangeCb: Int, inArray: Int?, unknown: Int?) -> String {
    var parts = ""
    parts += " rangeCb=\(rangeCb)"
    parts += " inArray=\(inArray.map(String.init) ?? "n/a")"
    parts += " unknown=\(unknown.map(String.init) ?? "n/a")"
    return parts
  }

  /// เขียนบรรทัด `rangetick` — **ของเพิ่มจากรอบ 10 ก.ย. 2026 (ADR-21 หัวข้อ 9)**
  ///
  /// ตอบคำถามเดียวที่บรรทัด transition ตอบไม่ได้: **"หน้าต่างจริงหลังถูกปลุกยาวแค่ไหน"**
  /// — ถ้า process ถูก suspend/ฆ่าเงียบ ๆ ตอนบีคอนนิ่งอยู่ บรรทัดสุดท้ายของ process
  /// นั้นจะเป็น transition เมื่อนานมาแล้ว แล้ว "เวลาที่ ranging หยุดจริง" จะแยกไม่ออก
  /// จาก "เวลาที่ความใกล้หยุดเปลี่ยน" (ความกำกวมชนิดเดียวกับ `rangefail` 0 บรรทัด)
  ///
  /// **ไม่ยิง notification** — เป็นข้อมูลของผู้ทดสอบ ไม่ใช่เหตุการณ์ที่ผู้ใช้ต้องรู้
  ///
  /// `inArray`/`unknown` ของบรรทัดนี้เป็น **ผลรวมทุก key ใน process** ต่างจากบรรทัด
  /// `proximity` ที่เป็นของ key เดียว — ตัวอ่านแยกได้จากคอลัมน์ `event=` (ดู kdoc ของ
  /// `BeaconKitRangeTickEvent`)
  private func recordRangeTick(_ event: BeaconKitRangeTickEvent) {
    BackgroundEvidenceLog.shared.append(
      line: BackgroundEvidenceLog.line(
        timestamp: event.timestamp,
        event: "rangetick",
        regionIdentifier: event.regionIdentifier,
        conclusion: currentRunContext(),
        rawSignals: rawSignalSummary(receiverEntry: true)
          + Self.rangeCounterSuffix(
            rangeCb: event.rangeCallbackCount,
            inArray: event.inArrayCount,
            unknown: event.unknownCount
          )
      )
    )
  }

  /// key ของ cooldown — ระดับ **บีคอนหนึ่งตัวในหนึ่ง region**
  ///
  /// ตรงกับ key ของ `ProximityGate` (ADR-21 หัวข้อ 3) โดยตั้งใจ เพราะข้อความที่
  /// ผู้ใช้เห็นมี `beacon=<major>/<minor>` อยู่ด้วย — บีคอนคนละตัวจึงให้ข้อความคนละ
  /// ใบที่อ่านแล้วแยกออก ต่างจากฝั่ง Android ที่จงใจ**ไม่**ใส่ตัวแยกบีคอนลง key
  /// เพราะที่นั่นไม่มี major/minor รายเฟรมให้ใส่ในข้อความตั้งแต่แรก
  ///
  /// **`static` ไม่ใช่ instance method** (แก้ตามรอบรีวิว QA) — ฟังก์ชันนี้ไม่ใช้
  /// `self` เลย (อ่านแค่ฟิลด์ของ `event` ที่รับเข้ามา) และ Swift `private` จำกัดแค่
  /// ไฟล์เดียวกัน `@testable import` ไม่ทะลุ ทำให้ `RunnerTests` เรียกไม่ได้เลย —
  /// เปลี่ยนเป็น `static` แบบ default access (internal) เหมือน
  /// [longCooldownSinceLastPostedMillisOrNull] เพื่อให้เทสยืนยันรูปร่าง key และ
  /// เคส "คนละ key ไม่กระทบกัน" ได้ตรง ๆ
  ///
  /// ⚠️ **`uuid.lowercased()` — แก้ตามรอบรีวิว QA 16 ก.ย. 2026** ฉบับก่อนหน้าใช้
  /// `event.uuid ?? "-"` ตรง ๆ ไม่ผ่าน `.lowercased()` ซึ่ง**ไม่ตรงกับ key ของ
  /// `ProximityGate` จริง** (`ProximityKeyCodec.key()` ใน
  /// `packages/beacon_kit_ios/.../ProximityGate.swift` คืน
  /// `"\(regionIdentifier)|\(uuid.lowercased())|\(major)|\(minor)"` — มี
  /// `.lowercased()`) และไม่ตรงกับฝั่ง Android (`longCooldownKeyFor()`:
  /// `event.uuid?.lowercase() ?: "-"`) — ข้อความ ADR-25 §4 ที่ว่าฟังก์ชันนี้ "ใช้
  /// key เดิมซ้ำเพราะตรงกับ `ProximityGate` อยู่แล้ว" จึง**ไม่ตรงกับโค้ดจริงในจุด
  /// นี้** (แจ้งให้แก้เอกสารแยกแล้ว) ถ้าตัวพิมพ์ของ `uuid` ต่างกันระหว่าง sighting
  /// บีคอนตัวเดียวจะได้สอง key และคูลดาวน์จะเงียบล้มเหลวโดยไม่มีอะไรฟ้อง
  ///
  /// ⚠️ **ผลกระทบต่อคูลดาวน์เดิม 60 วินาทีที่ใช้ key ตัวนี้ร่วมกันอยู่แล้ว
  /// (`consumeProximityCooldown`, suite `beacon_kit_example.proximity_cooldown`):
  /// การแก้นี้เปลี่ยน key ของคูลดาวน์เดิมไปด้วย** ค่าที่เก็บไว้ใน suite เดิมของ
  /// เครื่องที่อัปเกรดจะกลายเป็น key ที่ไม่มีใครอ่านอีก (`uuid` ตัวพิมพ์ผสมเดิมค้างอยู่
  /// แต่การอ่านครั้งถัดไปหา key ตัวพิมพ์เล็กแทน) — ผลจริงที่ยอมรับ: **อาจได้
  /// notification เกินมาหนึ่งใบต่อบีคอนตอนอัปเกรดครั้งเดียว** เพราะคูลดาวน์เดิม
  /// "มองไม่เห็น" ค่าที่เคยจดไว้ก่อนแก้ ไม่ใช่บั๊กที่ต้องแก้เพิ่ม เป็นความเสี่ยงระดับ
  /// POC ที่ยอมรับได้เหมือนความเสี่ยงเรื่อง reboot/เครื่องหลับที่ยอมรับไว้แล้วในไฟล์นี้
  static func proximityCooldownKey(for event: BeaconKitProximityChangedEvent) -> String {
    return [
      event.regionIdentifier,
      event.uuid?.lowercased() ?? "-",
      event.major.map(String.init) ?? "-",
      event.minor.map(String.init) ?? "-",
    ].joined(separator: "|")
  }

  /// `true` เมื่อยิง notification ได้ (และจดเวลาไว้แล้ว) · `false` เมื่อยังติด
  /// cooldown อยู่
  ///
  /// **เก็บลง `UserDefaults` ไม่ใช่ตัวแปรใน memory** เพราะ process ตายและถูกปลุก
  /// ใหม่ได้ตลอดในเส้นทางที่ ADR-21 รองรับ — cooldown ที่อยู่ใน memory อย่างเดียวจะ
  /// รีเซ็ตทุกครั้งที่ระบบสร้าง process ใหม่ ซึ่งแปลว่ามันจะไม่ทำงานเลยในเคสที่มัน
  /// ถูกสร้างมาเพื่อแก้ (เหตุผลเดียวกับที่ฝั่ง Android ใช้ `SharedPreferences`)
  ///
  /// นาฬิกาที่เทียบคือเวลาแบบ wall clock ที่ติดมากับ event เอง — ยอมแลกความเสี่ยง
  /// เรื่องผู้ใช้ปรับนาฬิกาเครื่อง (ซึ่งทำให้เกิด/หายไปได้แค่ notification ใบเดียว
  /// ตอน demo) กับการไม่ต้องจัดการโทเคนรอบบูต
  private func consumeProximityCooldown(key: String, nowMillis: Int64) -> Bool {
    guard let defaults = UserDefaults(suiteName: Self.proximityCooldownSuiteName) else {
      // อ่าน/เขียนที่เก็บ cooldown ไม่ได้ = ยอมให้เด้ง ดีกว่าเงียบไปทั้งรอบทดสอบ
      // (ความล้มเหลวของ "ตัวกันสแปม" ต้องไม่กลืน event ที่กำลังจะพิสูจน์)
      return true
    }
    let lastMillis = Int64(defaults.double(forKey: key))
    if lastMillis != 0 && nowMillis - lastMillis < Self.proximityNotificationCooldownMillis {
      return false
    }
    defaults.set(Double(nowMillis), forKey: key)
    return true
  }

  /// เรียก**หลังรู้ผลว่าไม่มี error จาก `UNUserNotificationCenter.add` แล้วเท่านั้น**
  /// — ไม่ใช่ตอนผ่านประตู 30 นาที (ADR-25 §4.1) · พารามิเตอร์เป็น
  /// `Date().timeIntervalSince1970` (wall clock) ตั้งแต่ ADR-25 §4.3 — เดิมเคยเป็น
  /// `atUptime: TimeInterval` (`ProcessInfo.processInfo.systemUptime`) ถอนแล้ว
  private func recordLongCooldownPosted(key: String, atEpochSeconds: TimeInterval) {
    guard let defaults = UserDefaults(suiteName: Self.proximityLongCooldownSuiteName) else { return }
    defaults.set(atEpochSeconds, forKey: key)
  }

  /// **pure function ล้วน ไม่แตะ `UserDefaults` เลย** — ตรรกะตัดสินใจของคูลดาวน์
  /// 30 นาทีแยกออกจาก I/O เดียวกับที่ฝั่ง Android แยก
  /// `longCooldownSinceLastPostedMillisOrNull` ออกจาก `SharedPreferences`
  /// (ADR-25 §4.1, แก้ตามรอบรีวิว 16 ก.ย. 2026) — แพทเทิร์นเดียวกับ `runContext`/
  /// `proximityRawSignalsSuffix` ในไฟล์นี้ที่แยกเป็น pure `static func` ให้
  /// `RunnerTests` เรียกตรง ๆ ได้ผ่าน `@testable import Runner` โดยไม่ต้องมี
  /// `UserDefaults` จริง
  ///
  /// `nil` เมื่อไม่ติดคูลดาวน์ 30 นาที (ยิงได้) · ค่าที่ไม่ใช่ `nil` คือจำนวน
  /// มิลลิวินาทีตั้งแต่โพสต์สำเร็จครั้งล่าสุด
  ///
  /// ⚠️ **ถอนย่อหน้าเดิมทั้งหมดแล้ว (ADR-25 §4.3, แก้ 17 ก.ย. 2026)** — ฉบับก่อน
  /// หน้าเขียนว่า "ใช้ `ProcessInfo.processInfo.systemUptime` ไม่ใช่ wall clock
  /// (ADR-25 §4): ตัวเดียวที่ใกล้เคียง `elapsedRealtime` ที่สุดบน iOS ... คูลดาวน์
  /// นี้อาจนับสั้นกว่าที่ตั้งใจจริงถ้าเครื่องหลับระหว่างนั้น (ยอมรับเป็นความเสี่ยง
  /// ระดับ POC เหมือนที่ Android ยอมรับเรื่อง reboot รีเซ็ตค่า)" — **ผิดทั้งขนาดและ
  /// ทิศทาง** ไฟล์หลักฐาน `docs/test-data/2026-09-17_ios_cooldown_desk.log` (บรรทัด
  /// 6 = โพสต์สำเร็จ · 13/18/34/42/49 = ถูกคูลดาวน์กัน) ยืนยันว่า `systemUptime`
  /// ไม่นับเวลาที่เครื่องหลับจริง: บรรทัด 34/42/49 รายงาน `sinceLastPostedMs` น้อย
  /// กว่าเวลาจริงอยู่ **1734.1 วินาทีเท่ากันเป๊ะทั้งสามบรรทัด** — คูลดาวน์จึงกินเวลา
  /// จริง `1800 + เวลาที่หลับ` วินาที (**บวก ไม่ใช่คูณ และไม่มีเพดาน**) = **fail-closed
  /// อย่างเป็นระบบ** (กลืนแจ้งเตือนที่ควรได้ไป) ไม่ใช่ fail-open เล็กน้อยแบบที่
  /// Android เจอตอน reboot
  ///
  /// **ของจริงตอนนี้: ใช้ wall clock (`Date().timeIntervalSince1970`) แทน (ADR-25
  /// §4.3/§4.3.1)** เพราะ "คูลดาวน์ 30 นาที" ที่ทีมธุรกิจเข้าใจคือ 30 นาทีของเวลา
  /// จริงบนโลก ไม่ใช่ 30 นาทีของเวลาที่เครื่องตื่นอยู่ และคูลดาวน์ 60 วินาทีเดิมของ
  /// ไฟล์นี้ (`consumeProximityCooldown`) ใช้ wall clock (`event.timestampMillis`)
  /// อยู่แล้วตั้งแต่ต้น
  ///
  /// **ข้อเสียของ wall clock ที่ต้องเขียนตรง ๆ — ไม่ปิดบัง (ADR-25 §4.3.1):**
  /// ผู้ใช้/ระบบปรับนาฬิกาเครื่อง (manual หรือ NTP sync) มีผลต่อคูลดาวน์นี้โดยตรง
  /// ต่างจาก `systemUptime`/`CLOCK_MONOTONIC` ที่ไม่กระทบเลย แยกเป็นสองทิศตามขนาด
  /// การปรับเทียบกับเวลาที่ผ่านไปตั้งแต่โพสต์สำเร็จครั้งล่าสุด:
  /// - **ปรับไปข้างหน้า** หรือ **ปรับย้อนหลังมากกว่าเวลาที่ผ่านไปจริง** (เข้า guard
  ///   `lastPostedEpochSecondsOrZero > nowEpochSeconds` ด้านล่าง) → **fail-open**
  ///   (ยิงเร็ว/บ่อยกว่าที่ตั้งใจ)
  /// - **ปรับย้อนหลังน้อยกว่าเวลาที่ผ่านไปจริง** (guard ไม่ติด) → **fail-closed:
  ///   คูลดาวน์ยืดออกเท่ากับ "ผลต่างสุทธิสะสม" ของการปรับย้อนหลังในหน้าต่างนั้น (`D`)
  ///   คือหมดอายุเมื่อเวลาจริงผ่านไป `1800 + D` วินาที** — ไม่ใช่ "ขนาดของการปรับ
  ///   ครั้งนั้น" เพราะฟังก์ชันนี้เทียบแค่สองค่า ณ จุดที่ตรวจ ไม่ได้นับจำนวนครั้งที่
  ///   ปรับ · `D` ไม่มีเพดานตายตัวเชิงทฤษฎี (จำกัดแค่ว่าต้องน้อยกว่าเวลาจริงที่ผ่าน
  ///   ไป มิฉะนั้นเข้า guard) และ**คูลดาวน์ที่หมดอายุแล้วกลับมาติดใหม่ได้**ถ้านาฬิกา
  ///   ถูกปรับย้อนหลังหลังจากนั้น เพราะค่าที่จดไว้ไม่เคยถูกล้าง — ยอมรับเป็นความเสี่ยง
  ///   ระดับ POC เพราะทริกเกอร์เป็นเหตุการณ์ที่เกิดนาน ๆ ครั้ง ต่างจากบั๊ก
  ///   `systemUptime` ที่ยืดทุกครั้งที่เครื่องหลับ (ADR-25 §4.3.1)
  ///
  /// - Parameters:
  ///   - lastPostedEpochSecondsOrZero: `Date().timeIntervalSince1970` ตอนโพสต์
  ///     คีย์นี้สำเร็จครั้งล่าสุด · `0` = ไม่เคยโพสต์คีย์นี้สำเร็จมาก่อน (ค่าเดียวกับ
  ///     default ของ `UserDefaults.double(forKey:)` ตรง ๆ จึงไม่ต้องมี sentinel
  ///     แยกต่างหาก)
  ///   - nowEpochSeconds: `Date().timeIntervalSince1970` ปัจจุบัน
  ///   - cooldownSeconds: ความยาวหน้าต่างคูลดาวน์ — ⚠️ **ไม่มีค่า default โดยตั้งใจ**
  ///     (ADR-25 §8.4.1) เพื่อบังคับให้ทุกจุดเรียก (ทั้ง I/O wrapper และเทส) ระบุ
  ///     หน้าต่างที่ตั้งใจทดสอบอย่างชัดเจน ป้องกันเทสเขียวผิดหน้าต่างเงียบ ๆ ถ้ามี
  ///     ค่า default แอบเปลี่ยนความหมายในอนาคต
  static func longCooldownSinceLastPostedMillisOrNull(
    lastPostedEpochSecondsOrZero: TimeInterval,
    nowEpochSeconds: TimeInterval,
    cooldownSeconds: TimeInterval
  ) -> Int64? {
    if lastPostedEpochSecondsOrZero == 0 { return nil }  // ไม่เคยโพสต์คีย์นี้สำเร็จมาก่อน
    if lastPostedEpochSecondsOrZero > nowEpochSeconds { return nil }  // นาฬิกาถูกปรับย้อนหลัง
    let sinceSeconds = nowEpochSeconds - lastPostedEpochSecondsOrZero
    return sinceSeconds < cooldownSeconds
      ? Int64(sinceSeconds * 1000) : nil
  }

  /// ชั้น I/O ที่บางที่สุด — แค่ **"อ่านค่าของ key"** จาก `UserDefaults` แล้วส่งต่อให้
  /// [longCooldownSinceLastPostedMillisOrNull] (pure) ตัดสินใจทั้งหมด (ADR-25
  /// §4.1) ไม่มีตรรกะเทียบเวลาอยู่ในฟังก์ชันนี้เลยแม้แต่บรรทัดเดียว — **อ่านอย่างเดียว
  /// ไม่จด** แยกจาก [recordLongCooldownPosted] · พารามิเตอร์เป็น
  /// `Date().timeIntervalSince1970` (wall clock) ตั้งแต่ ADR-25 §4.3 — เดิมเคยเป็น
  /// `nowUptime: TimeInterval` (`ProcessInfo.processInfo.systemUptime`) ถอนแล้ว ·
  /// ส่ง [longCooldownSeconds] (instance property ที่ตั้งไว้ตอน launch, ADR-25 §8.4)
  /// เป็นอาร์กิวเมนต์ที่สามแทนการพึ่ง default
  private func longCooldownBlockedSinceMs(key: String, nowEpochSeconds: TimeInterval) -> Int64? {
    guard let defaults = UserDefaults(suiteName: Self.proximityLongCooldownSuiteName) else { return nil }
    return Self.longCooldownSinceLastPostedMillisOrNull(
      lastPostedEpochSecondsOrZero: defaults.double(forKey: key),
      nowEpochSeconds: nowEpochSeconds,
      cooldownSeconds: longCooldownSeconds
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

  /// - Parameter onDelivered: เรียกเฉพาะตอน**ไม่มี error** จาก
  ///   `UNUserNotificationCenter.add` (ADR-25 §4.1) — สัญญาณที่ดีที่สุดที่มีคือ
  ///   "ฝั่งเราส่ง request ให้ระบบแล้วไม่มี error กลับมาทันที" (ยังไม่ยืนยันว่า
  ///   ผู้ใช้เห็น เหมือนกับที่ `posted=requested` เตือนไว้อยู่แล้ว) ค่า default
  ///   `nil` ทำให้ผู้เรียกเดิมที่ไม่เกี่ยวกับคูลดาวน์นี้ไม่ต้องแก้เลยแม้แต่บรรทัดเดียว
  private func postNotification(
    title: String,
    body: String,
    onDelivered: (() -> Void)? = nil
  ) {
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
    ) { error in
      guard let error = error else {
        onDelivered?()  // เรียกเฉพาะตอนไม่มี error — ADR-25 §4.1
        return
      }
      // เขียนบรรทัดที่สอง **เฉพาะตอนล้มเหลว** — เส้นทางสำเร็จมีบรรทัด
      // `posted=requested` อยู่แล้ว การเขียนซ้ำตอนสำเร็จจะทำให้ไฟล์หลักฐานยาวขึ้น
      // เท่าตัวโดยไม่เพิ่มข้อมูล · callback นี้อาจ**ไม่มาถึงเลย**ถ้าระบบ suspend
      // โปรเซสก่อน ซึ่งเป็นเหตุผลที่บรรทัดแรกต้องถูกเขียนก่อนยิงเสมอ
      BackgroundEvidenceLog.shared.append(
        line: BackgroundEvidenceLog.line(
          timestamp: Date(),
          event: "notification",
          regionIdentifier: "-",
          conclusion: "notifyFailed",
          rawSignals: "posted=false "
            + "reason=\(String(describing: error).replacingOccurrences(of: " ", with: "_"))"
        )
      )
    }
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
  ///
  /// คืน **`Bool?` ไม่ใช่ `Bool`** โดยตั้งใจ — นี่คือบทเรียนของ `launchKey` ย่อส่วน
  /// (ADR-16 หัวข้อ 2): ถ้ายุบ "cast `UIApplication.shared.delegate` เป็น
  /// `AppDelegate` ไม่สำเร็จ / ไม่มี delegate เลย" กับ "cast สำเร็จแต่ยังไม่เคย
  /// active จริง" ให้เหลือแค่ `false` เหมือนกัน เทสต์ที่อ่านค่านี้จะไม่มีทาง
  /// แยกได้เลยว่า "ไม่เคย active" ที่เห็นเป็นข้อเท็จจริงของแอป หรือเป็นเพราะทางผ่าน
  /// ของเทสต์เองใช้งานไม่ได้ตั้งแต่ต้น (เช่น รันนอกบริบทแอปจริง) — `nil` จึงสงวนไว้
  /// สื่อว่า "อ่านค่าจริงไม่ได้" แยกจาก `false` ที่แปลว่า "อ่านได้ ค่าจริงคือยังไม่
  /// เคย active" ผู้เรียก (เทสต์) ต้อง `XCTUnwrap` ค่านี้ก่อนเสมอ เพื่อให้ `nil`
  /// ทำให้เทสต์ fail ทันทีแทนที่จะเงียบเป็น `false` ที่ดูเหมือนผลที่ถูกต้อง
  static var hasEverBecomeActiveForTesting: Bool? {
    (UIApplication.shared.delegate as? AppDelegate)?.hasEverBecomeActive
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
