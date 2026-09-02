// วิเคราะห์ไฟล์ log ของ region enter/exit ที่ example app เขียนไว้
//
// ใช้ซ้ำได้กับ log ทุกรอบ — จงใจไม่ทำเป็นสคริปต์ครั้งเดียวทิ้ง เพราะจะมี log
// รอบใหม่เข้ามาเรื่อย ๆ และการเทียบผลข้ามรอบจะมีความหมายก็ต่อเมื่อคำนวณด้วย
// วิธีเดียวกันทุกครั้ง
//
// รัน:
//   dart run tool/analyze_region_log.dart <path/to/region_events.log>
//   dart run tool/analyze_region_log.dart <log> --dwell=300 --gap=900
//
// ไม่พึ่ง package ใดเลย (dart:io + dart:core เท่านั้น) จึงรันได้โดยไม่ต้อง
// `pub get` และไม่ผูกกับ pubspec ของ package ไหน

import 'dart:io';

/// หนึ่งบรรทัดใน log — รูปแบบกำหนดไว้ที่
/// `packages/beacon_kit/example/ios/Runner/BackgroundEvidenceLog.swift` และ
/// `packages/beacon_kit/example/android/app/src/main/kotlin/com/beaconkit/example/BackgroundEvidenceLog.kt`
/// (ทั้งสองฝั่งประกอบบรรทัดเหมือนกันโดยตั้งใจ)
///
/// **กติกาการแยกรูปแบบซ้ำกับ `EvidenceLogLine` ใน example app โดยตั้งใจ** —
/// ไฟล์นี้เป็นสคริปต์ที่ต้องรันได้ด้วย `dart run` เปล่า ๆ โดยไม่ `pub get` และ
/// ไม่ผูกกับ pubspec ของ package ไหน (ระบุไว้ที่หัวไฟล์) จึง import ข้ามมาไม่ได้
/// ถ้าจะแก้รูปแบบบรรทัด **ต้องแก้ทั้งสองที่**
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.processId,
    required this.event,
    required this.regionIdentifier,
    required this.conclusion,
    required this.lineNumber,
    required this.rawSignals,
  });

  /// เวลาที่บันทึกในไฟล์ **ตามเขตเวลาของเครื่องที่ทดสอบ** (ไม่ใช่ UTC และไม่ใช่
  /// เขตเวลาของเครื่องที่รันสคริปต์นี้)
  ///
  /// เก็บเป็น "wall clock" ที่ผู้ทดสอบเห็นบนนาฬิกา เพราะการวิเคราะห์ว่า flap
  /// ถี่ตอนกี่โมงจะไร้ความหมายทันทีถ้าเลื่อนเขตเวลา — และไฟล์ log อาจถูกวิเคราะห์
  /// บนเครื่องคนละโซนกับเครื่องที่ทดสอบ
  final DateTime timestamp;

  /// ตัวระบุ process ที่เขียนบรรทัดนี้ — `null` สำหรับ log ที่เก็บก่อน ADR-14
  ///
  /// **`null` แปลว่า "ไม่รู้" ไม่ใช่ "process เดิม"** — การนับ process จากไฟล์เก่า
  /// จึงทำไม่ได้ และต้องรายงานว่าทำไม่ได้ ไม่ใช่เดาแล้วรายงานตัวเลข
  final String? processId;
  final String event;
  final String regionIdentifier;
  final String conclusion;
  final String rawSignals;
  final int lineNumber;

  /// อายุ process ณ ตอนเขียนบรรทัด — `null` ถ้าอ่านไม่ได้
  ///
  /// **อ่านสองรูปแบบ และต้องอ่านได้ทั้งคู่ตลอดไป:**
  /// - `uptimeMs=1234` — รูปแบบปัจจุบัน (มิลลิวินาทีจำนวนเต็ม) อยู่ในตัวระบุ
  ///   process ที่ native เขียนไว้ต้นคอลัมน์สัญญาณดิบทั้งสองแพลตฟอร์ม
  /// - `uptime=1234.5s` — รูปแบบเดิม ยังต้องอ่านได้เพราะไฟล์หลักฐานจากรอบทดสอบ
  ///   ก่อนหน้า (เช่น `docs/test-data/2026-08-30_overnight_region_flapping.log`)
  ///   ใช้รูปแบบนั้น และ **ห้ามแก้ไฟล์เก่าให้เข้ารูปแบบใหม่**
  ///
  /// ลอง `uptimeMs` ก่อนเสมอ — ค่ามิลลิวินาทีละเอียดกว่าและเป็นค่าที่บรรทัดใหม่มี
  double? get uptimeSeconds {
    final millis = RegExp(r'uptimeMs=(\d+)').firstMatch(rawSignals);
    if (millis != null) {
      final parsed = int.tryParse(millis.group(1)!);
      if (parsed != null) return parsed / 1000.0;
    }
    final match = RegExp(r'uptime=([0-9.]+)s').firstMatch(rawSignals);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  /// ดึง timezone offset จากท้ายสตริง เช่น `+07:00` — `Z` หรือไม่มี = ศูนย์
  static Duration _offsetOf(String isoTimestamp) {
    final match = RegExp(r'([+-])(\d{2}):(\d{2})$')
        .firstMatch(isoTimestamp.trim());
    if (match == null) return Duration.zero;
    final sign = match.group(1) == '-' ? -1 : 1;
    return Duration(
          hours: int.parse(match.group(2)!),
          minutes: int.parse(match.group(3)!),
        ) *
        sign;
  }

  /// คอลัมน์ที่ 2 เป็น `processId` ก็ต่อเมื่อหน้าตาเป็นเลขฐานสิบหกพิมพ์เล็ก 8 ตัว
  ///
  /// ใช้รูปแบบของค่าเป็นตัวแยกรุ่นไฟล์ แทนการนับคอลัมน์อย่างเดียว — คอลัมน์ที่ 2
  /// ของไฟล์รูปแบบเก่าคือชื่อ event (`enter`/`exit`/`launch`) ซึ่งไม่มีทางตรงกับ
  /// รูปแบบนี้ จึงแยกได้แน่นอนโดยไม่ต้องพึ่งจำนวนคอลัมน์ที่อาจเพี้ยนได้
  static final RegExp _processIdPattern = RegExp(r'^[0-9a-f]{8}$');

  static LogEntry? tryParse(String line, int lineNumber) {
    final parts = line.split('\t');
    if (parts.length < 4) return null;
    final parsed = DateTime.tryParse(parts[0]);
    if (parsed == null) return null;
    // DateTime.parse แปลงเป็น UTC ให้อัตโนมัติเมื่อสตริงมี offset — บวก offset
    // กลับเข้าไปเพื่อให้ field ชั่วโมง/วัน อ่านได้ตรงกับนาฬิกาของผู้ทดสอบ
    final timestamp = parsed.toUtc().add(_offsetOf(parts[0]));

    final hasProcessId =
        parts.length >= 6 && _processIdPattern.hasMatch(parts[1]);
    final offset = hasProcessId ? 1 : 0;
    String columnAt(int index) =>
        parts.length > index + offset ? parts[index + offset] : '';

    return LogEntry(
      timestamp: timestamp,
      processId: hasProcessId ? parts[1] : null,
      event: columnAt(1),
      regionIdentifier: columnAt(2),
      conclusion: columnAt(3),
      rawSignals: columnAt(4),
      lineNumber: lineNumber,
    );
  }
}

