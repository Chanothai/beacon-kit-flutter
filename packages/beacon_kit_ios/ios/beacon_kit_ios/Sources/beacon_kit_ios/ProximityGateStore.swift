import Foundation

/// สถานะของ [ProximityGate] ทุก key ที่ต้องรอดข้าม process — เก็บลง `UserDefaults`
/// เป็น JSON ตาม **ADR-21 หัวข้อ 3**
///
/// ## ทำไมต้องเขียนลงดิสก์ ไม่ใช่เก็บใน memory อย่างเดียว
///
/// iOS ฆ่าและ relaunch process เหมือน Android: เส้นทางที่ ADR-21 มีอยู่เพื่อรองรับ
/// คือ "แอปถูกปลุกด้วย region event แล้วมีเวลาไม่กี่สิบวินาที" ซึ่งแปลว่า process
/// เกิดใหม่บ่อยมาก ถ้าหน้าต่าง/ตัวนับ dwell อยู่ใน memory อย่างเดียว ทุกอย่างจะ
/// รีเซ็ตทุกครั้งที่ถูกปลุก แล้ว `dwellSamples = 3` **จะไม่มีวันครบ** — gate เงียบ
/// ตลอดทั้งที่ผู้ใช้ยืนอยู่หน้าชั้นวาง (เหตุผลเดียวกับ ADR-20 หัวข้อ 3)
///
/// ## ไฟล์ (suite) แยกจากค่าอื่นของแอปโดยตั้งใจ
///
/// ใช้ `UserDefaults(suiteName:)` แยกโดเมนของตัวเอง ไม่ปนกับ `.standard` ของ host
/// app ด้วยเหตุผลเดียวกับที่ฝั่ง Android แยกไฟล์ prefs ของชั้น 2 ออกจาก
/// `BackgroundRegionStore`: (ก) ข้อมูลชั้น 2 ที่เสียหายลากค่าของ host app หรือของ
/// ชั้น 1 ลงไปด้วยไม่ได้ (ข) ล้างสถานะ POC ทิ้งได้โดยไม่แตะอย่างอื่น
///
/// ## ความล้มเหลวต้องมีร่องรอย ตั้งแต่คอมมิตแรก (ADR-21 หัวข้อ 7 ข้อ 2)
///
/// "เริ่มนับใหม่" เป็นคำตอบที่ถูกกับความเสียหาย**ชั่วคราว**เท่านั้น ถ้าเขียนไม่ได้
/// ทุกครั้งจริง ๆ อาการที่ออกมาคือ dwell เริ่มนับหนึ่งใหม่ทุกรอบ → `dwellSamples`
/// ไม่มีวันครบ → gate เงียบตลอด ซึ่ง **แยกไม่ออกจาก "ไม่มีบีคอนอยู่ใกล้" และ
/// "แอปไม่เคยถูกปลุก"** เลยจากไฟล์หลักฐาน — รอบ Android เสียเวลาสอบสวนทั้งรอบเพราะ
/// เรื่องนี้ (`android_background_scanning.md` ข้อ B) และต้องไปเพิ่ม `lastError`
/// ทีหลัง **iOS จึงมีตั้งแต่คอมมิตแรก**
///
/// [lastError] เก็บเป็นข้อความให้ผู้เรียกเอาไปเขียนลงไฟล์หลักฐานเอง แทนการ log
/// เองที่นี่ — คลาสนี้ไม่ควรตัดสินใจแทน host app ว่าร่องรอยต้องไปอยู่ที่ไหน
public final class ProximityGateStore {
  /// suite ของตัวเอง — ไม่ใช่ `UserDefaults.standard` (ดู kdoc ของคลาส)
  public static let suiteName = "com.bigc.beacon_kit_ios.proximity"

  /// ทั้งชุดอยู่ในคีย์เดียว — เขียนครั้งเดียวจบ ไม่มีสถานะเหลือครึ่ง ๆ
  private static let statesKey = "states"

  /// JSON ของ "ไม่มี key เลยจริง ๆ" — ต่างจาก "อ่านแล้วถอดไม่ออก" (ดู [load])
  private static let emptyJson = "[]"

  private static let fieldKey = "key"
  private static let fieldConfirmed = "confirmedBucket"
  private static let fieldPendingBucket = "pendingCloserBucket"
  private static let fieldPendingCount = "pendingCloserCount"
  private static let fieldWindow = "window"
  private static let fieldLastSampleAt = "lastSampleAt"

  private let defaults: UserDefaults

