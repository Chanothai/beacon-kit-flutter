import Foundation

/// ตัวเขียนไฟล์หลักฐานสำหรับ B5/B6 — **อยู่ใน example app เท่านั้น**
///
/// **ทำไมต้องเป็นโค้ด native ล้วน ไม่ผ่าน Dart (ADR-10):**
/// รอบทดสอบ B5 เมื่อ 30 ส.ค. 2026 ปัดแอปทิ้งจาก app switcher แล้วถอด/ใส่แบต
/// K9P ผลคือ **ไม่มีบรรทัดใน log เลยแม้แต่บรรทัดเดียว** ซึ่งตอนนั้นแยกไม่ออกว่า
/// "iOS ไม่ได้ปลุกแอปเลย" หรือ "ปลุกแล้วแต่ event ไปไม่ถึงคนเขียน log"
/// เพราะเส้นทาง log เดิมวิ่งผ่าน Dart ทั้งหมด (event channel -> `RegionEventLog`)
/// ซึ่งต้องมี Flutter engine ทำงานอยู่ก่อน — เงื่อนไขที่ไม่เป็นจริงตอน cold launch
/// เบื้องหลัง เครื่องมือวัดจึงตายพร้อมกับสิ่งที่มันควรวัด
///
/// ตัวนี้ไม่พึ่ง Flutter, ไม่พึ่ง Dart, ไม่พึ่ง path_provider — เขียนไฟล์ตรงจาก
/// Swift เท่านั้น จึงใช้ได้ทุกบริบทรวมถึงรอบ launch ที่ยังไม่มี UI
///
/// **ยังไม่ใช่หลักฐานว่า B5 ผ่าน** การมีเครื่องมือวัดที่ทำงานได้ กับการเห็นแอป
/// ฟื้นเองจริงบนอุปกรณ์จริง เป็นคนละเรื่องกัน
final class BackgroundEvidenceLog {
  static let shared = BackgroundEvidenceLog()

  static let fileName = "region_events.log"

  /// **ตัวระบุ process** — สุ่มใหม่ทุกครั้งที่ process เริ่ม เขียนลงทุกบรรทัด
  ///
  /// **ปัญหาที่ตัวนี้แก้ (ค้างมาตั้งแต่รอบเคส B1 ยังไม่เคยทำ):** ก่อนหน้านี้การ
  /// ตอบว่า "บรรทัดนี้มาจาก process ใหม่หรือ process เดิม" ทำได้ทางเดียวคือ
  /// **เดาจาก `uptime`** ที่อยู่ในคอลัมน์สัญญาณดิบ — ถ้า uptime น้อยก็เดาว่าเพิ่ง
  /// เริ่ม ซึ่งผิดได้สองทาง: process ที่รันมานานแล้วถูกปลุกอีกครั้งจะมี uptime สูง
  /// ทั้งที่ไม่ใช่ process ใหม่ และ process ใหม่ที่ระบบสร้างขึ้นแล้วส่ง event ช้า
  /// จะมี uptime สูงเช่นกัน
  ///
  /// ค่านี้ตอบได้แน่นอนโดยไม่ต้องเดา: **บรรทัดสองบรรทัดที่มี `processId` ต่างกัน
  /// มาจากคนละ process เสมอ** และ `processId` ที่ไม่เคยปรากฏในบรรทัดก่อนหน้าใน
  /// ไฟล์เดียวกัน = process ที่ถูกสร้างขึ้นมาใหม่
  ///
  /// ใช้ 8 ตัวอักษรแรกของ UUID พอ — ต้องอ่านด้วยตาบนหน้าจอมือถือระหว่างทดสอบ
  /// ไม่ได้ต้องการความเป็นเอกลักษณ์ระดับ global
  static let processId = String(UUID().uuidString.prefix(8)).lowercased()

