import 'dart:io';

import 'package:beacon_kit/beacon_kit.dart';

import 'launch_context.dart';

/// บันทึก region enter/exit ลงไฟล์ถาวรใน Application Support
///
/// **ทำไมต้องเขียนลงไฟล์ ไม่ใช่เก็บใน memory หรือ print:** หลักฐานที่ B5 ต้องการคือ
/// event ที่เกิดขึ้น**ตอนแอปถูกฆ่าไปแล้ว** ซึ่งไม่มีใครเห็นหน้าจอ ไม่มี debugger
/// ต่ออยู่ และ state ใน memory หายไปพร้อม process เดิม log ที่รอดข้าม process
/// เท่านั้นที่เป็นหลักฐานได้
///
/// อยู่ใน example app เท่านั้น — `beacon_kit` ไม่ควรบังคับรูปแบบการเก็บ log
class RegionEventLog {
  static const String _fileName = 'region_events.log';

  final ExampleDiagnostics _diagnostics;

  const RegionEventLog({
    ExampleDiagnostics diagnostics = const ExampleDiagnostics(),
  }) : this._(diagnostics);

  const RegionEventLog._(this._diagnostics);

  Future<File> _file() async {
    final dir = await _diagnostics.getLogDirectory();
    return File('$dir/$_fileName');
  }

  /// ต่อท้ายหนึ่งบรรทัดต่อหนึ่ง event
  ///
  /// ใช้ `FileMode.append` + `flush: true` เพื่อให้ข้อมูลลงดิสก์ก่อนฟังก์ชันคืนค่า
  /// สำคัญมากในเคสถูกปลุกเบื้องหลัง เพราะ iOS อาจ suspend process ทันทีหลังจบงาน
  /// ถ้ายังค้างอยู่ใน buffer จะหายไปทั้งบรรทัด = เสียหลักฐานที่รอมาทั้งรอบทดสอบ
  Future<void> append(
    IBeaconRegionStateEvent event,
    LaunchDiagnostics diagnostics,
  ) async {
    // ISO8601 พร้อม timezone offset — ห้ามใช้ UTC ล้วนหรือเวลาไร้ offset
    // เพราะผู้ทดสอบต้องเทียบกับเวลาบนนาฬิกาข้อมือตอนเดินเข้า/ออกจริง
    final timestamp = event.timestamp.toLocal().toIso8601String();
    final offset = _timezoneOffset(event.timestamp.toLocal());
    final line =
        '$timestamp$offset\t'
        '${event.state.name}\t'
        '${event.regionIdentifier}\t'
        '${diagnostics.context.name}\t'
        '${diagnostics.rawSignalSummary}';

    final file = await _file();
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

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

  static String _timezoneOffset(DateTime local) {
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final abs = offset.abs();
    final hh = abs.inHours.toString().padLeft(2, '0');
    final mm = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return '$sign$hh:$mm';
  }
}
