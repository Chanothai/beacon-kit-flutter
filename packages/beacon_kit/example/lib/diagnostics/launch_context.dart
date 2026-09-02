import 'package:flutter/services.dart';

/// สถานะของแอปตอนที่ event เกิดขึ้น — **คือสิ่งที่ B5 ต้องพิสูจน์**
///
/// ความต่างระหว่าง [relaunchedFromTerminated] กับ [background] คือหัวใจของสปรินต์:
/// ถ้าแอปรันอยู่เบื้องหลังอยู่แล้ว การได้รับ event ไม่ได้พิสูจน์อะไรมากนัก
/// แต่ถ้า iOS ปลุก process ที่**ถูกฆ่าไปแล้ว**ขึ้นมาใหม่เพื่อส่ง event นั่นคือ
/// background region monitoring ที่ทำงานได้จริงตามที่ต้องการ
enum AppRunContext {
  /// แอปอยู่หน้าจอ ผู้ใช้เห็นอยู่
  foreground,

  /// แอปรันอยู่เบื้องหลัง (process ยังมีชีวิต ผู้ใช้เคยเปิดแล้วใน session นี้)
  background,

  /// **process ถูกปลุกขึ้นมาใหม่จากสถานะถูกฆ่า** เพื่อส่ง location event
  relaunchedFromTerminated,

  /// แยกไม่ออก — สัญญาณขัดกันเองหรืออ่านค่าไม่ได้ ต้องดู raw signal ประกอบ
  unknown,
}

/// สัญญาณดิบจาก native ทั้งหมด + ข้อสรุปที่คำนวณจากมัน
///
/// จงใจเก็บ**สัญญาณดิบไว้ครบ**ไม่ใช่เก็บแค่ข้อสรุป เพราะวิธีแยก
/// "ถูกปลุกจากสถานะถูกฆ่า" ไม่มี API เดียวที่ตอบตรง ๆ ได้ (ดู `docs/` ประกอบ) —
/// ถ้าภายหลังพบว่าสูตรที่ใช้สรุปผิด ข้อมูลดิบใน log ยังตรวจย้อนกลับได้
/// โดยไม่ต้องทดสอบใหม่ทั้งรอบ
class LaunchDiagnostics {
  /// iOS ส่ง `UIApplication.LaunchOptionsKey.location` มาตอน launch หรือไม่
  final bool launchedByLocationKey;

  /// แอปเคยขึ้นมา foreground อย่างน้อยหนึ่งครั้งใน process นี้หรือยัง
  final bool hasEverBecomeActive;

  /// `active` / `inactive` / `background`
  final String applicationState;

  /// process นี้เปิดมานานกี่วินาทีแล้ว
  final double processUptimeSeconds;

  /// ตัวระบุ process ที่ native สุ่มไว้ตอนเริ่ม — ค่าเดียวกับคอลัมน์ที่ 2 ของ log
  ///
  /// มีไว้ให้หน้าจอแสดงได้ว่า "บรรทัดที่คุณเห็นใน log ตอนนี้มาจาก process เดียวกับ
  /// ที่กำลังรันอยู่หรือไม่" — คำถามที่ก่อนหน้านี้ตอบได้ด้วยการเดาจาก uptime เท่านั้น
  final String processId;

  const LaunchDiagnostics({
    required this.launchedByLocationKey,
    required this.hasEverBecomeActive,
    required this.applicationState,
    required this.processUptimeSeconds,
    required this.processId,
  });

  /// สรุปเป็น [AppRunContext] จากสัญญาณดิบ
  ///
  /// กติกา (เรียงตามลำดับการตัดสิน):
  /// 1. `applicationState == 'active'` -> [AppRunContext.foreground] ตรงไปตรงมา
  /// 2. ไม่เคย active เลยใน process นี้ + อยู่ background
  ///    -> [AppRunContext.relaunchedFromTerminated]
  ///    เหตุผล: process ที่ผู้ใช้เปิดเองต้องผ่าน active เสมอ ถ้าไม่เคยผ่านเลย
  ///    แปลว่า process นี้ถูกระบบสร้างขึ้นมาเอง ไม่ใช่ผู้ใช้เปิด
  /// 3. เคย active แล้ว + อยู่ background -> [AppRunContext.background]
  ///
  /// [launchedByLocationKey] ใช้เป็น**หลักฐานสนับสนุน**ไม่ใช่ตัวตัดสินหลัก
  /// เพราะ key นั้น deprecated ใน iOS 26.0 แล้ว การพึ่งมันตัวเดียวจะทำให้
  /// การทดสอบพังเงียบ ๆ ถ้า Apple ถอดออกจริงในอนาคต — แต่ถ้ามันเป็น `true`
  /// ก็เป็นการยืนยันซ้ำที่มีน้ำหนัก จึงบันทึกไว้ใน log ทุกบรรทัด
  AppRunContext get context {
    if (applicationState == 'active') return AppRunContext.foreground;
    if (applicationState == 'background' || applicationState == 'inactive') {
      return hasEverBecomeActive
          ? AppRunContext.background
          : AppRunContext.relaunchedFromTerminated;
    }
    return AppRunContext.unknown;
  }