  /// pid ของระบบปฏิบัติการสำหรับ process นี้
  ///
  /// **ไม่ใช่ตัวระบุ process** ระบบนำ pid กลับมาใช้ซ้ำได้หลัง process ตาย สอง
  /// บรรทัดที่ pid เท่ากันจึงอาจมาจากคนละ process — `processId` เท่านั้นที่ตอบ
  /// เรื่องนี้ได้ ค่านี้มีไว้เพื่อ **เทียบกับเครื่องมือของระบบ** (Console.app,
  /// `sysdiagnose`, log ของ CoreLocation) ตอนดีบัก ซึ่งเป็นสิ่งที่ `processId`
  /// ทำไม่ได้เพราะระบบไม่รู้จักมัน — เหตุผลเดียวกับ `pid` ฝั่ง Android
  static let pid = ProcessInfo.processInfo.processIdentifier

  /// **ตัวระบุ process ชุดมาตรฐาน — ต้องอยู่ต้นคอลัมน์สัญญาณดิบของทุกบรรทัด**
  ///
  /// รูปแบบตรงกับ `BackgroundEvidenceLog.processMarker` ฝั่ง Android เป๊ะ ทั้งชื่อ
  /// key ลำดับ และหน่วย:
  /// ```
  /// procUuid=<8 hex> pid=<os pid> uptimeMs=<ms> receiverEntry=<true|false>
  /// ```
  ///
  /// ## ทำไมต้องมีทั้งชุด ทั้งที่แต่ละตัวดูซ้ำกับที่อื่น
  ///
  /// คำถามที่รอบทดสอบต้องตอบคือ **"บรรทัดนี้มาจาก process ใหม่จริงหรือไม่"** ซึ่ง
  /// ก่อนหน้านี้ตอบได้ทางเดียวคือ **เดาจาก `uptime`** — ผิดได้ทั้งสองทาง
  ///
  /// - `procUuid` — **คำตอบที่ไม่ต้องเดา** ค่าต่างกัน = คนละ process เสมอ
  /// - `pid` — สะพานไปเครื่องมือของระบบ ซึ่งไม่รู้จัก `procUuid`
  /// - `uptimeMs` — อายุ process หน่วย **มิลลิวินาทีจำนวนเต็ม** ไม่ใช่วินาที
  ///   ทศนิยมแบบเดิม เพราะช่วงที่ต้องแยกให้ออกคือหลักร้อยมิลลิวินาที (event ที่
  ///   มาถึงทันทีหลัง process เกิด = ถูกปลุกเพื่อ event นั้น) ซึ่ง `%.1f` วินาที
  ///   ปัดทิ้งไปหมด
  /// - `receiverEntry` — บรรทัดนี้ถูกเขียนจากในโค้ดที่**ระบบเรียกเข้ามา**หรือไม่
  ///   ฝั่งนี้หมายถึง callback ของ `CLLocationManagerDelegate` (ฝั่ง Android คือ
  ///   `BroadcastReceiver.onReceive`) — คนละกลไก แต่ตอบคำถามเดียวกันคือ "บรรทัด
  ///   นี้เขียนจากเส้นทางที่ทำงานได้โดยไม่ต้องมี UI ใช่ไหม"
  ///
  /// ⚠️ `procUuid` **ซ้ำกับคอลัมน์ที่ 2 โดยตั้งใจ** และเป็นค่าเดียวกันเสมอ
  /// (มาจาก `processId` ตัวเดียวกัน จึงขัดแย้งกันไม่ได้) — คอลัมน์ที่ 2 ไว้ให้คน
  /// กวาดตาดูบนหน้าจอมือถือ ส่วน key นี้ไว้ให้เครื่องอ่านคู่กับ `pid`/`uptimeMs`
  /// ที่อยู่คอลัมน์เดียวกัน โดยไม่ต้องแยกคอลัมน์ก่อน ซึ่งจำเป็นตอน `grep` ไฟล์ดิบ
  /// **แทนที่คอมเมนต์เดิมที่ห้ามใส่ `processId` ลงสัญญาณดิบ** — ข้อกังวลตอนนั้นคือ
  /// regex จะเจอสองที่แล้วเลือกผิดตัว ซึ่งหมดไปเมื่อค่าทั้งสองมาจากแหล่งเดียวกัน
  /// และมีเทสต์ล็อกไว้ว่าต้องเท่ากัน
  ///
  /// [processId] และ [pid] รับเป็นพารามิเตอร์ที่มีค่า default เพื่อให้ XCTest
  /// ตรึงค่าได้ (เหตุผลเดียวกับ `line`) โค้ดจริงไม่ต้องส่ง
  static func processMarker(
    uptimeMillis: Int,
    receiverEntry: Bool,
    processId: String = BackgroundEvidenceLog.processId,
    pid: Int32 = BackgroundEvidenceLog.pid
  ) -> String {
    return "procUuid=\(processId) pid=\(pid) uptimeMs=\(uptimeMillis) "
      + "receiverEntry=\(receiverEntry)"
  }

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
  ///
  /// **ยังมีเคสที่เขียนไม่ได้อยู่ดี:** ถ้าเครื่องรีบูตแล้ว**ยังไม่เคยปลดล็อกเลย**
  /// สักครั้ง ไฟล์ระดับนี้ยังเข้าถึงไม่ได้ — ตรงกับที่ Apple ระบุว่า region
  /// monitoring เองก็ "can only occur after the user unlocks the device after a
  /// reboot" จึงเป็นข้อจำกัดที่ยอมรับ เพราะระดับที่ต่ำกว่านี้ (`.none`) แปลว่า
  /// ไม่เข้ารหัสเลย ซึ่งไม่เหมาะกับไฟล์ที่บันทึกว่าผู้ใช้อยู่สาขาไหนเวลาใด
  static let fileProtection = FileProtectionType.completeUntilFirstUserAuthentication

