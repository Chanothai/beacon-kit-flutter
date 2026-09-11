import Foundation

/// bucket ความใกล้ที่ [ProximityGate] ยืนยันได้ — **ไม่มี `unknown`**
///
/// ต่างจาก `BeaconProximity` ฝั่ง Dart ที่ reuse enum เดิมซึ่งมี `unknown` ติดมาด้วย
/// (แล้วต้องประกาศ invariant ว่า `unknown` ห้ามรั่วออกทางเอาต์พุต — ADR-19 หัวข้อ
/// 6(ช)) — ฝั่ง Swift สร้าง enum ใหม่ได้เลยจึงตัด `unknown` ทิ้งตั้งแต่ระดับชนิด
/// ข้อมูล เหมือน `ProximityBucket` ฝั่ง Kotlin เป๊ะ "ไม่มีคำตอบ" แทนด้วย `nil`
///
/// ⚠️ **enum นี้ไม่ใช่ `CLProximity`** และไฟล์นี้ **ห้าม `import CoreLocation`**
/// (ADR-21 หัวข้อ 2): การแปลง `CLProximity` -> `ProximityBucket?` เป็นหน้าที่ของ
/// `IBeaconRangingManager` ซึ่งเป็นชั้นที่แตะ CoreLocation อยู่แล้ว — ถ้าไฟล์นี้
/// พึ่ง CoreLocation เทสต์ทั้งชุดจะผูกกับเฟรมเวิร์กของระบบโดยไม่จำเป็น
///
/// `rawValue` คือชื่อที่ใช้ใน payload ของ event (ADR-20 หัวข้อ 5), ในไฟล์หลักฐาน
/// และใน JSON ที่เก็บลง `UserDefaults` — **ต้องตรงกับชื่อ enum ฝั่ง Dart/Kotlin**
/// (`near`/`immediate`/`far`) เพราะทั้งสามภาษาต้องอ่านค่าเดียวกันได้ตอนสัญญาถูก
/// ต่อจริง
public enum ProximityBucket: String, CaseIterable, Codable {
  case immediate
  case near
  case far

  /// ชื่อที่ใช้ข้ามภาษา — ตั้งชื่อเมธอดให้ตรงกับฝั่ง Kotlin (`wireName`) เพื่อให้
  /// อ่านโค้ดสองฝั่งคู่กันได้ ไม่ใช่เพราะ `rawValue` ใช้ไม่ได้
  public var wireName: String { rawValue }

  /// ถอดกลับจาก [wireName] — `nil` เมื่อไม่ตรงกับตัวใด (ค่าที่เก็บไว้เสียหาย)
  public static func fromWireName(_ value: String?) -> ProximityBucket? {
    guard let value = value else { return nil }
    return ProximityBucket(rawValue: value)
  }
}

/// อันดับความใกล้ (ยิ่งน้อยยิ่งใกล้) — ใช้เทียบว่า candidate "ใกล้กว่า" หรือ
/// "ไกลกว่า" bucket ที่ยืนยันอยู่ ตรงกับ `_rankOf` ของ `proximity_gate.dart` และ
/// `rankOfBucket` ฝั่ง Kotlin เป๊ะ
///
/// ฝั่ง Dart ต้องมีสาขา `unknown` ที่ `throw StateError` เพราะ enum ที่ reuse มามี
/// ค่านั้นอยู่ — ที่นี่ไม่มีสาขานั้นเพราะ [ProximityBucket] ไม่มี `unknown` ตั้งแต่
/// แรก (ความต่างที่ตั้งใจ ไม่ใช่การละเลย)
internal func rankOfBucket(_ bucket: ProximityBucket) -> Int {
  switch bucket {
  case .immediate: return 0
  case .near: return 1
  case .far: return 2
  }
}

/// เหตุผลของ transition — ตรงกับ `ProximityTransitionReason` ฝั่ง Dart/Kotlin
public enum ProximityTransitionReason: String, Codable {
  /// ใกล้ขึ้น และผ่านเกณฑ์ dwell ติดกันครบ `dwellSamples` แล้ว (ADR-19 6(ค))
  case closer

  /// ไกลลง — ยืนยันทันทีไม่ต้อง dwell (ADR-19 6(ค): ต้นทุนของการประกาศ "ไกล"
  /// ผิดพลาดถูกกว่าการประกาศ "ใกล้" ผิดพลาด)
  case farther

  /// เงียบเกิน `staleAfterMillis` — "วัดไม่ได้อีกแล้ว" ไม่ใช่ "ไกล" (ADR-19 6(ฉ))
  /// `to` เป็น `nil` เสมอเมื่อ reason นี้
  case stale

