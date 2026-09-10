import Foundation

/// event "ความใกล้เปลี่ยน" ที่คำนวณได้ฝั่ง iOS (ชั้นที่ 2 ของ ADR-21)
///
/// ฟิลด์ 9 ตัวแรกคือ **สัญญาที่ ADR-20 หัวข้อ 5 นิยามไว้แล้ว** (`proximityChanged`:
/// `{regionIdentifier, uuid, major, minor, from, to, reason, medianMeters?,
/// timestampMillis}`) — ADR-21 หัวข้อ 5 สั่งให้ใช้ของเดิม **ห้ามนิยามใหม่**
/// **วันนี้ยังไม่ส่งขึ้น Dart: ไม่มี MethodChannel ไม่มี EventChannel ไม่มี stream**
/// (ADR-21 หัวข้อ 6) ตั้งใจไม่ล็อก public API ก่อนพิสูจน์กลไกจริงบนเครื่อง
///
/// ⚠️ **[beacon] และ [storeError] ไม่ใช่ส่วนหนึ่งของสัญญา wire** — มีไว้ให้ไฟล์
/// หลักฐานของ host app เขียนลง log เท่านั้น ถ้าวันหนึ่งต่อ channel จริง **ห้ามใส่
/// สองฟิลด์นี้ลง payload** โดยไม่แก้ ADR-20 หัวข้อ 5 ก่อน
///
/// ทั้งสองฟิลด์มีตั้งแต่คอมมิตแรกตามคำสั่งของ **ADR-21 หัวข้อ 7** ซึ่งเป็นบทเรียน
/// ตรง ๆ จากรอบ Android: บรรทัด `event=proximity` ของคนละบีคอนพิมพ์ออกมาเหมือนกัน
/// หมดจนอ่านเป็นบั๊ก entry ซ้ำ และความล้มเหลวของที่เก็บ state ไม่เคยปรากฏในไฟล์เลย
public struct BeaconKitProximityChangedEvent {
  public init(
    regionIdentifier: String,
    uuid: String?,
    major: UInt16?,
    minor: UInt16?,
    from: ProximityBucket?,
    to: ProximityBucket?,
    reason: ProximityTransitionReason,
    medianMeters: Double?,
    timestampMillis: Int64,
    storeError: String?,
    rangeCallbackCount: Int,
    inArrayCount: Int,
    unknownCount: Int
  ) {
    self.regionIdentifier = regionIdentifier
    self.uuid = uuid
    self.major = major
    self.minor = minor
    self.from = from
    self.to = to
    self.reason = reason
    self.medianMeters = medianMeters
    self.timestampMillis = timestampMillis
    self.storeError = storeError
    self.rangeCallbackCount = rangeCallbackCount
    self.inArrayCount = inArrayCount
    self.unknownCount = unknownCount
  }

  /// identifier ที่แอปตั้งไว้ตอนลงทะเบียน region (ADR-8 ใช้เป็นรหัสสาขา)
  public let regionIdentifier: String

  /// uuid/major/minor **ของบีคอนตัวที่จุดชนวน transition นี้** ถอดมาจาก key ของ
  /// gate (ADR-21 หัวข้อ 3) ซึ่งประกอบจาก `CLBeacon` รายเฟรม — **ไม่ใช่**ค่าจาก
  /// region spec ที่ลงทะเบียนไว้แบบฝั่ง Android (ที่นั่นไม่มี parser จึงไม่มีค่า
  /// รายเฟรมให้ใช้ และ region แบบ wildcard จะได้ `null`)
  ///
  /// `nil` ได้ทางเดียวคือ key ถอดกลับไม่ได้ ซึ่งไม่ควรเกิด — ถ้าเห็นค่านี้เป็น
  /// `nil` ในไฟล์หลักฐาน แปลว่ามีบั๊กใน `ProximityKeyCodec` **ต้องเป็น `nil` ตาม
  /// จริง ห้ามเดาค่าแทน**
  public let uuid: String?
  public let major: UInt16?
  public let minor: UInt16?

  public let from: ProximityBucket?

  /// `nil` = "gate ไม่มีคำตอบแล้ว" (stale) **ไม่ใช่** [ProximityBucket.far]
  public let to: ProximityBucket?

  public let reason: ProximityTransitionReason

  /// **`nil` เสมอบนเส้นทางของ iOS** — ดู kdoc ของ [ProximityTransition.medianMeters]
  public let medianMeters: Double?

  public let timestampMillis: Int64

