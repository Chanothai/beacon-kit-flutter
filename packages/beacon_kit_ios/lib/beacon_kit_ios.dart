/// `beacon_kit_ios` — iOS platform implementation ของ `beacon_kit` federated plugin
///
/// เปิดเผย iBeacon ranging (ผ่าน CoreLocation) และ raw CoreBluetooth advertisement
/// scanning (ทุกฟอร์แมตยกเว้น iBeacon) เป็น `Stream<BeaconAdvertisement>` เดียวกัน —
/// ดู ARCHITECTURE.md หัวข้อ "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android"
/// และ ADR-4 "iOS platform channel contract" สำหรับที่มาของการออกแบบนี้
library;

import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

import 'src/beacon_kit_ios_platform.dart';
import 'src/ibeacon_region_request.dart';

export 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

export 'src/beacon_kit_ios_platform.dart';
export 'src/ibeacon_region_request.dart';
export 'src/method_channel_beacon_kit_ios.dart';

/// Facade หลักที่แอปเรียกใช้ — ห่อ [BeaconKitIosPlatform.instance] ไว้อีกชั้นตาม
/// federated plugin convention มาตรฐาน (แอปไม่ต้องรู้จัก platform interface class
/// เอง)
class BeaconKitIos {
  const BeaconKitIos();

  /// เริ่ม monitor+range iBeacon ตาม region ที่กำหนด (แทนที่ set การ monitor เดิม
  /// ทั้งหมด ไม่ merge)
  ///
  /// throw `PlatformException(code: 'TOO_MANY_REGIONS' | 'INVALID_REGION_UUID' |
  /// 'LOCATION_PERMISSION_DENIED')`
  Future<void> startIBeaconMonitoring(List<IBeaconRegionRequest> regions) {
    return BeaconKitIosPlatform.instance.startIBeaconMonitoring(regions);
  }

  Future<void> stopIBeaconMonitoring([List<String>? identifiers]) {
    return BeaconKitIosPlatform.instance.stopIBeaconMonitoring(identifiers);
  }

  /// throw `PlatformException(code: 'INVALID_ARGUMENT' |
  /// 'BLUETOOTH_UNAVAILABLE' | 'BLUETOOTH_PERMISSION_DENIED')`
  ///
  /// `INVALID_ARGUMENT` = ส่ง argument ผิดรูปแบบ (บั๊กของผู้เรียก) ต่างจาก
  /// `BLUETOOTH_UNAVAILABLE` ที่เป็นสภาวะของเครื่อง (Bluetooth ปิด/ไม่พร้อม)
  Future<void> startBluetoothScan(List<String> serviceUuids) {
    return BeaconKitIosPlatform.instance.startBluetoothScan(serviceUuids);
  }

  Future<void> stopBluetoothScan() {
    return BeaconKitIosPlatform.instance.stopBluetoothScan();
  }

  /// แต่ละ event = [BeaconAdvertisement] 1 ตัว (flatten แล้วจาก native batch ตาม
  /// ADR-4), `source == AdvertisementSource.coreLocation` เสมอ
  Stream<BeaconAdvertisement> get iBeaconRangingEvents =>
      BeaconKitIosPlatform.instance.iBeaconRangingEvents;

  /// แต่ละ event = [BeaconAdvertisement] 1 ตัว, `source ==
  /// AdvertisementSource.coreBluetooth` เสมอ — service data ของ Eddystone ถอดด้วย
  /// `EddystoneParser` ให้เสร็จก่อนส่งออก
  Stream<BeaconAdvertisement> get rawAdvertisementEvents =>
      BeaconKitIosPlatform.instance.rawAdvertisementEvents;
}