  /// ระบบประกาศว่าอุปกรณ์ **ออกจาก region** แล้ว (`didExitRegion`) — สถานะชั้นที่ 2
  /// ของทุก key ใน region นั้นถูกล้างทิ้ง `to` เป็น `nil` เสมอเหมือน [stale]
  ///
  /// ⚠️ **case นี้มีเฉพาะฝั่ง Swift — ไม่มีใน `proximity_gate.dart` (reference) และ
  /// ไม่มีฝั่ง Kotlin · ห้ามเรียกว่า "parity กับ Android" เด็ดขาด** ฝั่ง Android ล้าง
  /// store ของชั้น 2 ตอน `monitorStop` ของ example app **ไม่ใช่ตอน region exit** และ
  /// ไม่มี reason ตัวนี้อยู่จริงเลย
  ///
  /// **เป็นการเบี่ยงจาก reference โดยตั้งใจ** ด้วยเหตุผลที่เป็นความจริงเฉพาะ iOS:
  /// iOS มี boundary event ที่ระบบยืนยันเอง (`didExitRegion`) ซึ่งเชื่อถือได้และมา
  /// ถึงแม้ในรอบที่ process เพิ่งถูกปลุก — ต่างจากอีกสองแพลตฟอร์มที่ไม่มีสัญญาณคู่นี้
  /// ในชั้นเดียวกัน (รอบเดินจริง 10 ก.ย. 2026 พิสูจน์ว่า `didFailRangingFor` ไม่ใช่
  /// สัญญาณว่าบีคอนหาย: 0 บรรทัดทั้งรอบ ทั้งที่ iOS ประกาศ `exit` จริง —
  /// `docs/test-data/2026-09-10_ios_proximity_walk.log`)
  ///
  /// **เป็นหนี้ ไม่ใช่ของแถม:** ต้องยกกฎนี้ขึ้นไปที่ `proximity_gate.dart` แล้วไหลลง
  /// ทั้งสอง port ในรอบถัดไป ไม่งั้นจะมี **สามภาษาสามพฤติกรรม** (ADR-21 หัวข้อ 8)
  case regionExit

  public var wireName: String { rawValue }
}

/// ผลลัพธ์ตอน bucket ของ key หนึ่งเปลี่ยนจริง — คืนจาก [ProximityGate.push] /
/// [ProximityGate.sweepStale] / [ProximityGate.clearStates(matchingPrefix:emitting:)]
/// **เฉพาะตอนเปลี่ยนจริงเท่านั้น** ไม่ใช่ทุก sample
///
/// `to == nil` แปลว่า "gate ไม่มีคำตอบให้แล้ว" **ไม่ใช่ [ProximityBucket.far]** —
/// เกิดได้สองทางคือ [ProximityTransitionReason.stale] และ
/// [ProximityTransitionReason.regionExit] (ตัวหลังมีเฉพาะฝั่ง Swift ดู kdoc ของ case
/// นั้น) ผู้เรียกที่อยากรู้ว่า "ไกลแล้วจริง ๆ" ต้องเช็ค `to == .far` ตรง ๆ ไม่ใช่
/// เช็คว่าไม่ใช่ near/immediate
public struct ProximityTransition: Equatable {
  public init(
    key: String,
    from: ProximityBucket?,
    to: ProximityBucket?,
    reason: ProximityTransitionReason,
    medianMeters: Double?
  ) {
    self.key = key
    self.from = from
    self.to = to
    self.reason = reason
    self.medianMeters = medianMeters
  }

  /// key ทึบตามรูปแบบของ [ProximityKeyCodec] — gate ไม่ตีความเอง
  public let key: String
  public let from: ProximityBucket?
  public let to: ProximityBucket?
  public let reason: ProximityTransitionReason

  /// **`nil` เสมอบนเส้นทางของ iOS** — เส้นทางเดียวที่ port มาคือ Apple bucket ซึ่ง
  /// ไม่มีการคำนวณระยะเป็นเมตรเลย (ADR-21 หัวข้อ 2: `ibeaconTxPower` เป็น `null`
  /// เสมอเมื่อ `osDecoded` จึงคำนวณ path-loss ไม่ได้ตั้งแต่ต้น)
  ///
  /// คงฟิลด์นี้ไว้เพราะสัญญา event ของ ADR-20 หัวข้อ 5 นิยาม `medianMeters` เป็น
  /// optional ไว้แล้วโดยเผื่อกรณีนี้โดยเฉพาะ — ถ้าตัดฟิลด์ทิ้ง โครงสร้างสองฝั่งจะ
  /// ต่างกันโดยไม่มีเหตุผลเชิงความหมายรองรับ
  public let medianMeters: Double?
}