  /// สรุปสัญญาณดิบเป็นข้อความสั้นสำหรับแสดงบนหน้าจอ
  ///
  /// **ไม่ใช่ตัวที่เขียนลง log** — ผู้เขียน log คือโค้ด native ฝั่งเดียว (ADR-10)
  /// ตัวนี้มีไว้ให้หน้าจอแสดงสถานะปัจจุบันเท่านั้น
  String get rawSignalSummary =>
      'pid=$processId '
      'launchKey=$launchedByLocationKey '
      'everActive=$hasEverBecomeActive '
      'state=$applicationState '
      'uptime=${processUptimeSeconds.toStringAsFixed(1)}s';
}

/// สะพานไปยังโค้ด native ของ **example app เอง** (ไม่ใช่ของ `beacon_kit`)
/// ผลของการพิสูจน์ว่า **เครื่องมือวัดเขียนไฟล์ได้จริง** โดยไม่ต้องพึ่ง beacon
///
/// native เขียน 1 บรรทัดผ่านตัวเขียนตัวเดียวกับที่เส้นทางเบื้องหลังใช้ แล้ว
/// **อ่านไฟล์กลับขึ้นมาจริง ๆ** — ไม่ใช่แค่ "เรียกแล้วไม่ throw"
///
/// **ทำไมต้องมีทั้งชุด ไม่ใช่ `bool ok` ตัวเดียว:** ความล้มเหลวแต่ละแบบแก้คนละทาง
/// เขียนไม่ได้ (`errorAfterWrite`) · เขียนได้แต่อ่านไม่ได้ (`readError` — บน iOS
/// คือเครื่องรีบูตแล้วยังไม่ปลดล็อก) · เขียนได้อ่านได้แต่ไม่ตรง
/// (`readBackMatches == false`) ถ้ายุบเป็นค่าเดียวจะกลับไปเดาเหมือนเดิม
class EvidenceLogSelfTest {
  const EvidenceLogSelfTest({
    required this.path,
    required this.errorBeforeWrite,
    required this.writtenLine,
    required this.errorAfterWrite,
    required this.fileExists,
    required this.fileSizeBytes,
    required this.lineCount,
    required this.readBackLine,
    required this.readBackMatches,
    required this.readError,
  });

  /// path เต็มของไฟล์หลักฐาน — เอาไปต่อท้าย `adb ... cat` ได้ตรง ๆ
  final String path;

  /// `lastError` ที่ค้างอยู่ **ก่อน** self-test เขียนทับ
  ///
  /// สำคัญที่สุดในชุดนี้: การเขียนที่สำเร็จจะล้าง `lastError` เป็น `null` ค่านี้
  /// จึงเป็นครั้งเดียวที่จะได้เห็น error ที่เกิดตอนไม่มีใครดูหน้าจอ
  final String? errorBeforeWrite;

  final String writtenLine;

  /// `null` = การเขียนของ self-test สำเร็จ
  final String? errorAfterWrite;

  final bool fileExists;
  final int fileSizeBytes;

  /// จำนวนบรรทัดที่ไม่ว่างในไฟล์ **หลัง** เขียน (รวมบรรทัดที่เพิ่งเขียน)
  final int lineCount;

  /// บรรทัดสุดท้ายที่อ่านกลับได้ — `null` ถ้าอ่านไม่ได้หรือไฟล์ว่าง
  final String? readBackLine;

  /// บรรทัดที่อ่านกลับได้ตรงกับบรรทัดที่เพิ่งเขียนหรือไม่
  final bool readBackMatches;

  /// `null` = อ่านไฟล์กลับมาได้ (คนละความล้มเหลวกับ [errorAfterWrite])
  final String? readError;

