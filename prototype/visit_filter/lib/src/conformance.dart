import 'visit_event.dart';
import 'visit_filter.dart';
import 'visit_filter_state.dart';
import 'visit_observation.dart';

/// การเข้ารหัส **conformance vector** — สัญญากลางที่ทั้งสามภาษาต้องให้ผลตรงกัน
///
/// ⚠️ **เวลาทั้งหมดเป็นจำนวนเต็มมิลลิวินาทีนับจาก epoch (Int64) เท่านั้น**
/// ห้ามใช้ชนิดวันเวลาของแพลตฟอร์มในไฟล์ vector เด็ดขาด:
///
/// - Swift `Date` เก็บเป็น `Double` วินาที — ค่ามิลลิวินาทีบางค่าแทนไม่ได้เป๊ะ
///   การเทียบเท่ากันจึงเป็นการเทียบทศนิยม
/// - Swift `TimeInterval` และ `Duration` ของ Kotlin/Java คนละความละเอียดกัน
/// - Dart `int` เป็น 64 บิตบน VM แต่ 53 บิตบน JS (epoch มิลลิวินาทียังพอดี)
///
/// ตัวเลขจำนวนเต็มมิลลิวินาทีเป็นชนิดเดียวที่ทั้งสามภาษาแทนได้ตรงกันทุกค่า
int encodeTime(DateTime time) {
  if (time.microsecondsSinceEpoch % 1000 != 0) {
    throw ArgumentError.value(
      time,
      'time',
      'มีเศษต่ำกว่ามิลลิวินาที — vector ต้องเป็นจำนวนเต็มมิลลิวินาที '
          'เพราะ Swift Date แทนค่านั้นไม่ได้เป๊ะ',
    );
  }
  return time.millisecondsSinceEpoch;
}

DateTime decodeTime(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);

Map<String, Object?> encodeObservation(VisitObservation observation) =>
    switch (observation) {
      RegionSeen(:final regionId, :final at) => {
          'kind': 'regionSeen',
          'regionId': regionId,
          'atMs': encodeTime(at),
        },
      RegionNotSeen(:final regionId, :final at) => {
          'kind': 'regionNotSeen',
          'regionId': regionId,
          'atMs': encodeTime(at),
        },
      TimeAdvanced(:final at) => {
          'kind': 'timeAdvanced',
          'atMs': encodeTime(at),
        },
      SensingLost(:final at, :final cause) => {
          'kind': 'sensingLost',
          'atMs': encodeTime(at),
          'cause': cause.name,
        },
      SensingRestored(:final at) => {
          'kind': 'sensingRestored',
          'atMs': encodeTime(at),
        },
      ObservationsEnded(:final at) => {
          'kind': 'observationsEnded',
          'atMs': encodeTime(at),
        },
    };

VisitObservation decodeObservation(Map<String, Object?> json) {
  final at = decodeTime(json['atMs']! as int);
  final regionId = json['regionId'] as String?;
  return switch (json['kind']! as String) {
    'regionSeen' => RegionSeen(regionId: regionId!, at: at),
    'regionNotSeen' => RegionNotSeen(regionId: regionId!, at: at),
    'timeAdvanced' => TimeAdvanced(at: at),
    'sensingLost' => SensingLost(
        at: at,
        cause: SensingLossCause.values
            .firstWhere((c) => c.name == json['cause']),
      ),
    'sensingRestored' => SensingRestored(at: at),
    'observationsEnded' => ObservationsEnded(at: at),
    final unknown => throw FormatException('observation ชนิด "$unknown" ไม่รู้จัก'),
  };
}

Map<String, Object?> encodeEvent(VisitEvent event) => switch (event) {
      VisitStarted(:final regionId, :final at, :final evidence) => {
          'kind': 'visitStarted',
          'regionId': regionId,
          'atMs': encodeTime(at),
          'evidence': evidence.name,
        },
      VisitEnded(
        :final regionId,
        :final startedAt,
        :final endedAt,
        :final reason
      ) =>
        {
          'kind': 'visitEnded',
          'regionId': regionId,
          'startedAtMs': encodeTime(startedAt),
          'endedAtMs': encodeTime(endedAt),
          'reason': reason.name,
        },
    };

/// state ตั้งต้นของหนึ่งเคส — เข้ารหัสเท่าที่ต้องใช้จริง
Map<String, Object?> encodeState(VisitFilterState state) => {
      'lastObservationAtMs': state.lastObservationAt == null
          ? null
          : encodeTime(state.lastObservationAt!),
      'sensing': state.sensing.name,
      'sensingLostAtMs': state.sensingLostAt == null
          ? null
          : encodeTime(state.sensingLostAt!),
      // เรียง key เสมอ — Swift `Dictionary` ไม่รับประกันลำดับ และ JSON ที่ลำดับ
      // ไม่คงที่จะทำให้ diff ของไฟล์ vector อ่านไม่ได้
      'regions': {
        for (final regionId in state.regions.keys.toList()..sort())
          regionId: _encodeRegion(state.regions[regionId]!),
      },
    };

Map<String, Object?> _encodeRegion(RegionState region) => {
      'present': region.present,
      'lastPresentAtMs': region.lastPresentAt == null
          ? null
          : encodeTime(region.lastPresentAt!),
      'absentSinceMs':
          region.absentSince == null ? null : encodeTime(region.absentSince!),
      'silencePausedMs': region.silencePaused.inMilliseconds,
      'visit': region.visit == null
          ? null
          : {
              'startedAtMs': encodeTime(region.visit!.startedAt),
              'evidence': region.visit!.evidence.name,
            },
    };

VisitFilterState decodeState(Map<String, Object?> json) {
  final regionsJson = (json['regions'] ?? <String, Object?>{}) as Map<String, Object?>;
  final lastObservationAtMs = json['lastObservationAtMs'] as int?;
  final sensingLostAtMs = json['sensingLostAtMs'] as int?;
  return VisitFilterState(
    regions: {
      for (final entry in regionsJson.entries)
        entry.key: _decodeRegion(entry.value! as Map<String, Object?>),
    },
    lastObservationAt:
        lastObservationAtMs == null ? null : decodeTime(lastObservationAtMs),
    sensing: SensingStatus.values
        .firstWhere((s) => s.name == (json['sensing'] ?? 'available')),
    sensingLostAt:
        sensingLostAtMs == null ? null : decodeTime(sensingLostAtMs),
  );
}

RegionState _decodeRegion(Map<String, Object?> json) {
  final visitJson = json['visit'] as Map<String, Object?>?;
  final lastPresentAtMs = json['lastPresentAtMs'] as int?;
  final absentSinceMs = json['absentSinceMs'] as int?;
  return RegionState(
    present: json['present']! as bool,
    lastPresentAt:
        lastPresentAtMs == null ? null : decodeTime(lastPresentAtMs),
    absentSince: absentSinceMs == null ? null : decodeTime(absentSinceMs),
    silencePaused:
        Duration(milliseconds: (json['silencePausedMs'] ?? 0) as int),
    visit: visitJson == null
        ? null
        : OpenVisit(
            startedAt: decodeTime(visitJson['startedAtMs']! as int),
            evidence: VisitStartEvidence.values
                .firstWhere((e) => e.name == visitJson['evidence']),
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
  required Duration cooldown,
  required Duration blindnessCeiling,
  required VisitFilterState initialState,
  required List<VisitObservation> observations,
}) {
  final filter =
      VisitFilter(cooldown: cooldown, blindnessCeiling: blindnessCeiling);
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