/// สถานะภายในของ key เดียว — **public เพราะ `ProximityGateStore` ต้อง serialize
/// มันลง `UserDefaults` ทุกครั้งที่ push** (ADR-21 หัวข้อ 3)
///
/// เป็น **struct (value type)**: [ProximityGate] แก้ค่าแล้วเขียนกลับลงแผนที่เสมอ
/// ไม่แก้ของเดิมในที่ — snapshot ที่ผู้เรียกถืออยู่จึงไม่ถูกแก้ใต้เท้าโดยไม่รู้ตัว
/// (เหตุผลเดียวกับที่ฝั่ง Kotlin ใช้ `data class` + `copy()`)
///
/// ## ทำไม **ไม่มี** ฟิลด์ `droppedNoTxPowerCount` แบบฝั่ง Dart/Kotlin
///
/// counter ตัวนั้นนับ sample ที่ถูกทิ้งตาม ADR-19 หัวข้อ 6(จ) (`proximity == null`
/// **และ** `txPower == null` = คำนวณอะไรไม่ได้เลย) ซึ่งเป็น**สาขาที่ไปไม่ถึงบน
/// เส้นทางนี้**: อินพุตเดียวของ gate ฝั่ง Swift คือ Apple bucket ตาม ADR-21 หัวข้อ
/// 2 ไม่มี rssi/txPower ให้คำนวณตั้งแต่แรก
///
/// ส่วน sample ที่เป็น `unknown` (ADR-19 6(ง)) **ห้ามนับ counter ใด ๆ ทั้งสิ้น** —
/// ADR-21 หัวข้อ 2 เขียนไว้ตรง ๆ ว่า "ทิ้ง sample **ห้ามแตะ state แม้แต่ฟิลด์เดียว**"
/// และข้อยกเว้น counter ของ ADR-19 6(จ) ผูกกับสาขา txPower เท่านั้น ไม่ใช่สาขา
/// `unknown` — การเพิ่ม counter ที่นี่จึงเป็นการเบี่ยงจาก reference implementation
/// ทั้งที่ ADR ห้ามไว้ชัดเจน (ดูรายงานการเบี่ยงในรอบ implement)
public struct ProximityKeyState: Equatable {
  public init(
    confirmedBucket: ProximityBucket? = nil,
    pendingCloserBucket: ProximityBucket? = nil,
    pendingCloserCount: Int = 0,
    window: [ProximityBucket] = [],
    lastSampleAt: Int64? = nil
  ) {
    self.confirmedBucket = confirmedBucket
    self.pendingCloserBucket = pendingCloserBucket
    self.pendingCloserCount = pendingCloserCount
    self.window = window
    self.lastSampleAt = lastSampleAt
  }

  /// bucket ที่ยืนยันแล้ว — `nil` = ยังไม่เคยยืนยันอะไรเลยสำหรับ key นี้
  public var confirmedBucket: ProximityBucket?

  /// bucket ที่ใกล้กว่าและกำลังรอ dwell ครบ — `nil` = ไม่มีตัวไหนรออยู่
  public var pendingCloserBucket: ProximityBucket?

  public var pendingCloserCount: Int

  /// หน้าต่าง bucket ดิบของ Apple เรียงตามลำดับที่เข้ามา **ตัวใหม่ต่อท้ายเสมอ**
  /// (ลำดับคือข้อมูล ไม่ใช่แค่ที่เก็บ — ถ้าสลับ การตัดหัวรอบถัดไปจะตัดผิดตัว) —
  /// คู่ขนานกับ `appleProximityWindow` ของ `proximity_gate.dart` ไม่ใช่ `window`
  /// ที่เป็นระยะเมตรของเส้นทาง Android
  public var window: [ProximityBucket]

  /// เวลา (จาก [ProximityGate.clock], epoch millis) ของ sample **ที่ใช้ตัดสินใจ
  /// ได้จริง** ล่าสุด — sample ที่ถูกทิ้ง (`unknown`) ห้ามขยับค่านี้ ไม่งั้น
  /// staleness จะตรวจจับ "มีสัญญาณเข้ามาแต่ใช้อะไรไม่ได้เลย" ไม่ได้ (ADR-19 6(ง))
  public var lastSampleAt: Int64?
}

/// คู่ (key, state) หนึ่งรายการ — ใช้แทน `Dictionary` ในทุก API ที่ **ลำดับมี
/// ความหมาย**
///
/// `Dictionary` ของ Swift ไม่รับประกันลำดับการวนซ้ำเลย (และสลับได้ทุกครั้งที่รัน)
/// ถ้าใช้มันเป็นชนิดข้อมูลของ [ProximityGate.snapshotStates] /
/// [ProximityGate.sweepStale] ลำดับของ transition ที่ออกมาและลำดับที่เขียนลง JSON
/// จะทำซ้ำไม่ได้ ทั้งเทสต์และไฟล์หลักฐานจะอ่านยากขึ้นโดยไม่มีเหตุผล — ฝั่ง Kotlin
/// แก้ปัญหาเดียวกันนี้ด้วย `LinkedHashMap`
public struct ProximityKeyEntry: Equatable {
  public init(key: String, state: ProximityKeyState) {
    self.key = key
    self.state = state
  }

  public let key: String
  public let state: ProximityKeyState
}

/// ประกอบ/ถอด key ของ [ProximityGate] ตาม **ADR-21 หัวข้อ 3**
///
/// `"<regionIdentifier>|<uuid ตัวพิมพ์เล็ก>|<major>|<minor>"`
///
/// ⚠️ **ห้ามใช้ identifier ของวิทยุ (`CBPeripheral.identifier`) เป็นส่วนหนึ่งของ
/// key เด็ดขาด** — ค่านั้นสุ่มใหม่ทุกครั้งที่ถอน-ลงแอปใหม่ (ADR-19) ฝั่ง Android
/// ยอมใช้ MAC เฉพาะ POC เพราะไม่มี parser ให้ถอด uuid/major/minor รายเฟรม ส่วน
/// iOS ไม่มีข้อจำกัดนั้นเพราะ `CLBeacon` ให้ครบสามค่าทุกเฟรมอยู่แล้ว
///
/// **pure function ล้วน** — ทดสอบได้โดยไม่ต้องมีอุปกรณ์
public enum ProximityKeyCodec {
  /// ตัวคั่นระหว่างส่วนของ key — ประกาศไว้ที่เดียวเพื่อไม่ให้มีสตริง `"|"` ลอย
  /// อยู่หลายที่แล้ว drift กัน
  public static let separator: Character = "|"

