/// สัญญากลาง (platform interface) ของ beacon_kit — vendor-agnostic broadcast-path
/// entities และ pure-function parser สำหรับ iBeacon/Eddystone
///
/// อ้างอิง: ARCHITECTURE.md, ADR-3 "Parser contract — EddystoneParser / IBeaconParser"
library;

export 'src/entities/beacon_advertisement.dart';
export 'src/entities/eddystone_frame.dart';
export 'src/entities/ibeacon_frame.dart';
export 'src/parsers/eddystone_parser.dart';
export 'src/parsers/ibeacon_parser.dart';
export 'src/parsers/parse_result.dart';
