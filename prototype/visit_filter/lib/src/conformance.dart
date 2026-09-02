import 'epoch_millis.dart';
import 'visit_event.dart';
import 'visit_filter.dart';
import 'visit_filter_state.dart';
import 'visit_observation.dart';

/// การเข้ารหัส **conformance vector** — สัญญากลางที่ทั้งสามภาษาต้องให้ผลตรงกัน
///
/// ⚠️ **เวลาทั้งหมดเป็นจำนวนเต็มมิลลิวินาทีนับจาก epoch (Int64) เท่านั้น**
/// ตั้งแต่ชั้นข้อมูลของ reducer ขึ้นมา (ดู [EpochMillis]) ไฟล์ vector จึงเขียนค่า
/// ลงไปตรง ๆ **ไม่มีการแปลงชนิดตรงกลางให้พลาดได้**:
///
/// - Swift `Date` เก็บเป็น `Double` วินาที — ค่ามิลลิวินาทีบางค่าแทนไม่ได้เป๊ะ
///   การเทียบเท่ากันจึงเป็นการเทียบทศนิยม
/// - Swift `TimeInterval` และ `Duration` ของ Kotlin/Java คนละความละเอียดกัน
/// - Dart `int` เป็น 64 บิตบน VM แต่ 53 บิตบน JS (epoch มิลลิวินาทียังพอดี)
///
/// enum เข้ารหัสด้วย **ชื่อค่าเป็นสตริง** ไม่ใช่ลำดับตัวเลข เพราะการเรียงลำดับ
/// สมาชิก enum ต่างกันระหว่างสามภาษาได้ง่ายและจะเพี้ยนแบบเงียบสนิท

Map<String, Object?> encodeObservation(VisitObservation observation) =>
    switch (observation) {
      RegionSeen(:final regionId, :final atMs) => {
        'kind': 'regionSeen',
        'regionId': regionId,
        'atMs': atMs,
      },
      RegionNotSeen(:final regionId, :final atMs) => {
        'kind': 'regionNotSeen',
        'regionId': regionId,
        'atMs': atMs,
      },
      TimeAdvanced(:final atMs) => {'kind': 'timeAdvanced', 'atMs': atMs},
      SensingLost(:final atMs, :final cause) => {
        'kind': 'sensingLost',
        'atMs': atMs,
        'cause': cause.name,
      },
      SensingRestored(:final atMs) => {'kind': 'sensingRestored', 'atMs': atMs},
      ObservationsEnded(:final atMs) => {
        'kind': 'observationsEnded',
        'atMs': atMs,
      },
    };

VisitObservation decodeObservation(Map<String, Object?> json) {
  final atMs = json['atMs']! as int;
  final regionId = json['regionId'] as String?;
  return switch (json['kind']! as String) {
    'regionSeen' => RegionSeen(regionId: regionId!, atMs: atMs),
    'regionNotSeen' => RegionNotSeen(regionId: regionId!, atMs: atMs),
    'timeAdvanced' => TimeAdvanced(atMs: atMs),
    'sensingLost' => SensingLost(
      atMs: atMs,
      cause: SensingLossCause.values.firstWhere((c) => c.name == json['cause']),
    ),
    'sensingRestored' => SensingRestored(atMs: atMs),
    'observationsEnded' => ObservationsEnded(atMs: atMs),
    final unknown => throw FormatException(
      'observation ชนิด "$unknown" ไม่รู้จัก',
    ),
  };
}

Map<String, Object?> encodeEvent(VisitEvent event) => switch (event) {
  VisitStarted(:final regionId, :final atMs, :final evidence) => {
    'kind': 'visitStarted',
    'regionId': regionId,
    'atMs': atMs,
    'evidence': evidence.name,
  },
  VisitEnded(
    :final regionId,
    :final startedAtMs,
    :final endedAtMs,
    :final reason,
  ) =>
    {
      'kind': 'visitEnded',
      'regionId': regionId,
      'startedAtMs': startedAtMs,
      'endedAtMs': endedAtMs,
      'reason': reason.name,
    },
};