  public static func key(
    regionIdentifier: String,
    uuid: String,
    major: UInt16,
    minor: UInt16
  ) -> String {
    return "\(regionIdentifier)\(separator)\(uuid.lowercased())\(separator)\(major)\(separator)\(minor)"
  }

  /// ผลของการถอด key กลับ — `nil` ทั้งก้อนเมื่อรูปแบบไม่ตรง (ห้ามเดาค่าแทน)
  public struct Parsed: Equatable {
    public let regionIdentifier: String
    public let uuid: String
    public let major: UInt16
    public let minor: UInt16
  }

  /// ถอด key กลับเป็นสามค่าของ iBeacon + regionIdentifier
  ///
  /// **ตัดจากท้ายไม่ใช่จากหัว** เพราะ `regionIdentifier` เป็นสตริงที่ host app ตั้ง
  /// เองได้อิสระ (ADR-8 ใช้เป็นรหัสสาขา) จึงมีตัว `|` ปนได้ ส่วนสามส่วนท้าย
  /// (uuid/major/minor) มีรูปแบบตายตัวเสมอ — ถ้าตัดจากหัว key ของ region ที่ชื่อมี
  /// `|` จะถอดผิดเงียบ ๆ
  public static func parse(_ key: String) -> Parsed? {
    let parts = key.split(separator: separator, omittingEmptySubsequences: false)
    guard parts.count >= 4 else { return nil }
    guard let minor = UInt16(parts[parts.count - 1]),
      let major = UInt16(parts[parts.count - 2])
    else { return nil }
    let uuid = String(parts[parts.count - 3])
    let regionIdentifier = parts[0..<(parts.count - 3)]
      .map(String.init)
      .joined(separator: String(separator))
    return Parsed(
      regionIdentifier: regionIdentifier,
      uuid: uuid,
      major: major,
      minor: minor
    )
  }
}

/// ชั้นตัดสินใจ "ใกล้พอหรือยัง" ฝั่ง Swift — **port ตรงจาก
/// `packages/beacon_kit/lib/src/proximity/proximity_gate.dart`** เฉพาะ**เส้นทาง
/// Apple bucket** ตาม ADR-21 หัวข้อ 2 (ห้ามแก้ฝั่ง Dart ซึ่งเป็น reference)
///
/// ## pure Swift ล้วน — ห้าม `import CoreLocation` และห้ามเรียก `Date()` ในไฟล์นี้
///
/// ไม่มี I/O ไม่แตะ BLE/CoreLocation API ไม่มี `Timer` ในตัวเอง และ**ไม่เรียก
/// นาฬิกาของระบบเอง** ([clock] ต้องฉีดเข้ามาเสมอ) เหตุผลเดียวกับฝั่ง Dart/Kotlin:
/// เทสต์ต้องคุมเวลาได้แบบ deterministic โดยไม่ต้องมีอุปกรณ์จริง — ถ้าไฟล์นี้เผลอ
/// เรียก `Date()` แม้ตัวเดียว เทสต์ stale ทั้งชุดจะเขียนไม่ได้และกลายเป็น Track B
/// ทันที การเก็บสถานะลงดิสก์เป็นหน้าที่ของ `ProximityGateStore` คนละไฟล์
///
/// ## สิ่งที่ **ตั้งใจไม่ port** มาจากฝั่ง Dart
///
/// เส้นทาง median/เมตร (`estimateDistanceMeters` + `_classify` + hysteresis
/// `enterMeters`/`exitMeters`/`immediateMeters`) **ไม่มีในไฟล์นี้** เพราะ iOS ตอน
/// ranging ได้ `source == osDecoded` ซึ่ง `ibeaconTxPower` เป็น `null` เสมอ
/// (`beacon_advertisement.dart:120`) จึงไม่มีวัตถุดิบให้คำนวณ path-loss เลย —
/// ตรงข้ามกับฝั่ง Kotlin ที่ตัดเส้นทาง Apple bucket ทิ้งเพราะ Android ไม่มี bucket
/// ให้ **ทั้งสองภาษาต้องเท่ากับ Dart ไม่ใช่เท่ากับกันเอง** (ADR-21 หัวข้อ 2)
///
/// ## ค่า default = ตาราง ADR-19 หัวข้อ 8 เป๊ะ
///
/// `windowSize = 5` · `dwellSamples = 3` · `staleAfter = 10 วินาที` —
/// **ห้ามยืม 60 วินาทีของ ADR-20 หัวข้อ 7** ซึ่งคำนวณจากอัตรา batch ที่วัดได้จริง
/// ของเส้นทางเบื้องหลัง Android ส่วน iOS ยังไม่มีไฟล์ข้อมูลแม้แต่ไฟล์เดียว การยืม
/// มาใช้คือการเดา (ADR-21 หัวข้อ 4) — เป็นค่า **POC เท่านั้น ยังไม่ calibrate**
public final class ProximityGate {
  /// - Parameters:
  ///   - clock: แหล่งเวลา (epoch millis) — **ฉีดเข้ามาเสมอ ไม่มี default**
  ///     ผู้เรียกจริงส่งนาฬิกาของระบบเข้ามา เทสต์ส่งนาฬิกาปลอม
  ///   - windowSize: จำนวน bucket สูงสุดในหน้าต่างที่ใช้หา mode ต่อ key
  ///   - dwellSamples: จำนวน sample ติดกันขั้นต่ำก่อนยืนยัน bucket ที่ "ใกล้กว่า"
  ///   - staleAfterMillis: เงียบเกินกี่มิลลิวินาทีถึงถือว่า "วัดไม่ได้อีกแล้ว"
  public init(
    clock: @escaping () -> Int64,
    windowSize: Int = 5,
    dwellSamples: Int = 3,
    staleAfterMillis: Int64 = 10_000
  ) {
    self.clock = clock
    self.windowSize = windowSize
    self.dwellSamples = dwellSamples
    self.staleAfterMillis = staleAfterMillis
  }

