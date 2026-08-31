import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
import 'package:flutter/services.dart';

import 'scan_permission_status.dart';

/// Service UUID ของ Eddystone (`0xFEAA`) ในรูปแบบ 128-bit เต็ม — ตรงกับที่ฝั่ง
/// iOS ใช้ (`method_channel_beacon_kit_ios.dart`) เพื่อให้ key ของ `serviceData`
/// ที่ข้าม channel มาเหมือนกันทั้งสองแพลตฟอร์ม
const String _eddystoneServiceUuid = '0000feaa-0000-1000-8000-00805f9b34fb';

/// implementation ของ [BeaconKitPlatform] ฝั่ง Android ผ่าน method/event channel
///
/// **ไม่มี parser อยู่ในไฟล์นี้เลยแม้แต่บรรทัดเดียว** — ใช้ `IBeaconParser` และ
/// `EddystoneParser` จาก `beacon_kit_platform_interface` ตัวเดียวกับที่ฝั่ง iOS ใช้
/// นี่คือจุดที่ทำให้ "beacon ตัวเดียวกันขึ้นบนทั้งสองเครื่องด้วยโค้ดถอดรหัสชุด
/// เดียวกัน" เป็นจริง ไม่ใช่แค่คำพูด
class MethodChannelBeaconKitAndroid extends BeaconKitPlatform {
  static const MethodChannel _methodChannel = MethodChannel(
    'beacon_kit_android/methods',
  );

  static const EventChannel _rawAdvertisementChannel = EventChannel(
    'beacon_kit_android/raw_advertisement_events',
  );

  Stream<BeaconAdvertisement>? _rawAdvertisementEvents;

  @override
  Future<void> startBluetoothScan(List<String> serviceUuids) {
    return _methodChannel.invokeMethod<void>('startBluetoothScan', {
      'serviceUuids': serviceUuids,
    });
  }

  @override
  Future<void> stopBluetoothScan() =>
      _methodChannel.invokeMethod<void>('stopBluetoothScan');

  @override
  Stream<BeaconAdvertisement> get rawAdvertisementEvents =>
      _rawAdvertisementEvents ??= _rawAdvertisementChannel
          .receiveBroadcastStream()
          .map(_mapRawAdvertisementEvent);

  /// ขอสิทธิ์ที่จำเป็นสำหรับสแกน BLE บน Android 12
  /// (`BLUETOOTH_SCAN` + `ACCESS_FINE_LOCATION` — ดู ADR-12 ว่าทำไมต้องมีทั้งคู่)
  Future<ScanPermissionStatus> requestScanPermissions() async {
    final raw = await _methodChannel.invokeMethod<String>(
      'requestScanPermissions',
    );
    return _mapPermissionStatus(raw);
  }

  /// อ่านสถานะสิทธิ์ปัจจุบันโดย**ไม่**แสดง prompt
  Future<ScanPermissionStatus> getScanPermissionStatus() async {
    final raw = await _methodChannel.invokeMethod<String>(
      'getScanPermissionStatus',
    );
    return _mapPermissionStatus(raw);
  }

  /// เปิดหน้า Settings ของแอป — ทางเดียวที่เหลือเมื่อสถานะเป็น
  /// [ScanPermissionStatus.permanentlyDenied]
  Future<void> openAppSettings() =>
      _methodChannel.invokeMethod<void>('openAppSettings');

  /// ค่าที่ไม่รู้จักถูกตีเป็น [ScanPermissionStatus.denied] — **จงใจเลือกฝั่งที่
  /// ปลอดภัยกว่า** ถ้าเดาว่า granted แล้วผิด แอปจะไปเรียกสแกนแล้วล้มเหลวแบบไม่มี
  /// คำอธิบาย ซึ่งแย่กว่าการขอสิทธิ์เกินจำเป็นหนึ่งครั้ง
  static ScanPermissionStatus _mapPermissionStatus(String? raw) {
    switch (raw) {
      case 'granted':
        return ScanPermissionStatus.granted;
      case 'permanentlyDenied':
        return ScanPermissionStatus.permanentlyDenied;
      case 'notDetermined':
        return ScanPermissionStatus.notDetermined;
      case 'denied':
      default:
        return ScanPermissionStatus.denied;
    }
  }

  /// 1 event = 1 `ScanResult` จาก `BluetoothLeScanner`
  ///
  /// ถอดสองฟอร์แมตจาก byte ดิบชุดเดียวกัน:
  /// - **iBeacon** จาก manufacturer data ของ Apple — ฝั่ง Kotlin ต่อ company ID
  ///   `0x4C 0x00` กลับเข้าไปให้แล้ว (`ScanRecord.getManufacturerSpecificData()`
  ///   ตัดออก แต่ `IBeaconParser` คาดหวัง AD value เต็ม 25 bytes — ระบุไว้ใน
  ///   doc ของ parser เอง)
  /// - **Eddystone** จาก service data ของ `0xFEAA`
  ///
  /// **ไม่ drop event ที่ parse ไม่สำเร็จ** — ยังส่งออกพร้อม `raw = {}` เพราะ
  /// MAC/RSSI ยังมีประโยชน์ และการเงียบหายไปเฉย ๆ คืออาการที่ดีบักยากที่สุด
  BeaconAdvertisement _mapRawAdvertisementEvent(dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    final address = map['deviceAddress'] as String;
    final rssi = map['rssi'] as int;
    final timestampMs = map['timestamp'] as int;
    final serviceData = map['serviceData'] as Map<dynamic, dynamic>?;
    final appleManufacturerData = map['appleManufacturerData'];

    final raw = <String, dynamic>{};
    Uint8List? rawBytes;
    String? ibeaconUuid;
    int? ibeaconMajor;
    int? ibeaconMinor;
    int? ibeaconTxPower;

    if (appleManufacturerData != null) {
      final bytes = _toUint8List(appleManufacturerData);
      final result = IBeaconParser.parse(bytes);
      if (result is ParseSuccess<IBeaconFrame>) {
        final frame = result.value;
        ibeaconUuid = frame.uuid;
        ibeaconMajor = frame.major;
        ibeaconMinor = frame.minor;
        ibeaconTxPower = frame.txPower;
        raw['ibeacon'] = frame;
        rawBytes = bytes;
      }
    }

    final eddystoneRaw = serviceData?[_eddystoneServiceUuid];
    if (eddystoneRaw != null) {
      final bytes = _toUint8List(eddystoneRaw);
      final result = EddystoneParser.parse(bytes);
      if (result is ParseSuccess<EddystoneFrame>) {
        raw['eddystone'] = result.value;
        rawBytes ??= bytes;
      }
    }

    return BeaconAdvertisement(
      deviceId: BeaconDeviceId(value: address, kind: DeviceIdKind.macAddress),
      rssi: rssi,
      source: AdvertisementSource.rawParsed,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
      ibeaconUuid: ibeaconUuid,
      ibeaconMajor: ibeaconMajor,
      ibeaconMinor: ibeaconMinor,
      ibeaconTxPower: ibeaconTxPower,
      raw: raw,
      rawBytes: rawBytes,
    );
  }

  static Uint8List _toUint8List(Object value) {
    if (value is Uint8List) return value;
    return Uint8List.fromList((value as List).cast<int>());
  }
}
