/// ผลลัพธ์ที่ decode แล้วของ Apple iBeacon manufacturer-specific data
/// (company ID 0x004C, frame prefix 0x02 0x15)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-3 "Parser contract — EddystoneParser / IBeaconParser"
final class IBeaconFrame {
  final String uuid; // lowercase, hyphenated (8-4-4-4-12)
  final int major;
  final int minor;
  final int txPower; // measured power @ 1m, signed 8-bit dBm

  const IBeaconFrame({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.txPower,
  });

  @override
  String toString() =>
      'IBeaconFrame(uuid: $uuid, major: $major, minor: $minor, txPower: $txPower)';
}