  public let clock: () -> Int64
  public let windowSize: Int
  public let dwellSamples: Int
  public let staleAfterMillis: Int64

  private var states: [String: ProximityKeyState] = [:]

  /// ลำดับการเห็น key ครั้งแรก — ดู kdoc ของ [ProximityKeyEntry] ว่าทำไมต้องเก็บ
  /// ลำดับแยกแทนการพึ่งลำดับของ `Dictionary`
  private var keyOrder: [String] = []

  /// bucket ที่ยืนยันแล้วของ [key] — `nil` เมื่อไม่มี state (ไม่เคย push หรือหลุด
  /// stale ไปแล้ว) หรือมี state แต่ยังไม่เคยยืนยัน bucket ใดเลย
  ///
  /// **ไม่มีวันคืนค่าที่แปลว่า `unknown`** (invariant ของ ADR-19 หัวข้อ 6(ช)) —
  /// ที่นี่บังคับด้วยชนิดข้อมูลตั้งแต่แรกเพราะ [ProximityBucket] ไม่มี case นั้น
  public func currentBucket(key: String) -> ProximityBucket? {
    return states[key]?.confirmedBucket
  }

  /// state ดิบของ [key] — สำหรับ `ProximityGateStore` และเทสต์เท่านั้น
  public func stateOf(key: String) -> ProximityKeyState? {
    return states[key]
  }

  /// สถานะของทุก key ณ ตอนนี้ เรียงตามลำดับที่เห็น key ครั้งแรก —
  /// `ProximityGateStore` เอาไป serialize ลงดิสก์ทุกครั้งที่จบ batch
  public func snapshotStates() -> [ProximityKeyEntry] {
    return keyOrder.compactMap { key in
      guard let state = states[key] else { return nil }
      return ProximityKeyEntry(key: key, state: state)
    }
  }

  /// เขียนทับสถานะทั้งหมดด้วยของที่กู้มาจากดิสก์ — **ต้องเรียกก่อน [push] เสมอ**
  /// ไม่งั้น dwell จะเริ่มนับหนึ่งใหม่ทุกครั้งที่ระบบสร้าง process ใหม่ แล้ว
  /// `dwellSamples = 3` จะไม่มีวันครบ (ADR-21 หัวข้อ 3)
  public func restoreStates(_ restored: [ProximityKeyEntry]) {
    states.removeAll()
    keyOrder.removeAll()
    for entry in restored {
      setState(entry.state, for: entry.key)
    }
  }

  /// ลบ state ของทุก key ที่ขึ้นต้นด้วย [prefix] ทิ้งจากหน่วยความจำ
  ///
  /// มีไว้ให้ `stopMonitoring(identifiers:)` ล้างสถานะชั้น 2 ของ region ที่เลิก
  /// เฝ้าแล้ว (ADR-21 หัวข้อ 7 ข้อ 2 — หนี้ที่ฝั่ง Android ยังค้างอยู่ **iOS ต้อง
  /// ไม่ทำซ้ำ**) ถ้าไม่ล้าง แล้ววันหนึ่ง region identifier เดิมถูกลงทะเบียนใหม่
  /// dwell/หน้าต่างเก่าจากคนละรอบการเฝ้าจะถูกนำมาสานต่อทันทีเหมือนข้อมูลต่อเนื่อง
  /// ซึ่งเป็นบั๊กชนิดเดียวกับที่กฎ stale ของ ADR-19 6(ฉ) มีไว้ป้องกัน
  public func removeStates(matchingPrefix prefix: String) {
    // ผลลัพธ์ถูกทิ้งโดยตั้งใจ: `emitting: nil` แปลว่า "ล้างเงียบ ๆ" อยู่แล้ว จึงไม่มี
    // transition ให้ทิ้งตั้งแต่แรก (ดู [clearStates(matchingPrefix:emitting:)])
    _ = clearStates(matchingPrefix: prefix, emitting: nil)
  }

