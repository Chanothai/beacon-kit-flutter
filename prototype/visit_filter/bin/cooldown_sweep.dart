// หา cooldown ต่ำที่สุดที่ยังผ่านเกณฑ์รับของทั้งสองไฟล์
//
//   dart run bin/cooldown_sweep.dart
//
// ⚠️ ผลลัพธ์ของสคริปต์นี้ **ไม่ใช่ค่าที่ควรตั้งเป็น default** — มันคือขอบของ
// ข้อมูลสองชุด การตั้ง default ที่ขอบแปลว่าคืนถัดไปที่เงียบนานกว่าเดิมแค่
// มิลลิวินาทีเดียวจะทำให้ได้ visit ปลอมทันที
import 'dart:io';

import 'package:visit_filter_prototype/region_log.dart';
import 'package:visit_filter_prototype/visit_filter.dart';

const String testDataDir = '../../docs/test-data';

const List<String> files = [
  '2026-08-30_overnight_region_flapping.log',
  '2026-09-01_android_overnight_region_flapping.log',
];

int visitCount(List<VisitObservation> observations, Duration cooldown) {
  // ไฟล์หลักฐานทั้งสองไม่มี observation ชนิด SensingLost เลย ค่านี้จึงไม่มีผล
  final filter = VisitFilter(
    cooldown: cooldown,
    blindnessCeiling: const Duration(minutes: 15),
  );
  var state = VisitFilterState.initial;
  var count = 0;
  for (final observation in observations) {
    final reduction = filter.reduce(state, observation);
    state = reduction.state;
    count += reduction.events.whereType<VisitStarted>().length;
  }
  return count;
}

/// ช่วงเงียบทั้งหมดที่วัดได้จากไฟล์ — จาก `exit` ถึง `enter` ถัดไป
///
/// เป็นตัวเดียวกับที่ cooldown ต้องครอบให้ได้ (reducer นับความเงียบจากเวลาที่
/// แพลตฟอร์มประกาศว่าไม่เห็น)
List<Duration> silenceGaps(List<RegionLogEntry> entries) {
  final gaps = <Duration>[];
  DateTime? absentSince;
  for (final entry in entries) {
    switch (entry.event) {
      case 'exit':
        absentSince ??= entry.instant;
      case 'enter':
        if (absentSince != null) {
          gaps.add(entry.instant.difference(absentSince));
          absentSince = null;
        }
    }
  }
  gaps.sort();
  return gaps;
}

String human(Duration d) {
  final ms = d.inMilliseconds;
  final minutes = ms ~/ 60000;
  final seconds = (ms % 60000) / 1000;
  return minutes > 0
      ? '$minutes นาที ${seconds.toStringAsFixed(3)} วินาที'
      : '${seconds.toStringAsFixed(3)} วินาที';
}

/// ค่า cooldown ต่ำที่สุด (ความละเอียด 1 มิลลิวินาที) ที่ยังได้ visit 1 ครั้ง
Duration lowestPassing(List<VisitObservation> observations, {required int ceilingMs}) {
  var low = 1;
  var high = ceilingMs;
  if (visitCount(observations, Duration(milliseconds: high)) != 1) {
    throw StateError('เพดาน ${high}ms ยังไม่ผ่าน — ขยายเพดานก่อน');
  }
  while (low < high) {
    final mid = low + (high - low) ~/ 2;
    if (visitCount(observations, Duration(milliseconds: mid)) == 1) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return Duration(milliseconds: low);
}

void main() {
  final observationsByFile = <String, List<VisitObservation>>{};
  final gapsByFile = <String, List<Duration>>{};
  for (final file in files) {
    final entries = parseRegionLog('$testDataDir/$file');
    observationsByFile[file] = observationsFromLog(entries);
    gapsByFile[file] = silenceGaps(entries);
  }

  const int ceilingMs = 60 * 60 * 1000;
  stdout.writeln('=' * 70);
  stdout.writeln('cooldown ต่ำสุดที่ยังได้ VisitStarted = 1 (ความละเอียด 1 ms)');
  stdout.writeln('=' * 70);

  var combined = Duration.zero;
  for (final file in files) {
    final lowest = lowestPassing(observationsByFile[file]!, ceilingMs: ceilingMs);
    final gaps = gapsByFile[file]!;
    if (lowest > combined) combined = lowest;
    stdout.writeln(file);
    stdout.writeln('  ต่ำสุดที่ผ่าน   : ${lowest.inMilliseconds} ms = ${human(lowest)}');
    stdout.writeln('  ช่วงเงียบยาวสุด : ${gaps.last.inMilliseconds} ms = ${human(gaps.last)}');
    stdout.writeln('  ยาวเป็นอันดับ 2 : ${gaps[gaps.length - 2].inMilliseconds} ms = '
        '${human(gaps[gaps.length - 2])}');
    stdout.writeln('  จำนวนช่วงเงียบ  : ${gaps.length}');
    stdout.writeln('');
  }

  stdout.writeln('-' * 70);
  stdout.writeln('ค่าที่ใช้ได้กับ **ทั้งสองไฟล์**: ${combined.inMilliseconds} ms '
      '= ${human(combined)}');
  for (final file in files) {
    final worst = gapsByFile[file]!.last;
    final margin = combined - worst;
    stdout.writeln('  ระยะห่างจากช่วงเงียบยาวสุดของ $file: '
        '${margin.inMilliseconds} ms');
  }
  stdout.writeln('');

  stdout.writeln('-' * 70);
  stdout.writeln('จำนวน VisitStarted ที่ค่า cooldown ต่าง ๆ');
  stdout.writeln('-' * 70);
  const List<Duration> probes = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 3),
    Duration(minutes: 3, seconds: 29),
    Duration(minutes: 3, seconds: 30),
    Duration(minutes: 4),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];
  stdout.writeln('cooldown'.padRight(24) + files.map((f) => f.split('_').first).join('   '));
  for (final probe in probes) {
    final counts = files.map((f) =>
        visitCount(observationsByFile[f]!, probe).toString().padLeft(10));
    stdout.writeln(human(probe).padRight(24) + counts.join('   '));
  }
  stdout.writeln('');

  stdout.writeln('-' * 70);
  stdout.writeln('ระยะห่างจากขอบเมื่อเลือกค่าต่าง ๆ (ค่า − ช่วงเงียบยาวสุดที่ยังต่ำกว่าค่านั้น)');
  stdout.writeln('-' * 70);
  for (final probe in probes.where((p) => p >= combined)) {
    for (final file in files) {
      final gaps = gapsByFile[file]!;
      final below = gaps.where((g) => g < probe);
      if (below.isEmpty) continue;
      final margin = probe - below.last;
      final headroom = below.last.inMilliseconds == 0
          ? '—'
          : '${(margin.inMilliseconds / below.last.inMilliseconds * 100).toStringAsFixed(1)}%';
      stdout.writeln('${human(probe).padRight(24)}${file.split('_').first.padRight(12)}'
          'เผื่อ ${human(margin).padRight(26)}($headroom เหนือช่วงที่แย่ที่สุด)');
    }
  }
}
