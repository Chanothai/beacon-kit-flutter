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

/// **ข้อมูลใน [BeaconAdvertisement] นี้ถูกถอดรหัสมาอย่างไร** — ไม่ใช่ "มาจาก
/// แพลตฟอร์มไหน"
///
/// เดิมค่าในนี้ตั้งชื่อตาม API ของ iOS (`coreLocation` / `coreBluetooth`) ปนกับค่า
/// ชื่อแพลตฟอร์ม (`android`) — ADR-13 เปลี่ยนเป็นชื่อที่อธิบาย **คุณสมบัติของ
/// ข้อมูล** แทน ด้วยเหตุผล 3 ข้อ:
///
/// 1. ชื่อ API ของ iOS ไม่มีความหมายบน Android — คนที่อ่านโค้ดฝั่ง Android ต้องไป
///    เรียนรู้ CoreBluetooth ก่อนถึงจะเข้าใจว่าค่านี้แปลว่าอะไร
/// 2. สิ่งที่ผู้เรียก**ต้องตัดสินใจจริง ๆ** จากค่านี้มีอย่างเดียว คือ "ฟิลด์
///    `ibeacon*` เชื่อได้แค่ไหน" ซึ่งขึ้นกับว่า **OS ถอดให้ หรือเราถอดเอง**
///    ไม่ได้ขึ้นกับว่าเป็น iOS หรือ Android
/// 3. `coreBluetooth` กับ `android` เดิมมีคุณสมบัติ**เหมือนกันทุกประการ**ในแง่นี้
///    (ได้ byte ดิบมาแล้ว Dart parser ถอด) การแยกเป็นสองค่าจึงล่อให้ผู้เรียกเขียน
///    `if (แพลตฟอร์ม)` ทั้งที่ไม่ควรต้องรู้ — จึงยุบเหลือค่าเดียว
///
/// ถ้าจำเป็นต้องรู้จริง ๆ ว่าอุปกรณ์มาจากวิทยุฝั่งไหน ให้ดู [BeaconDeviceId.kind]
/// ซึ่งแยก `macAddress` (Android) ออกจาก `coreBluetoothPeripheralId` (iOS) อยู่แล้ว
/// — ข้อมูลไม่ได้หายไปจากการยุบค่า แค่ย้ายไปอยู่ที่ที่ถูกต้องกว่า
enum AdvertisementSource {
  /// **OS ถอดรหัสมาให้แล้ว** — ปัจจุบันมีทางเดียวคือ iOS CoreLocation ranging
  /// (`CLBeaconRegion`)
  ///
  /// การันตีว่า**มี**: `ibeaconUuid` / `ibeaconMajor` / `ibeaconMinor` / `proximity`
  ///
  /// การันตีว่า**ไม่มี**: `ibeaconTxPower` เป็น null เสมอ (`CLBeacon` ไม่มีฟิลด์นี้
  /// ตรง ๆ), `raw` ว่างเสมอ, `rawBytes` เป็น null เสมอ
  osDecoded,

  /// **ได้ byte ดิบมาจากวิทยุ แล้ว Dart parser ถอดเอง** — iOS CoreBluetooth
  /// (`CBCentralManager`) และ Android (`BluetoothLeScanner`) เข้าทางนี้ทั้งคู่
  ///
  /// การันตีว่า**มี**: `rawBytes`
  ///
  /// **ไม่การันตี**: `ibeacon*` มีค่าก็ต่อเมื่อ `IBeaconParser.parse()` สำเร็จ และ
  /// `raw['eddystone']` มีก็ต่อเมื่อ `EddystoneParser` สำเร็จ — ผู้เรียก**ต้องเช็ค
  /// null เสมอ** ต่างจาก [osDecoded] ที่ OS การันตีให้ · `proximity` เป็น null เสมอ
  /// เพราะคำนวณจาก byte ไม่ได้ (ดู [BeaconProximity])
  ///
  /// ⚠️ **บน iOS ทางนี้จะไม่มีวันเห็น iBeacon** เพราะ iOS mask manufacturer data
  /// ของ iBeacon ทิ้งที่ระดับ CoreBluetooth ทั้งหมด — เป็นข้อจำกัดของแพลตฟอร์ม
  /// ไม่ใช่ของ enum นี้ (ดู ARCHITECTURE.md "ข้อจำกัดของ iOS ที่บังคับให้
  /// สถาปัตยกรรมต่างจาก Android") ส่วนบน Android เห็นได้ปกติ
  rawParsed,
}

/// ค่า proximity ที่ OS คำนวณให้ (ระยะห่างโดยประมาณจาก RSSI/txPower ภายในของ OS เอง)
/// ไม่มีทางเทียบเท่าจาก Dart parser เพราะไม่ใช่ field ที่ decode ได้จาก byte ของ ADV
/// — มีค่าเฉพาะ `source == AdvertisementSource.osDecoded` เท่านั้น
enum BeaconProximity { unknown, immediate, near, far }

/// Domain entity กลางที่รวมผลลัพธ์จากทุก source (ฟิลด์ที่ OS ถอดให้แล้ว กับ raw
/// bytes ที่ผ่าน Dart parser แล้ว) เป็นชนิดเดียว
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
  // การันตีว่ามีค่าเมื่อ source == osDecoded เสมอ
  // ไม่การันตีเมื่อ source == rawParsed — มีค่าก็ต่อเมื่อ IBeaconParser.parse()
  // สำเร็จ (ADR-3) ซึ่งบน iOS จะไม่มีวันสำเร็จเพราะ OS mask iBeacon ทิ้งที่ระดับ
  // CoreBluetooth ส่วนบน Android สำเร็จได้ปกติ
  final String? ibeaconUuid; // lowercase, hyphenated (8-4-4-4-12)
  final int? ibeaconMajor; // 0-65535
  final int? ibeaconMinor; // 0-65535
  final int? ibeaconTxPower; // measured power @ 1m, signed 8-bit dBm — null เสมอเมื่อ source == osDecoded
  final BeaconProximity? proximity; // มีค่าเฉพาะ source == osDecoded

  // ---- raw decoded payload: มาจาก Dart parser (EddystoneParser ฯลฯ) ----
  final Map<String, dynamic> raw; // เช่น {'eddystone': EddystoneUidFrame(...)} — ว่างเสมอเมื่อ source == osDecoded
  final Uint8List? rawBytes; // raw service/manufacturer bytes ก่อน parse, null เมื่อ source == osDecoded — เก็บไว้ debug/forward-compat

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
