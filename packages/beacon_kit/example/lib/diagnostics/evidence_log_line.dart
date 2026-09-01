/// ตัวอ่านหนึ่งบรรทัดของไฟล์หลักฐาน (`region_events.log`)
///
/// ไฟล์นี้ถูกเขียนด้วยโค้ด native ล้วนทั้งสองแพลตฟอร์ม:
/// - iOS: `ios/Runner/BackgroundEvidenceLog.swift`
/// - Android: `android/app/src/main/kotlin/com/beaconkit/example/BackgroundEvidenceLog.kt`
///
/// ทั้งสองฝั่งประกอบบรรทัดด้วยรูปแบบเดียวกันโดยตั้งใจ เพื่อให้ **เทียบผลข้าม
/// แพลตฟอร์มด้วยเครื่องมือชุดเดียวกันได้จริง** ไม่ใช่แค่ "มี log ทั้งคู่"
library;

/// รูปแบบบรรทัดปัจจุบัน — TAB คั่น 6 คอลัมน์
///
/// ```
/// timestamp \t processId \t event \t regionIdentifier \t conclusion \t rawSignals
/// ```
///
/// **รูปแบบเก่า (5 คอลัมน์) ยังต้องอ่านได้** — ไฟล์หลักฐานจากรอบทดสอบก่อน
/// ADR-14 (เช่น `docs/test-data/2026-08-30_overnight_region_flapping.log`)
/// ไม่มีคอลัมน์ `processId` และ **ห้ามแก้ไฟล์เหล่านั้นให้เข้ารูปแบบใหม่** เพราะ
/// มันคือหลักฐานดิบของสิ่งที่เกิดขึ้นจริง การแก้ย้อนหลังทำให้มันเชื่อถือไม่ได้
class EvidenceLogLine {
  const EvidenceLogLine({
    required this.timestamp,
    required this.processId,
    required this.event,
    required this.regionIdentifier,
    required this.conclusion,
    required this.rawSignals,
  });

  /// timestamp ดิบตามที่อยู่ในไฟล์ (ISO8601 + offset ของเครื่องที่ทดสอบ)
  final String timestamp;

  /// ตัวระบุ process ที่เขียนบรรทัดนี้ — `null` สำหรับไฟล์รูปแบบเก่า
  ///
  /// **`null` ไม่ได้แปลว่า "process เดิม"** แปลว่า *ไม่รู้* — ผู้อ่านต้องไม่สรุป
  /// อะไรจากมัน นี่คือเหตุผลที่ใช้ `null` แทนการเติมค่าปลอมอย่าง `'-'`
  final String? processId;

  /// `launch` / `enter` / `exit` / `scan-result` …
  final String event;
  final String regionIdentifier;

  /// `foreground` / `background` / `relaunchedFromTerminated` / `unknown`
  final String conclusion;

  /// สัญญาณดิบทั้งหมดที่ native เก็บไว้ ณ ตอนเขียนบรรทัด
  final String rawSignals;

  /// บรรทัดนี้เป็นบรรทัดแรกของ process ใหม่หรือไม่
  ///
  /// native เขียน `launch` **หนึ่งบรรทัดต่อหนึ่ง process เสมอ** ไม่ว่ารอบนั้นจะมี
  /// event ตามมาหรือไม่ — บรรทัด `launch` จึงเป็นหลักฐานตรงว่า "process ถูกสร้าง
  /// ขึ้นมาใหม่" โดยไม่ต้องเดาจาก uptime อีกต่อไป
  bool get marksNewProcess => event == 'launch';

  /// `true` เมื่อบรรทัดนี้คือสิ่งที่การทดสอบเบื้องหลังต้องการพิสูจน์:
  /// event ที่ถึงมือเราขณะที่ process **ไม่เคยขึ้น foreground เลย**
  bool get isFromRelaunchedProcess => conclusion == 'relaunchedFromTerminated';

  /// คอลัมน์ที่ 2 เป็น `processId` ก็ต่อเมื่อหน้าตาเป็นเลขฐานสิบหกพิมพ์เล็ก 8 ตัว
  ///
  /// ใช้รูปแบบของค่าเป็นตัวแยกรุ่นไฟล์ แทนการนับจำนวนคอลัมน์อย่างเดียว เพราะ
  /// `rawSignals` ของไฟล์เก่าอาจมี TAB ปนมาได้ในทางทฤษฎี ซึ่งจะทำให้การนับพลาด
  /// ส่วนคอลัมน์ที่ 2 ของไฟล์เก่าคือชื่อ event (`enter`/`exit`/`launch`) ที่ไม่มี
  /// ทางตรงกับรูปแบบนี้
  static final RegExp _processIdPattern = RegExp(r'^[0-9a-f]{8}$');

  /// คืน `null` ถ้าบรรทัดผิดรูปแบบจนแยกคอลัมน์ไม่ได้ — ผู้เรียกควรแสดงบรรทัดดิบ
  /// ต่อไป ไม่ใช่ซ่อนทิ้ง เพราะบรรทัดที่อ่านไม่ออกก็ยังเป็นหลักฐาน
  static EvidenceLogLine? tryParse(String line) {
    final parts = line.split('\t');
    if (parts.length < 4) return null;

    final hasProcessId =
        parts.length >= 6 && _processIdPattern.hasMatch(parts[1]);
    final offset = hasProcessId ? 1 : 0;

    String columnAt(int index) =>
        parts.length > index + offset ? parts[index + offset] : '';

    return EvidenceLogLine(
      timestamp: parts[0],
      processId: hasProcessId ? parts[1] : null,
      event: columnAt(1),
      regionIdentifier: columnAt(2),
      conclusion: columnAt(3),
      rawSignals: columnAt(4),
    );
  }
}
