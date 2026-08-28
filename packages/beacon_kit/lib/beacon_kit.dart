/// `beacon_kit` — app-facing Dart API สำหรับสแกน/เชื่อมต่อ beacon แบบ
/// vendor-agnostic (facade เดียวที่แอปเรียก ไม่เห็นคลาสของยี่ห้อใดโดยตรง)
///
/// อ้างอิง: ARCHITECTURE.md
library;

export 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
// ADR-6 (28 ส.ค. 2026): export เฉพาะ 3 ชื่อนี้จาก beacon_kit_ios ตรง ๆ (ไม่ export
// ทั้ง barrel) — ต่างจาก IBeaconRegionRequest ที่ beacon_kit ตั้งใจไม่ผูกและมี
// IBeaconRegionConfig เป็น facade ของตัวเองแทน (ดูคอมเมนต์ใน
// ibeacon_region_config.dart) เพราะ region enter/exit/unknown state และ
// authorization level เป็นแนวคิดที่ยังไม่มี contract กลางใน
// beacon_kit_platform_interface (แพ็กเกจนั้นถูกแก้โดย agent อื่นคู่ขนานอยู่ใน
// สปรินต์นี้ ห้ามแตะ) การสร้าง facade type ซ้ำของ beacon_kit เองตอนนี้จะเป็นการ
// เดาโครงที่ platform_interface อาจเลือกในอนาคต จึง export type ของ
// beacon_kit_ios ตรง ๆ ไปพลางก่อน (ผูกกับ iOS ชัดเจนในชื่อ `IBeacon...` อยู่แล้ว
// ไม่ทำให้ผู้เรียกเข้าใจผิดว่าเป็น cross-platform) — ดู
// GenericIBeaconEddystoneAdapter.regionStateEvents/getIBeaconAuthorizationLevel
export 'package:beacon_kit_ios/beacon_kit_ios.dart'
    show IBeaconAuthorizationLevel, IBeaconRegionState, IBeaconRegionStateEvent;

export 'src/beacon_adapter.dart';
export 'src/beacon_manager.dart';
export 'src/generic_ibeacon_eddystone_adapter.dart';
export 'src/ibeacon_region_config.dart';
