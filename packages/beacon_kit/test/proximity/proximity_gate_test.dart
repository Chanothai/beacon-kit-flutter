/// Test ของ [ProximityGate] ตาม ARCHITECTURE.md ADR-19 — pure Dart class ทั้งหมด
/// ไม่มี I/O จริงเลยสักฟังก์ชัน จึงเทสต์ได้ครบด้วย [_FakeClock] ที่ควบคุมเวลาเองล้วน ๆ
/// **ห้ามรอเวลาจริงด้วยกลไก async ใด ๆ ในไฟล์นี้เด็ดขาด** (เช่น การ delay ผ่าน
/// `Future` หรือ `sleep` ของ `dart:io`) — ทุกเทสต์ที่เกี่ยวกับ `staleAfter` เดินเวลา
/// ผ่าน [_FakeClock.advance] เท่านั้น
///
/// ค่าทุกตัวในไฟล์นี้เป็นค่าสังเคราะห์ (synthetic) ล้วน ๆ ที่คำนวณย้อนกลับจากสูตร
/// log-distance path loss เอง (ดู `distance_estimator_test.dart` สำหรับเหตุผลเต็ม ๆ
/// ว่าทำไมใช้ log จริงจาก `docs/test-data/` ไม่ได้เลย — ไฟล์เหล่านั้นเป็น region
/// enter/exit event ระดับสาขา ไม่มี RSSI รายบรรทัดให้ใช้เป็น input ของ [ProximityGate]
/// ได้เลย ไม่ว่าจะเส้นทาง Android (rssi/txPower) หรือ iOS (proximity bucket) ก็ตาม)
library;

import 'package:beacon_kit/beacon_kit.dart';
import 'package:flutter_test/flutter_test.dart';

