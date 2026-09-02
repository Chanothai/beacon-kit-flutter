import 'package:test/test.dart';
import 'package:visit_filter_prototype/visit_filter.dart';

/// จุดอ้างอิงเวลาคงที่ — เทสต์ห้ามพึ่งนาฬิกาจริง ด้วยเหตุผลเดียวกับที่ reducer
/// ห้ามอ่านนาฬิกา
final int t0 = DateTime.utc(2026, 9, 2, 10).millisecondsSinceEpoch;

/// ⚠️ `Duration` ที่นี่เป็นความสะดวกในการเขียนเทสต์เท่านั้น — reducer รับจำนวนเต็ม
/// มิลลิวินาที การแปลงเกิดที่บรรทัดล่างนี้ที่เดียว
int at(Duration offset) => t0 + offset.inMilliseconds;

const Duration cooldown = Duration(minutes: 5);
const Duration blindnessCeiling = Duration(minutes: 15);
final VisitFilter filter = VisitFilter(
  cooldownMs: cooldown.inMilliseconds,
  blindnessCeilingMs: blindnessCeiling.inMilliseconds,
);

/// ป้อน observation ทีละตัวแบบที่ผู้เรียกจริงต้องทำ — ถือ state เองแล้วส่งกลับ
({List<VisitEvent> events, VisitFilterState state}) run(
  Iterable<VisitObservation> observations, {
  VisitFilterState from = VisitFilterState.initial,
  VisitFilter? using,
}) {
  final reducer = using ?? filter;
  var state = from;
  final events = <VisitEvent>[];
  for (final observation in observations) {
    final reduction = reducer.reduce(state, observation);
    state = reduction.state;
    events.addAll(reduction.events);
  }
  return (events: events, state: state);
}

List<VisitStarted> startsIn(List<VisitEvent> events) =>
    events.whereType<VisitStarted>().toList();
List<VisitEnded> endsIn(List<VisitEvent> events) =>
    events.whereType<VisitEnded>().toList();