  /// เวลาเดียวกับ [timestampMillis] ในรูป `Date` — ให้ host app เอาไป format ลง
  /// ไฟล์หลักฐานได้โดยไม่ต้องแปลงเอง
  public var timestamp: Date {
    Date(timeIntervalSince1970: Double(timestampMillis) / 1000)
  }

  /// ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — **ตัวแยกว่าบรรทัดนี้เป็นของบีคอนตัวไหน**
  /// (`"<major>/<minor>"`) ตามคำสั่งของ ADR-21 หัวข้อ 7 ข้อ 1
  ///
  /// `"n/a"` เมื่อถอด key ไม่ได้ — ค่าที่อ่านออกได้ว่า "ตอบไม่ได้" ดีกว่าช่องว่าง
  /// ที่ตัวอ่านคอลัมน์สัญญาณดิบจะมองเป็นคนละ key
  public var beacon: String {
    guard let major = major, let minor = minor else { return "n/a" }
    return "\(major)/\(minor)"
  }

  /// ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — เหตุผลที่ `ProximityGateStore` ล้มเหลวใน
  /// รอบนี้ (`nil` = อ่าน/เขียนสำเร็จ)
  ///
  /// จำเป็นเพราะ **มีเส้นทางที่ state หายโดยไม่มี `stale` ออกมาเลย**: `load()`
  /// ล้มเหลว → กู้ได้ค่าว่าง → transition ถัดไปได้ `from=none` โดยไม่มีอะไรฟ้อง
  /// (ADR-21 หัวข้อ 7 ข้อ 2)
  public let storeError: String?

  /// ⚠️ log เท่านั้น ไม่ใช่สัญญา wire — **ตัวนับ 3 ตัวของ ADR-21 หัวข้อ 9**
  /// (เพิ่มหลังรอบเดินจริง 10 ก.ย. 2026)
  ///
  /// ทั้งสามตัวเป็นค่าของ **process นี้เท่านั้น** ไม่รอดข้าม launch และ **ไม่ถูกเก็บ
  /// ลง `ProximityGateStore`** โดยตั้งใจ — มันเป็นเครื่องมือวัดของรอบทดสอบ ไม่ใช่
  /// สถานะที่ gate ใช้ตัดสินใจ (ADR-21 หมายเหตุข้อ 1 ห้ามใส่ counter ลง
  /// `ProximityKeyState` เพราะจะเบี่ยงจาก reference ทั้งที่ไม่จำเป็น)
  ///
  /// **ห้ามรวมสามตัวนี้เป็นตัวเดียว** — บน iOS "ไม่มี sample" มีสองความหมายที่แก้
  /// คนละทาง: ranging ไม่เดิน (`rangeCallbackCount` ไม่ขยับ) กับ ranging เดินแต่
  /// Apple ถอดบีคอนออกจาก array (`rangeCallbackCount` ขยับ แต่ `inArrayCount` ไม่ขยับ)
  ///
  /// จำนวนครั้งที่ `didRange` ถูกเรียกใน process นี้ — **ระดับ process ไม่ใช่ระดับ
  /// key** ตอบว่า "ranging เดินอยู่จริงไหม ถี่แค่ไหน"
  public let rangeCallbackCount: Int

  /// จำนวนครั้งที่บีคอน **ตัวที่ key ของ event นี้ชี้ถึง** อยู่ใน array ของ `didRange`
  /// ใน process นี้ — ตอบว่า "Apple ถอดบีคอนออกจาก array บ่อยไหม"
  public let inArrayCount: Int

  /// จำนวนครั้งที่บีคอนตัวนั้นอยู่ใน array **แต่ `proximity == .unknown`** (นับรวมอยู่
  /// ใน [inArrayCount] ด้วย) — ตอบว่า "Apple ส่ง `unknown` บ่อยแค่ไหน"
  ///
  /// ตัวเลขนี้คือกุญแจของ **สมมติฐาน B** ใน ADR-21 หัวข้อ 9: ถ้าค่านี้สูง คำตอบของ
  /// `stale` 33% อยู่ที่กฎ "`unknown` ไม่ต่ออายุ `lastSampleAt`" (ADR-19 6(ง))
  /// **ไม่ใช่ที่ตัวเลข `staleAfter`**
  public let unknownCount: Int
}