/// นาฬิกาปลอมที่เทสต์ควบคุมเองทั้งหมด — inject เข้า [ProximityGate.new] ผ่าน
/// [call] แทนนาฬิกาจริงของระบบ ตามสัญญาของ [ProximityGate.clock]
/// (ดู dartdoc: "ต้อง inject เข้ามาเสมอ ไม่มี default เพื่อให้เทสต์ควบคุมเวลาได้แบบ
/// deterministic โดยไม่ต้องพึ่งนาฬิกาจริงของเครื่อง")
class _FakeClock {
  DateTime now = DateTime.utc(2026, 9, 8);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

const _uuid = '7777772e-6b6b-6d63-6e2e-636f6d000001';
const _key = (uuid: _uuid, major: 1, minor: 1);

/// สร้าง [BeaconAdvertisement] แบบ "Android ปกติ" (`source == rawParsed`) — มี
/// `rssi`/`ibeaconTxPower` ให้คำนวณระยะเอง ไม่มี `proximity` เลย (`null` เสมอ) ตรง
/// กับสัญญาที่ `beacon_advertisement.dart` การันตีไว้สำหรับ source นี้
BeaconAdvertisement _androidSample({
  required int rssi,
  int? txPower,
  ProximityBeaconKey key = _key,
}) => BeaconAdvertisement(
  deviceId: const BeaconDeviceId(
    value: 'aa:bb:cc:dd:ee:ff',
    kind: DeviceIdKind.macAddress,
  ),
  rssi: rssi,
  source: AdvertisementSource.rawParsed,
  timestamp: DateTime.utc(2026, 9, 8),
  ibeaconUuid: key.uuid,
  ibeaconMajor: key.major,
  ibeaconMinor: key.minor,
  ibeaconTxPower: txPower,
);

/// สร้าง [BeaconAdvertisement] แบบ "iOS ranging" (`source == osDecoded`) — มี
/// `proximity` ให้ใช้ตรง ๆ ตามสัญญาของ source นี้ — [txPower] เปิดให้ตั้งค่าได้
/// (ปกติควรเป็น `null` ตามสัญญาจริงของ `osDecoded`) เพื่อใช้พิสูจน์ในเทสต์ข้อ E ว่า
/// [ProximityGate] ไม่แตะค่านี้เลยเมื่อ `proximity != null` ไม่ว่าจะมีค่าอะไรอยู่ก็ตาม
BeaconAdvertisement _iosSample({
  required BeaconProximity proximity,
  int? txPower,
  int rssi = -60,
  ProximityBeaconKey key = _key,
}) => BeaconAdvertisement(
  deviceId: const BeaconDeviceId(
    value: 'FAKE-CB-PERIPHERAL-ID',
    kind: DeviceIdKind.coreBluetoothPeripheralId,
  ),
  rssi: rssi,
  source: AdvertisementSource.osDecoded,
  timestamp: DateTime.utc(2026, 9, 8),
  ibeaconUuid: key.uuid,
  ibeaconMajor: key.major,
  ibeaconMinor: key.minor,
  ibeaconTxPower: txPower,
  proximity: proximity,
);

void main() {
  group('B: median ทน outlier', () {
    test('window [-70,-70,-95,-70,-70] (RSSI แปลงเป็นระยะแล้วเข้า median) ไม่กระโดด '
        'ตามค่าผิดปกติตัวเดียว (-95) — เหตุผลที่ ADR-19 หัวข้อ 6(ก) เลือก median '
        'ไม่ใช่ average', () {
      final clock = _FakeClock();
      final gate = ProximityGate(clock: clock.call);
      const txPower = -59;

      for (final rssi in [-70, -70, -95, -70, -70]) {
        gate.push(_androidSample(rssi: rssi, txPower: txPower));
      }

      final snapshot = gate.debugSnapshot(_key)!;
      final expectedMedian = estimateDistanceMeters(
        rssi: -70,
        txPower: txPower,
        pathLossExponent: gate.pathLossExponent,
      );
      final outlierDistance = estimateDistanceMeters(
        rssi: -95,
        txPower: txPower,
        pathLossExponent: gate.pathLossExponent,
      );

      // median ต้องเท่ากับระยะของ -70 (ค่าปกติ 4 ใน 5 ตัว) แบบเป๊ะ ไม่ใช่ถูกลาก
      // เข้าใกล้ระยะของ -95 (outlier) เลยแม้แต่น้อย
      expect(snapshot.medianMeters, closeTo(expectedMedian, 0.0001));
      expect(snapshot.medianMeters, isNot(closeTo(outlierDistance, 1.0)));
    });
  });

  group('C: hysteresis', () {
    test('เดิน 6m → 4m → 2.5m → 4m → 5.5m ได้ transition แค่ 2 ครั้ง (เข้าที่ 2.5, '
        'ออกที่ 5.5) ไม่ใช่ 4 — dead zone ระหว่าง enterMeters(3.0)/exitMeters(5.0) '
        'กันไม่ให้ทุกก้าวที่ไม่ได้ข้ามเกณฑ์เดิมกลายเป็น transition ใหม่', () {
      final clock = _FakeClock();
      // windowSize/dwellSamples = 1 เพื่อแยกทดสอบ hysteresis ล้วน ๆ โดยไม่ปนกับ
      // ผลของการ smoothing หน้าต่าง (B) หรือ dwell (D) ซึ่งมีเทสต์แยกของตัวเองแล้ว
      final gate = ProximityGate(
        clock: clock.call,
        windowSize: 1,
        dwellSamples: 1,
        pathLossExponent: 2.0,
        enterMeters: 3.0,
        exitMeters: 5.0,
        immediateMeters: 1.0,
      );
      const txPower = -40;

      // priming: ยืนยัน baseline "far" ก่อนเริ่มเดินตามที่โจทย์ระบุ — sample
      // แรกสุดของ key ใด ๆ ตาม ADR-19 หัวข้อ 6(ซ) ยืนยัน far ได้ทันทีอยู่แล้ว
      // (baseline เทียบเท่า far) ซึ่งตัวมันเองนับเป็น transition เสมอไม่ว่าจะ
      // priming ด้วยระยะเท่าไหร่ก็ตาม — ไม่ใช่ transition ที่โจทย์ข้อ C สนใจ
      // (โจทย์สนใจเฉพาะ transition ที่เกิดระหว่าง "เดิน" 5 ก้าวที่ระบุ) จึงไม่
      // เก็บ/ไม่ assert ผลลัพธ์ของ push นี้
      gate.push(_androidSample(rssi: -66, txPower: txPower)); // ~19.95m

      // rssi ต่อไปนี้คำนวณย้อนกลับจาก d = 10^((txPower-rssi)/(10*2.0)) ให้ตรง
      // กับระยะที่โจทย์ระบุ (คลาดเคลื่อนเล็กน้อยจากการปัด rssi เป็น int แต่ยังอยู่
      // ห่างจากทุก threshold อย่างน้อย 0.4m ปลอดภัยจากการเพี้ยนข้ามเกณฑ์)
      final transitions = <ProximityTransition>[];
      for (final rssi in [-56, -52, -48, -52, -55]) {
        // ~6.31m, ~3.98m, ~2.51m, ~3.98m, ~5.62m ตามลำดับ
        final t = gate.push(_androidSample(rssi: rssi, txPower: txPower));
        if (t != null) transitions.add(t);
      }

      expect(transitions, hasLength(2));
      expect(transitions[0].reason, ProximityTransitionReason.closer);
      expect(transitions[0].from, BeaconProximity.far);
      expect(transitions[0].to, BeaconProximity.near);
      expect(transitions[1].reason, ProximityTransitionReason.farther);
      expect(transitions[1].from, BeaconProximity.near);
      expect(transitions[1].to, BeaconProximity.far);
    });
  });

  group('D: dwell', () {
    test('2 sample ที่อยู่ใน enterMeters แล้วหลุด (กลับไป far ก่อนครบ dwellSamples) → '
        'ไม่มี transition เลย — dwell ต้องกันไม่ให้ "ใกล้" ที่ยังไม่ทันยืนยันเต็มจำนวน '
        'ถูกนับเป็นการเปลี่ยน bucket จริง (ADR-19 หัวข้อ 6(ค))', () {
      final clock = _FakeClock();
      final gate = ProximityGate(
        clock: clock.call,
        windowSize: 1,
        pathLossExponent: 2.0,
        // dwellSamples ใช้ค่า default (3) ตรง ๆ ตามที่โจทย์ระบุ "2 sample...
        // แล้วหลุด" (2 < 3 คือยังไม่ครบเกณฑ์)
      );
      const txPower = -40;

      // priming: ยืนยัน baseline far ก่อน (เหตุผลเดียวกับข้อ C — ไม่ assert ผล
      // ของ push นี้)
      gate.push(_androidSample(rssi: -66, txPower: txPower)); // ~19.95m
      expect(gate.currentBucket(_key), BeaconProximity.far);

      const nearRssi = -48; // ~2.51m — อยู่ใน enterMeters(3.0)
      final t1 = gate.push(_androidSample(rssi: nearRssi, txPower: txPower));
      final t2 = gate.push(_androidSample(rssi: nearRssi, txPower: txPower));
      expect(t1, isNull);
      expect(t2, isNull);
      expect(
        gate.debugSnapshot(_key)!.pendingCloserBucket,
        BeaconProximity.near,
      );
      expect(gate.debugSnapshot(_key)!.pendingCloserCount, 2);

      // "หลุด" — กลับไปไกลกว่า enterMeters ก่อนครบ 3 sample ติดกัน
      const fallOutRssi = -56; // ~6.31m
      final t3 = gate.push(_androidSample(rssi: fallOutRssi, txPower: txPower));

      expect(t3, isNull);
      expect(gate.currentBucket(_key), BeaconProximity.far); // ไม่เคยขยับเลย
      final snap = gate.debugSnapshot(_key)!;
      expect(snap.pendingCloserBucket, isNull); // pending ถูกล้างแล้ว
      expect(snap.pendingCloserCount, 0);
    });
  });

  group('E: เส้นทาง iOS', () {
    test('proximity = near ให้ bucket near โดยไม่แตะ ibeaconTxPower เลย (txPower เป็น '
        'null ตามสัญญาจริงของ source == osDecoded)', () {
      final clock = _FakeClock();
      final gate = ProximityGate(clock: clock.call, dwellSamples: 1);

      final t = gate.push(
        _iosSample(proximity: BeaconProximity.near, txPower: null),
      );

      expect(t, isNotNull);
      expect(t!.to, BeaconProximity.near);
      // เส้นทาง iOS ไม่มี medianMeters เพราะไม่ได้คำนวณระยะเองเลย (ADR-19 หัวข้อ
      // "medianMeters" ของ ProximityTransition)
      expect(t.medianMeters, isNull);

      final snap = gate.debugSnapshot(_key)!;
      expect(
        snap.window,
        isEmpty,
      ); // ไม่มีการคำนวณระยะจาก rssi/txPower เกิดขึ้นเลย
      expect(snap.appleProximityWindow, [BeaconProximity.near]);
    });

    test('proximity != null ชนะเสมอแม้ ibeaconTxPower/rssi จะมีค่าที่บ่งบอกระยะคนละ '
        'เรื่องกันโดยสิ้นเชิง — พิสูจน์ว่า txPower/rssi ไม่ถูกใช้คำนวณทับเลยตามลำดับ '
        'การตัดสินของ ADR-19 หัวข้อ 4 ข้อ 1', () {
      final clock = _FakeClock();
      final gate = ProximityGate(clock: clock.call, dwellSamples: 1);

      // rssi=-20, txPower=-59 ถ้าคำนวณเป็นระยะจริงจะได้ระยะที่ใกล้กว่า
      // immediateMeters มาก (ควรจะเป็น immediate) แต่ proximity สั่งมาว่า far —
      // ต้องได้ far เท่านั้น
      final t = gate.push(
        _iosSample(proximity: BeaconProximity.far, txPower: -59, rssi: -20),
      );

      expect(t!.to, BeaconProximity.far);
    });

    test(
      'proximity = unknown ไม่เปลี่ยน state เลย (ทิ้ง sample ทั้งหมดตาม ADR-19 '
      'หัวข้อ 6(ง) — ห้ามแตะแม้แต่หน้าต่าง appleProximityWindow)',
      () {
        final clock = _FakeClock();
        final gate = ProximityGate(clock: clock.call, dwellSamples: 1);

        gate.push(_iosSample(proximity: BeaconProximity.near, txPower: null));
        expect(gate.currentBucket(_key), BeaconProximity.near);

        final t = gate.push(
          _iosSample(proximity: BeaconProximity.unknown, txPower: null),
        );

        expect(t, isNull);
        expect(gate.currentBucket(_key), BeaconProximity.near); // ไม่เปลี่ยน
        expect(gate.debugSnapshot(_key)!.appleProximityWindow, [
          BeaconProximity.near,
        ]); // unknown ไม่ถูกเติมเข้าหน้าต่างเลย
      },
    );
  });

  group('F: drop + counter', () {
    test('txPower == null && proximity == null → ทิ้ง sample และนับ '
        'droppedNoTxPowerCount เพิ่ม (ห้าม default ค่า txPower ตาม ADR-19 หัวข้อ 6(จ))', () {
      final clock = _FakeClock();
      final gate = ProximityGate(clock: clock.call);

      final t1 = gate.push(_androidSample(rssi: -60, txPower: null));
      expect(t1, isNull);

      var snap = gate.debugSnapshot(_key)!;
      expect(snap.droppedNoTxPowerCount, 1);
      expect(snap.lastSampleAt, isNull); // ห้ามขยับแม้แต่เวลา
      expect(snap.window, isEmpty);
      expect(gate.currentBucket(_key), isNull);

      final t2 = gate.push(_androidSample(rssi: -61, txPower: null));
      expect(t2, isNull);
      snap = gate.debugSnapshot(_key)!;
      expect(snap.droppedNoTxPowerCount, 2);
    });
  });

  group('G: stale ด้วย clock ปลอม', () {
    test(
      'เลยเวลา staleAfter → push() คืน transition ที่ to == null พร้อม reason stale '
      '(ADR-19 หัวข้อ 6(ฉ)) — วัดจาก clock ที่ inject เข้ามา ไม่ใช่เวลาจริง',
      () {
        final clock = _FakeClock();
        final gate = ProximityGate(
          clock: clock.call,
          dwellSamples: 1,
          staleAfter: const Duration(seconds: 10),
        );

        gate.push(_iosSample(proximity: BeaconProximity.near));
        expect(gate.currentBucket(_key), BeaconProximity.near);

        clock.advance(
          const Duration(seconds: 11),
        ); // เกิน staleAfter (ไม่มีการรอเวลาจริงเลย)

        final t = gate.push(_iosSample(proximity: BeaconProximity.near));

        expect(t, isNotNull);
        expect(t!.from, BeaconProximity.near);
        expect(t.to, isNull);
        expect(t.reason, ProximityTransitionReason.stale);
        expect(gate.currentBucket(_key), isNull);
      },
    );
  });

  group('H: assert', () {
    test('exitMeters <= enterMeters ต้อง assert (dead zone จะกลับด้าน)', () {
      expect(
        () => ProximityGate(
          clock: () => DateTime.utc(2026, 9, 8),
          enterMeters: 5.0,
          exitMeters: 5.0,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ProximityGate(
          clock: () => DateTime.utc(2026, 9, 8),
          enterMeters: 5.0,
          exitMeters: 3.0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('I: invariant §6(ช) — ห้าม emit unknown ออก public API', () {
    test('ไม่มี code path ไหนคืน BeaconProximity.unknown ออกทาง push()/'
        'currentBucket()/sweepStale()/debugSnapshot().confirmedBucket เลย แม้จะ '
        'ป้อน unknown ปนเข้าไปบ่อยแค่ไหนก็ตาม', () {
      final clock = _FakeClock();
      final gate = ProximityGate(
        clock: clock.call,
        dwellSamples: 1,
        staleAfter: const Duration(seconds: 5),
      );

      final proximities = [
        BeaconProximity.unknown,
        BeaconProximity.near,
        BeaconProximity.unknown,
        BeaconProximity.immediate,
        BeaconProximity.unknown,
        BeaconProximity.far,
        BeaconProximity.unknown,
      ];

      for (final p in proximities) {
        final t = gate.push(_iosSample(proximity: p));
        if (t != null) {
          expect(t.to, isNot(BeaconProximity.unknown));
          expect(t.from, isNot(BeaconProximity.unknown));
        }
        expect(gate.currentBucket(_key), isNot(BeaconProximity.unknown));
        expect(
          gate.debugSnapshot(_key)!.confirmedBucket,
          isNot(BeaconProximity.unknown),
        );
        clock.advance(const Duration(seconds: 1));
      }

      clock.advance(const Duration(seconds: 10)); // ดันให้เลย staleAfter แน่นอน
      final staleTransitions = gate.sweepStale();
      expect(staleTransitions, isNotEmpty);
      for (final t in staleTransitions) {
        expect(t.to, isNot(BeaconProximity.unknown));
        expect(t.from, isNot(BeaconProximity.unknown));
      }
      expect(gate.currentBucket(_key), isNot(BeaconProximity.unknown));
    });
  });

  group('J: บั๊ก 4 ข้อที่แก้ใน ea7e12c', () {
    test('[1/4] sample ที่ drop (unknown) ห้ามต่ออายุ staleness — confirm near แล้ว '
        'ส่ง unknown รัว ๆ ต้องยังหลุด stale ตามช่องว่างเวลาเทียบกับ sample ที่ตัดสินใจ '
        'ได้จริงล่าสุด ไม่ใช่ค้าง near ตลอดไป', () {
      final clock = _FakeClock();
      final gate = ProximityGate(
        clock: clock.call,
        dwellSamples: 1,
        staleAfter: const Duration(seconds: 10),
      );

      gate.push(_iosSample(proximity: BeaconProximity.near)); // t=0 ยืนยัน near
      expect(gate.currentBucket(_key), BeaconProximity.near);

      clock.advance(const Duration(seconds: 5));
      final dropped = gate.push(
        _iosSample(proximity: BeaconProximity.unknown),
      ); // t=5 (5s <= staleAfter ยังไม่ stale)
      expect(dropped, isNull);
      expect(gate.currentBucket(_key), BeaconProximity.near); // ยังไม่หลุด

      // ถ้า unknown ที่ t=5 เคยต่ออายุ lastSampleAt (บั๊กเดิม) ช่องว่างจาก t=5 ถึง
      // t=11 จะแค่ 6 วินาที (ยังไม่ stale) — ต้องไม่เป็นแบบนั้น: lastSampleAt ต้อง
      // ยังค้างอยู่ที่ t=0 ทำให้ช่องว่างจริงคือ 11 วินาที (> staleAfter)
      clock.advance(const Duration(seconds: 6)); // now = t=11
      final t = gate.push(_iosSample(proximity: BeaconProximity.unknown));

      expect(t, isNotNull);
      expect(t!.reason, ProximityTransitionReason.stale);
      expect(t.from, BeaconProximity.near);
      expect(t.to, isNull);
    });

    // [2/4] stale reset ล้าง pending dwell — ถูกล็อกโดยเทสต์
    // "[K.a] stale ขณะ pending dwell (ยังไม่ confirmed)" ในกลุ่ม K ด้านล่าง
    // (เทสต์เดียวกันครอบทั้งบั๊ก 2/4 และหัวข้อ K.a ของ ADR-19 หัวข้อ 6(ฉ))
    //
    // จงใจเขียนเป็นคอมเมนต์ ไม่ใช่ `test(..., skip: ...)` ที่ตัวว่าง — เทสต์ที่
    // `skip` แบบไม่มีเงื่อนไขจะถูกข้ามตลอดไป มีค่าเป็นศูนย์ในเชิงการทดสอบ แต่
    // เพิ่ม `~1 skip` ถาวรในผล CI ซึ่งบดบัง skip จริงที่ควรถูกเห็นในอนาคต

    test('[3/4] sweepStale() ต้อง emit transition ได้แม้ไม่มี push() เรียกเข้ามาอีกเลย '
        '(เคส "ลูกค้าเดินออกจากร้าน" — ไม่มี sample ให้ push() ตรวจจับความเงียบได้เอง)', () {
      final clock = _FakeClock();
      final gate = ProximityGate(
        clock: clock.call,
        dwellSamples: 1,
        staleAfter: const Duration(seconds: 10),
      );

      gate.push(_iosSample(proximity: BeaconProximity.near));
      expect(gate.currentBucket(_key), BeaconProximity.near);

      clock.advance(const Duration(seconds: 11));
      final transitions = gate.sweepStale(); // ไม่มี push() ใด ๆ ระหว่างนี้เลย

      expect(transitions, hasLength(1));
      expect(transitions.single.key, _key);
      expect(transitions.single.from, BeaconProximity.near);
      expect(transitions.single.to, isNull);
      expect(transitions.single.reason, ProximityTransitionReason.stale);
      expect(gate.currentBucket(_key), isNull);
    });

    test(
      '[4/4] เส้นทาง iOS ต้องไม่ flap — near ×4 แล้ว far ×1 ต้องยังเป็น near '
      '(mode ของหน้าต่างยังเป็น near 4 ต่อ 1 ไม่ใช่ bucket ดิบล่าสุดของ Apple)',
      () {
        final clock = _FakeClock();
        final gate = ProximityGate(clock: clock.call, dwellSamples: 1);

        for (var i = 0; i < 4; i++) {
          gate.push(_iosSample(proximity: BeaconProximity.near));
        }
        expect(gate.currentBucket(_key), BeaconProximity.near);

        final farTransition = gate.push(
          _iosSample(proximity: BeaconProximity.far),
        );

        expect(farTransition, isNull); // ไม่มี transition — mode ยังเป็น near
        expect(gate.currentBucket(_key), BeaconProximity.near);
      },
    );
  });

  group('K: เพิ่มจากการอ่าน diff', () {
    test('[K.a] stale ขณะ pending dwell (ยังไม่ confirmed): near×2 → เกิน staleAfter → '
        'near×1 → ไม่มี transition เลย (pending ถูกล้าง เริ่มนับใหม่จาก 1) และไม่มี '
        'stale transition เพราะไม่เคย confirmed มาก่อน (ล็อกบั๊ก 2/4 พร้อมกัน ตาม '
        'ADR-19 หัวข้อ 6(ฉ): "สิ่งที่ต้อง reset เมื่อหลุด stale")', () {
      final clock = _FakeClock();
      final gate = ProximityGate(
        clock: clock.call,
        windowSize: 1,
        // dwellSamples ใช้ค่า default (3) ตรง ๆ — ต้อง > 1 เพื่อให้มีสถานะ
        // "pending" (ยังไม่ confirmed) ให้ทดสอบตามที่โจทย์ต้องการ
        pathLossExponent: 2.0,
        staleAfter: const Duration(seconds: 10),
      );
      const txPower = -40;
      const nearRssi = -48; // ~2.51m อยู่ใน enterMeters(3.0) → near

      final t1 = gate.push(_androidSample(rssi: nearRssi, txPower: txPower));
      final t2 = gate.push(_androidSample(rssi: nearRssi, txPower: txPower));
      expect(t1, isNull);
      expect(t2, isNull);
      expect(gate.debugSnapshot(_key)!.pendingCloserCount, 2);
      expect(gate.currentBucket(_key), isNull); // ไม่เคย confirmed

      clock.advance(const Duration(seconds: 11)); // เกิน staleAfter

      final t3 = gate.push(_androidSample(rssi: nearRssi, txPower: txPower));

      expect(
        t3,
        isNull,
      ); // ไม่มีอะไรให้ประกาศว่าหลุด เพราะไม่เคย confirmed มาก่อน
      final snap = gate.debugSnapshot(_key)!;
      expect(snap.pendingCloserBucket, BeaconProximity.near);
      expect(snap.pendingCloserCount, 1); // เริ่มนับใหม่จาก 1 ไม่ใช่สานต่อจาก 2
      expect(gate.currentBucket(_key), isNull);
    });

    test('[K.b] stale ขณะ confirmed ทิ้ง sample ที่จุดชนวน — หลัง stale transition '
        'แล้ว debugSnapshot() ต้องมี window ว่างและ lastSampleAt เป็น null '
        '(ล็อก design choice ที่บันทึกไว้ใน ADR-19 หัวข้อ 7 ห้ามใครมาแก้ "ให้ดีขึ้น" '
        'โดยไม่รู้ตัว)', () {
      final clock = _FakeClock();
      final gate = ProximityGate(
        clock: clock.call,
        dwellSamples: 1,
        staleAfter: const Duration(seconds: 10),
      );

      gate.push(_iosSample(proximity: BeaconProximity.near));
      expect(gate.currentBucket(_key), BeaconProximity.near);

      clock.advance(const Duration(seconds: 11));
      final t = gate.push(_iosSample(proximity: BeaconProximity.near));
      expect(t!.reason, ProximityTransitionReason.stale);

      final snap = gate.debugSnapshot(_key)!;
      expect(snap.window, isEmpty);
      expect(snap.appleProximityWindow, isEmpty);
      expect(snap.lastSampleAt, isNull);
      expect(snap.confirmedBucket, isNull);
    });

    test(
      '[K.c] iOS tie-break: window [immediate, immediate, near, near, far] → '
      'candidate ต้องเป็น near (เสมอกันระหว่าง immediate/near ที่นับได้ 2 ครั้ง '
      'เท่ากัน เลือกตัวที่ไกลกว่าตาม ADR-19 หัวข้อ 4 ข้อ 1)',
      () {
        final clock = _FakeClock();
        final gate = ProximityGate(clock: clock.call, dwellSamples: 1);
        // windowSize default = 5 พอดีกับ 5 sample ด้านล่าง ไม่มี eviction เกิดขึ้น

        for (final p in [
          BeaconProximity.immediate,
          BeaconProximity.immediate,
          BeaconProximity.near,
          BeaconProximity.near,
          BeaconProximity.far,
        ]) {
          gate.push(_iosSample(proximity: p));
        }

        expect(gate.currentBucket(_key), BeaconProximity.near);
        expect(gate.debugSnapshot(_key)!.appleProximityWindow, [
          BeaconProximity.immediate,
          BeaconProximity.immediate,
          BeaconProximity.near,
          BeaconProximity.near,
          BeaconProximity.far,
        ]);
      },
    );

    test(
      '[K.d] drop ห้ามมีผลข้างเคียงอื่นนอกจาก counter: ส่ง unknown ×10 แล้ว '
      'debugSnapshot() ต้องได้ lastSampleAt == null, window ว่าง, '
      'appleProximityWindow ว่าง, และ droppedNoTxPowerCount == 0 (unknown ไม่นับ '
      'เป็น noTxPower — คนละเหตุผลของการ drop ตาม ADR-19 หัวข้อ 6(ง) vs 6(จ))',
      () {
        final clock = _FakeClock();
        final gate = ProximityGate(clock: clock.call);

        for (var i = 0; i < 10; i++) {
          final t = gate.push(_iosSample(proximity: BeaconProximity.unknown));
          expect(t, isNull);
        }

        final snap = gate.debugSnapshot(_key)!;
        expect(snap.lastSampleAt, isNull);
        expect(snap.window, isEmpty);
        expect(snap.appleProximityWindow, isEmpty);
        expect(snap.droppedNoTxPowerCount, 0);
      },
    );
  });
}