void main() {
  group('การเริ่มการมาเยือน', () {
    test('เห็นการเปลี่ยนจากไม่อยู่เป็นอยู่ → arrivalObserved', () {
      final result = run([
        RegionNotSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionSeen(regionId: 'a', atMs: at(const Duration(seconds: 10))),
      ]);

      expect(startsIn(result.events), [
        VisitStarted(
          regionId: 'a',
          atMs: at(const Duration(seconds: 10)),
          evidence: VisitStartEvidence.arrivalObserved,
        ),
      ]);
    });

    test('observation แรกบอกว่าอยู่แล้ว → alreadyInsideAtFirstObservation', () {
      final result = run([RegionSeen(regionId: 'a', atMs: at(Duration.zero))]);

      expect(
        startsIn(result.events).single.evidence,
        VisitStartEvidence.alreadyInsideAtFirstObservation,
      );
    });

    test('กู้ state ที่บันทึกไว้ว่ากำลังอยู่ในโซน → ไม่เริ่มการมาเยือนซ้ำ', () {
      final restored = VisitFilterState(
        regions: {
          'a': RegionState.insideSince(
            at(Duration.zero),
            visit: OpenVisit(
              startedAtMs: at(Duration.zero),
              evidence: VisitStartEvidence.alreadyInsideAtFirstObservation,
            ),
          ),
        },
        lastObservationAtMs: at(Duration.zero),
      );

      final result = run([
        RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 30))),
      ], from: restored);

      expect(
        startsIn(result.events),
        isEmpty,
        reason: 'การมาเยือนเดิมยังเปิดอยู่ ไม่ควรมี VisitStarted ใหม่',
      );
    });

    test('กู้ state ว่าอยู่ในโซนแต่ยังไม่มีการมาเยือนเปิด → alreadyInside', () {
      final restored = VisitFilterState(
        regions: {'a': RegionState.insideSince(at(Duration.zero))},
        lastObservationAtMs: at(Duration.zero),
      );

      final result = run([
        RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
      ], from: restored);

      expect(
        startsIn(result.events).single.evidence,
        VisitStartEvidence.alreadyInsideAtFirstObservation,
      );
    });
  });

  group('ครบ cooldown แล้วต้องดูสถานะปัจจุบันก่อน', () {
    test('ยังเห็น beacon อยู่ → ไม่ยิงอะไร ถือเป็นการมาเยือนครั้งเดิม', () {
      // นี่คือกับดักหลัก: ระหว่างที่อยู่ในโซน แพลตฟอร์มไม่ส่งอะไรมาเลย
      // "เวลาที่เห็นครั้งสุดท้าย" จึงเก่ากว่า cooldown ได้เป็นชั่วโมงทั้งที่
      // ผู้ใช้ยังนั่งอยู่ที่เดิม
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        TimeAdvanced(atMs: at(const Duration(hours: 4))),
        TimeAdvanced(atMs: at(const Duration(hours: 8))),
      ]);

      expect(startsIn(result.events), hasLength(1));
      expect(endsIn(result.events), isEmpty);
      expect(result.state.regionState('a').visit, isNotNull);
    });

    test(
      'ครบ cooldown ตอนไม่เห็นแล้ว → ปิดการมาเยือน แต่ไม่ยิง VisitStarted',
      () {
        final result = run([
          RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
          RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
          TimeAdvanced(atMs: at(const Duration(minutes: 6, seconds: 1))),
        ]);

        expect(startsIn(result.events), hasLength(1));
        expect(endsIn(result.events), [
          VisitEnded(
            regionId: 'a',
            startedAtMs: at(Duration.zero),
            endedAtMs: at(Duration.zero),
            reason: VisitEndReason.cooldownElapsed,
          ),
        ]);
        expect(result.state.regionState('a').visit, isNull);
      },
    );

    test('ปิดแล้วครั้งหน้าที่เจอค่อยยิง VisitStarted ใหม่', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        RegionSeen(
          regionId: 'a',
          atMs: at(const Duration(minutes: 6, seconds: 1)),
        ),
      ]);

      expect(startsIn(result.events), hasLength(2));
      expect(
        startsIn(result.events).last.evidence,
        VisitStartEvidence.arrivalObserved,
      );
      // ปิดของเก่าก่อน แล้วค่อยเปิดของใหม่ — ลำดับนี้สำคัญกับผู้บริโภค event
      expect(result.events.map((e) => e.runtimeType.toString()), [
        'VisitStarted',
        'VisitEnded',
        'VisitStarted',
      ]);
    });

    test('ปิดที่หลักฐานสุดท้ายที่เห็น ไม่ใช่ตอนที่รู้ตัวว่าครบ cooldown', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 2))),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 3))),
        TimeAdvanced(atMs: at(const Duration(hours: 9))),
      ]);

      expect(
        endsIn(result.events).single.endedAtMs,
        at(const Duration(minutes: 2)),
      );
    });
  });

  group('การรวม flap', () {
    test('เข้า-ออกถี่ ๆ ภายใน cooldown → การมาเยือนเดียว', () {
      final observations = <VisitObservation>[
        RegionNotSeen(regionId: 'a', atMs: at(Duration.zero)),
      ];
      // 40 รอบ เข้า 30 วินาที ออก 30 วินาที — รูปแบบเดียวกับที่วัดได้จริง
      for (var i = 0; i < 40; i++) {
        observations.add(
          RegionSeen(
            regionId: 'a',
            atMs: at(Duration(minutes: i)),
          ),
        );
        observations.add(
          RegionNotSeen(
            regionId: 'a',
            atMs: at(Duration(minutes: i, seconds: 30)),
          ),
        );
      }

      final result = run(observations);
      expect(startsIn(result.events), hasLength(1));
    });

    test('exit ซ้ำติดกันไม่เลื่อนจุดเริ่มความเงียบ', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 2))),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 3))),
        TimeAdvanced(atMs: at(const Duration(minutes: 6, seconds: 1))),
      ]);

      expect(
        endsIn(result.events),
        hasLength(1),
        reason: 'ความเงียบต้องนับจาก exit ตัวแรก (นาทีที่ 1) ไม่ใช่ตัวล่าสุด',
      );
    });
  });

  group('state แยกต่อ region', () {
    test('ออกจาก A แล้วเข้า B — ทั้งสองต้องไม่กลืนกัน', () {
      final result = run([
        RegionNotSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 10))),
        RegionSeen(regionId: 'b', atMs: at(const Duration(minutes: 11))),
        ObservationsEnded(atMs: at(const Duration(minutes: 20))),
      ]);

      final starts = startsIn(result.events);
      expect(starts.map((s) => s.regionId), ['a', 'b']);
      expect(endsIn(result.events).map((e) => e.regionId), ['a', 'b']);
    });

    test('cooldown ของแต่ละ region เดินแยกกัน', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        RegionSeen(regionId: 'b', atMs: at(const Duration(minutes: 4))),
        RegionNotSeen(regionId: 'b', atMs: at(const Duration(minutes: 5))),
        TimeAdvanced(atMs: at(const Duration(minutes: 6, seconds: 30))),
      ]);

      // a เงียบมา 5 นาที 30 วินาที → ครบ · b เงียบมา 1 นาที 30 วินาที → ยังไม่ครบ
      expect(endsIn(result.events).map((e) => e.regionId), ['a']);
      expect(result.state.regionsWithOpenVisit, ['b']);
    });

    test(
      'หลาย region หมด cooldown พร้อมกัน → ลำดับ event เรียงตาม identifier',
      () {
        final result = run([
          RegionSeen(regionId: 'zulu', atMs: at(Duration.zero)),
          RegionSeen(regionId: 'alpha', atMs: at(Duration.zero)),
          RegionNotSeen(regionId: 'zulu', atMs: at(const Duration(seconds: 1))),
          RegionNotSeen(
            regionId: 'alpha',
            atMs: at(const Duration(seconds: 1)),
          ),
          TimeAdvanced(atMs: at(const Duration(minutes: 6))),
        ]);

        expect(endsIn(result.events).map((e) => e.regionId), ['alpha', 'zulu']);
      },
    );
  });

  group('ขอบข้อมูล', () {
    test('ยังอยู่ในโซนตอนข้อมูลหมด → ปิดที่ขอบ ไม่ใช่ทิ้ง', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        ObservationsEnded(atMs: at(const Duration(hours: 3))),
      ]);

      expect(endsIn(result.events), [
        VisitEnded(
          regionId: 'a',
          startedAtMs: at(Duration.zero),
          endedAtMs: at(const Duration(hours: 3)),
          reason: VisitEndReason.observationsEnded,
        ),
      ]);
    });

    test('ไม่อยู่แล้วแต่ยังไม่ครบ cooldown → ปิดที่หลักฐานสุดท้าย', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        ObservationsEnded(atMs: at(const Duration(minutes: 3))),
      ]);

      final ended = endsIn(result.events).single;
      expect(ended.endedAtMs, at(Duration.zero));
      expect(ended.reason, VisitEndReason.observationsEnded);
    });

    test('ไม่มีการมาเยือนเปิดค้าง → ObservationsEnded ไม่ยิงอะไร', () {
      final result = run([
        RegionNotSeen(regionId: 'a', atMs: at(Duration.zero)),
        ObservationsEnded(atMs: at(const Duration(minutes: 1))),
      ]);

      expect(result.events, isEmpty);
    });
  });

  group('ตาบอด — นาฬิกา cooldown หยุด', () {
    test(
      'บั๊กที่พบจริง: ปิด Bluetooth 10 นาทีขณะอยู่ที่เดิม → การมาเยือนเดียว',
      () {
        final withoutBlindness = run([
          RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
          RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
          RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 11))),
        ]);
        expect(
          startsIn(withoutBlindness.events),
          hasLength(2),
          reason:
              'ป้อนสภาพตาบอดเป็น RegionNotSeen = บั๊กเดิม '
              'ลูกค้าได้แจ้งเตือนซ้ำทั้งที่ไม่ได้ไปไหน',
        );

        final withBlindness = run([
          RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
          RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
          SensingLost(
            atMs: at(const Duration(minutes: 1)),
            cause: SensingLossCause.bluetoothOff,
          ),
          SensingRestored(atMs: at(const Duration(minutes: 11))),
          RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 11))),
        ]);
        expect(startsIn(withBlindness.events), hasLength(1));
        expect(endsIn(withBlindness.events), isEmpty);
      },
    );

    test('ห้ามปิดการมาเยือนระหว่างตาบอด แม้ cooldown จะครบไปแล้ว', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        SensingLost(
          atMs: at(const Duration(minutes: 2)),
          cause: SensingLossCause.bluetoothOff,
        ),
        // ถ้านาฬิกาไม่หยุด cooldown ครบตั้งแต่นาทีที่ 6
        TimeAdvanced(atMs: at(const Duration(minutes: 9))),
      ]);

      expect(endsIn(result.events), isEmpty);
      expect(result.state.regionsWithOpenVisit, ['a']);
    });

    test('หลังกลับมามองเห็น นับเวลาที่เหลือต่อ ไม่ใช่เริ่มนับใหม่', () {
      final observations = <VisitObservation>[
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        SensingLost(
          atMs: at(const Duration(minutes: 2)),
          cause: SensingLossCause.bluetoothOff,
        ),
        SensingRestored(atMs: at(const Duration(minutes: 10))),
      ];

      // เงียบจริง 11 นาที หัก 8 นาทีที่ตาบอด = 3 นาที → ยังไม่ครบ
      expect(
        endsIn(
          run([
            ...observations,
            TimeAdvanced(atMs: at(const Duration(minutes: 12))),
          ]).events,
        ),
        isEmpty,
      );

      // เงียบจริง 13 นาที หัก 8 = 5 นาที → ครบพอดี
      expect(
        endsIn(
          run([
            ...observations,
            TimeAdvanced(atMs: at(const Duration(minutes: 14))),
          ]).events,
        ).single.reason,
        VisitEndReason.cooldownElapsed,
      );
    });

    test('หักเฉพาะส่วนที่ทับกับความเงียบจริง', () {
      // ตาบอดตั้งแต่นาทีที่ 1 แต่เพิ่งเงียบตอนนาทีที่ 3 → หักได้แค่ 3→8 = 5 นาที
      final observations = <VisitObservation>[
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        SensingLost(
          atMs: at(const Duration(minutes: 1)),
          cause: SensingLossCause.scanRegistrationLost,
        ),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 3))),
        SensingRestored(atMs: at(const Duration(minutes: 8))),
      ];

      // เงียบจริง 9 นาที หัก 5 = 4 นาที → ยังไม่ครบ
      expect(
        endsIn(
          run([
            ...observations,
            TimeAdvanced(atMs: at(const Duration(minutes: 12))),
          ]).events,
        ),
        isEmpty,
      );
      // เงียบจริง 10 นาที หัก 5 = 5 นาที → ครบ
      expect(
        endsIn(
          run([
            ...observations,
            TimeAdvanced(atMs: at(const Duration(minutes: 13))),
          ]).events,
        ),
        hasLength(1),
      );
    });
  });

  group('ตาบอดเกินเพดาน — ล้างสถานะทิ้ง', () {
    test('เกินเพดาน → ปิดด้วย sensingLostBeyondCeiling แล้วลบ state ทิ้ง', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        SensingLost(
          atMs: at(const Duration(minutes: 2)),
          cause: SensingLossCause.bluetoothOff,
        ),
        SensingRestored(atMs: at(const Duration(minutes: 30))),
      ]);

      expect(
        endsIn(result.events).single.reason,
        VisitEndReason.sensingLostBeyondCeiling,
      );
      expect(
        endsIn(result.events).single.endedAtMs,
        at(Duration.zero),
        reason: 'ปิดที่หลักฐานสุดท้ายที่เห็น ไม่ใช่เวลาที่รู้ตัว',
      );
      expect(
        result.state.regions,
        isEmpty,
        reason: 'ตาบอดนานขนาดนั้นแล้วอ้างอะไรไม่ได้ ต้องล้างทิ้ง',
      );
    });

    test(
      'หลังล้าง ครั้งหน้าที่เห็นเป็น alreadyInside ไม่ใช่ arrivalObserved',
      () {
        final result = run([
          RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
          RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
          SensingLost(
            atMs: at(const Duration(minutes: 2)),
            cause: SensingLossCause.bluetoothOff,
          ),
          SensingRestored(atMs: at(const Duration(minutes: 30))),
          RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 31))),
        ]);

        expect(
          startsIn(result.events).last.evidence,
          VisitStartEvidence.alreadyInsideAtFirstObservation,
          reason:
              'เราไม่เคยเห็นการมาถึง — ตอบไม่ได้ว่าเขาออกไปแล้วกลับมาหรือไม่',
        );
      },
    );

    test('ขอบเพดาน: ครบพอดีล้าง · ขาด 1 มิลลิวินาทีไม่ล้าง', () {
      List<VisitEvent> eventsForBlindness(Duration blindFor) => run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        SensingLost(
          atMs: at(const Duration(minutes: 2)),
          cause: SensingLossCause.bluetoothOff,
        ),
        SensingRestored(atMs: at(const Duration(minutes: 2) + blindFor)),
      ]).events;

      expect(
        endsIn(eventsForBlindness(blindnessCeiling)).single.reason,
        VisitEndReason.sensingLostBeyondCeiling,
      );
      expect(
        endsIn(
          eventsForBlindness(
            blindnessCeiling - const Duration(milliseconds: 1),
          ),
        ),
        isEmpty,
      );
    });

    test(
      'ล้างครั้งเดียวต่อหนึ่งช่วงตาบอด — การมาเยือนใหม่ต้องไม่ถูกล้างซ้ำ',
      () {
        final result = run([
          SensingLost(
            atMs: at(Duration.zero),
            cause: SensingLossCause.bluetoothOff,
          ),
          // เลยเพดานแล้ว แต่ยังตาบอดอยู่ · ผลสแกนที่ค้างอยู่เข้ามา
          RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 20))),
          TimeAdvanced(atMs: at(const Duration(minutes: 25))),
          TimeAdvanced(atMs: at(const Duration(minutes: 40))),
        ]);

        expect(startsIn(result.events), hasLength(1));
        expect(
          endsIn(result.events),
          isEmpty,
          reason: 'ช่วงตาบอดนี้ล้างไปแล้วครั้งหนึ่ง ห้ามล้างซ้ำ',
        );
        expect(result.state.regionsWithOpenVisit, ['a']);
      },
    );

    test('SensingLost ซ้ำไม่เลื่อนเพดาน', () {
      final result = run([
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionNotSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
        SensingLost(
          atMs: at(const Duration(minutes: 2)),
          cause: SensingLossCause.bluetoothOff,
        ),
        SensingLost(
          atMs: at(const Duration(minutes: 14)),
          cause: SensingLossCause.bluetoothOff,
        ),
        TimeAdvanced(atMs: at(const Duration(minutes: 17))),
      ]);

      expect(
        endsIn(result.events).single.reason,
        VisitEndReason.sensingLostBeyondCeiling,
        reason:
            'เพดานต้องนับจาก SensingLost ตัวแรก (นาทีที่ 2) '
            'ไม่ใช่ตัวล่าสุด',
      );
    });

    test('ตาบอดตอนไม่มีการมาเยือนเปิดค้าง → เงียบสนิท', () {
      final result = run([
        RegionNotSeen(regionId: 'a', atMs: at(Duration.zero)),
        SensingLost(
          atMs: at(const Duration(minutes: 1)),
          cause: SensingLossCause.bluetoothOff,
        ),
        SensingRestored(atMs: at(const Duration(minutes: 40))),
      ]);

      expect(result.events, isEmpty);
    });
  });

  group('observation ที่รับไม่ได้', () {
    test('เวลาเดินถอยหลัง → ปฏิเสธ และ state ไม่ถูกแก้', () {
      final before = filter
          .reduce(
            VisitFilterState.initial,
            RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 5))),
          )
          .state;

      final reduction = filter.reduce(
        before,
        RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 4))),
      );

      expect(reduction.accepted, isFalse);
      expect(reduction.rejection, ObservationRejection.timestampWentBackwards);
      expect(reduction.events, isEmpty);
      expect(identical(reduction.state, before), isTrue);
    });

    test('เวลาเท่าเดิมเป๊ะ → รับได้ (ระบบคิว event แล้วส่งมาติดกัน)', () {
      final result = run([
        RegionNotSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
      ]);

      expect(startsIn(result.events), hasLength(1));
    });
  });

  group('ความบริสุทธิ์ของฟังก์ชัน', () {
    test('reduce ตัวเดิมสองครั้งให้ผลเหมือนกัน และไม่แก้ state เดิม', () {
      final seeded = run([
        RegionNotSeen(regionId: 'a', atMs: at(Duration.zero)),
        RegionSeen(regionId: 'a', atMs: at(const Duration(minutes: 1))),
      ]).state;
      final snapshot = seeded.toString();

      final observation = RegionNotSeen(
        regionId: 'a',
        atMs: at(const Duration(minutes: 2)),
      );
      final first = filter.reduce(seeded, observation);
      final second = filter.reduce(seeded, observation);

      expect(seeded.toString(), snapshot, reason: 'state เดิมต้องไม่ถูกแก้');
      expect(first.state.toString(), second.state.toString());
      expect(first.events, second.events);
    });

    test('state ที่คืนออกมาแก้ไม่ได้', () {
      final state = filter
          .reduce(
            VisitFilterState.initial,
            RegionSeen(regionId: 'a', atMs: at(Duration.zero)),
          )
          .state;

      expect(
        () => state.regions['b'] = RegionState.unknown,
        throwsUnsupportedError,
      );
    });
  });
}