  /// ล้าง state ของทุก key ที่ขึ้นต้นด้วย [prefix] **พร้อมประกาศ transition** ให้ทุก
  /// key ที่ **เคย confirm bucket มาก่อน** — key ที่ยังค้าง dwell อยู่ถูกล้าง**เงียบ ๆ**
  /// ไม่มี transition (หลักการเดียวกับ [sweepStale] เป๊ะ: ไม่เคยประกาศว่า "ใกล้"
  /// ก็ไม่มีอะไรให้ประกาศว่า "หลุด")
  ///
  /// ผู้เรียกจริงมีรายเดียวคือ `IBeaconRangingManager.didExitRegion` ด้วย
  /// [ProximityTransitionReason.regionExit] — **อ่าน kdoc ของ case นั้นก่อนใช้ที่อื่น**
  /// เพราะมันเป็น reason ที่มีเฉพาะฝั่ง Swift (เบี่ยงจาก reference โดยตั้งใจ)
  ///
  /// คืน transition เรียงตามลำดับที่เห็น key ครั้งแรก เหมือน [sweepStale]
  public func clearStates(
    matchingPrefix prefix: String,
    emitting reason: ProximityTransitionReason
  ) -> [ProximityTransition] {
    return clearStates(matchingPrefix: prefix, emitting: Optional(reason))
  }

  /// - Parameter reason: `nil` = ล้างเงียบ ๆ ไม่คืน transition ใด ๆ เลย
  private func clearStates(
    matchingPrefix prefix: String,
    emitting reason: ProximityTransitionReason?
  ) -> [ProximityTransition] {
    let removed = keyOrder.filter { $0.hasPrefix(prefix) }
    guard !removed.isEmpty else { return [] }

    var transitions: [ProximityTransition] = []
    for key in removed {
      let state = states.removeValue(forKey: key)
      guard let reason = reason, let hadConfirmed = state?.confirmedBucket else { continue }
      transitions.append(
        ProximityTransition(
          key: key,
          from: hadConfirmed,
          to: nil,
          reason: reason,
          medianMeters: nil
        )
      )
    }
    keyOrder.removeAll { $0.hasPrefix(prefix) }
    return transitions
  }

  /// ป้อน sample หนึ่งตัวของ [key] — คืน [ProximityTransition] **เฉพาะตอน bucket
  /// ที่ยืนยันแล้วเปลี่ยนจริง** มิฉะนั้น `nil`
  ///
  /// - Parameter bucket: bucket ที่ OS ถอดให้แล้ว · **`nil` = `CLProximity.unknown`**
  ///   ("The proximity of the beacon could not be determined" — คำต่อคำจาก Apple)
  ///   ซึ่งแปลว่า **"วัดไม่ได้" ไม่ใช่ "ไกล"** (ADR-19 หัวข้อ 6(ง)) ผู้เรียกต้อง
  ///   ส่งค่าตามจริง **ห้ามแปลง `unknown` เป็น `.far` ที่ฝั่งผู้เรียกเด็ดขาด**
  ///
  /// ลำดับการตัดสินตรงกับ `ProximityGate.push` ฝั่ง Dart เป๊ะ:
  /// 1. อ่าน [clock] ครั้งเดียว
  /// 2. เช็ค stale **ก่อนอย่างอื่นทั้งหมด** — ถ้าหลุด stale และเคยมี confirmed
  ///    bucket จะคืน transition ทันทีโดย**ทิ้ง sample ของรอบนี้** (ดูคอมเมนต์ในตัว)
  /// 3. `bucket == nil` (`unknown`) → ทิ้ง sample **ไม่แตะ state เลยแม้แต่ฟิลด์เดียว**
  /// 4. ใส่ลงหน้าต่าง -> หา mode (เสมอกันเลือกตัวที่ไกลกว่า) -> dwell
  public func push(key: String, bucket: ProximityBucket?) -> ProximityTransition? {
    let now = clock()
    let existing = states[key]

    // ---- stale ก่อนอื่นทั้งหมด (ADR-19 หัวข้อ 6(ฉ)) ----
    // ใช้ clock() ไม่ใช่ `CLBeacon.timestamp` เพราะความเงียบที่ต้องจับคือ "ไม่มี
    // push() เข้ามานานแค่ไหนตามเวลาจริงที่ gate ประมวลผล"
    var state = existing
    if let existing = existing, isStale(existing, now: now) {
      // รีเซ็ต **ทุกฟิลด์** ไม่ใช่แค่ confirmed — key ที่ค้าง dwell อยู่แล้วหายไป
      // นาน ต้องไม่กลับมาสานต่อ dwell เดิมเหมือนข้อมูลต่อเนื่องกัน (ADR-19 6(ฉ))
      let fresh = ProximityKeyState()
      setState(fresh, for: key)
      state = fresh
      if let hadConfirmed = existing.confirmedBucket {
        // ทิ้ง sample ของรอบนี้ไปพร้อมกับ transition นี้โดยตั้งใจ — push() คืนได้
        // ทีละ 1 transition sample ที่จุดชนวน stale จะถูกประมวลผลใหม่ในรอบถัดไป
        // ด้วย state ที่รีเซ็ตแล้ว (ตรงกับฝั่ง Dart/Kotlin)
        return ProximityTransition(
          key: key,
          from: hadConfirmed,
          to: nil,
          reason: .stale,
          medianMeters: nil
        )
      }
      // ไม่เคย confirm มาก่อน (แค่ค้าง dwell ตอนหายไป) — ไม่มีอะไรให้ประกาศว่าหลุด
      // ใช้ sample ของรอบนี้เริ่ม state ใหม่ต่อได้เลยในรอบเดียวกันนี้
    }

    guard let bucket = bucket else {
      // ADR-19 หัวข้อ 6(ง) + ADR-21 หัวข้อ 2: `unknown` = "วัดไม่ได้" ต้องทิ้ง
      // sample ทั้งหมด **ห้ามแตะ state ใด ๆ เลยแม้แต่ `lastSampleAt`** (sample นี้
      // ไม่ได้ยืนยันอะไรเลย การขยับ lastSampleAt จะเป็นการต่ออายุ freshness ปลอม ๆ
      // ให้ bucket ที่ยืนยันอยู่ก่อนหน้า จนบีคอนที่เงียบสนิทไม่มีวันหลุด stale)
      //
      // ต่างจากฝั่ง Dart ตรงที่นี่ไม่สร้าง entry เปล่าให้ key ที่ยังไม่มี state
      // (Dart สร้างก่อนเช็ค unknown) — ผลลัพธ์ที่สังเกตได้จากภายนอกเหมือนกันทุกทาง
      // เพราะ entry เปล่านั้นไม่มีผลต่อการตัดสินใจใด ๆ เลย และ ADR-19 หัวข้อ 7 เอง
      // บันทึกไว้ว่า entry เปล่าคือขยะที่ต้องมี eviction ในอนาคต
      return nil
    }

    var current = state ?? ProximityKeyState()
    current.window.append(bucket)
    if current.window.count > windowSize {
      current.window.removeFirst(current.window.count - windowSize)
    }
    current.lastSampleAt = now

    // ADR-19 หัวข้อ 4 ข้อ 1: mode ของหน้าต่าง ไม่ใช่ค่าล่าสุดตรง ๆ
    let candidate = Self.bucketCandidate(window: current.window)

    return applyDwell(key: key, state: current, candidate: candidate)
  }

