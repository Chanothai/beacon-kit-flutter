import 'dart:io';

import 'launch_context.dart';

/// บันทึก region enter/exit ลงไฟล์ถาวรใน Application Support
///
/// **ทำไมต้องเขียนลงไฟล์ ไม่ใช่เก็บใน memory หรือ print:** หลักฐานที่ B5 ต้องการคือ
/// event ที่เกิดขึ้น**ตอนแอปถูกฆ่าไปแล้ว** ซึ่งไม่มีใครเห็นหน้าจอ ไม่มี debugger
/// ต่ออยู่ และ state ใน memory หายไปพร้อม process เดิม log ที่รอดข้าม process
/// เท่านั้นที่เป็นหลักฐานได้
///
/// **ตั้งแต่ ADR-10 คลาสนี้เป็นฝ่าย "อ่าน" อย่างเดียว** — ผู้เขียนไฟล์คือโค้ด native
/// (`BackgroundEvidenceLog.swift`) เพราะเส้นทาง Dart ใช้ไม่ได้ตอน process ถูกปลุก
/// ขึ้นมาเบื้องหลังโดยไม่มี UI ซึ่งเป็นเคสเดียวที่ B5 ต้องการพิสูจน์
///
/// อยู่ใน example app เท่านั้น — `beacon_kit` ไม่ควรบังคับรูปแบบการเก็บ log
class RegionEventLog {
  static const String _fileName = 'region_events.log';

  final ExampleDiagnostics _diagnostics;

  const RegionEventLog({
    ExampleDiagnostics diagnostics = const ExampleDiagnostics(),
  }) : this._(diagnostics);

  const RegionEventLog._(this._diagnostics);

  /// เตรียมไฟล์ผ่าน native ทุกครั้ง เพื่อให้ **Data Protection class ถูกตั้งเสมอ**
  /// ไม่ใช่แค่ตอนสร้างครั้งแรก — ถ้าไฟล์ถูกลบ/สร้างใหม่ระหว่างทาง (เช่นผู้ใช้กด
  /// ล้าง log) ไฟล์ใหม่ต้องได้ค่าเดียวกัน ไม่ตกไปใช้ default ที่เราไม่ได้ควบคุม
  Future<File> _file() async =>
      File(await _diagnostics.prepareLogFile(_fileName));

  /// protection class จริงที่ไฟล์ได้รับ — ใช้ตรวจสอบ ไม่ใช่เชื่อว่าตั้งสำเร็จ
  Future<String?> protectionClass() =>
      _diagnostics.getLogFileProtection(_fileName);

  /// อ่าน log ทั้งหมด บรรทัดใหม่สุดอยู่บนสุด
  Future<List<String>> read() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    final lines = await file.readAsLines();
    return lines.where((l) => l.trim().isNotEmpty).toList().reversed.toList();
  }

  /// ล้าง log เพื่อเริ่มรอบทดสอบใหม่ให้สะอาด
  ///
  /// ลบไฟล์ทิ้งแทนการเขียนทับด้วยค่าว่าง เพื่อให้แยกออกชัดว่า "ยังไม่เคยมี event"
  /// ต่างจาก "เคยมีแล้วถูกล้าง" ไม่ได้ — ทั้งสองกรณีจบที่ไม่มีไฟล์เหมือนกัน
  /// ซึ่งตรงกับความต้องการ คือเริ่มรอบใหม่จากศูนย์จริง ๆ
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<String> path() async => (await _file()).path;
}
