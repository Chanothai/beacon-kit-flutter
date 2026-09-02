import 'visit_event.dart';
import 'visit_filter_state.dart';
import 'visit_observation.dart';

/// สาเหตุที่ observation ถูกปฏิเสธ — state ไม่ถูกแก้เลยเมื่อเกิดขึ้น
enum ObservationRejection {
  /// เวลาเดินถอยหลังจาก observation ก่อนหน้า
  ///
  /// **ไม่ปรับให้เอง** เพราะการปรับคือการเดา — ผู้เรียกต้องรู้ว่าลำดับพัง
  timestampWentBackwards,
}

/// ผลของการ reduce หนึ่งครั้ง
final class VisitReduction {
  const VisitReduction({
    required this.state,
    this.events = const <VisitEvent>[],
    this.rejection,
  });

  final VisitFilterState state;

  /// event ที่เกิดจาก observation นี้ — ว่างได้ และว่างเป็นเรื่องปกติ
  final List<VisitEvent> events;

  /// `null` = รับ observation ไว้แล้ว
  final ObservationRejection? rejection;

  bool get accepted => rejection == null;
}

/// ชั้นกรอง visit — **ฟังก์ชันบริสุทธิ์ล้วน**
///
/// `(state, observation) -> (newState, emittedEvents)`
///
/// คลาสนี้ถือแค่ค่าคอนฟิก ไม่มี state ภายใน ไม่มี `Timer` ไม่มี `Stream`
/// และไม่อ่านนาฬิกา — ทั้งหมดนี้เป็นข้อบังคับ ไม่ใช่สไตล์:
///
/// - ฝั่ง Android กระบวนการที่ระบบปลุกมาเพื่อ `onReceive` มีอายุหลักสิบมิลลิวินาที
///   `Timer` ที่ตั้งไว้จะตายไปกับ process **โดยไม่มีอะไรฟ้อง** — โค้ดแบบนั้นผ่าน
///   เทสต์ในเครื่องแต่พังบนอุปกรณ์จริง
/// - รูปแบบ reducer พอร์ตไป Kotlin/Swift ได้ตรงตัวถ้าภายหลังตัดสินว่าต้องวางที่
///   native (ยังไม่ตัดสิน)
final class VisitFilter {
  /// ⚠️ ตรวจค่าด้วยการ **throw ไม่ใช่ `assert`** — `assert` ของ Dart ถูกถอดทิ้งใน
  /// release build ส่วน `require()` ของ Kotlin และ `precondition` ของ Swift ทำงาน
  /// เสมอ ถ้าใช้ `assert` พฤติกรรมของสามภาษาจะต่างกันเฉพาะใน release เท่านั้น
  /// ซึ่งเป็นความต่างที่หาไม่เจอที่สุด
  VisitFilter({required this.cooldown, required this.blindnessCeiling}) {
    if (cooldown <= Duration.zero) {
      throw ArgumentError.value(cooldown, 'cooldown', 'ต้องมากกว่าศูนย์');
    }
    if (blindnessCeiling <= Duration.zero) {
      throw ArgumentError.value(
        blindnessCeiling,
        'blindnessCeiling',
        'ต้องมากกว่าศูนย์',
      );
    }
  }

  /// เงียบนานเท่าไรจึงถือว่าการมาเยือนจบ
  ///
  /// นับจาก **เวลาที่แพลตฟอร์มประกาศว่าไม่เห็น** ([RegionNotSeen.at]) ไม่ใช่จาก
  /// เวลาที่เห็นครั้งสุดท้าย — เพราะระหว่างที่ยังอยู่ในโซน แพลตฟอร์มไม่ส่งอะไรมา
  /// เลย การนับจาก "เห็นครั้งสุดท้าย" จะปิดการมาเยือนของคนที่นั่งอยู่เฉย ๆ ทิ้ง
  ///
  /// ⚠️ **ไม่มีค่า default โดยตั้งใจ** — ผู้เรียกต้องเลือกเอง ดู README
  final Duration cooldown;

  /// ตาบอดได้นานที่สุดเท่าไรก่อนจะ **ล้างสถานะทิ้งทั้งหมด**
  ///
  /// ระหว่างตาบอดนาฬิกา cooldown หยุดเดิน (ดู [SensingLost]) แต่การหยุดนาฬิกาไป
  /// เรื่อย ๆ ไม่มีที่สิ้นสุดก็ผิด — คนที่ปิด Bluetooth ทิ้งไว้สามวันแล้วเปิดกลับ
  /// ไม่ได้ "ยังอยู่ในสาขาเดิม" · เกินเพดานนี้แล้วเราไม่รู้อะไรเลย จึงล้างทิ้ง
  /// แทนที่จะเดา
  ///
  /// ⚠️ **ไม่มีค่า default โดยตั้งใจ** — ยังไม่มีข้อมูลสนามสำหรับตั้งค่านี้เลย
  /// (log สองคืนที่มีไม่มีช่วงตาบอดที่ตรวจได้แม้แต่ช่วงเดียว)
  final Duration blindnessCeiling;

