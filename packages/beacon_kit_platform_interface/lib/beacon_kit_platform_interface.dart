/// สัญญากลาง (platform interface) ของ beacon_kit — `BeaconKitPlatform`
/// (สัญญาข้ามแพลตฟอร์มของเส้นทางสแกน advertisement ดิบ ตาม ADR-13),
/// vendor-agnostic broadcast-path entities และ pure-function parser สำหรับ iBeacon/Eddystone รวมถึง domain
/// entity/usecase สำหรับ mapping BigC ID scheme (identity triple ->
/// ข้อมูลธุรกิจ)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-3 "Parser contract — EddystoneParser /
/// IBeaconParser", ADR-5 "BigC ID Scheme สำหรับ multi-vendor provisioning",
/// ADR-7 "ตำแหน่งของ domain entity/usecase สำหรับ BigC ID mapping",
/// ADR-8 "Two-tier region registration"
library;

export 'src/beacon_kit_platform.dart';
export 'src/entities/beacon_advertisement.dart';
export 'src/entities/bigc_branch.dart';
export 'src/entities/bigc_beacon_identity.dart';
export 'src/entities/bigc_beacon_metadata.dart';
export 'src/entities/eddystone_frame.dart';
export 'src/entities/ibeacon_frame.dart';
export 'src/entities/region_registration_plan.dart';
export 'src/parsers/eddystone_parser.dart';
export 'src/parsers/ibeacon_parser.dart';
export 'src/parsers/parse_result.dart';
export 'src/usecases/bigc_beacon_metadata_repository.dart';
export 'src/usecases/plan_region_registration.dart';
export 'src/usecases/resolve_bigc_beacon_metadata.dart';
export 'src/usecases/resolve_bigc_beacon_metadata_result.dart';