  /// ตรวจทุก key ว่าเงียบเกิน [staleAfterMillis] แล้วหรือยัง **โดยไม่ต้องรอ sample
  /// ใหม่** — จำเป็นเพราะเคสหลักคือ "ลูกค้าเดินออกจากร้าน" ซึ่งแปลว่าไม่มี sample
  /// ให้ [push] จับความเงียบได้เองอีกเลย
  ///
  /// **ไม่มี `Timer` ในตัวเอง** (ADR-19 6(ฌ) · ADR-21 หัวข้อ 4) — ผู้เรียกฝั่ง iOS
  /// คือ `IBeaconRangingManager` ตอนที่ CoreLocation เรียก `didRange` หรือ
  /// `didFailRangingFor` เข้ามา **ไม่ใช่ timer** ผลที่ต้องยอมรับเหมือนฝั่ง Android:
  /// stale ถูกค้นพบตอน callback ถัดไป ไม่ใช่ที่วินาทีที่ 10 พอดี
  ///
  /// คืน transition ของทุก key ที่เพิ่งหลุดในการเรียกครั้งนี้ เรียงตามลำดับที่เห็น
  /// key ครั้งแรก — key ที่ยังไม่เคยยืนยัน bucket ใดถูกล้าง state เงียบ ๆ โดยไม่มี
  /// transition (ไม่มีอะไรให้ประกาศว่าหลุด)
  public func sweepStale() -> [ProximityTransition] {
    let now = clock()
    var transitions: [ProximityTransition] = []

    for key in keyOrder {
      guard let state = states[key], isStale(state, now: now) else { continue }
      setState(ProximityKeyState(), for: key)
      guard let hadConfirmed = state.confirmedBucket else { continue }
      transitions.append(
        ProximityTransition(
          key: key,
          from: hadConfirmed,
          to: nil,
          reason: .stale,
          medianMeters: nil
        )
      )
    }

    return transitions
  }

  // MARK: - ภายใน

  /// เงียบเกิน [staleAfterMillis] แล้วหรือยัง — `lastSampleAt == nil` (ยังไม่เคยมี
  /// sample ที่ใช้ตัดสินได้เลย) ถือว่า **ยังไม่ stale** ตรงกับ `_resetIfStale`
  /// ฝั่ง Dart ที่คืน `null` ทันทีในกรณีนั้น
  private func isStale(_ state: ProximityKeyState, now: Int64) -> Bool {
    guard let lastSampleAt = state.lastSampleAt else { return false }
    return now - lastSampleAt > staleAfterMillis
  }

  private func setState(_ state: ProximityKeyState, for key: String) {
    if states[key] == nil {
      keyOrder.append(key)
    }
    states[key] = state
  }

