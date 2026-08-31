import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

import 'beacon_kit_ios_platform.dart';

/// เชื่อม `BeaconKitIosPlatform` (สัญญาเฉพาะ iOS) เข้ากับ `BeaconKitPlatform`
/// (สัญญากลางข้ามแพลตฟอร์ม ตาม ADR-13)
///
/// **ทำไมต้องมีคลาสกลางแทนที่จะให้ `BeaconKitIosPlatform` extend
/// `BeaconKitPlatform` ตรง ๆ:** ทั้งคู่เป็น `PlatformInterface` ที่มี token ของ
/// ตัวเอง — การสืบทอดกันจะทำให้ `verifyToken` ของสัญญากลางเทียบกับ token ของ iOS
/// แล้วไม่ผ่าน คลาสบางนี้จึงเป็นทางที่ตรงไปตรงมาที่สุดและไม่แตะโครงเดิมเลย
///
/// **จงใจ delegate ไปที่ `BeaconKitIosPlatform.instance` ทุกครั้ง ไม่ cache** —
/// เพื่อให้เทสต์ที่สลับ `BeaconKitIosPlatform.instance` เป็น mock ยังใช้ได้เหมือน
/// เดิมโดยไม่ต้องรู้ว่ามีชั้นนี้อยู่
class BeaconKitIosBridge extends BeaconKitPlatform {
  @override
  Future<void> startBluetoothScan(List<String> serviceUuids) =>
      BeaconKitIosPlatform.instance.startBluetoothScan(serviceUuids);

  @override
  Future<void> stopBluetoothScan() =>
      BeaconKitIosPlatform.instance.stopBluetoothScan();

  @override
  Stream<BeaconAdvertisement> get rawAdvertisementEvents =>
      BeaconKitIosPlatform.instance.rawAdvertisementEvents;
}
