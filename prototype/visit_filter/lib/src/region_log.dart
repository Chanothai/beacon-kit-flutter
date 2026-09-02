import 'dart:io';

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
    required this.instant,
    required this.utcOffset,
    required this.event,
    required this.regionId,
    required this.lineNumber,
  });

  /// เวลาสัมบูรณ์ (UTC) — ใช้คำนวณระยะห่างเท่านั้น
  final DateTime instant;

  /// offset ที่เขียนอยู่ในไฟล์ เช่น `+07:00`
  ///
  /// ⚠️ **ต้องเก็บไว้** — ทั้งสองไฟล์ใช้เวลาท้องถิ่นของเครื่องทดสอบ ไม่ใช่ UTC
  /// การรายงานเป็น UTC จะทำให้ข้อสรุปเรื่อง "ช่วงกลางคืน" เลื่อนไป 7 ชั่วโมง
  final Duration utcOffset;

  final String event;
  final String regionId;
  final int lineNumber;

  /// เวลาหน้าปัดของเครื่องทดสอบ (ยังคง flag เป็น UTC ตามข้อจำกัดของ `DateTime`)
  DateTime get wallClock => instant.add(utcOffset);
}

/// ฟอร์แมตกลับเป็นรูปแบบเดียวกับที่อยู่ในไฟล์ (เวลาท้องถิ่น + offset)
String formatWithOffset(DateTime instant, Duration utcOffset) {
  final wall = instant.toUtc().add(utcOffset);
  final sign = utcOffset.isNegative ? '-' : '+';
  final absolute = utcOffset.abs();
  final hh = absolute.inHours.toString().padLeft(2, '0');
  final mm = (absolute.inMinutes % 60).toString().padLeft(2, '0');
  final base = wall.toIso8601String();
  // `toIso8601String()` ของ DateTime ที่เป็น UTC ลงท้ายด้วย `Z` เสมอ
  return '${base.substring(0, base.length - 1)}$sign$hh:$mm';
}

final RegExp _offsetPattern = RegExp(r'(?:Z|([+-])(\d{2}):(\d{2}))$');

Duration _parseUtcOffset(String timestamp) {
  final match = _offsetPattern.firstMatch(timestamp);
  if (match == null) {
    throw FormatException('ไม่มี UTC offset ในเวลา "$timestamp" — '
        'ไฟล์หลักฐานต้องมี offset เสมอ');
  }
  if (match.group(1) == null) return Duration.zero;
  final sign = match.group(1) == '-' ? -1 : 1;
  return Duration(
    hours: sign * int.parse(match.group(2)!),
    minutes: sign * int.parse(match.group(3)!),
  );
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
        instant: DateTime.parse(columns[0]),
        utcOffset: _parseUtcOffset(columns[0]),
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
          RegionSeen(regionId: entry.regionId, at: entry.instant),
        );
      case 'exit':
        observations.add(
          RegionNotSeen(regionId: entry.regionId, at: entry.instant),
        );
      default:
        observations.add(TimeAdvanced(at: entry.instant));
    }
  }
  if (entries.isNotEmpty) {
    observations.add(ObservationsEnded(at: entries.last.instant));
  }
  return observations;
}
