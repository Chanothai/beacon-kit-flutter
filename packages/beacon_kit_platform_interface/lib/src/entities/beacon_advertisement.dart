import 'dart:typed_data';

/// ชนิดของ identity ที่ [BeaconDeviceId.value] แทน — จำเป็นเพราะแต่ละ platform/API
/// ให้ "identity" ของอุปกรณ์คนละแบบกันโดยสิ้นเชิง เก็บปนกันในฟิลด์ String เดียว
/// จะทำให้โค้ด dedup/persist ข้าม kind กันโดยไม่ตั้งใจ (บั๊กเงียบที่ compile ผ่าน
/// แต่พังตอน runtime)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-1 "BeaconAdvertisement.macAddress -> BeaconDeviceId"
enum DeviceIdKind {
  /// Android BluetoothDevice.address — MAC address จริงจากวิทยุ คงที่ข้าม install
  macAddress,

  /// iOS CBPeripheral.identifier (CoreBluetooth) — UUID สุ่มต่อแอป ไม่ใช่ MAC จริง
  /// เปลี่ยนได้เมื่อถอน-ลงแอปใหม่ ใช้เทียบ "อุปกรณ์เดียวกันภายในการติดตั้งนี้" เท่านั้น
  coreBluetoothPeripheralId,

  /// iOS CLBeacon (CoreLocation) — ไม่มี physical device identifier ให้เลย
  /// ใช้ identity เชิงตรรกะแทน รูปแบบ `<uuid>:<major>:<minor>` (uuid เป็น lowercase)
  /// หมายเหตุ: สอง beacon ที่ตั้งค่า uuid/major/minor ซ้ำกันจะได้ deviceId เดียวกัน
  /// — เป็นข้อจำกัดของ platform เอง ไม่ใช่บั๊กของ SDK นี้
  iBeaconLogicalId,
}

/// Identity ของอุปกรณ์ beacon หนึ่งตัว — ประกอบด้วยค่า [value] และ [kind] ที่บอกว่า
/// ค่านั้นมาจาก identity scheme ไหน ห้ามเทียบ/dedup สอง instance ที่ [kind] ต่างกัน
/// ราวกับเป็นอุปกรณ์เดียวกัน (`value` ตรงกันข้าม kind โดยบังเอิญไม่มีความหมายอะไร)
///
/// `BeaconManager.scanAll()` ที่ merge stream จากหลาย adapter/source ต้อง dedup
/// ตามคู่ (kind, value) เสมอ
class BeaconDeviceId {
  final String value;
  final DeviceIdKind kind;

  const BeaconDeviceId({required this.value, required this.kind});

  @override
  bool operator ==(Object other) =>
      other is BeaconDeviceId && other.value == value && other.kind == kind;

  @override
  int get hashCode => Object.hash(value, kind);

  @override
  String toString() => 'BeaconDeviceId(value: $value, kind: $kind)';
}

/// แหล่งข้อมูลดิบที่ BeaconAdvertisement นี้เดินทางมา — บอกว่า field กลุ่มไหน
/// การันตีว่ามีค่า และกลุ่มไหนการันตีว่าไม่มี (null / ว่าง)
enum AdvertisementSource {
  /// iOS, ผ่าน CLLocationManager ranging (CLBeaconRegion) — เฉพาะ iBeacon เท่านั้น
  /// ibeaconUuid/Major/Minor/proximity การันตีว่ามีค่าเสมอ, ibeaconTxPower เป็น null
  /// เสมอ (CLBeacon ไม่มี field นี้ตรง ๆ), raw และ rawBytes ว่างเสมอ
  coreLocation,

  /// iOS, ผ่าน CBCentralManager scan — ทุกฟอร์แมต "ยกเว้น" iBeacon (OS mask
  /// iBeacon manufacturer data ทิ้งที่ระดับ CoreBluetooth ทั้งหมด — ดูหัวข้อ
  /// "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android")
  /// ibeacon* ทุกฟิลด์เป็น null เสมอ, raw/rawBytes มีค่าจาก Dart parser (Eddystone ฯลฯ)
  coreBluetooth,