  /// รีดิวซ์หนึ่ง observation
  VisitReduction reduce(VisitFilterState state, VisitObservation observation) {
    final now = observation.at;
    final previous = state.lastObservationAt;
    if (previous != null && now.isBefore(previous)) {
      return VisitReduction(
        state: state,
        rejection: ObservationRejection.timestampWentBackwards,
      );
    }

    final events = <VisitEvent>[];
    var regions = Map<String, RegionState>.of(state.regions);
    var sensing = state.sensing;
    var sensingLostAt = state.sensingLostAt;

    // ── ตรวจเพดานการตาบอดก่อนเสมอ ──
    // ต้องมาก่อนทุกอย่าง รวมถึงก่อน `SensingRestored` — การกลับมามองเห็นหลังตาบอด
    // นานเกินเพดานคือการ "ล้างแล้วเริ่มใหม่" ไม่ใช่การ "หักเวลาที่หยุดไป"
    if (sensing == SensingStatus.lost &&
        sensingLostAt != null &&
        now.difference(sensingLostAt) >= blindnessCeiling) {
      regions = _resetAfterBlindnessCeiling(regions, events);
      sensing = SensingStatus.lostBeyondCeiling;
    }

    switch (observation) {
      case RegionSeen(:final regionId):
        regions = _settleOne(regions, regionId, now, events, sensing);
        regions = _applySeen(regions, regionId, now, events);
      case RegionNotSeen(:final regionId):
        regions = _settleOne(regions, regionId, now, events, sensing);
        regions = _applyNotSeen(regions, regionId, now);
      case TimeAdvanced():
        regions = _settleAll(regions, now, events, sensing);
      case SensingLost():
        // ตาบอดซ้ำระหว่างที่ตาบอดอยู่แล้วไม่เลื่อนจุดเริ่ม — ด้วยเหตุผลเดียวกับ
        // `exit` ซ้ำ: ถ้าเลื่อนได้ เพดานจะไม่มีวันถึงเมื่อระบบยิงถี่กว่าเพดาน
        if (sensing == SensingStatus.available) {
          sensing = SensingStatus.lost;
          sensingLostAt = now;
        }
      case SensingRestored():
        if (sensing == SensingStatus.lost && sensingLostAt != null) {
          regions = _creditPausedSilence(regions, sensingLostAt, now);
        }
        sensing = SensingStatus.available;
        sensingLostAt = null;
        // ตัดสินทันทีด้วยนาฬิกาที่เดินต่อแล้ว — การมาเยือนที่ครบ cooldown ไป
        // ตั้งแต่ก่อนตาบอดต้องปิดตรงนี้ ไม่ใช่รอ observation ตัวถัดไป
        regions = _settleAll(regions, now, events, sensing);
      case ObservationsEnded():
        regions = _settleAll(regions, now, events, sensing);
        regions = _closeOpenVisitsAtEdge(regions, now, events);
    }

    return VisitReduction(
      state: VisitFilterState(
        regions: Map<String, RegionState>.unmodifiable(regions),
        lastObservationAt: now,
        sensing: sensing,
        sensingLostAt: sensingLostAt,
      ),
      events: List<VisitEvent>.unmodifiable(events),
    );
  }

  // ── ตาบอด ─────────────────────────────────────────────────────────────────

  /// หักเวลาที่ตาบอดออกจากความเงียบของทุก region ที่กำลังนับ cooldown อยู่
  ///
  /// หักเฉพาะ**ส่วนที่ทับกับความเงียบจริง** — ถ้าเราตาบอดตั้งแต่ก่อนที่ region นี้
  /// จะเงียบ ส่วนที่อยู่ก่อนหน้าความเงียบไม่ได้ถูกกินไปจากใครจึงไม่ต้องคืน
  Map<String, RegionState> _creditPausedSilence(
    Map<String, RegionState> regions,
    DateTime blindSince,
    DateTime restoredAt,
  ) {
    final result = Map<String, RegionState>.of(regions);
    for (final regionId in regions.keys.toList()..sort()) {
      final region = result[regionId]!;
      final absentSince = region.absentSince;
      if (region.present || absentSince == null) continue;
      final overlapStart =
          absentSince.isAfter(blindSince) ? absentSince : blindSince;
      if (!restoredAt.isAfter(overlapStart)) continue;
      result[regionId] = region.copyWith(
        silencePaused: region.silencePaused + restoredAt.difference(overlapStart),
      );
    }
    return result;
  }

