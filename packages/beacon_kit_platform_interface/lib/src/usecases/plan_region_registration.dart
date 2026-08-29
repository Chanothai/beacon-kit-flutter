import 'dart:math' as math;

import '../entities/bigc_branch.dart';
import '../entities/region_registration_plan.dart';

/// เพดานจำนวน region ที่ iOS ให้ monitor พร้อมกันได้ต่อแอป
///
/// ยืนยันจากเอกสารทางการของ Apple: "An app can register up to 20 regions at a
/// time." (`CLLocationManager.startMonitoring(for:)`) — ดู ARCHITECTURE.md ADR-8
const int kMaxMonitoredRegions = 20;

/// `identifier` ของ region ชั้นที่ 1 (ตาข่ายกันพลาด) — คงที่ ไม่ผูกกับสาขาใด
const String kFleetWideRegionIdentifier = 'bigc-fleet-wide';

/// จำนวน region ชั้นที่ 2 สูงสุด = เพดานทั้งหมด ลบที่กันไว้ให้ชั้นที่ 1 หนึ่งอัน
const int kMaxBranchRegions = kMaxMonitoredRegions - 1;

/// วางแผนว่าจะลงทะเบียน region ชุดไหนกับ CoreLocation — **pure function**
/// ไม่แตะ CoreLocation ไม่แตะ I/O ทดสอบได้ครบโดยไม่ต้องมีอุปกรณ์ (Track A)
///
/// implement ตาม ARCHITECTURE.md ADR-8 "Two-tier region registration"
///
/// สัญญา 3 ข้อที่ฟังก์ชันนี้รักษาไว้เสมอ (มี unit test บังคับทุกข้อ):
///
/// 1. **region ชั้นที่ 1 อยู่ในผลลัพธ์เสมอ และอยู่ตัวแรกเสมอ** ไม่ว่า input จะเป็น
///    อะไร — สาขา 0 แห่ง, สาขาเป็นหมื่น, หรือไม่รู้ตำแหน่งผู้ใช้เลย
///    เหตุผล: ถ้าชั้นที่ 1 หลุดหายไป จะเกิดจุดบอดที่ "เงียบเหมือนไม่มีใครเดินผ่าน"
///    ซึ่งแยกจากการทำงานปกติไม่ออก (ADR-8)
/// 2. **จำนวนรวมไม่เกิน [kMaxMonitoredRegions] เสมอ**
/// 3. ชั้นที่ 2 เรียงตามระยะจาก [userLocation] (ใกล้ก่อน) แล้วตัดที่
///    [kMaxBranchRegions]
///
/// [userLocation] เป็น `null` ได้ (ยังไม่รู้ตำแหน่งผู้ใช้) — กรณีนั้นจะคงลำดับ
/// ของ [branches] ตามที่ส่งเข้ามาแล้วตัดตามเพดาน ไม่พยายามเดาว่าสาขาไหนใกล้
List<PlannedRegion> planRegionRegistration({
  required String bigcProximityUuid,
  required List<BigcBranch> branches,
  ApproximateLocation? userLocation,
}) {
  // ชั้นที่ 1 — ใส่ก่อนเสมอ ก่อนพิจารณาอะไรทั้งสิ้น เพื่อให้เป็นไปไม่ได้ในเชิงโครงสร้าง
  // ที่มันจะถูกตัดออกด้วย logic ด้านล่าง
  final plan = <PlannedRegion>[
    PlannedRegion(
      identifier: kFleetWideRegionIdentifier,
      uuid: bigcProximityUuid,
      tier: RegionTier.fleetWide,
    ),
  ];

  if (branches.isEmpty) return List.unmodifiable(plan);

  final ordered = List<BigcBranch>.of(branches);
  if (userLocation != null) {
    // เรียงใกล้ก่อน — ใช้ระยะกำลังสองแบบระนาบ พอสำหรับการ "จัดลำดับ" ไม่ต้อง
    // แม่นระดับ geodesic เพราะเราสนแค่ว่าสาขาไหนใกล้กว่ากัน ไม่ได้ใช้ค่าระยะจริง
    ordered.sort((a, b) {
      final da = _squaredDistance(userLocation, a);
      final db = _squaredDistance(userLocation, b);
      final byDistance = da.compareTo(db);
      // ระยะเท่ากันเป๊ะ -> เรียงด้วย branchCode ให้ผลลัพธ์ deterministic
      // (ไม่งั้นลำดับจะขึ้นกับ sort implementation ซึ่งทดสอบซ้ำไม่ได้)
      return byDistance != 0
          ? byDistance
          : a.branchCode.compareTo(b.branchCode);
    });
  }

  for (final branch in ordered.take(kMaxBranchRegions)) {
    plan.add(
      PlannedRegion(
        identifier: branch.branchCode,
        uuid: bigcProximityUuid,
        major: branch.major,
        tier: RegionTier.branch,
      ),
    );
  }

  assert(
    plan.length <= kMaxMonitoredRegions,
    'แผนต้องไม่เกินเพดาน $kMaxMonitoredRegions region ของ iOS',
  );
  assert(
    plan.first.tier == RegionTier.fleetWide,
    'region ชั้นที่ 1 ต้องอยู่ในแผนเสมอและอยู่ตัวแรก (ADR-8)',
  );

  return List.unmodifiable(plan);
}

/// ระยะกำลังสองแบบระนาบ — ใช้จัดลำดับเท่านั้น ไม่ใช่ค่าระยะจริงบนผิวโลก
double _squaredDistance(ApproximateLocation from, BigcBranch to) {
  final dLat = from.latitude - to.latitude;
  final dLon = from.longitude - to.longitude;
  // ชดเชยว่าองศาลองจิจูดสั้นลงเมื่อเข้าใกล้ขั้วโลก ไม่งั้นการจัดลำดับจะเพี้ยน
  // ในละติจูดสูง (ประเทศไทยอยู่ละติจูดต่ำ ผลต่างน้อย แต่ทำให้ถูกไว้ก่อน)
  final lonScale = math.cos(from.latitude * math.pi / 180);
  final scaledLon = dLon * lonScale;
  return dLat * dLat + scaledLon * scaledLon;
}