/// state ตั้งต้นของหนึ่งเคส — เข้ารหัสเท่าที่ต้องใช้จริง
Map<String, Object?> encodeState(VisitFilterState state) => {
  'lastObservationAtMs': state.lastObservationAtMs,
  'sensing': state.sensing.name,
  'sensingLostAtMs': state.sensingLostAtMs,
  // เรียง key เสมอ — Swift `Dictionary` ไม่รับประกันลำดับ และ JSON ที่ลำดับ
  // ไม่คงที่จะทำให้ diff ของไฟล์ vector อ่านไม่ได้
  'regions': {
    for (final regionId in state.regions.keys.toList()..sort())
      regionId: _encodeRegion(state.regions[regionId]!),
  },
};

Map<String, Object?> _encodeRegion(RegionState region) => {
  'present': region.present,
  'lastPresentAtMs': region.lastPresentAtMs,
  'absentSinceMs': region.absentSinceMs,
  'silencePausedMs': region.silencePausedMs,
  'visit': region.visit == null
      ? null
      : {
          'startedAtMs': region.visit!.startedAtMs,
          'evidence': region.visit!.evidence.name,
        },
};

VisitFilterState decodeState(Map<String, Object?> json) {
  final regionsJson =
      (json['regions'] ?? <String, Object?>{}) as Map<String, Object?>;
  return VisitFilterState(
    regions: {
      for (final entry in regionsJson.entries)
        entry.key: _decodeRegion(entry.value! as Map<String, Object?>),
    },
    lastObservationAtMs: json['lastObservationAtMs'] as int?,
    sensing: SensingStatus.values.firstWhere(
      (s) => s.name == (json['sensing'] ?? 'available'),
    ),
    sensingLostAtMs: json['sensingLostAtMs'] as int?,
  );
}

RegionState _decodeRegion(Map<String, Object?> json) {
  final visitJson = json['visit'] as Map<String, Object?>?;
  return RegionState(
    present: json['present']! as bool,
    lastPresentAtMs: json['lastPresentAtMs'] as int?,
    absentSinceMs: json['absentSinceMs'] as int?,
    silencePausedMs: (json['silencePausedMs'] ?? 0) as int,
    visit: visitJson == null
        ? null
        : OpenVisit(
            startedAtMs: visitJson['startedAtMs']! as int,
            evidence: VisitStartEvidence.values.firstWhere(
              (e) => e.name == visitJson['evidence'],
            ),
          ),
  );
}

/// ผลของการเล่นหนึ่งเคสจนจบ
final class ConformanceRun {
  const ConformanceRun({
    required this.events,
    required this.rejections,
    required this.finalState,
  });

  final List<VisitEvent> events;

  /// `{'index': ลำดับของ observation, 'reason': ชื่อสาเหตุ}`
  final List<Map<String, Object?>> rejections;

  final VisitFilterState finalState;
}

/// เล่นหนึ่งเคส — **ตรรกะเดียวกับที่ port ทั้งสองภาษาต้องทำ**
ConformanceRun runConformanceCase({
  required EpochMillis cooldownMs,
  required EpochMillis blindnessCeilingMs,
  required VisitFilterState initialState,
  required List<VisitObservation> observations,
}) {
  final filter = VisitFilter(
    cooldownMs: cooldownMs,
    blindnessCeilingMs: blindnessCeilingMs,
  );
  var state = initialState;
  final events = <VisitEvent>[];
  final rejections = <Map<String, Object?>>[];
  for (var i = 0; i < observations.length; i++) {
    final reduction = filter.reduce(state, observations[i]);
    state = reduction.state;
    events.addAll(reduction.events);
    final rejection = reduction.rejection;
    if (rejection != null) {
      rejections.add({'index': i, 'reason': rejection.name});
    }
  }
  return ConformanceRun(
    events: events,
    rejections: rejections,
    finalState: state,
  );
}