  /// - Parameter defaults: ฉีดเข้ามาได้เพื่อให้เทสต์ใช้ suite ชั่วคราวของตัวเอง —
  ///   โค้ดจริงไม่ต้องส่ง
  public init(defaults: UserDefaults? = nil) {
    if let defaults = defaults {
      self.defaults = defaults
    } else if let suite = UserDefaults(suiteName: Self.suiteName) {
      self.defaults = suite
    } else {
      // ตามเอกสารของ `init?(suiteName:)` ค่านี้เป็น nil ได้เมื่อชื่อ suite ใช้ไม่ได้
      // — ถอยไปใช้ `.standard` ดีกว่าไม่มีที่เก็บเลย (state หายทุกครั้ง = dwell ไม่
      // มีวันครบ) แต่ **ต้องมีร่องรอย** ไม่ใช่ถอยเงียบ ๆ
      self.defaults = .standard
      self.lastError = "init:suite-unavailable"
    }
  }

  /// เหตุผลของความล้มเหลวล่าสุดของ [load]/[save] — `nil` แปลว่ารอบล่าสุดไม่มีปัญหา
  ///
  /// ผู้เรียก (`IBeaconRangingManager`) อ่านค่านี้**หลัง** `save()` ของแต่ละ batch
  /// เพื่อให้ครอบทั้งความล้มเหลวของ load และ save ในรอบเดียวกัน แล้วแนบไปกับ event
  /// ให้ host app เขียนลงไฟล์หลักฐาน (`store=` ในบรรทัด `event=proximity`)
  public private(set) var lastError: String?

  /// ล้าง [lastError] ก่อนเริ่ม batch ใหม่
  ///
  /// จำเป็นเพราะฝั่ง iOS instance ของ store **มีอายุยาวเท่ากับ process** (ต่างจาก
  /// ฝั่ง Android ที่สร้างใหม่ทุก `onReceive`) ถ้าไม่ล้าง error จากรอบเมื่อชั่วโมง
  /// ที่แล้วจะติดค้างอยู่ในบรรทัดหลักฐานของรอบที่ไม่มีปัญหาอะไรเลย
  public func resetLastError() {
    lastError = nil
  }

  /// อ่านสถานะทุก key ที่เก็บไว้ — **คืน array ว่างเมื่ออ่านไม่สำเร็จ** (เท่ากับ
  /// "เริ่มนับใหม่") พร้อมตั้ง [lastError] ไว้เสมอ ห้ามเงียบ
  ///
  /// แยก "ไม่มีอะไรเก็บไว้" (ไม่มีค่าในคีย์เลย หรือเป็น `[]`) ออกจาก "เก็บไว้จริง
  /// แต่ถอดไม่ออก" — ความต่างเดียวกับ `[]` vs `<read-failed:...>` ของ ADR-17
  public func load() -> [ProximityKeyEntry] {
    guard let raw = defaults.string(forKey: Self.statesKey) else { return [] }
    let entries = Self.entriesFromJson(raw)
    if entries.isEmpty && raw != Self.emptyJson {
      lastError = "load:unparsable(\(raw.utf8.count)B)"
    }
    return entries
  }

  /// เขียนทับสถานะทั้งหมดในครั้งเดียว
  ///
  /// **ไม่เรียก `synchronize()`** — Apple ระบุเองว่าเมธอดนั้น "is unnecessary and
  /// shouldn't be used" เพราะระบบซิงก์ให้เป็นระยะอยู่แล้ว (ต่างจากฝั่ง Android ที่
  /// `apply()` vs `commit()` เป็นความต่างที่จับต้องได้จริง) ผลที่ต้องยอมรับคือมี
  /// ช่องเวลาสั้น ๆ ที่ค่าล่าสุดยังไม่ลงดิสก์ถ้าระบบฆ่า process ทันที — **ถ้ารอบ
  /// ทดสอบเครื่องจริงพบว่า dwell ไม่มีวันครบเพราะ state หายข้าม process ให้กลับมา
  /// ทบทวนข้อนี้เป็นอันดับแรก** และบันทึกผลไว้ใน ADR-21 (ยังไม่มีข้อมูลภาคสนาม
  /// ตอนเขียน จึงไม่เดาไปก่อน)
  public func save(_ entries: [ProximityKeyEntry]) {
    guard let json = Self.entriesToJson(entries) else {
      lastError = "save:serialize-failed"
      return
    }
    defaults.set(json, forKey: Self.statesKey)
  }

  /// ลบสถานะของทุก key ที่ขึ้นต้นด้วย [prefix] ออกจากดิสก์
  ///
  /// เรียกจาก `stopMonitoring(identifiers:)` ของ SDK ตาม **ADR-21 หัวข้อ 7 ข้อ 2**
  /// (ฝั่ง Android ยังเป็นหนี้ค้างเพราะต้องแก้ที่ example app — iOS ต้องไม่ทำซ้ำ)
  public func removeStates(matchingPrefix prefix: String) {
    let remaining = load().filter { !$0.key.hasPrefix(prefix) }
    save(remaining)
  }