/// ชีพจรของ ranging หนึ่งครั้ง — **ไม่ใช่ "ความใกล้เปลี่ยน" และไม่ใช่สัญญา wire ใด ๆ**
/// (ADR-21 หัวข้อ 9 "ของเพิ่ม")
///
/// ## ทำไมต้องมี ทั้งที่ไม่มีอะไรเปลี่ยน
///
/// คำถาม "หน้าต่างจริงหลังถูกปลุกยาวแค่ไหน" ตอบไม่ได้จากไฟล์หลักฐานที่มีแต่บรรทัด
/// transition: ถ้า process ถูก suspend/ฆ่าเงียบ ๆ โดยที่บีคอนยังนิ่งอยู่ บรรทัด
/// สุดท้ายของ process นั้นจะเป็น transition เมื่อนานมาแล้ว แล้ว "เวลาที่ ranging
/// หยุดจริง" จะแยกไม่ออกจาก "เวลาที่ความใกล้หยุดเปลี่ยน" — ความกำกวมชนิดเดียวกับที่
/// รอบเดินจริง 10 ก.ย. 2026 เจอกับ `rangefail` (0 บรรทัด แปลได้สองอย่าง)
///
/// ยิง **อย่างมากทุก 30 วินาทีต่อ process** จาก `didRange` เท่านั้น · **ไม่ยิง
/// notification** (เป็นข้อมูลของผู้ทดสอบ ไม่ใช่เหตุการณ์ที่ผู้ใช้ต้องรู้)
public struct BeaconKitRangeTickEvent {
  public init(
    regionIdentifier: String,
    rangeCallbackCount: Int,
    inArrayCount: Int,
    unknownCount: Int,
    timestampMillis: Int64
  ) {
    self.regionIdentifier = regionIdentifier
    self.rangeCallbackCount = rangeCallbackCount
    self.inArrayCount = inArrayCount
    self.unknownCount = unknownCount
    self.timestampMillis = timestampMillis
  }

  /// region ของ `didRange` ที่จุดชนวน tick นี้ — ไม่ใช่ "ทุก region ที่ range อยู่"
  public let regionIdentifier: String

  public let rangeCallbackCount: Int

  /// ⚠️ **ความหมายต่างจากฟิลด์ชื่อเดียวกันใน [BeaconKitProximityChangedEvent]** —
  /// ที่นั่นเป็นของ key เดียว ที่นี่เป็น **ผลรวมของทุก key ใน process นี้** เพราะ
  /// บรรทัด tick ไม่ได้พูดถึงบีคอนตัวใดตัวหนึ่ง (ตัวอ่านแยกได้จากคอลัมน์ `event=`
  /// ซึ่งเป็น `rangetick` ไม่ใช่ `proximity`)
  public let inArrayCount: Int

  /// ผลรวมของทุก key เช่นเดียวกับ [inArrayCount]
  public let unknownCount: Int

  public let timestampMillis: Int64

  public var timestamp: Date {
    Date(timeIntervalSince1970: Double(timestampMillis) / 1000)
  }
}

/// ทางออกของชั้น proximity (ADR-21 ชั้นที่ 2) ไปยัง **โค้ด native ของ host app**
///
/// แยกเป็นไฟล์/ชนิดของตัวเองแทนการเพิ่ม hook ใน `IBeaconRangingManager.onRegionStateEvent`
/// โดยตั้งใจ: ชั้น 1 (region enter/exit) มีหลักฐานจากอุปกรณ์จริงระดับ `observed`
/// แล้ว (ADR-14/ADR-10) ส่วนชั้นนี้ยังไม่เคยรันบนเครื่องจริงเลยแม้แต่ครั้งเดียว
/// — การแยกทำให้ `git diff` ของรอบนี้พิสูจน์ได้ทันทีว่า**ไม่มีบรรทัดใดของทางออก
/// ชั้น 1 ถูกแตะ** ซึ่งเป็นเงื่อนไขที่ ADR-21 บังคับไว้
///
/// pattern เดียวกับ `BackgroundProximityMonitor` ฝั่ง Android เป๊ะ (host app ตั้ง
/// observer เองจากจุดที่ทำงานเสมอไม่ว่า process จะเกิดด้วยเหตุใด — ฝั่ง iOS คือ
/// `application(_:didFinishLaunchingWithOptions:)`) และด้วยเหตุผลเดียวกัน
/// **SDK ไม่ตั้งให้เอง**
///
/// ⚠️ **ยังไม่มี event channel คู่ขนานเหมือนชั้น 1 และไม่มีคิว event ลงดิสก์** —
/// ADR-21 หัวข้อ 6 ระบุว่ารอบนี้ยังไม่ส่งขึ้น Dart การมีคิวไว้ก่อนจะเป็นการล็อก
/// สัญญาที่ยังไม่พิสูจน์ ผลที่ต้องยอมรับ: event ที่เกิดตอนไม่มี observer **หายไป
/// จริง ๆ** (ไม่ใช่ค้างรอ) — รับได้เพราะ example app ตั้ง observer ตั้งแต่
/// `didFinishLaunchingWithOptions` ซึ่งจบก่อน CoreLocation เรียก delegate เสมอ
public enum BackgroundProximityMonitor {
  public typealias ProximityObserver = (BeaconKitProximityChangedEvent) -> Void

