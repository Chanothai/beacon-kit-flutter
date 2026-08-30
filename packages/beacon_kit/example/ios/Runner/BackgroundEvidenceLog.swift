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
  /// รูปแบบคั่นด้วย TAB 5 คอลัมน์ ต้องตรงกับที่หน้า "ดู log" ฝั่ง Dart อ่าน:
  /// `timestamp(ISO8601+offset) \t event \t regionIdentifier \t conclusion \t rawSignals`
  ///
  /// ใช้เวลา **local พร้อม offset** ไม่ใช่ UTC ล้วน เพราะผู้ทดสอบต้องเทียบกับเวลา
  /// บนนาฬิกาข้อมือตอนถอด/ใส่แบตจริง การต้องบวกลบ 7 ชั่วโมงในหัวระหว่างอ่าน log
  /// คือที่มาของการอ่านผลผิด
  static func line(
    timestamp: Date,
    event: String,
    regionIdentifier: String,
    conclusion: String,
    rawSignals: String
  ) -> String {
    return [
      iso8601WithOffset(timestamp),
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
