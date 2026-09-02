import 'conformance.dart';
import 'conformance_cases.dart';
import 'region_log.dart';
import 'visit_observation.dart';

/// รุ่นของรูปแบบไฟล์ vector — ขึ้นเลขเมื่อ **โครงสร้างไฟล์** เปลี่ยน
/// (ไม่ใช่เมื่อค่าที่คาดหวังเปลี่ยน) เพื่อให้ port ที่อ่านไฟล์รู้ว่าต้องแก้ตัวอ่าน
const int vectorFormatVersion = 1;

/// สร้างเอกสาร vector ทั้งฉบับจากรายการเคส
Map<String, Object?> buildVectorDocument({required String repoRoot}) {
  final cases = <Map<String, Object?>>[];
  for (final testCase in conformanceCases) {
    final logFile = testCase.logFile;
    final observations = logFile != null
        ? observationsFromLog(parseRegionLog('$repoRoot/$logFile'))
        : testCase.observations!;

    final run = runConformanceCase(
      cooldownMs: testCase.cooldown.inMilliseconds,
      blindnessCeilingMs: testCase.blindnessCeiling.inMilliseconds,
      initialState: testCase.initialState,
      observations: observations,
    );

    cases.add({
      'name': testCase.name,
      'why': testCase.why,
      'cooldownMs': testCase.cooldown.inMilliseconds,
      'blindnessCeilingMs': testCase.blindnessCeiling.inMilliseconds,
      'initialState': encodeState(testCase.initialState),
      if (logFile != null)
        'logFile': logFile
      else
        'observations': [
          for (final observation in observations)
            encodeObservation(observation),
        ],
      'observationCount': observations.length,
      'expectedEvents': [for (final event in run.events) encodeEvent(event)],
      'expectedRejections': run.rejections,
      'expectedFinalState': encodeState(run.finalState),
    });
  }

  return {
    'formatVersion': vectorFormatVersion,
    'note': 'สัญญากลางของชั้นกรอง visit — Dart / Kotlin / Swift ต้องให้ผลตรงกันทุกช่อง. '
        'เวลาทุกค่าเป็นจำนวนเต็มมิลลิวินาทีนับจาก epoch (UTC). '
        'สร้างด้วย `dart run bin/generate_vectors.dart` ห้ามแก้ด้วยมือ.',
    'source': 'prototype/visit_filter',
    'cases': cases,
  };
}

/// อ่าน observation ของเคสหนึ่งกลับมา — รองรับทั้งแบบเขียนตรงและแบบอ้างไฟล์ log
List<VisitObservation> observationsForCase(
  Map<String, Object?> caseJson, {
  required String repoRoot,
}) {
  final logFile = caseJson['logFile'] as String?;
  if (logFile != null) {
    return observationsFromLog(parseRegionLog('$repoRoot/$logFile'));
  }
  return [
    for (final observation in caseJson['observations']! as List<Object?>)
      decodeObservation(observation! as Map<String, Object?>),
  ];
}
