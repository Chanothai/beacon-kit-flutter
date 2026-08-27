import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

/// สัญญากลางของ "adapter" หนึ่งตัว — ตัวแทนของแหล่งข้อมูล beacon หนึ่งประเภท
/// (broadcast-only vendor-agnostic หรือ connect-capable เฉพาะยี่ห้อ)
///
/// อ้างอิง: ARCHITECTURE.md หัวข้อ "Dart API หลัก (`beacon_kit`)"
abstract class BeaconAdapter {
  /// รหัสยี่ห้อ/adapter เช่น `"generic_ibeacon_eddystone"`, `"kkm_k9p"` — ใช้แยก
  /// adapter เวลา debug/log เท่านั้น ไม่ใช่ identity ของอุปกรณ์ (ดู [BeaconDeviceId])
  String get vendorId;

  /// `false` = broadcast-only, [connect] จะ throw [UnsupportedError] เสมอ
  bool get supportsConnect;

  /// Path A — รับ broadcast อย่างเดียว ใช้ได้กับทุก adapter ไม่ว่า
  /// [supportsConnect] จะเป็นเท็จหรือจริงก็ตาม
  Stream<BeaconAdvertisement> scan();

  /// Path B — เปิดการเชื่อมต่อ GATT กับอุปกรณ์เฉพาะเจาะจง throw
  /// [UnsupportedError] ถ้า [supportsConnect] เป็นเท็จ (broadcast-only adapter)
  Future<BeaconConnection> connect({
    // TODO(ADR-1 follow-up): เปลี่ยนเป็น BeaconDeviceId เมื่อเริ่มงาน KkmK9pAdapter
    // (Track B, ยังไม่เริ่มสปรินต์นี้) — macAddress เดิมมีปัญหา identity เดียวกับ
    // BeaconAdvertisement.macAddress รุ่นเก่าที่ถูกแทนที่ด้วย BeaconDeviceId แล้ว
    // (ดู ARCHITECTURE.md ADR-1) แต่ connect-path ยังไม่ถูกแก้วันนี้เพราะเป็น
    // Track B ที่ต้องรอฮาร์ดแวร์ K9P จริงตาม SPRINT.md
    required String macAddress,
    required String password,
    Duration timeout = const Duration(seconds: 15),
  });
}

/// สัญญากลางของการเชื่อมต่อ GATT หนึ่ง session — คืนจาก [BeaconAdapter.connect]
///
/// รอบนี้ implement เฉพาะ [readConfig]/[writeConfig]/[disconnect] —
/// `readSensorHistory`/`startFirmwareUpdate` ข้ามรอบนี้ (Track B, ยังไม่เริ่ม
/// KkmK9pAdapter ตาม SPRINT.md)
abstract class BeaconConnection {
  Future<Map<String, dynamic>> readConfig();
  Future<void> writeConfig(Map<String, dynamic> config);
  Future<void> disconnect();
}