  /// สร้าง (ถ้ายังไม่มี) ไฟล์ log พร้อมตั้ง protection class ให้ชัดเจน แล้วคืน path
  ///
  /// ตั้ง protection ทั้งที่ **directory** และ **ไฟล์**: directory เพื่อให้ไฟล์ใหม่
  /// ที่ถูกสร้างในนั้นภายหลังได้ค่าเดียวกัน และไฟล์เพื่อให้ไฟล์ที่มีอยู่แล้วจากการ
  /// ติดตั้งเวอร์ชันก่อนหน้าถูกอัปเดตด้วย
  static func prepareLogFile(named fileName: String) throws -> String {
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
      attributes: [.protectionKey: fileProtection]
    )
    try fm.setAttributes([.protectionKey: fileProtection], ofItemAtPath: dir.path)

    let fileURL = dir.appendingPathComponent(fileName)
    if !fm.fileExists(atPath: fileURL.path) {
      fm.createFile(
        atPath: fileURL.path,
        contents: nil,
        attributes: [.protectionKey: fileProtection]
      )
    } else {
      try fm.setAttributes([.protectionKey: fileProtection], ofItemAtPath: fileURL.path)
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

  /// ประกอบหนึ่งบรรทัดของ log — **pure function** จึงมี XCTest คลุมได้จริง
  ///
  /// รูปแบบคั่นด้วย TAB **6 คอลัมน์** ต้องตรงกับที่หน้า "ดู log" ฝั่ง Dart,
  /// `tool/analyze_region_log.dart` และฝั่ง Android (`BackgroundEvidenceLog.kt`)
  /// อ่าน:
  /// `timestamp(ISO8601+offset) \t processId \t event \t regionIdentifier \t conclusion \t rawSignals`
  ///
  /// **คอลัมน์ `processId` เพิ่มเข้ามาทีหลัง** — ไฟล์ log เก่าที่เก็บไว้เป็นหลักฐาน
  /// (เช่น `docs/test-data/2026-08-30_overnight_region_flapping.log`) ยังเป็น 5
  /// คอลัมน์อยู่ ตัวอ่านทุกตัวจึงต้องรองรับทั้งสองแบบ วิธีแยกคือดูว่าคอลัมน์ที่ 2
  /// เป็นเลขฐานสิบหก 8 ตัวหรือไม่ (ดู `LogEntry.tryParse`) **ห้ามแก้ไฟล์เก่าให้
  /// เข้ารูปแบบใหม่** เพราะมันคือหลักฐานดิบจากรอบทดสอบที่เกิดขึ้นจริง
  ///
  /// ใช้เวลา **local พร้อม offset** ไม่ใช่ UTC ล้วน เพราะผู้ทดสอบต้องเทียบกับเวลา
  /// บนนาฬิกาข้อมือตอนถอด/ใส่แบตจริง การต้องบวกลบ 7 ชั่วโมงในหัวระหว่างอ่าน log
  /// คือที่มาของการอ่านผลผิด
  ///
  /// [processId] รับเป็นพารามิเตอร์ที่มีค่า default เพื่อให้ XCTest ตรึงค่าได้
  /// โค้ดจริงไม่ต้องส่ง
  static func line(
    timestamp: Date,
    processId: String = BackgroundEvidenceLog.processId,
    event: String,
    regionIdentifier: String,
    conclusion: String,
    rawSignals: String
  ) -> String {
    return [
      iso8601WithOffset(timestamp),
      processId,
      event,
      regionIdentifier,
      conclusion,
      rawSignals,
    ].joined(separator: "\t")
  }

  /// `DateFormatter` ตัวเดียวใช้ซ้ำ — สร้างใหม่ทุกครั้งแพงและตรงนี้อยู่ในเส้นทางที่
  /// เวลาที่ระบบให้มาสั้นมาก (ถูกปลุกเบื้องหลัง)
  ///
  /// ตั้ง `locale` เป็น `en_US_POSIX` ตามที่ Apple กำหนดสำหรับ fixed-format date
  /// ไม่งั้นเครื่องที่ตั้งปฏิทินพุทธ (พบได้ทั่วไปในไทย) จะได้ปี 2569 ใน log
  /// ซึ่งทำให้เทียบเวลากับ log ฝั่งอื่นไม่ได้เลย
  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return formatter
  }()

