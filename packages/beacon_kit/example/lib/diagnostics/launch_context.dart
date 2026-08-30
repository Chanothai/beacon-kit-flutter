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

  const LaunchDiagnostics({
    required this.launchedByLocationKey,
    required this.hasEverBecomeActive,
    required this.applicationState,
    required this.processUptimeSeconds,
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

  /// สรุปสัญญาณดิบเป็นข้อความสั้นสำหรับต่อท้ายบรรทัด log
  String get rawSignalSummary =>
      'launchKey=$launchedByLocationKey '
      'everActive=$hasEverBecomeActive '
      'state=$applicationState '
      'uptime=${processUptimeSeconds.toStringAsFixed(1)}s';
}

/// สะพานไปยังโค้ด native ของ **example app เอง** (ไม่ใช่ของ `beacon_kit`)
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