  /// ผ่าน = เขียนได้ **และ** อ่านกลับได้ **และ** ตรงกับที่เขียน
  ///
  /// [errorBeforeWrite] ไม่นับรวมโดยตั้งใจ — มันคือ error ของ *รอบก่อน* ไม่ใช่
  /// ผลของการทดสอบครั้งนี้ แต่หน้าจอต้องแสดงมันเสมอ
  bool get passed =>
      errorAfterWrite == null &&
      readError == null &&
      fileExists &&
      readBackMatches;

  static EvidenceLogSelfTest fromMap(Map<String, Object?> raw) {
    return EvidenceLogSelfTest(
      path: (raw['path'] as String?) ?? '?',
      errorBeforeWrite: raw['errorBeforeWrite'] as String?,
      writtenLine: (raw['writtenLine'] as String?) ?? '',
      errorAfterWrite: raw['errorAfterWrite'] as String?,
      fileExists: (raw['fileExists'] as bool?) ?? false,
      fileSizeBytes: (raw['fileSizeBytes'] as num?)?.toInt() ?? 0,
      lineCount: (raw['lineCount'] as num?)?.toInt() ?? 0,
      readBackLine: raw['readBackLine'] as String?,
      readBackMatches: (raw['readBackMatches'] as bool?) ?? false,
      readError: raw['readError'] as String?,
    );
  }
}

class ExampleDiagnostics {
  static const MethodChannel _channel = MethodChannel(
    'beacon_kit_example/diagnostics',
  );

  const ExampleDiagnostics();

  Future<LaunchDiagnostics> getLaunchDiagnostics() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getLaunchDiagnostics',
    );
    return LaunchDiagnostics(
      launchedByLocationKey: (raw?['launchedByLocationKey'] as bool?) ?? false,
      hasEverBecomeActive: (raw?['hasEverBecomeActive'] as bool?) ?? false,
      applicationState: (raw?['applicationState'] as String?) ?? 'unknown',
      processUptimeSeconds:
          (raw?['processUptimeSeconds'] as num?)?.toDouble() ?? 0,
      // `?` แทนการเดา — ถ้า native ไม่ส่งมา ต้องเห็นบนหน้าจอว่าไม่รู้ ไม่ใช่เห็น
      // ค่าที่ดูเหมือนของจริง
      processId: (raw?['processId'] as String?) ?? '?',
    );
  }

  /// สร้างไฟล์ log (ถ้ายังไม่มี) พร้อมตั้ง Data Protection class ให้ชัดเจน
  /// แล้วคืน path — ดูเหตุผลที่ต้องตั้งเองใน `BackgroundEvidenceLog.fileProtection`
  Future<String> prepareLogFile(String fileName) async {
    final path = await _channel.invokeMethod<String>('prepareLogFile', {
      'fileName': fileName,
    });
    if (path == null) {
      throw StateError('native ไม่คืน path ของไฟล์ log');
    }
    return path;
  }

  /// error ล่าสุดของการเขียน log **ฝั่ง native** (`null` = ครั้งล่าสุดสำเร็จ)
  ///
  /// ตอน iOS ปลุกแอปขึ้นมาเบื้องหลังไม่มีใครเห็น error ที่เกิดตรงนั้น ถ้าไม่เก็บไว้
  /// ให้ดึงย้อนหลัง อาการจะออกมาเป็น "ไม่มีบรรทัดใน log" เฉย ๆ ซึ่งแยกไม่ออกจาก
  /// "แอปไม่เคยถูกปลุกเลย" — คนละสาเหตุกันคนละเรื่อง
  Future<String?> getLogWriteError() =>
      _channel.invokeMethod<String>('getLogWriteError');

  /// เขียน 1 บรรทัดลงไฟล์หลักฐานจริง แล้วอ่านกลับมาทันที — ดู [EvidenceLogSelfTest]
  Future<EvidenceLogSelfTest> runEvidenceLogSelfTest() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'runEvidenceLogSelfTest',
    );
    if (raw == null) {
      throw StateError('native ไม่คืนผล self-test');
    }
    return EvidenceLogSelfTest.fromMap(raw);
  }

  /// อ่าน protection class จริงของไฟล์ log กลับมาเพื่อตรวจสอบ (`null` = ยังไม่มีไฟล์)
  Future<String?> getLogFileProtection(String fileName) => _channel
      .invokeMethod<String>('getLogFileProtection', {'fileName': fileName});

  Future<bool> requestNotificationAuthorization() async =>
      await _channel.invokeMethod<bool>('requestNotificationAuthorization') ??
      false;

  Future<void> postNotification({
    required String title,
    required String body,
  }) => _channel.invokeMethod<void>('postNotification', {
    'title': title,
    'body': body,
  });
}
