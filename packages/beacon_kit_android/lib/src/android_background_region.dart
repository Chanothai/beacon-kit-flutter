/// ชนิดข้อมูลของเส้นทาง "เฝ้า region เบื้องหลัง" ฝั่ง Android (ADR-14)
///
/// ## ทำไมทุกชื่อขึ้นต้นด้วย `Android` และทำไมไม่ยกขึ้นสัญญากลาง
///
/// ADR-9 เขียนดักไว้ตั้งแต่ก่อนเริ่มงาน Android ว่า:
///
/// > "ห้ามสมมติว่า `startIBeaconMonitoring()` จะทำงานเหมือนกันทั้งสองแพลตฟอร์ม
/// > ... ถ้า Android ทำแบบนั้นไม่ได้ **ห้าม implement ให้มัน 'ดูเหมือนทำได้'**"
///
/// ก้อนที่ 2 ตอบตารางคำถามของ ADR-9 ครบแล้ว และคำตอบคือ **ทำไม่ได้เทียบเท่า** —
/// รายละเอียดอยู่ใน ADR-14 หัวข้อ 1 สรุปสามข้อที่ต่างกันจนยกขึ้นสัญญากลางไม่ได้:
///
/// 1. iOS ให้ enter/exit ที่ **ระบบ** คำนวณ · Android ให้แค่ "เจอ advertisement"
///    ส่วน exit เป็น**ข้อสรุปของเราเอง**จากการไม่เห็นครบ N วินาที
/// 2. iOS เก็บ region ไว้ที่ระดับระบบและอยู่ข้าม launch เอง · Android เก็บไม่ได้
///    ต้องลงทะเบียนใหม่เองหลังรีบูต และ **หายถาวรหลัง force-stop**
/// 3. เวลาที่ใช้ประกาศ exit ฝั่ง iOS ระบบกำหนด (วัดได้ ~30 วินาที ADR-11) ·
///    ฝั่งนี้เราตั้งเองได้ แต่ถูกจำกัดด้วยความถี่ของนาฬิกาปลุกของระบบ
///
/// ตาม ADR-13 หัวข้อ 4 ข้อ 3: เมื่อพบว่าทำไม่ได้เทียบเท่า **ให้แยกเป็นความสามารถ
/// คนละชื่อตามที่แต่ละแพลตฟอร์มทำได้จริง แล้วให้แอปเลือกเองอย่างรู้ตัว** — ชื่อที่
/// ขึ้นต้นด้วย `Android` คือการทำตามข้อนั้น ผู้เรียกเห็นตั้งแต่ชื่อว่ากำลังใช้
/// ความสามารถเฉพาะแพลตฟอร์ม ไม่ใช่สัญญากลาง
library;

/// region หนึ่งอันที่ขอให้เฝ้าตอนแอปไม่ได้เปิดอยู่
///
/// รูปร่างเหมือน `IBeaconRegionConfig` ฝั่ง iOS เพราะทั้งคู่อธิบาย beacon ชุดเดียว
/// กันตามสคีมของ ADR-5 (UUID เดียวทั้งบริษัท · major = สาขา · minor = อุปกรณ์)
/// — **แต่สิ่งที่เกิดขึ้นหลังส่งเข้าไปต่างกัน** ดูเอกสารหัวไฟล์
class AndroidBeaconRegion {
  const AndroidBeaconRegion({
    required this.identifier,
    required this.uuid,
    this.major,
    this.minor,
  }) : assert(
         major != null || minor == null,
         'ระบุ minor โดยไม่ระบุ major ไม่ได้ — byte ของ minor อยู่ถัดจาก major '
         'ใน iBeacon payload การกรองจึงข้ามไปเฉพาะ minor ไม่ได้ด้วยโครงของ ScanFilter',
       );

  /// ชื่อที่ผู้เรียกตั้งเอง — **ต้องไม่ซ้ำ และไม่ควรเปลี่ยนระหว่างเวอร์ชันแอป**
  ///
  /// เป็นกุญแจของสถานะที่เก็บลงดิสก์ฝั่ง native ถ้าเปลี่ยน สถานะเดิมจะกลายเป็น
  /// ขยะที่ไม่มีใครล้าง และ region เดิมจะถูกรายงาน `enter` ซ้ำอีกครั้ง
  final String identifier;