  /// ล้างทุกอย่าง — สำหรับเวลาไล่บั๊กในสนาม
  public func clear() {
    defaults.removeObject(forKey: Self.statesKey)
  }

  // MARK: - JSON (pure — มี XCTest คลุมได้โดยไม่ต้องมี UserDefaults จริง)

  /// แปลงสถานะเป็น JSON — **pure function**
  ///
  /// เก็บเป็น **array ไม่ใช่ object** เพราะลำดับของ key ต้องรอดข้าม process ด้วย
  /// (`JSONSerialization` ไม่รับประกันลำดับคีย์ของ object และ `Dictionary` ของ
  /// Swift ก็ไม่รับประกัน) — เหตุผลเดียวกับที่ [ProximityKeyEntry] มีตัวตน
  ///
  /// bucket เขียนด้วย [ProximityBucket.wireName] ไม่ใช่ index ของ enum — index จะ
  /// เปลี่ยนความหมายเงียบ ๆ ถ้ามีใครเพิ่ม/สลับ case วันหลัง แล้วสถานะที่ค้างอยู่บน
  /// เครื่องผู้ใช้จะถูกอ่านผิดโดยไม่มีอะไรฟ้อง
  internal static func entriesToJson(_ entries: [ProximityKeyEntry]) -> String? {
    var root: [[String: Any]] = []
    for entry in entries {
      var object: [String: Any] = [
        fieldKey: entry.key,
        fieldPendingCount: entry.state.pendingCloserCount,
        // เขียนตามลำดับเดิมของหน้าต่าง — ลำดับคือข้อมูล ไม่ใช่แค่ที่เก็บ
        // (ตัวใหม่สุดต้องอยู่ท้ายเสมอ ไม่งั้นการตัดหัวรอบหน้าจะตัดผิดตัว)
        fieldWindow: entry.state.window.map { $0.wireName },
      ]
      // คีย์ที่ไม่มีค่า = **ไม่เขียนคีย์นั้นเลย** (ไม่ใช่ `NSNull`) ตอนอ่านกลับจึง
      // ได้ `nil` ตรงตามความหมายที่ต้องการพอดี และ payload เล็กลงด้วย
      if let confirmed = entry.state.confirmedBucket {
        object[fieldConfirmed] = confirmed.wireName
      }
      if let pending = entry.state.pendingCloserBucket {
        object[fieldPendingBucket] = pending.wireName
      }
      if let lastSampleAt = entry.state.lastSampleAt {
        object[fieldLastSampleAt] = NSNumber(value: lastSampleAt)
      }
      root.append(object)
    }

    guard JSONSerialization.isValidJSONObject(root),
      let data = try? JSONSerialization.data(withJSONObject: root),
      let json = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return json
  }

  /// ถอด JSON กลับเป็นสถานะ — **รายการที่ถอดไม่ออกถูกข้ามไปเงียบ ๆ ไม่ throw**
  ///
  /// ผลที่แย่ที่สุดคือ key นั้นเริ่มนับ dwell ใหม่ ซึ่งยอมรับได้กว่าการทำให้ทั้ง
  /// batch (รวมชั้น 1 ที่มีหลักฐานระดับ `observed` แล้ว) ล้มเพราะสถานะ POC เสียหาย
  /// ตัวเดียว — [load] เป็นคนตัดสินว่า "ว่างเพราะไม่มีอะไร" หรือ "ว่างเพราะถอดไม่ออก"
  internal static func entriesFromJson(_ raw: String) -> [ProximityKeyEntry] {
    guard let data = raw.data(using: .utf8),
      let root = try? JSONSerialization.jsonObject(with: data),
      let array = root as? [[String: Any]]
    else {
      return []
    }

    var entries: [ProximityKeyEntry] = []
    for object in array {
      guard let key = object[fieldKey] as? String else { continue }
      let window = (object[fieldWindow] as? [String] ?? [])
        .compactMap { ProximityBucket.fromWireName($0) }
      let state = ProximityKeyState(
        confirmedBucket: ProximityBucket.fromWireName(object[fieldConfirmed] as? String),
        pendingCloserBucket: ProximityBucket.fromWireName(object[fieldPendingBucket] as? String),
        pendingCloserCount: (object[fieldPendingCount] as? NSNumber)?.intValue ?? 0,
        window: window,
        lastSampleAt: (object[fieldLastSampleAt] as? NSNumber)?.int64Value
      )
      entries.append(ProximityKeyEntry(key: key, state: state))
    }
    return entries
  }
}