  /// หา candidate จากหน้าต่าง bucket ดิบของ Apple ด้วย **mode** (ค่าที่พบบ่อยที่สุด)
  /// — **ถ้าเสมอกันเลือกตัวที่ไกลกว่า** port ตรงจาก `_appleBucketCandidate` ของ
  /// `proximity_gate.dart`
  ///
  /// **เหตุผล (ADR-19 หัวข้อ 4 ข้อ 1, แก้บั๊กจากรอบ implement แรกฝั่ง Dart):**
  /// การใช้ bucket ของ Apple ตรง ๆ โดยไม่ smoothing ทำให้เส้นทางนี้ไม่มี hysteresis
  /// เลย ผสมกับกฎ "ไกลขึ้นไม่ต้อง dwell" (6(ค)) ทำให้ Apple ส่ง `far` มาครั้งเดียว
  /// ก็หลุดจาก `near` ทันที แล้วอีกไม่กี่ sample กลับเข้า `near` ใหม่ วนซ้ำได้ทุก
  /// ไม่กี่วินาที — mode ของหน้าต่างทำให้ outlier ครั้งเดียวไม่มีน้ำหนักพอเปลี่ยน
  /// candidate ส่วนการเลือก "ไกลกว่า" ตอนเสมอกันสอดคล้องกับต้นทุนไม่สมมาตรของ 6(ค)
  /// (การประกาศ "ใกล้" ผิดพลาดแพงกว่า จึงไม่ควรชนะเมื่อข้อมูลก้ำกึ่งพอ ๆ กัน)
  ///
  /// **pure + `internal`** เพื่อให้ XCTest ตรวจตารางการตัดสินนี้ได้ตรง ๆ
  internal static func bucketCandidate(window: [ProximityBucket]) -> ProximityBucket {
    var counts: [ProximityBucket: Int] = [:]
    for bucket in window {
      counts[bucket, default: 0] += 1
    }

    var best: ProximityBucket?
    var bestCount = -1
    // วนตาม `allCases` (immediate -> near -> far) ไม่ใช่ตามลำดับของ Dictionary
    // เพราะลำดับของ Dictionary ใน Swift ไม่คงที่ — ผลลัพธ์ต้องเท่ากันทุกครั้งที่รัน
    for bucket in ProximityBucket.allCases {
      guard let count = counts[bucket] else { continue }
      let isMoreFrequent = count > bestCount
      let isTieButFarther =
        count == bestCount && best != nil && rankOfBucket(bucket) > rankOfBucket(best!)
      if isMoreFrequent || isTieButFarther {
        best = bucket
        bestCount = count
      }
    }

    // หน้าต่างมี sample อย่างน้อย 1 ตัวเสมอตอนฟังก์ชันนี้ถูกเรียกจาก push()
    // (เพิ่งใส่เข้าไปก่อนเรียก) — สาขานี้จึงไปไม่ถึงในทางปฏิบัติ เลือก `.far`
    // แทนการ crash เพราะ `.far` คือค่าที่ปลอดภัยที่สุดตามต้นทุนไม่สมมาตรของ 6(ค)
    // (ฝั่ง Dart ใช้ `best!` ได้เพราะเป็น private ล้วน ส่วนที่นี่ `internal` จึงมี
    // ทางถูกเรียกจากเทสต์ด้วยหน้าต่างว่าง)
    return best ?? .far
  }

  /// บังคับ dwell (ADR-19 หัวข้อ 6(ค)) — candidate ที่ **ใกล้กว่า** ต้องผ่านเกณฑ์
  /// ติดกัน ≥ [dwellSamples] ก่อนยืนยัน ส่วน candidate ที่ **ไกลกว่า** ยืนยันทันที
  ///
  /// **sample แรกของ key ใช้ baseline เท่ากับ [ProximityBucket.far]** (ไม่ใช่ "ต้อง
  /// dwell เสมอ") — candidate แรกที่เป็น far จึงยืนยันได้ทันที ส่วน near/immediate
  /// ยังต้อง dwell ตรงกับฝั่ง Dart และ ADR-19 หัวข้อ 6(ซ)
  ///
  /// ฟังก์ชันนี้เป็นคนเขียน state กลับลงแผนที่เสมอทุกสาขา (ผู้เรียกส่ง state ที่
  /// อัปเดต window/lastSampleAt มาแล้วแต่ยังไม่ได้บันทึก)
  private func applyDwell(
    key: String,
    state: ProximityKeyState,
    candidate: ProximityBucket
  ) -> ProximityTransition? {
    var next = state
    let current = state.confirmedBucket

    if current == candidate {
      next.pendingCloserBucket = nil
      next.pendingCloserCount = 0
      setState(next, for: key)
      return nil
    }

    let baselineRank = current != nil ? rankOfBucket(current!) : rankOfBucket(.far)
    let becomingCloser = rankOfBucket(candidate) < baselineRank

    if !becomingCloser {
      next.pendingCloserBucket = nil
      next.pendingCloserCount = 0
      next.confirmedBucket = candidate
      setState(next, for: key)
      return ProximityTransition(
        key: key,
        from: current,
        to: candidate,
        reason: .farther,
        // เส้นทาง Apple bucket ไม่มีระยะเป็นเมตรให้รายงาน (ADR-21 หัวข้อ 2)
        medianMeters: nil
      )
    }

    let pendingCount = state.pendingCloserBucket == candidate ? state.pendingCloserCount + 1 : 1

    if pendingCount < dwellSamples {
      next.pendingCloserBucket = candidate
      next.pendingCloserCount = pendingCount
      setState(next, for: key)
      return nil
    }

    next.pendingCloserBucket = nil
    next.pendingCloserCount = 0
    next.confirmedBucket = candidate
    setState(next, for: key)
    return ProximityTransition(
      key: key,
      from: current,
      to: candidate,
      reason: .closer,
      medianMeters: nil
    )
  }
}
