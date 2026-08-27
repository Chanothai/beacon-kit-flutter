/// `beacon_kit` — app-facing Dart API สำหรับสแกน/เชื่อมต่อ beacon แบบ
/// vendor-agnostic (facade เดียวที่แอปเรียก ไม่เห็นคลาสของยี่ห้อใดโดยตรง)
///
/// อ้างอิง: ARCHITECTURE.md
library;

export 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

export 'src/beacon_adapter.dart';
export 'src/beacon_manager.dart';
export 'src/generic_ibeacon_eddystone_adapter.dart';
export 'src/ibeacon_region_config.dart';