  /// กันการอ่าน/เขียนพร้อมกันระหว่างเธรดที่ตั้ง observer (main ตอน launch) กับเธรด
  /// ที่ CoreLocation เรียก delegate เข้ามา — ราคาถูกกว่าการสมมติว่าเป็นเธรดเดียวกัน
  /// เสมอแล้วผิดในวันที่ไม่มีใครดู (คู่ขนานกับ `@Volatile` ฝั่ง Kotlin)
  private static let lock = NSLock()
  private static var observer: ProximityObserver?
  private static var backgroundLocationUpdatesTraceStorage: String?

  /// ผู้สังเกตการณ์ของ `didFailRangingFor` — **นับความเงียบให้เป็นตัวเลข ไม่ใช่อนุมาน
  /// จากการไม่มีบรรทัด**
  ///
  /// ## ⚠️ ผลรอบเดินจริง 10 ก.ย. 2026: `didFailRangingFor` **ไม่ใช่**สัญญาณว่าบีคอนหาย
  ///
  /// `docs/test-data/2026-09-10_ios_proximity_walk.log` มี `event=rangefail`
  /// **0 บรรทัด** ทั้งไฟล์ ทั้งที่ผู้ทดสอบเดินพ้นสัญญาณไปสองนาทีและ iOS ประกาศ
  /// `exit` ของ region จริงในรอบเดียวกัน — **พิสูจน์แล้วว่าเป็นสมมติฐานที่ผิด**
  /// (สมมติฐานเดิมมาจาก abstract ของ Apple: "couldn't detect any beacons that satisfy
  /// the provided constraint" ซึ่งอ่านได้ว่าเป็นเคส "ไม่เจอเลย")
  ///
  /// ความหมายที่เหลืออยู่จริงคือ **"ranging เองล้มเหลว"** (เช่น Bluetooth ถูกปิด,
  /// สิทธิ์ถูกถอน) ไม่ใช่ "บีคอนหายไปจากที่เกิดเหตุ" — **ห้ามพึ่ง callback นี้เป็นจุด
  /// sweep เด็ดขาด** จุด sweep ที่เชื่อถือได้คือท้าย `didRange` ทุกครั้ง (เรียก
  /// `sweepStale()` เสมอแม้ array ว่าง) และ `didExitRegion` — ดู ADR-21 หัวข้อ 4/8
  ///
  /// ## ยังเก็บ observer นี้ไว้ทำไม
  ///
  /// เพราะเคส "ranging ล้มเหลว" ยังต้องแยกออกจาก "ranging เดินแต่ไม่เจออะไร" ให้ได้
  /// จากไฟล์หลักฐาน — และการไม่มีบรรทัดแยกไม่ออกระหว่าง "callback ไม่เคยยิง" กับ
  /// "ยิงแต่ไม่มีอะไรให้รายงาน" (บทเรียนตรงจาก `android_background_scanning.md` ข้อ B)
  /// **บรรทัด `rangefail` ที่ 0 บรรทัดคือผลลัพธ์เชิงบวกของรอบนั้น ไม่ใช่โค้ดที่ไร้ค่า**
  public static func setRangingFailureObserver(_ newObserver: ((String) -> Void)?) {
    lock.lock()
    defer { lock.unlock() }
    rangingFailureObserver = newObserver
  }

  private static var rangingFailureObserver: ((String) -> Void)?

  /// แจ้งว่า `didFailRangingFor` ยิงสำหรับ region หนึ่ง — ห่อ error ของ host เหมือน
  /// `emit` เพื่อไม่ให้โค้ดของแอปทำให้เส้นทางเบื้องหลังของ SDK ล้ม
  public static func emitRangingFailure(regionIdentifier: String) {
    lock.lock()
    let observer = rangingFailureObserver
    lock.unlock()
    observer?(regionIdentifier)
  }