  /// proximity UUID (รูปแบบ 128-bit มีขีดคั่น)
  final String uuid;

  /// `null` = ไม่เจาะจง (รับทุก major ของ UUID นี้)
  final int? major;

  /// `null` = ไม่เจาะจง — ระบุได้เฉพาะเมื่อระบุ [major] ด้วย
  final int? minor;

  Map<String, Object?> toMap() => {
    'identifier': identifier,
    'uuid': uuid,
    if (major != null) 'major': major,
    if (minor != null) 'minor': minor,
  };
}

/// สถานะที่ **เราคำนวณเอง** ว่าอยู่ในหรือออกจาก region แล้ว
enum AndroidRegionState {
  /// เห็น advertisement ของ region นี้เป็นครั้งแรกหลังจากที่เคยออกไป
  enter,

  /// ไม่เห็น advertisement ของ region นี้ครบตามเวลาที่ตั้งไว้
  ///
  /// **ไม่ใช่สิ่งที่ระบบบอก** — เป็นข้อสรุปจากความเงียบ ซึ่งแปลว่าอาจเกิดจากสาเหตุ
  /// อื่นที่ไม่ใช่ผู้ใช้เดินออกจากพื้นที่: beacon แบตหมด, Bluetooth ถูกปิด,
  /// ระบบ throttle การสแกน, หรือ MIUI ฆ่าแอปทิ้ง
  exit,
}

/// event เข้า/ออก region ที่มาจากเส้นทางเบื้องหลังฝั่ง Android
class AndroidBackgroundRegionEvent {
  const AndroidBackgroundRegionEvent({
    required this.regionIdentifier,
    required this.state,
    required this.timestamp,
    required this.fromBackgroundProcess,
  });

  final String regionIdentifier;
  final AndroidRegionState state;

  /// เวลาที่ **native บันทึก event** ไม่ใช่เวลาที่ Dart ได้รับ
  ///
  /// สองค่านี้ต่างกันได้เป็นชั่วโมงในกรณีที่ event ถูกคิวไว้ตอนแอปปิดอยู่แล้ว
  /// ส่งให้ตอนผู้ใช้เปิดแอปครั้งถัดไป — ถ้าใช้เวลาที่ Dart ได้รับ สถิติทั้งหมด
  /// จะกองอยู่ที่ "ตอนเปิดแอป" ซึ่งผิดความจริงทั้งชุด
  final DateTime timestamp;

  /// `true` เมื่อ event เกิดขึ้นตอนที่ process **ยังไม่เคยมี UI เลย**
  ///
  /// นี่คือค่าที่ต้องเป็น `true` จึงจะพิสูจน์ได้ว่าการทำงานเบื้องหลังทำงานจริง —
  /// ถ้าเป็น `false` ทั้งหมด แปลว่าเราเพิ่งพิสูจน์แค่ว่า "แอปที่เปิดอยู่เห็น beacon"
  /// ซึ่งก้อนที่ 1 พิสูจน์ไปแล้ว
  final bool fromBackgroundProcess;

  static AndroidBackgroundRegionEvent? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final identifier = raw['regionIdentifier'] as String?;
    final state = switch (raw['state']) {
      'enter' => AndroidRegionState.enter,
      'exit' => AndroidRegionState.exit,
      _ => null,
    };
    if (identifier == null || state == null) return null;
    return AndroidBackgroundRegionEvent(
      regionIdentifier: identifier,
      state: state,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (raw['timestampMillis'] as num?)?.toInt() ?? 0,
      ),
      fromBackgroundProcess: (raw['fromBackgroundProcess'] as bool?) ?? false,
    );
  }
}

/// ผลของการสั่งลงทะเบียนเฝ้า region — **รายอัน ไม่ใช่ค่ารวม**
///
/// `BluetoothLeScanner.startScan(..., PendingIntent)` คืน `int` แทนการ throw
/// ถ้า SDK สรุปให้เหลือ success/fail ค่าเดียว ผู้เรียกจะไม่มีทางรู้ว่า region ไหน
/// ลงทะเบียนไม่ติด และอาการจะออกมาเป็น "บางสาขาใช้ได้ บางสาขาไม่ได้"
class AndroidBackgroundMonitoringResult {
  const AndroidBackgroundMonitoringResult({
    required this.registered,
    required this.failed,
  });

