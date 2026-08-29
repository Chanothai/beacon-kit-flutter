// Test ของ [planRegionRegistration] — pure function ตาม ARCHITECTURE.md ADR-8
//
// *** Track A (SPRINT.md) ***
// ไฟล์นี้ทดสอบ "การตัดสินใจว่าจะลงทะเบียน region ชุดไหน" ซึ่งเป็น logic ล้วน ๆ
// ไม่แตะ CoreLocation จึงพิสูจน์ได้ 100% โดยไม่ต้องมีอุปกรณ์
//
// สิ่งที่ไฟล์นี้ **ไม่ได้** พิสูจน์: ว่า CoreLocation รับ region ชุดนี้ไปแล้วทำงาน
// ถูกต้องจริง (เช่น didEnterRegion ยิงกี่ครั้งเมื่อ region ซ้อนทับกัน — เป็น open
// question ที่ ADR-8 ระบุไว้ว่ายังไม่ยืนยัน ต้องทดสอบบนเครื่องจริง)
library;

import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

const String _uuid = 'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE';

/// สร้างสาขาปลอม n แห่ง เรียง major 1..n และวางห่างจาก (0,0) เพิ่มขึ้นเรื่อย ๆ
/// (สาขาที่ index น้อย = ใกล้ (0,0) มากกว่า)
List<BigcBranch> _branches(int n) => List.generate(
  n,
  (i) => BigcBranch(
    branchCode: 'BR-${(i + 1).toString().padLeft(4, '0')}',
    major: i + 1,
    latitude: (i + 1) * 0.1,
    longitude: 0,
  ),
);