/// ช่วงเวลาหนึ่งช่วง (อยู่ในโซน หรือหลุดออกจากโซน)
class Interval {
  Interval(this.start, this.end, this.startLine);

  final DateTime start;
  final DateTime end;
  final int startLine;

  Duration get duration => end.difference(start);
}

void main(List<String> args) {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    stderr.writeln(
      'ใช้: dart run tool/analyze_region_log.dart <log> [--dwell=<วินาที>] [--gap=<วินาที>]',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final file = File(positional.first);
  if (!file.existsSync()) {
    stderr.writeln('ไม่พบไฟล์: ${file.path}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final entries = <LogEntry>[];
  final unparsed = <int>[];
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) continue;
    final entry = LogEntry.tryParse(lines[i], i + 1);
    if (entry == null) {
      unparsed.add(i + 1);
    } else {
      entries.add(entry);
    }
  }

  if (entries.isEmpty) {
    stderr.writeln('ไม่มีบรรทัดที่ parse ได้เลยใน ${file.path}');
    exitCode = 65; // EX_DATAERR
    return;
  }

  _printHeader(file, entries, unparsed);
  _printProcessLifetimes(entries);
  final anomalies = _printSequenceIntegrity(entries);
  final inside = _buildIntervals(entries, from: 'enter', to: 'exit');
  final outside = _buildIntervals(entries, from: 'exit', to: 'enter');
  _printStats('ช่วงที่อยู่ในโซน (enter → exit ถัดไป)', inside);
  _printStats('ช่วงที่หลุดออกจากโซน (exit → enter ถัดไป)', outside);
  _printHistogram('การกระจายตัวของช่วงที่อยู่ในโซน', inside);
  _printHistogram('การกระจายตัวของช่วงที่หลุดออก', outside);
  _printDeliveryArtifacts(entries);
  _printExitDelaySignature(inside);
  _printHourlyFlap(entries);
  _printDebounceSweep(inside, outside, args);
  _printFooter(anomalies);
}

void _printHeader(File file, List<LogEntry> entries, List<int> unparsed) {
  final first = entries.first.timestamp;
  final last = entries.last.timestamp;
  final span = last.difference(first);
  final counts = <String, int>{};
  for (final e in entries) {
    counts[e.event] = (counts[e.event] ?? 0) + 1;
  }

  _title('ภาพรวมของไฟล์');
  print('ไฟล์            : ${file.path}');
  print('บรรทัดที่ parse ได้ : ${entries.length}');
  if (unparsed.isNotEmpty) {
    print(
      '⚠️ บรรทัดที่ parse ไม่ได้ : ${unparsed.length} (บรรทัดที่ ${unparsed.join(", ")})',
    );
  }
  print('เริ่ม           : ${_wall(first)}');
  print('จบ             : ${_wall(last)}');
  print('กินเวลารวม      : ${_humanDuration(span)}');
  final keys = counts.keys.toList()..sort();
  for (final key in keys) {
    print('event "$key" : ${counts[key]} ครั้ง');
  }

  final conclusions = <String, int>{};
  for (final e in entries) {
    conclusions[e.conclusion] = (conclusions[e.conclusion] ?? 0) + 1;
  }
  print('');
  print('คอลัมน์ข้อสรุป (บอกว่าแต่ละ event เกิดตอนแอปอยู่ในบริบทไหน):');
  final ckeys = conclusions.keys.toList()..sort();
  for (final key in ckeys) {
    print('  $key : ${conclusions[key]}');
  }
}

/// process แต่ละตัวมีชีวิตอยู่นานแค่ไหน และแต่ละ event มาจาก process ไหน
///
/// สำคัญเพราะถ้ามีหลายบรรทัด `launch` ในไฟล์เดียว แปลว่า process ตายแล้วถูก
/// ปลุกใหม่ระหว่างทาง ซึ่งเป็นคนละเรื่องกับการที่แอปรันยาวทั้งคืน
///
/// **สองโหมด และต้องบอกผู้อ่านเสมอว่ากำลังใช้โหมดไหน:**
///
/// - ไฟล์ที่มีคอลัมน์ `processId` (ตั้งแต่ ADR-14) — จัดกลุ่ม event ตาม
///   `processId` ตรง ๆ **เป็นข้อเท็จจริง ไม่ใช่การอนุมาน**
/// - ไฟล์รูปแบบเก่า — ต้องเดาว่า event อยู่ระหว่าง `launch` สองบรรทัดไหน ซึ่ง
///   **ผิดได้** ถ้าบรรทัด `launch` หายไป (เช่นเขียนไฟล์ไม่สำเร็จตอนเครื่องล็อก)
///   หรือถ้า event ถูกคิวไว้แล้วส่งข้ามรอบ process — จึงพิมพ์คำเตือนกำกับ
void _printProcessLifetimes(List<LogEntry> entries) {
  _title('อายุของแต่ละ process');

  final withProcessId = entries.where((e) => e.processId != null).toList();
  if (withProcessId.length == entries.length && entries.isNotEmpty) {
    _printProcessLifetimesById(entries);
    return;
  }

  if (withProcessId.isNotEmpty) {
    print(
      '⚠️  ไฟล์นี้ปนกันสองรูปแบบ: ${withProcessId.length} จาก ${entries.length} '
      'บรรทัดมี processId — รายงานข้างล่างใช้วิธีเดาจากบรรทัด launch ทั้งไฟล์',
    );
    print('');
  } else {
    print(
      '⚠️  ไฟล์นี้ไม่มีคอลัมน์ processId (เก็บก่อน ADR-14) — การจับคู่ event เข้ากับ '
      'process ข้างล่างเป็น**การอนุมานจากลำดับเวลา ไม่ใช่ข้อเท็จจริง**',
    );
    print('');
  }

  final launches = entries.where((e) => e.event == 'launch').toList();
  if (launches.isEmpty) {
    print(
      'ไม่มีบรรทัด launch ในไฟล์นี้ (log อาจถูกล้างหลัง process เริ่มไปแล้ว)',
    );
    return;
  }
  print('พบบรรทัด launch ${launches.length} ครั้ง');
  print('');
  for (var i = 0; i < launches.length; i++) {
    final launch = launches[i];
    final nextLaunchTime = i + 1 < launches.length
        ? launches[i + 1].timestamp
        : entries.last.timestamp;
    // uptime สูงสุดที่บันทึกได้ก่อน process ถัดไปจะเริ่ม
    final owned = entries.where(
      (e) =>
          !e.timestamp.isBefore(launch.timestamp) &&
          (i + 1 >= launches.length || e.timestamp.isBefore(nextLaunchTime)),
    );
    var maxUptime = 0.0;
    for (final e in owned) {
      final uptime = e.uptimeSeconds;
      if (uptime != null && uptime > maxUptime) maxUptime = uptime;
    }
    print(
      'launch #${i + 1} ${_wall(launch.timestamp)} '
      '· ${launch.conclusion} '
      '· อายุที่บันทึกได้สูงสุด ${_humanDuration(Duration(milliseconds: (maxUptime * 1000).round()))} '
      '· ${_launchRegions(launch)}',
    );
  }
}

/// รายงานแบบที่ **ไม่ต้องเดาอะไรเลย** — ใช้ได้เมื่อทุกบรรทัดมี `processId`
void _printProcessLifetimesById(List<LogEntry> entries) {
  // เรียงตามลำดับที่เจอครั้งแรกในไฟล์ ไม่ใช่ตามตัวอักษรของ id — ผู้อ่านต้องเห็น
  // ลำดับเวลาที่ process เกิดขึ้นจริง
  final order = <String>[];
  final byProcess = <String, List<LogEntry>>{};
  for (final entry in entries) {
    final id = entry.processId!;
    if (!byProcess.containsKey(id)) order.add(id);
    byProcess.putIfAbsent(id, () => []).add(entry);
  }

  print(
    'พบ ${order.length} process จาก processId ที่ต่างกัน (ไม่ใช่การอนุมาน)',
  );
  print('');

  for (var i = 0; i < order.length; i++) {
    final id = order[i];
    final owned = byProcess[id]!;
    final launch = owned.where((e) => e.event == 'launch').firstOrNull;
    var maxUptime = 0.0;
    for (final e in owned) {
      final uptime = e.uptimeSeconds;
      if (uptime != null && uptime > maxUptime) maxUptime = uptime;
    }
    final events = <String, int>{};
    for (final e in owned) {
      events[e.event] = (events[e.event] ?? 0) + 1;
    }
    final breakdown = events.entries
        .map((e) => '${e.key}×${e.value}')
        .join(' ');

    print(
      // `procUuid=` ไม่ใช่ `pid=` — ค่านี้คือคอลัมน์ที่ 2 (ตัวระบุที่เราสร้างเอง)
      // ไม่ใช่ pid ของระบบปฏิบัติการ ป้ายเดิมทำให้คนที่เอาไปเทียบกับ `logcat`
      // หาไม่เจอแล้วสรุปว่า process ไม่ตรงกัน — pid จริงอยู่ในคอลัมน์สัญญาณดิบ
      'process #${i + 1} procUuid=$id '
      '${_wall(owned.first.timestamp)} → ${_wall(owned.last.timestamp)}',
    );
    print(
      // ⚠️ `conclusion` ของบรรทัด `launch` **ไม่ใช่หลักฐาน** ทั้งสองแพลตฟอร์ม:
      // มันถูกคำนวณใน `Application.onCreate()` / `didFinishLaunchingWithOptions`
      // ซึ่งเกิดก่อนที่แอปจะมี UI ได้เสมอ ค่าจึงเป็น `relaunchedFromTerminated`
      // ทุกครั้งแม้ผู้ใช้จะกดไอคอนเปิดแอปเอง — พิมพ์ไว้เป็นสัญญาณดิบเท่านั้น
      '   บริบทตอนเริ่ม (ไม่ใช่หลักฐาน ดูหมายเหตุท้ายรายงาน) : '
      '${launch?.conclusion ?? "ไม่มีบรรทัด launch — process นี้เริ่มก่อนล้าง log"}',
    );
    print(
      '   อายุสูงสุดที่บันทึกได้ : '
      '${_humanDuration(Duration(milliseconds: (maxUptime * 1000).round()))}',
    );
    print('   event : $breakdown');
    if (launch != null) {
      print('   ${_launchRegions(launch)}');
    }
    print('');
  }

  // สิ่งที่รอบทดสอบต้องการตอบให้ได้: มี process ที่ระบบสร้างขึ้นมาเองไหม
  //
  // **นับจากบรรทัด `enter`/`exit` เท่านั้น ไม่ใช่บรรทัด `launch`** — บรรทัด
  // `launch` ถูกเขียนใน `Application.onCreate()` (Android) /
  // `didFinishLaunchingWithOptions` (iOS) ซึ่งจบก่อนที่ Activity/scene ตัวแรกจะ
  // ขึ้นมาเสมอ ณ จุดนั้นแอปยัง "ไม่เคย foreground" ทุกครั้ง ค่า `conclusion` ของ
  // บรรทัดนั้นจึงเป็น `relaunchedFromTerminated` เสมอ **แม้ผู้ใช้กดไอคอนเปิดเอง**
  // การนับจากบรรทัดนั้นคือการนับ process ทั้งหมด ไม่ใช่การนับหลักฐาน
  final relaunched = order
      .where(
        (id) => byProcess[id]!.any(
          (e) =>
              (e.event == 'enter' || e.event == 'exit') &&
              e.conclusion == 'relaunchedFromTerminated',
        ),
      )
      .toList();
  print(
    'process ที่ได้ event ตอนยังไม่เคยมี UI (enter/exit + relaunchedFromTerminated) : '
    '${relaunched.length} จาก ${order.length}',
  );
  if (relaunched.isNotEmpty) {
    print('   ${relaunched.join(", ")}');
  }
  print('');
  print(
    'หมายเหตุ: สิ่งที่พิสูจน์ว่าเป็น process ใหม่คือ **procUuid ที่ไม่เคยปรากฏ '
    'มาก่อนในไฟล์เดียวกัน** เท่านั้น · `conclusion` ของบรรทัด `launch` เป็น '
    '`relaunchedFromTerminated` เสมอโดยโครงสร้างของโค้ด จึงห้ามอ้างเป็นหลักฐาน',
  );
}

/// region ที่ระบบยังเก็บไว้ให้ตอน launch — ชื่อ key ต่างกันตามแพลตฟอร์ม
///
/// iOS เขียน `monitoredRegions=[...]` (มาจาก `CLLocationManager.monitoredRegions`)
/// ส่วน Android เขียน `restoredRegions=[...]` (มาจากไฟล์ที่เราเก็บเอง เพราะ
/// Android ไม่มีชุด region ระดับ OS ให้ถาม — ดู ADR-14) **ตั้งใจใช้คนละชื่อ**
/// เพื่อไม่ให้ใครอ่าน log แล้วเข้าใจว่าสองแพลตฟอร์มได้ค่านี้มาจากที่เดียวกัน
/// `restoredRegions=<read-failed:เหตุผล>` ฝั่ง Android **ไม่ใช่รายการว่าง** แต่คือ
/// "อ่านไฟล์สถานะไม่สำเร็จ จึงตอบไม่ได้ว่ามีอะไรอยู่" — สองอย่างนี้เคยเขียนออกมา
/// เป็น `[]` เหมือนกัน ซึ่งทำให้ตีความผลผิดไปคนละทาง
String _launchRegions(LogEntry launch) {
  for (final key in const ['monitoredRegions', 'restoredRegions']) {
    final failed = RegExp('$key=<read-failed:([^>]*)>')
        .firstMatch(launch.rawSignals);
    if (failed != null) {
      return '$key: อ่านไม่สำเร็จ (${failed.group(1)}) — '
          '**ไม่ใช่** "ไม่มี region เก็บไว้"';
    }
    final match = RegExp('$key=\\[([^\\]]*)\\]').firstMatch(launch.rawSignals);
    if (match != null) return '$key=[${match.group(1)}]';
  }
  return 'region ตอน launch: ไม่มีข้อมูลในบรรทัดนี้';
}

/// ตรวจว่า enter/exit สลับกันเป็นคู่จริงหรือไม่ — คืนรายการความผิดปกติที่เจอ
List<String> _printSequenceIntegrity(List<LogEntry> entries) {
  _title('ความถูกต้องของลำดับ enter/exit');
  final anomalies = <String>[];
  String? previous;
  LogEntry? previousEntry;
  var transitions = 0;

  for (final e in entries) {
    if (e.event != 'enter' && e.event != 'exit') continue;
    if (previous != null && e.event == previous) {
      anomalies.add(
        'บรรทัด ${e.lineNumber}: "${e.event}" ซ้ำติดกัน '
        '(ครั้งก่อนอยู่บรรทัด ${previousEntry!.lineNumber} '
        'ห่างกัน ${_humanDuration(e.timestamp.difference(previousEntry.timestamp))})',
      );
    }
    previous = e.event;
    previousEntry = e;
    transitions++;
  }

  final enters = entries.where((e) => e.event == 'enter').length;
  final exits = entries.where((e) => e.event == 'exit').length;
  print(
    'enter $enters ครั้ง / exit $exits ครั้ง (รวม $transitions transition)',
  );
  print(
    'เริ่มด้วย: ${entries.firstWhere((e) => e.event == "enter" || e.event == "exit").event}',
  );
  print(
    'จบด้วย  : ${entries.lastWhere((e) => e.event == "enter" || e.event == "exit").event}',
  );

  if (anomalies.isEmpty) {
    print('✅ สลับกันครบทุกคู่ ไม่มี event ซ้อนหรือหายไป');
  } else {
    print('⚠️ พบความผิดปกติ ${anomalies.length} จุด:');
    for (final a in anomalies) {
      print('   - $a');
    }
  }
  return anomalies;
}

List<Interval> _buildIntervals(
  List<LogEntry> entries, {
  required String from,
  required String to,
}) {
  final result = <Interval>[];
  LogEntry? open;
  for (final e in entries) {
    if (e.event != 'enter' && e.event != 'exit') continue;
    if (e.event == from) {
      // ถ้าเปิดค้างอยู่แล้วให้ใช้ตัวล่าสุด (เคส event ซ้ำติดกัน)
      open = e;
    } else if (e.event == to && open != null) {
      result.add(Interval(open.timestamp, e.timestamp, open.lineNumber));
      open = null;
    }
  }
  return result;
}

void _printStats(String label, List<Interval> intervals) {
  _title(label);
  if (intervals.isEmpty) {
    print('ไม่มีข้อมูล');
    return;
  }
  final seconds =
      intervals.map((i) => i.duration.inMilliseconds / 1000).toList()..sort();
  print('จำนวนช่วง : ${seconds.length}');
  print('ต่ำสุด    : ${_humanSeconds(seconds.first)}');
  print('มัธยฐาน   : ${_humanSeconds(_percentile(seconds, 50))}');
  print('เปอร์เซ็นไทล์ 90 : ${_humanSeconds(_percentile(seconds, 90))}');
  print('สูงสุด    : ${_humanSeconds(seconds.last)}');
  final total = seconds.fold<double>(0, (a, b) => a + b);
  print('รวมทั้งหมด : ${_humanSeconds(total)}');
  print('ค่าเฉลี่ย   : ${_humanSeconds(total / seconds.length)}');
}

/// เปอร์เซ็นไทล์แบบ nearest-rank — เลือกค่าที่มีอยู่จริงในชุดข้อมูล ไม่ประมาณ
/// ค่าระหว่างจุด เพราะข้อมูลชุดนี้เล็กและการประมาณจะสร้างตัวเลขที่ไม่เคยเกิดจริง
double _percentile(List<double> sorted, int percentile) {
  if (sorted.isEmpty) return 0;
  final rank = (percentile / 100 * sorted.length).ceil();
  final index = (rank - 1).clamp(0, sorted.length - 1);
  return sorted[index];
}

const List<({String label, int upperBoundSeconds})> _buckets = [
  (label: '< 10 วินาที', upperBoundSeconds: 10),
  (label: '10-30 วินาที', upperBoundSeconds: 30),
  (label: '30-60 วินาที', upperBoundSeconds: 60),
  (label: '1-2 นาที', upperBoundSeconds: 120),
  (label: '2-5 นาที', upperBoundSeconds: 300),
  (label: '5-15 นาที', upperBoundSeconds: 900),
  (label: '15-60 นาที', upperBoundSeconds: 3600),
  (label: '> 1 ชั่วโมง', upperBoundSeconds: 1 << 30),
];

void _printHistogram(String label, List<Interval> intervals) {
  _title(label);
  if (intervals.isEmpty) {
    print('ไม่มีข้อมูล');
    return;
  }
  final counts = List<int>.filled(_buckets.length, 0);
  for (final interval in intervals) {
    final seconds = interval.duration.inMilliseconds / 1000;
    for (var i = 0; i < _buckets.length; i++) {
      if (seconds < _buckets[i].upperBoundSeconds) {
        counts[i]++;
        break;
      }
    }
  }
  final maxCount = counts.fold<int>(0, (a, b) => a > b ? a : b);
  for (var i = 0; i < _buckets.length; i++) {
    if (counts[i] == 0) continue;
    final bar = '█' * ((counts[i] / maxCount) * 40).round().clamp(1, 40);
    final percent = (counts[i] / intervals.length * 100).toStringAsFixed(1);
    print(
      '${_padRight(_buckets[i].label, 14)} ${_padLeft("${counts[i]}", 4)} '
      '(${_padLeft(percent, 5)}%) $bar',
    );
  }
}

/// แยก transition ที่น่าจะเป็น **ผลของการส่ง event ค้าง** ออกจากการเข้า/ออกจริง
///
/// สองกลุ่มที่ต้องระวังเป็นพิเศษ:
///
/// 1. **คู่ที่ห่างกันไม่ถึง 1 วินาที** — เป็นไปไม่ได้ทางกายภาพที่จะออกแล้วเข้าใหม่
///    ในเสี้ยววินาที เกือบแน่นอนว่าเป็น event ที่ระบบคิวไว้แล้วส่งมาติด ๆ กัน
///    timestamp ในไฟล์คือ **เวลาที่แอปได้รับ** ไม่ใช่เวลาที่ข้ามขอบเขตจริง
/// 2. **transition ที่เกิดภายใน 5 วินาทีหลังบรรทัด `launch`** — process เพิ่งเกิด
///    ใหม่ `lastKnownRegionState` ในหน่วยความจำว่างเปล่า จึงยิง event แรกออกมา
///    เสมอไม่ว่าสถานะจริงจะเปลี่ยนหรือไม่
///
/// ทั้งสองกลุ่มยัง**นับรวมอยู่ในสถิติข้างบน** จงใจไม่ตัดทิ้งเงียบ ๆ — แสดงแยกให้
/// เห็นเพื่อให้คนอ่านตัดสินใจเองว่าจะนับหรือไม่นับ
void _printDeliveryArtifacts(List<LogEntry> entries) {
  _title(
    'transition ที่น่าจะเป็นผลของการส่ง event ค้าง (ไม่ใช่การเข้า/ออกจริง)',
  );

  final launchTimes = entries
      .where((e) => e.event == 'launch')
      .map((e) => e.timestamp)
      .toList();
  final transitions = entries
      .where((e) => e.event == 'enter' || e.event == 'exit')
      .toList();

  final subSecond = <String>[];
  for (var i = 1; i < transitions.length; i++) {
    final gap = transitions[i].timestamp.difference(
      transitions[i - 1].timestamp,
    );
    if (gap.inMilliseconds < 1000) {
      subSecond.add(
        'บรรทัด ${transitions[i - 1].lineNumber}→${transitions[i].lineNumber} '
        '${_wall(transitions[i].timestamp)} '
        '${transitions[i - 1].event}→${transitions[i].event} '
        'ห่างกัน ${gap.inMilliseconds} มิลลิวินาที',
      );
    }
  }

  final nearLaunch = transitions.where((t) {
    for (final launchTime in launchTimes) {
      final delta = t.timestamp.difference(launchTime);
      if (!delta.isNegative && delta.inSeconds < 5) return true;
    }
    return false;
  }).toList();

  print('คู่ที่ห่างกันไม่ถึง 1 วินาที : ${subSecond.length} คู่');
  for (final line in subSecond) {
    print('  - $line');
  }
  print('');
  print('transition ภายใน 5 วินาทีหลัง launch : ${nearLaunch.length} รายการ');
  for (final t in nearLaunch) {
    print('  - บรรทัด ${t.lineNumber} ${_wall(t.timestamp)} ${t.event}');
  }

  final enters = transitions.where((e) => e.event == 'enter').length;
  final enterArtifacts =
      nearLaunch.where((e) => e.event == 'enter').length +
      subSecond.where((l) => l.contains('exit→enter')).length;
  print('');
  print('สรุปการนับ "enter" ได้หลายแบบ — เลือกเองตามคำถามที่จะตอบ:');
  print('  นับดิบทุกบรรทัด                       : $enters');
  print(
    '  ตัด enter ที่เป็น artifact ข้างบนออก     : ${enters - enterArtifacts}',
  );
  print(
    '  (ตัวเลขสองค่านี้ต่างกัน $enterArtifacts — ต้องระบุทุกครั้งว่าใช้แบบไหน)',
  );
}

/// หา "ลายเซ็น" ของเวลาหน่วงก่อนประกาศ exit ที่ CoreLocation ใช้
///
/// ถ้าระบบหน่วงคงที่ก่อนประกาศ exit ช่วงที่อยู่ในโซนของ flap ที่สัญญาณหายทันที
/// จะกองอยู่ที่ค่าคงที่นั้นพอดี — ดูจากการกระจายตัวละเอียดระดับวินาที
void _printExitDelaySignature(List<Interval> inside) {
  _title('ลายเซ็นของเวลาหน่วงก่อนประกาศ exit');
  if (inside.isEmpty) {
    print('ไม่มีข้อมูล');
    return;
  }
  final seconds = inside.map((i) => i.duration.inMilliseconds / 1000).toList()
    ..sort();
  final perSecond = <int, int>{};
  for (final value in seconds) {
    if (value >= 25 && value < 40) {
      perSecond[value.floor()] = (perSecond[value.floor()] ?? 0) + 1;
    }
  }
  if (perSecond.isEmpty) {
    print('ไม่พบช่วงที่อยู่ในโซนในช่วง 25-40 วินาที');
    return;
  }
  print('การกระจายตัวละเอียดของช่วงที่อยู่ในโซน เฉพาะช่วง 25-40 วินาที:');
  final keys = perSecond.keys.toList()..sort();
  final maxCount = perSecond.values.fold<int>(0, (a, b) => a > b ? a : b);
  for (final key in keys) {
    final count = perSecond[key]!;
    final bar = '█' * ((count / maxCount) * 40).round().clamp(1, 40);
    print(
      '  ${_padLeft("$key", 2)}-${key + 1} วินาที ${_padLeft("$count", 3)} $bar',
    );
  }
  final tight = seconds.where((v) => v >= 29.5 && v <= 30.5).length;
  print('');
  print(
    'ช่วงที่อยู่ในโซน 29.5-30.5 วินาที : $tight จาก ${seconds.length} '
    '(${(tight / seconds.length * 100).toStringAsFixed(1)}%)',
  );
  print(
    'ยิ่งกองแน่นที่ค่าเดียว ยิ่งบอกว่าเป็นค่าคงที่ของระบบ ไม่ใช่ความบังเอิญ',
  );
}

void _printHourlyFlap(List<LogEntry> entries) {
  _title('ความถี่ของ flap ต่อชั่วโมง (นับ enter)');
  final perHour = <String, int>{};
  for (final e in entries.where((e) => e.event == 'enter')) {
    final local = e.timestamp;
    final key =
        '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:00';
    perHour[key] = (perHour[key] ?? 0) + 1;
  }
  if (perHour.isEmpty) {
    print('ไม่มีข้อมูล');
    return;
  }
  final keys = perHour.keys.toList()..sort();
  final maxCount = perHour.values.fold<int>(0, (a, b) => a > b ? a : b);
  for (final key in keys) {
    final count = perHour[key]!;
    final bar = '█' * ((count / maxCount) * 40).round().clamp(1, 40);
    print('$key ${_padLeft("$count", 3)} $bar');
  }
  final busiest = keys.reduce((a, b) => perHour[a]! >= perHour[b]! ? a : b);
  final quietest = keys.reduce((a, b) => perHour[a]! <= perHour[b]! ? a : b);
  print('');
  print('ถี่ที่สุด : $busiest (${perHour[busiest]} ครั้ง)');
  print('น้อยที่สุด : $quietest (${perHour[quietest]} ครั้ง)');
}

/// จำลองผลของค่า debounce ต่าง ๆ กับข้อมูลจริง
///
/// กติกาที่จำลอง (ตรงกับที่ ADR-11 กำหนด):
///   1. **รวม session**: ถ้า exit แล้ว enter ใหม่ภายใน `gap` ให้ถือเป็น session
///      เดิม ไม่ใช่การเข้าสาขาครั้งใหม่
///   2. **ต้องอยู่นานพอ**: หลังรวมแล้ว session ที่กินเวลารวมน้อยกว่า `dwell`
///      ไม่นับเป็นการเข้าสาขา
///
/// ลำดับสำคัญ — ต้องรวมก่อนแล้วค่อยกรองด้วยเวลา ถ้ากรองก่อน ช่วงสั้น ๆ ที่
/// ต่อเนื่องกันจะถูกตัดทิ้งทีละอันทั้งที่รวมกันแล้วนานพอ
void _printDebounceSweep(
  List<Interval> inside,
  List<Interval> outside,
  List<String> args,
) {
  _title('จำลองผลของค่า debounce กับข้อมูลจริง');
  if (inside.isEmpty) {
    print('ไม่มีข้อมูล');
    return;
  }

  final customDwell = _intArg(args, 'dwell');
  final customGap = _intArg(args, 'gap');

  print('ก่อนกรอง: ${inside.length} ช่วง (enter ที่มี exit ปิดครบคู่)');
  final maxOutside = outside.isEmpty
      ? Duration.zero
      : outside.map((o) => o.duration).reduce((a, b) => a > b ? a : b);
  print('ช่วงที่หลุดออกนานที่สุดในไฟล์นี้: ${_humanDuration(maxOutside)}');
  print(
    '→ ค่า "รวม session" ที่มากกว่านี้จะยุบทั้งไฟล์เหลือ session เดียวโดยอัตโนมัติ',
  );
  print('');
  print(
    '${_padRight("รวม session ถ้าห่างน้อยกว่า", 28)}'
    '${_padRight("ต้องอยู่ต่อเนื่องอย่างน้อย", 26)}เหลือกี่ครั้ง',
  );
  print('-' * 70);

  final gaps = <int>[60, 120, 180, 240, 300, 600, 1800];
  final dwells = <int>[0, 60, 120, 300, 600];
  if (customGap != null && !gaps.contains(customGap)) gaps.add(customGap);
  if (customDwell != null && !dwells.contains(customDwell))
    dwells.add(customDwell);
  gaps.sort();
  dwells.sort();

  for (final gap in gaps) {
    for (final dwell in dwells) {
      final count = _simulate(inside, gapSeconds: gap, dwellSeconds: dwell);
      final marker = (gap == customGap && dwell == customDwell)
          ? '  ← ที่ระบุมา'
          : '';
      print(
        '${_padRight(_humanSeconds(gap.toDouble()), 28)}'
        '${_padRight(dwell == 0 ? "ไม่กำหนด" : _humanSeconds(dwell.toDouble()), 26)}'
        '$count$marker',
      );
    }
    print('-' * 70);
  }
}

/// คืนจำนวน session ที่เหลือหลังรวมและกรอง
int _simulate(
  List<Interval> inside, {
  required int gapSeconds,
  required int dwellSeconds,
}) {
  if (inside.isEmpty) return 0;
  // 1) รวมช่วงที่ห่างกันน้อยกว่า gap เข้าด้วยกัน
  final merged = <({DateTime start, DateTime end, Duration insideTotal})>[];
  var start = inside.first.start;
  var end = inside.first.end;
  var insideTotal = inside.first.duration;
  for (var i = 1; i < inside.length; i++) {
    final gap = inside[i].start.difference(end);
    if (gap.inSeconds < gapSeconds) {
      end = inside[i].end;
      insideTotal += inside[i].duration;
    } else {
      merged.add((start: start, end: end, insideTotal: insideTotal));
      start = inside[i].start;
      end = inside[i].end;
      insideTotal = inside[i].duration;
    }
  }
  merged.add((start: start, end: end, insideTotal: insideTotal));

  // 2) กรองด้วยเวลาที่อยู่จริงรวมกันใน session
  return merged.where((m) => m.insideTotal.inSeconds >= dwellSeconds).length;
}

void _printFooter(List<String> anomalies) {
  _title('ข้อควรระวังในการตีความ');
  print('- ตัวเลขทั้งหมดมาจาก log ไฟล์เดียว = การทดสอบรอบเดียว สถานที่เดียว');
  print('  เครื่องเดียว ห้ามใช้เป็นค่ามาตรฐานจนกว่าจะเก็บจากสาขาจริงหลายที่');
  print(
    '- ช่วงที่ "หลุดออก" สั้นกว่า 30 วินาทีแทบเป็นไปไม่ได้ เพราะ CoreLocation',
  );
  print(
    '  หน่วงก่อนประกาศ exit อยู่แล้ว — ถ้าเจอ ให้สงสัยว่า process เพิ่งเริ่มใหม่',
  );
  print('  แล้ว state ในหน่วยความจำถูกรีเซ็ต (ดูบรรทัด launch ประกอบ)');
  if (anomalies.isNotEmpty) {
    print(
      '- ⚠️ มีความผิดปกติของลำดับ ${anomalies.length} จุด ตรวจก่อนใช้ตัวเลขข้างบน',
    );
  }
}

// ---- helper ----

void _title(String text) {
  print('');
  print('=' * 70);
  print(text);
  print('=' * 70);
}

int? _intArg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) {
      return int.tryParse(a.substring(name.length + 3));
    }
  }
  return null;
}

String _two(int value) => value.toString().padLeft(2, '0');

/// พิมพ์เวลาแบบ wall clock ของเครื่องที่ทดสอบ — จงใจไม่ใช้ `toIso8601String()`
/// เพราะมันจะเติม `Z` ต่อท้ายและทำให้อ่านผิดว่าเป็น UTC
String _wall(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} '
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

String _padLeft(String text, int width) => text.padLeft(width);

String _padRight(String text, int width) =>
    text.length >= width ? text : text + ' ' * (width - text.length);

String _humanSeconds(double seconds) =>
    _humanDuration(Duration(milliseconds: (seconds * 1000).round()));

String _humanDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} มิลลิวินาที';
  if (d.inSeconds < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} วินาที';
  }
  if (d.inMinutes < 60) {
    return '${d.inMinutes} นาที ${d.inSeconds % 60} วินาที';
  }
  return '${d.inHours} ชั่วโมง ${d.inMinutes % 60} นาที';
}
