import 'dart:io';

import 'epoch_millis.dart';
import 'visit_observation.dart';

/// ตัวอ่านไฟล์หลักฐานใน `docs/test-data/` — **สำหรับเทสต์และเครื่องมือเท่านั้น**
/// ไม่ใช่ส่วนหนึ่งของชั้นกรอง
///
/// รองรับทั้งสองรูปแบบและต้องรองรับตลอดไป (ห้ามแก้ไฟล์เก่าให้เข้ารูปแบบใหม่ ดู
/// `docs/test-data/GROUND_TRUTH.md`):
///
/// - **5 คอลัมน์** (iOS คืน 30 ส.ค. — ก่อนมีคอลัมน์ `processId`)
///   `timestamp · event · regionId · conclusion · rawSignals`
/// - **6 คอลัมน์** (Android คืน 1 ก.ย.)
///   `timestamp · processId · event · regionId · conclusion · rawSignals`
final class RegionLogEntry {
  const RegionLogEntry({
    required this.atMs,
    required this.utcOffsetMs,
    required this.event,
    required this.regionId,
    required this.lineNumber,
  });

  /// เวลาสัมบูรณ์เป็นจำนวนเต็มมิลลิวินาทีนับจาก epoch (UTC)
  final EpochMillis atMs;

  /// offset ที่เขียนอยู่ในไฟล์ เช่น `+07:00`
  ///
  /// ⚠️ **ต้องเก็บไว้** — ทั้งสองไฟล์ใช้เวลาท้องถิ่นของเครื่องทดสอบ ไม่ใช่ UTC
  /// การรายงานเป็น UTC จะทำให้ข้อสรุปเรื่อง "ช่วงกลางคืน" เลื่อนไป 7 ชั่วโมง
  final EpochMillis utcOffsetMs;

  final String event;
  final String regionId;
  final int lineNumber;
}

/// ฟอร์แมตกลับเป็นรูปแบบเดียวกับที่อยู่ในไฟล์ (เวลาท้องถิ่น + offset)
///
/// เป็นหนึ่งในสองที่ที่ `DateTime` ยังปรากฏ — **ขอบของระบบ** ตรรกะของชั้นกรอง
/// ไม่แตะชนิดนี้เลย
String formatWithOffset(EpochMillis atMs, EpochMillis utcOffsetMs) {
  final wall =
      DateTime.fromMillisecondsSinceEpoch(atMs + utcOffsetMs, isUtc: true);
  final sign = utcOffsetMs.isNegative ? '-' : '+';
  final absolute = utcOffsetMs.abs();
  final hh = (absolute ~/ 3600000).toString().padLeft(2, '0');
  final mm = (absolute % 3600000 ~/ 60000).toString().padLeft(2, '0');
  final base = wall.toIso8601String();
  // `toIso8601String()` ของ DateTime ที่เป็น UTC ลงท้ายด้วย `Z` เสมอ
  return '${base.substring(0, base.length - 1)}$sign$hh:$mm';
}

final RegExp _offsetPattern = RegExp(r'(?:Z|([+-])(\d{2}):(\d{2}))$');

EpochMillis _parseUtcOffsetMs(String timestamp) {
  final match = _offsetPattern.firstMatch(timestamp);
  if (match == null) {
    throw FormatException('ไม่มี UTC offset ในเวลา "$timestamp" — '
        'ไฟล์หลักฐานต้องมี offset เสมอ');
  }
  if (match.group(1) == null) return 0;
  final sign = match.group(1) == '-' ? -1 : 1;
  return sign *
      (int.parse(match.group(2)!) * 3600000 +
          int.parse(match.group(3)!) * 60000);
}

/// แปลง `DateTime` ที่ได้จากการ parse เป็นจำนวนเต็มมิลลิวินาที
///
/// **โยนถ้ามีเศษต่ำกว่ามิลลิวินาที** — ชั้นกรองทำงานบนจำนวนเต็มมิลลิวินาทีเท่านั้น
/// การปัดเงียบ ๆ ตรงนี้จะทำให้ผลของสามภาษาต่างกันโดยไม่มีใครเห็น
EpochMillis _epochMillisOf(DateTime parsed, String raw) {
  if (parsed.microsecondsSinceEpoch % 1000 != 0) {
    throw FormatException(
      'เวลา "$raw" ละเอียดกว่ามิลลิวินาที — ชั้นกรองรองรับแค่มิลลิวินาที',
    );
  }
  return parsed.millisecondsSinceEpoch;
}

List<RegionLogEntry> parseRegionLog(String path) {
  final entries = <RegionLogEntry>[];
  final lines = File(path).readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final columns = line.split('\t');
    final int eventIndex;
    switch (columns.length) {
      case 5:
        eventIndex = 1;
      case 6:
        eventIndex = 2;
      default:
        throw FormatException(
          '$path:${i + 1} มี ${columns.length} คอลัมน์ — รองรับแค่ 5 หรือ 6',
        );
    }
    entries.add(
      RegionLogEntry(
        atMs: _epochMillisOf(DateTime.parse(columns[0]), columns[0]),
        utcOffsetMs: _parseUtcOffsetMs(columns[0]),
        event: columns[eventIndex],
        regionId: columns[eventIndex + 1],
        lineNumber: i + 1,
      ),
    );
  }
  return entries;
}

/// แปลงไฟล์หลักฐานเป็นลำดับ observation ที่ป้อนเข้า reducer ได้ตรง ๆ
///
/// - `enter` → [RegionSeen]
/// - `exit` → [RegionNotSeen]
/// - อย่างอื่น (`launch`, `selftest`) → [TimeAdvanced] · **ไม่ใช่หลักฐานว่าอยู่
///   หรือไม่อยู่** แต่เป็นเวลาที่เดินไปถึงแล้วจริง ๆ ซึ่ง reducer ต้องรู้
/// - ปิดท้ายด้วย [ObservationsEnded] ที่ **บรรทัดสุดท้ายของไฟล์** เพื่อปิดช่วงที่
///   เปิดค้างที่ขอบข้อมูล
List<VisitObservation> observationsFromLog(List<RegionLogEntry> entries) {
  final observations = <VisitObservation>[];
  for (final entry in entries) {
    switch (entry.event) {
      case 'enter':
        observations.add(
          RegionSeen(regionId: entry.regionId, atMs: entry.atMs),
        );
      case 'exit':
        observations.add(
          RegionNotSeen(regionId: entry.regionId, atMs: entry.atMs),
        );
      default:
        observations.add(TimeAdvanced(atMs: entry.atMs));
    }
  }
  if (entries.isNotEmpty) {
    observations.add(ObservationsEnded(atMs: entries.last.atMs));
  }
  return observations;
}