void main() {
  group('planRegionRegistration — สัญญาที่ห้ามผิดไม่ว่ากรณีใด (ADR-8)', () {
    test('สาขา 0 แห่ง -> ต้องยังได้ region ชั้นที่ 1 กลับมา 1 อัน '
        '(ห้ามคืน list ว่าง เพราะจะไม่มีอะไรปลุกแอปเลย)', () {
      final plan = planRegionRegistration(
        bigcProximityUuid: _uuid,
        branches: const [],
      );

      expect(plan, hasLength(1));
      expect(plan.single.tier, RegionTier.fleetWide);
      expect(plan.single.identifier, kFleetWideRegionIdentifier);
      expect(
        plan.single.major,
        isNull,
        reason: 'ชั้นที่ 1 ต้องไม่ระบุ major เพื่อให้ครอบคลุมทั้งฟลีต',
      );
    });

    test(
      'สาขาเกิน 20 แห่ง -> รวมต้องไม่เกิน 20 และชั้นที่ 2 ต้องได้ 19 พอดี',
      () {
        final plan = planRegionRegistration(
          bigcProximityUuid: _uuid,
          branches: _branches(100),
          userLocation: const ApproximateLocation(latitude: 0, longitude: 0),
        );

        expect(plan, hasLength(kMaxMonitoredRegions));
        expect(
          plan.where((r) => r.tier == RegionTier.branch),
          hasLength(kMaxBranchRegions),
        );
        expect(plan.where((r) => r.tier == RegionTier.fleetWide), hasLength(1));
      },
    );

    test('ชั้นที่ 1 ต้องไม่ถูกตัดออกไม่ว่ากรณีใด — ทดสอบตั้งแต่ 0 ถึง 100 สาขา '
        'ทั้งแบบรู้และไม่รู้ตำแหน่งผู้ใช้', () {
      for (final count in [0, 1, 18, 19, 20, 21, 100]) {
        for (final location in [
          null,
          const ApproximateLocation(latitude: 0, longitude: 0),
        ]) {
          final plan = planRegionRegistration(
            bigcProximityUuid: _uuid,
            branches: _branches(count),
            userLocation: location,
          );

          expect(
            plan.first.tier,
            RegionTier.fleetWide,
            reason:
                'สาขา $count แห่ง (userLocation=$location): '
                'ชั้นที่ 1 ต้องอยู่ตัวแรกเสมอ',
          );
          expect(
            plan.where((r) => r.tier == RegionTier.fleetWide),
            hasLength(1),
            reason: 'สาขา $count แห่ง: ชั้นที่ 1 ต้องมีอันเดียว ไม่ซ้ำ',
          );
          expect(
            plan.length,
            lessThanOrEqualTo(kMaxMonitoredRegions),
            reason: 'สาขา $count แห่ง: ต้องไม่เกินเพดาน 20 ของ iOS',
          );
        }
      }
    });
  });

  group('planRegionRegistration — การเลือกสาขาชั้นที่ 2', () {
    test(
      'เรียงสาขาใกล้ผู้ใช้ก่อน แล้วตัดที่ 19 (ไม่ใช่เอา 19 ตัวแรกของ list)',
      () {
        // ส่งเข้าแบบไกล -> ใกล้ (กลับลำดับ) เพื่อพิสูจน์ว่าเรียงใหม่จริง
        final reversed = _branches(30).reversed.toList();

        final plan = planRegionRegistration(
          bigcProximityUuid: _uuid,
          branches: reversed,
          userLocation: const ApproximateLocation(latitude: 0, longitude: 0),
        );

        final branchCodes = plan
            .where((r) => r.tier == RegionTier.branch)
            .map((r) => r.identifier)
            .toList();

        expect(branchCodes, hasLength(kMaxBranchRegions));
        expect(
          branchCodes.first,
          'BR-0001',
          reason: 'สาขาที่ใกล้ที่สุดต้องมาก่อน แม้จะถูกส่งเข้ามาเป็นตัวสุดท้าย',
        );
        expect(
          branchCodes,
          isNot(contains('BR-0021')),
          reason: 'สาขาที่ไกลเกิน 19 อันดับแรกต้องไม่ถูกเลือก',
        );
      },
    );

    test(
      'ไม่รู้ตำแหน่งผู้ใช้ (null) -> คงลำดับที่ส่งเข้ามา ไม่เดาว่าอันไหนใกล้',
      () {
        final plan = planRegionRegistration(
          bigcProximityUuid: _uuid,
          branches: _branches(30).reversed.toList(),
        );

        final branchCodes = plan
            .where((r) => r.tier == RegionTier.branch)
            .map((r) => r.identifier)
            .toList();

        expect(branchCodes.first, 'BR-0030');
        expect(branchCodes, hasLength(kMaxBranchRegions));
      },
    );

    test(
      'region ชั้นที่ 2 ต้องใส่ major และใช้ branchCode เป็น identifier',
      () {
        final plan = planRegionRegistration(
          bigcProximityUuid: _uuid,
          branches: const [
            BigcBranch(
              branchCode: 'BR-RAMA9',
              major: 42,
              latitude: 13.75,
              longitude: 100.56,
            ),
          ],
        );

        final branch = plan.firstWhere((r) => r.tier == RegionTier.branch);
        expect(branch.identifier, 'BR-RAMA9');
        expect(branch.major, 42);
        expect(branch.uuid, _uuid);
      },
    );

    test('ระยะเท่ากันเป๊ะ -> ลำดับ deterministic (เรียงด้วย branchCode)', () {
      // สองสาขาห่างจากผู้ใช้เท่ากันพอดี คนละทิศ
      const branches = [
        BigcBranch(branchCode: 'BR-ZZZZ', major: 2, latitude: 1, longitude: 0),
        BigcBranch(branchCode: 'BR-AAAA', major: 1, latitude: -1, longitude: 0),
      ];

      final first = planRegionRegistration(
        bigcProximityUuid: _uuid,
        branches: branches,
        userLocation: const ApproximateLocation(latitude: 0, longitude: 0),
      );
      final second = planRegionRegistration(
        bigcProximityUuid: _uuid,
        branches: branches.reversed.toList(),
        userLocation: const ApproximateLocation(latitude: 0, longitude: 0),
      );

      expect(
        first.map((r) => r.identifier),
        second.map((r) => r.identifier),
        reason: 'ผลลัพธ์ต้องไม่ขึ้นกับลำดับที่ส่งเข้ามาเมื่อระยะเท่ากัน',
      );
      expect(first[1].identifier, 'BR-AAAA');
    });

    test('ทุก region ในแผนต้องใช้ UUID เดียวกันทั้งหมด (ADR-5)', () {
      final plan = planRegionRegistration(
        bigcProximityUuid: _uuid,
        branches: _branches(5),
      );

      expect(plan.every((r) => r.uuid == _uuid), isTrue);
    });
  });
}