  /// Android, ผ่าน BluetoothLeScanner — ทุกฟอร์แมตรวม iBeacon (Android ไม่ mask)
  /// ibeacon* มีค่าได้ก็ต่อเมื่อ IBeaconParser.parse() บน manufacturerData สำเร็จ
  /// (ไม่การันตีเหมือน coreLocation เพราะเป็นผล parse ไม่ใช่ native ถอดให้)
  /// raw/rawBytes มีค่าเสมอ (raw ADV bytes จาก OS)
  android,
}

/// ค่า proximity ที่ CoreLocation คำนวณให้ (ระยะห่างโดยประมาณจาก RSSI/txPower ภายใน
/// ของ OS เอง) ไม่มีทางเทียบเท่าฝั่ง Android/Dart parser เพราะไม่ใช่ field ที่ decode
/// ได้จาก byte ของ ADV — มีค่าเฉพาะ source == coreLocation เท่านั้น
enum BeaconProximity { unknown, immediate, near, far }

/// Domain entity กลางที่รวมผลลัพธ์จากทุก source (CoreLocation typed fields,
/// CoreBluetooth/Android raw bytes ที่ผ่าน Dart parser แล้ว) เป็นชนิดเดียว
/// เพื่อให้ `BeaconManager.scanAll()` merge เป็น `Stream<BeaconAdvertisement>` เดียวได้
/// โดยไม่ต้อง type-check/cast ตาม source ที่ปลายทาง
///
/// อ้างอิง: ARCHITECTURE.md, ADR-2 "แหล่งที่มาของข้อมูล + shape เต็มของ BeaconAdvertisement"
class BeaconAdvertisement {
  // ---- ระบุตัวตน (ดู ADR-1) ----
  final BeaconDeviceId deviceId;
  final int rssi; // dBm, ค่าดิบจาก OS ไม่ผ่านการแปลง
  final AdvertisementSource source;
  final DateTime
  timestamp; // UTC, เวลาที่ Dart layer ได้รับ event (ไม่ใช่เวลา broadcast จริง)

  // ---- iBeacon-typed fields ----
  // มีค่าการันตีเมื่อ source == coreLocation เสมอ
  // มีค่าแบบไม่การันตีเมื่อ source == android และ IBeaconParser.parse() สำเร็จ (ADR-3)
  // เป็น null เสมอเมื่อ source == coreBluetooth (iOS มองไม่เห็น iBeacon ทาง CoreBluetooth)
  final String? ibeaconUuid; // lowercase, hyphenated (8-4-4-4-12)
  final int? ibeaconMajor; // 0-65535
  final int? ibeaconMinor; // 0-65535
  final int? ibeaconTxPower; // measured power @ 1m, signed 8-bit dBm — null เสมอเมื่อ source == coreLocation
  final BeaconProximity? proximity; // มีค่าเฉพาะ source == coreLocation

  // ---- raw decoded payload: มาจาก Dart parser (EddystoneParser ฯลฯ) ----
  final Map<String, dynamic> raw; // เช่น {'eddystone': EddystoneUidFrame(...)} — ว่างเสมอเมื่อ source == coreLocation
  final Uint8List? rawBytes; // raw service/manufacturer bytes ก่อน parse, null เมื่อ source == coreLocation — เก็บไว้ debug/forward-compat

  const BeaconAdvertisement({
    required this.deviceId,
    required this.rssi,
    required this.source,
    required this.timestamp,
    this.ibeaconUuid,
    this.ibeaconMajor,
    this.ibeaconMinor,
    this.ibeaconTxPower,
    this.proximity,
    this.raw = const {},
    this.rawBytes,
  });

  @override
  String toString() =>
      'BeaconAdvertisement(deviceId: $deviceId, rssi: $rssi, source: $source, '
      'timestamp: $timestamp, ibeaconUuid: $ibeaconUuid, ibeaconMajor: $ibeaconMajor, '
      'ibeaconMinor: $ibeaconMinor, ibeaconTxPower: $ibeaconTxPower, '
      'proximity: $proximity, raw: $raw, rawBytes: $rawBytes)';
}
