import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:visit_filter_prototype/conformance.dart';

/// ยืนยันว่าไฟล์ vector ที่ **commit ไว้** ยังตรงกับพฤติกรรมของโค้ดปัจจุบัน
///
/// เทสต์นี้คือกลไกกันสามภาษาเพี้ยนจากกัน: ถ้าใครแก้พฤติกรรมของ reducer แล้วไม่
/// สร้างไฟล์ vector ใหม่ เทสต์นี้ล้ม · ถ้าสร้างใหม่ diff ของไฟล์จะโผล่ใน review
/// และเทสต์ของ port ฝั่ง Kotlin/Swift ที่อ่านไฟล์เดียวกันจะล้มจนกว่าจะตามแก้
const String repoRoot = '../..';
const String vectorsPath = '../../spec/visit_filter/vectors.json';

void main() {
  final committed =
      jsonDecode(File(vectorsPath).readAsStringSync()) as Map<String, Object?>;

  test('ไฟล์ vector ที่ commit ไว้ตรงกับพฤติกรรมปัจจุบัน', () {
    final regenerated = buildVectorDocument(repoRoot: repoRoot);
    expect(
      const JsonEncoder.withIndent('  ').convert(regenerated),
      const JsonEncoder.withIndent('  ').convert(committed),
      reason: 'พฤติกรรมเปลี่ยนแต่ไฟล์ vector ยังเป็นของเดิม — '
          'รัน `dart run bin/generate_vectors.dart` แล้ว commit ไฟล์ที่ได้ '
          'พร้อมกับตามแก้ port ฝั่ง Kotlin และ Swift ใน PR เดียวกัน',
    );
  });

  test('รูปแบบไฟล์เป็นรุ่นที่ตัวอ่านรู้จัก', () {
    expect(committed['formatVersion'], vectorFormatVersion);
  });

  final cases = committed['cases']! as List<Object?>;

  test('มีเคสครบและชื่อไม่ซ้ำ', () {
    final names = cases
        .map((c) => (c! as Map<String, Object?>)['name']! as String)
        .toList();
    expect(names.toSet(), hasLength(names.length));
    expect(names, contains('real-log-ios-2026-08-30'));
    expect(names, contains('real-log-android-2026-09-01'));
  });

  for (final entry in cases) {
    final caseJson = entry! as Map<String, Object?>;
    final name = caseJson['name']! as String;

    test('เล่นเคส "$name" จากไฟล์ vector แล้วได้ผลตามที่เขียนไว้', () {
      final run = runConformanceCase(
        cooldownMs: caseJson['cooldownMs']! as int,
        blindnessCeilingMs: caseJson['blindnessCeilingMs']! as int,
        initialState:
            decodeState(caseJson['initialState']! as Map<String, Object?>),
        observations: observationsForCase(caseJson, repoRoot: repoRoot),
      );

      expect(
        [for (final event in run.events) encodeEvent(event)],
        caseJson['expectedEvents'],
      );
      expect(run.rejections, caseJson['expectedRejections']);
      expect(encodeState(run.finalState), caseJson['expectedFinalState']);
    });
  }

  test('เวลาทุกค่าในไฟล์ vector เป็นจำนวนเต็มมิลลิวินาที', () {
    // Swift `Date` เก็บเป็น Double วินาที — ถ้ามีเศษต่ำกว่ามิลลิวินาทีหลุดเข้าไป
    // port ฝั่ง Swift จะเทียบไม่ตรงด้วยเหตุผลที่ดีบักยากมาก
    void checkNumbers(Object? node, String path) {
      switch (node) {
        case final Map<String, Object?> map:
          for (final entry in map.entries) {
            checkNumbers(entry.value, '$path.${entry.key}');
          }
        case final List<Object?> list:
          for (var i = 0; i < list.length; i++) {
            checkNumbers(list[i], '$path[$i]');
          }
        case double _:
          fail('$path เป็นทศนิยม — ไฟล์ vector ต้องมีแต่จำนวนเต็ม');
        default:
          break;
      }
    }

    checkNumbers(committed, 'root');
  });
}