  /// ตาบอดนานเกินเพดาน — **ล้างสถานะของทุก region ทิ้ง**
  ///
  /// ปิดการมาเยือนที่เปิดค้างด้วย [VisitEndReason.sensingLostBeyondCeiling] แล้ว
  /// **ลบ entry ของ region ทิ้งทั้งหมด** ไม่ใช่แค่ตั้งเป็น "ไม่อยู่" — เพราะเรา
  /// ตอบไม่ได้ว่าผู้ใช้อยู่หรือไม่อยู่ · ผลคือครั้งหน้าที่เห็น beacon จะได้
  /// [VisitStartEvidence.alreadyInsideAtFirstObservation] ซึ่งตรงกับความจริงว่า
  /// เราไม่เคยเห็นการมาถึง
  Map<String, RegionState> _resetAfterBlindnessCeiling(
    Map<String, RegionState> regions,
    List<VisitEvent> events,
  ) {
    for (final regionId in regions.keys.toList()..sort()) {
      final region = regions[regionId]!;
      final visit = region.visit;
      if (visit == null) continue;
      events.add(
        VisitEnded(
          regionId: regionId,
          startedAt: visit.startedAt,
          endedAt: region.lastPresentAt ?? visit.startedAt,
          reason: VisitEndReason.sensingLostBeyondCeiling,
        ),
      );
    }
    return <String, RegionState>{};
  }

  // ── ครบ cooldown แล้วทำอะไร ───────────────────────────────────────────────

  /// ตัดสินว่าการมาเยือนที่เปิดอยู่ของ region นี้จบแล้วหรือยัง ณ เวลา [now]
  ///
  /// **ครบ cooldown แล้วห้ามยิง event ทันที** — ต้องดูสถานะปัจจุบันก่อนเสมอ:
  ///
  /// - ยังเห็น beacon อยู่ → **ไม่ยิงอะไร** ถือเป็นการมาเยือนครั้งเดิม
  /// - ไม่เห็นแล้ว → ปิดการมาเยือน แล้ว region กลับไปอยู่สภาพ "พร้อมยิงครั้งหน้า"
  ///
  /// ถ้าเขียนเป็น "ครบเวลาแล้วยิงเลย" จะได้ `VisitStarted` ปลอมทุก cooldown
  /// ตลอดเวลาที่ลูกค้ายังอยู่ในร้าน
  RegionState _settle(
    String regionId,
    RegionState region,
    DateTime now,
    List<VisitEvent> events,
    SensingStatus sensing,
  ) {
    final visit = region.visit;
    if (visit == null) return region;

    // ── ตาบอดอยู่ → นาฬิกา cooldown หยุด ──
    // ห้ามปิดการมาเยือนด้วยความเงียบที่เราเป็นคนทำให้เงียบเอง · เพดานการตาบอด
    // ถูกตรวจไปแล้วที่ `reduce` ก่อนจะมาถึงตรงนี้
    if (sensing != SensingStatus.available) return region;

    // ระหว่างที่ยังอยู่ในโซน แพลตฟอร์มไม่ส่งอะไรมาเลย — ช่วงเงียบจึงต้องนับจาก
    // เวลาที่ประกาศว่าไม่เห็น ไม่ใช่จากเวลาที่เห็นครั้งสุดท้าย
    final silenceStart = region.present ? region.lastPresentAt : region.absentSince;
    if (silenceStart == null) return region;
    if (now.difference(silenceStart) - region.silencePaused < cooldown) {
      return region;
    }

    // ── ครบ cooldown แล้ว — ดูสถานะปัจจุบันก่อน ──
    if (region.present) {
      // ยังเห็นอยู่ · การมาเยือนครั้งเดิม · ไม่ยิงอะไร
      //
      // สาขานี้ **ถูกเรียกจริงกับข้อมูลจริง** ไม่ใช่กันไว้เฉย ๆ: ไฟล์ iOS คืน
      // 30 ส.ค. มีช่วงที่อยู่ในโซนต่อเนื่อง 3 ชั่วโมง 10 นาทีโดยไม่มี event ใด
      // เลย ถ้าไม่มีการ์ดนี้ การมาเยือนจะถูกปิดกลางคัน แล้ว `enter` ถัดไปจะกลาย
      // เป็น `VisitStarted` ปลอม
      return region;
    }

    events.add(
      VisitEnded(
        regionId: regionId,
        startedAt: visit.startedAt,
        endedAt: region.lastPresentAt ?? visit.startedAt,
        reason: VisitEndReason.cooldownElapsed,
      ),
    );
    return region.copyWith(clearVisit: true);
  }

  Map<String, RegionState> _settleOne(
    Map<String, RegionState> regions,
    String regionId,
    DateTime now,
    List<VisitEvent> events,
    SensingStatus sensing,
  ) {
    final region = regions[regionId];
    if (region == null) return regions;
    final settled = _settle(regionId, region, now, events, sensing);
    if (identical(settled, region)) return regions;
    return {...regions, regionId: settled};
  }

