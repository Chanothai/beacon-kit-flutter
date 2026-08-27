/// ผลลัพธ์ที่ decode แล้วของ Eddystone frame หนึ่งเฟรม (service `0000FEAA-...`)
/// — sealed class แยกตาม frame type ให้ผู้เรียกใช้ pattern matching (switch)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-3 "Parser contract — EddystoneParser / IBeaconParser"
sealed class EddystoneFrame {
  const EddystoneFrame();
}

/// Eddystone-UID (`0x00`) — namespace/instance identity แบบ static
final class EddystoneUidFrame extends EddystoneFrame {
  final String namespaceId; // 10 bytes -> 20 hex chars, lowercase
  final String instanceId; // 6 bytes -> 12 hex chars, lowercase
  final int txPower; // calibrated @ 0m, signed 8-bit dBm

  const EddystoneUidFrame({
    required this.namespaceId,
    required this.instanceId,
    required this.txPower,
  });

  @override
  String toString() =>
      'EddystoneUidFrame(namespaceId: $namespaceId, instanceId: $instanceId, '
      'txPower: $txPower)';
}

/// Eddystone-URL (`0x10`) — URL ที่ compress ด้วย scheme/suffix encoding
final class EddystoneUrlFrame extends EddystoneFrame {
  final int txPower;
  final String url; // ขยาย scheme prefix + encoded suffix ตาม spec แล้ว

  const EddystoneUrlFrame({required this.txPower, required this.url});

  @override
  String toString() => 'EddystoneUrlFrame(txPower: $txPower, url: $url)';
}

/// Eddystone-TLM (`0x20`) — telemetry ของตัว beacon เอง (battery/temperature/uptime)
final class EddystoneTlmFrame extends EddystoneFrame {
  final int version; // ปกติ 0x00
  final double batteryVoltageMv; // มิลลิโวลต์, 0 = ไม่รองรับ
  final double? temperatureC; // null เมื่อ raw == 0x8000 (sensor ไม่รองรับ)
  final int advertisingPduCount;
  final Duration timeSincePowerOn; // resolution 0.1s ตาม spec

  const EddystoneTlmFrame({
    required this.version,
    required this.batteryVoltageMv,
    required this.temperatureC,
    required this.advertisingPduCount,
    required this.timeSincePowerOn,
  });

  @override
  String toString() =>
      'EddystoneTlmFrame(version: $version, batteryVoltageMv: $batteryVoltageMv, '
      'temperatureC: $temperatureC, advertisingPduCount: $advertisingPduCount, '
      'timeSincePowerOn: $timeSincePowerOn)';
}