  /// identifier ของ region ที่ลงทะเบียนกับระบบสำเร็จ
  final List<String> registered;

  /// identifier → เหตุผลที่ล้มเหลว
  ///
  /// ค่าที่พบได้: `BLUETOOTH_PERMISSION_DENIED`, `BLUETOOTH_UNAVAILABLE`,
  /// `SCAN_FAILED_SCANNING_TOO_FREQUENTLY`, `SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES`
  /// และ `SCAN_FAILED_*` อื่น ๆ ที่ระบบคืนมา
  ///
  /// **ตัวเลขที่ระบบใช้ throttle ยืนยันไม่ได้จากเอกสาร** (ADR-12 หัวข้อ 2ค) จึงไม่
  /// มีการ retry อัตโนมัติที่นี่ — การเดาแล้วยิงซ้ำมีแต่จะโดน throttle หนักขึ้น
  final Map<String, String> failed;

  bool get isCompleteSuccess => failed.isEmpty && registered.isNotEmpty;

  static AndroidBackgroundMonitoringResult fromMap(Map<Object?, Object?> raw) {
    return AndroidBackgroundMonitoringResult(
      registered:
          (raw['registered'] as List?)?.map((e) => e as String).toList() ??
          const [],
      failed:
          (raw['failed'] as Map?)?.map(
            (key, value) => MapEntry(key as String, value as String),
          ) ??
          const {},
    );
  }
}

/// สิ่งที่ **แอปเราเองจำไว้** ว่ากำลังเฝ้าอะไรอยู่
///
/// ⚠️ **ไม่ใช่คำตอบว่าระบบกำลังเฝ้าอะไรอยู่จริง** ฝั่ง iOS ถาม
/// `CLLocationManager.monitoredRegions` แล้วได้ความจริงจากระบบ ส่วน Android
/// **ไม่มี API ให้ถามข้อนั้น** ค่าที่นี่จึงมาจากไฟล์ของเราเอง ถ้าระบบล้างการ
/// ลงทะเบียนทิ้ง (เช่นหลังผู้ใช้ force-stop) ค่านี้จะยังบอกว่ามี ทั้งที่ไม่มีอะไร
/// ทำงานอยู่แล้ว — ความต่างนี้บันทึกไว้ใน ADR-14 หัวข้อ 4 เป็นข้อจำกัดที่แก้ไม่ได้
/// ด้วยโค้ด ไม่ใช่จุดที่ยังทำไม่เสร็จ
class AndroidBackgroundMonitoringStatus {
  const AndroidBackgroundMonitoringStatus({
    required this.isActive,
    required this.regionIdentifiers,
    required this.exitTimeoutSeconds,
    required this.queuedEventCount,
  });

  /// แอปเคยสั่งเริ่มแล้วและยังไม่ได้สั่งหยุด
  final bool isActive;
  final List<String> regionIdentifiers;

  /// ค่า N ที่ใช้อยู่ — "ไม่เห็นกี่วินาทีถือว่าออกจาก region"
  final int exitTimeoutSeconds;

  /// event ที่เกิดตอนไม่มี Flutter engine และยังรอส่งให้ Dart
  ///
  /// ค่ามากกว่า 0 ตอนเพิ่งเปิดแอป = **หลักฐานว่ามีอะไรเกิดขึ้นตอนแอปปิดอยู่**
  final int queuedEventCount;

  static AndroidBackgroundMonitoringStatus fromMap(Map<Object?, Object?> raw) {
    return AndroidBackgroundMonitoringStatus(
      isActive: (raw['isActive'] as bool?) ?? false,
      regionIdentifiers:
          (raw['regionIdentifiers'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      exitTimeoutSeconds: (raw['exitTimeoutSeconds'] as num?)?.toInt() ?? 0,
      queuedEventCount: (raw['queuedEventCount'] as num?)?.toInt() ?? 0,
    );
  }
}