  /// ตัดสินทุก region — **เรียงตาม identifier เสมอ** เพื่อให้ลำดับ event
  /// ที่ยิงออกมาไม่ขึ้นกับลำดับที่ key ถูกใส่เข้า map (ต้องพอร์ตไป Kotlin/Swift
  /// แล้วได้ผลเหมือนกัน)
  Map<String, RegionState> _settleAll(
    Map<String, RegionState> regions,
    DateTime now,
    List<VisitEvent> events,
    SensingStatus sensing,
  ) {
    final result = Map<String, RegionState>.of(regions);
    for (final regionId in regions.keys.toList()..sort()) {
      result[regionId] =
          _settle(regionId, result[regionId]!, now, events, sensing);
    }
    return result;
  }

  // ── การเปลี่ยนสถานะจาก observation ────────────────────────────────────────

  Map<String, RegionState> _applySeen(
    Map<String, RegionState> regions,
    String regionId,
    DateTime now,
    List<VisitEvent> events,
  ) {
    final previous = regions[regionId];
    final seen = (previous ?? RegionState.unknown).copyWith(
      present: true,
      lastPresentAt: now,
      clearAbsentSince: true,
      // เห็นอีกครั้ง = ความเงียบช่วงเดิมจบแล้ว เวลาที่หยุดไว้ของช่วงนั้นหมดความหมาย
      silencePaused: Duration.zero,
    );

    if (seen.visit != null) {
      // อยู่ในการมาเยือนเดิมอยู่แล้ว — แค่ต่ออายุหลักฐาน ไม่ยิงอะไร
      return {...regions, regionId: seen};
    }

    // ไม่เคยมีข้อมูลของ region นี้เลย หรือกู้ state กลับมาแบบ "อยู่ในโซนอยู่แล้ว"
    // → ตอบไม่ได้ว่าการมาถึงเกิดขึ้นเมื่อไร
    final sawArrival = previous != null && !previous.present;
    final evidence = sawArrival
        ? VisitStartEvidence.arrivalObserved
        : VisitStartEvidence.alreadyInsideAtFirstObservation;

    events.add(
      VisitStarted(regionId: regionId, at: now, evidence: evidence),
    );
    return {
      ...regions,
      regionId: seen.copyWith(
        visit: OpenVisit(startedAt: now, evidence: evidence),
      ),
    };
  }

  Map<String, RegionState> _applyNotSeen(
    Map<String, RegionState> regions,
    String regionId,
    DateTime now,
  ) {
    final previous = regions[regionId] ?? RegionState.unknown;
    // `exit` ซ้ำ ๆ ติดกันต้องไม่เลื่อนจุดเริ่มความเงียบออกไป มิฉะนั้น cooldown
    // จะไม่มีวันครบถ้าแพลตฟอร์มยิง `exit` ถี่กว่า cooldown
    final startsNewSilence = previous.present || previous.absentSince == null;
    final absentSince = startsNewSilence ? now : previous.absentSince!;
    return {
      ...regions,
      regionId: previous.copyWith(
        present: false,
        absentSince: absentSince,
        // ความเงียบช่วงใหม่เริ่มนับศูนย์เสมอ · ถ้าเป็น `exit` ซ้ำของช่วงเดิม
        // ต้องคงเวลาที่หยุดไว้ ไม่งั้นการตาบอดที่ผ่านมาจะถูกลืม
        silencePaused:
            startsNewSilence ? Duration.zero : previous.silencePaused,
      ),
    };
  }

  /// ปิดการมาเยือนที่ยังเปิดค้างที่ **ขอบข้อมูล** — ห้ามทิ้ง
  Map<String, RegionState> _closeOpenVisitsAtEdge(
    Map<String, RegionState> regions,
    DateTime now,
    List<VisitEvent> events,
  ) {
    final result = Map<String, RegionState>.of(regions);
    for (final regionId in regions.keys.toList()..sort()) {
      final region = result[regionId]!;
      final visit = region.visit;
      if (visit == null) continue;
      events.add(
        VisitEnded(
          regionId: regionId,
          startedAt: visit.startedAt,
          // ยังอยู่ในโซนตอนข้อมูลหมด → ปิดที่ขอบข้อมูล
          // ไม่อยู่แล้วแต่ยังไม่ครบ cooldown → ปิดที่หลักฐานสุดท้ายที่มี
          endedAt:
              region.present ? now : (region.lastPresentAt ?? visit.startedAt),
          reason: VisitEndReason.observationsEnded,
        ),
      );
      result[regionId] = region.copyWith(clearVisit: true);
    }
    return result;
  }
}