  static func iso8601WithOffset(_ date: Date) -> String {
    return formatter.string(from: date)
  }

  /// ต่อท้ายหนึ่งบรรทัดลงไฟล์แบบ **synchronous + fsync**
  ///
  /// ต้อง `synchronize()` ก่อนคืนค่า เพราะ iOS อาจ suspend process ทันทีที่งาน
  /// เบื้องหลังจบ ถ้าข้อมูลยังค้างใน buffer ของ kernel จะหายทั้งบรรทัด =
  /// เสียหลักฐานที่รอมาทั้งรอบทดสอบ
  ///
  /// กลืน error ทิ้งเงียบ ๆ ไม่ได้ — แต่ตอนถูกปลุกเบื้องหลังไม่มีใครดู error ให้
  /// จึงบันทึกไว้ใน `lastError` ให้ฝั่ง Dart ดึงไปแสดงบนหน้าจอทีหลังได้
  private(set) var lastError: String?

  func append(line: String) {
    do {
      let path = try Self.prepareLogFile(named: Self.fileName)
      guard let handle = FileHandle(forWritingAtPath: path) else {
        lastError = "เปิดไฟล์ log เพื่อเขียนไม่ได้: \(path)"
        return
      }
      defer { try? handle.close() }
      try handle.seekToEnd()
      guard let data = (line + "\n").data(using: .utf8) else {
        lastError = "แปลงบรรทัด log เป็น UTF-8 ไม่ได้"
        return
      }
      try handle.write(contentsOf: data)
      try handle.synchronize()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }
}