  /// ผู้สังเกตการณ์ของ [BeaconKitRangeTickEvent] — **ของเพิ่มจากรอบ 10 ก.ย. 2026
  /// (ADR-21 หัวข้อ 9)** ถ้าไม่ต้องการแล้วลบทิ้งได้โดยไม่กระทบเส้นทางอื่นเลย
  public static func setRangeTickObserver(_ newObserver: ((BeaconKitRangeTickEvent) -> Void)?) {
    lock.lock()
    defer { lock.unlock() }
    rangeTickObserver = newObserver
  }

  private static var rangeTickObserver: ((BeaconKitRangeTickEvent) -> Void)?

  /// แจ้งชีพจรของ ranging — **ผู้เรียกเป็นคนคุมจังหวะ (อย่างมากทุก 30 วินาที)**
  /// ไม่ใช่ที่นี่ เพราะการ throttle ต้องใช้นาฬิกาเดียวกับที่ประทับลง event
  internal static func emitRangeTick(_ event: BeaconKitRangeTickEvent) {
    lock.lock()
    let observer = rangeTickObserver
    lock.unlock()
    observer?(event)
  }

  public static func setProximityObserver(_ newObserver: ProximityObserver?) {
    lock.lock()
    defer { lock.unlock() }
    observer = newObserver
  }

  /// ส่ง [event] ให้ observer — **ครบทุก transition ไม่กรองอะไรทั้งสิ้น**
  ///
  /// `closer` / `farther` / `stale` ถูกส่งออกหมดตามสัญญาที่ ADR-20 หัวข้อ 5 นิยาม
  /// ไว้ **การตัดสินว่า event ไหน "ควรรบกวนผู้ใช้" เป็นนโยบายของแอป ไม่ใช่ความ
  /// สามารถของแพลตฟอร์ม** จึงอยู่ที่ example app แนวเดียวกับตำแหน่งของ cooldown
  /// (ADR-21 หัวข้อ 6 · ADR-11 หัวข้อ 7) — ถ้ากรองที่นี่ ชั้น 2 จะไม่มีสัญญาณ
  /// "ออก/วัดไม่ได้" ให้ใครเลย และรอบทดสอบบนเครื่องจริงจะไม่มีบรรทัดหลักฐานที่ตอบ
  /// ได้ว่า `staleAfter = 10 วินาที` ของ ADR-19 หัวข้อ 8 ใช้ได้จริงกับ iOS หรือไม่
  /// (ซึ่งเป็นคำถามเปิดข้อใหญ่ที่สุดของ ADR-21 หัวข้อ 4)
  internal static func emit(_ event: BeaconKitProximityChangedEvent) {
    lock.lock()
    let current = observer
    lock.unlock()
    current?(event)
  }

  /// ผลการตัดสินใจเรื่อง `allowsBackgroundLocationUpdates` ของ process นี้ —
  /// `nil` แปลว่ายังไม่เคยถึงจุดที่ตัดสิน (ยังไม่มี `didRange` เข้ามาเลย)
  ///
  /// **ทำไมต้องเปิดให้อ่าน:** Apple ระบุว่าการตั้งค่านี้เป็น `true` ทั้งที่
  /// `Info.plist` ไม่มี `UIBackgroundModes`/`location` เป็น "a fatal error that
  /// terminates the app" (คำต่อคำ — `docs/sources/apple_proximity_ranging.md`
  /// หัวข้อ 6) SDK จึงต้องตรวจก่อนตั้ง และ **เมื่อไม่ตั้ง ต้องมีร่องรอย ห้ามเงียบ**
  /// (ADR-21 หัวข้อ 1) — host app ที่สงสัยว่าทำไมชั้น 2 เงียบตอน background อ่าน
  /// ค่านี้แล้วรู้คำตอบทันทีโดยไม่ต้องเดา
  public static var backgroundLocationUpdatesTrace: String? {
    lock.lock()
    defer { lock.unlock() }
    return backgroundLocationUpdatesTraceStorage
  }

  internal static func recordBackgroundLocationUpdatesTrace(_ trace: String) {
    lock.lock()
    backgroundLocationUpdatesTraceStorage = trace
    lock.unlock()
    // SDK นี้ไม่มีระบบ log ของตัวเองและไม่ควรบังคับ framework ใดให้ host app —
    // `NSLog` หนึ่งบรรทัดครั้งเดียวต่อ process คือร่องรอยที่ถูกที่สุดที่ยังตามได้
    // จาก Console.app/`sysdiagnose` ตอนไล่บั๊กบนเครื่องจริง
    NSLog("[beacon_kit_ios] proximity: %@", trace)
  }
}
