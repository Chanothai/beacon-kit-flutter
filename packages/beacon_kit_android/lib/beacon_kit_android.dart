/// `beacon_kit_android` — Android platform implementation ของ `beacon_kit`
/// federated plugin
///
/// **ขอบเขตของแพ็กเกจนี้ตอนนี้: สแกนตอนแอปเปิดอยู่เท่านั้น** ยังไม่มีส่วนทำงาน
/// เบื้องหลัง (จะทำเป็นก้อนแยก) และยังไม่มีอะไรเทียบเท่า region monitoring ของ
/// iOS — ดู ADR-9 ว่าทำไมถึงยังไม่ยกเมธอดคู่นั้นขึ้นเป็นสัญญากลาง
library;

import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

import 'src/method_channel_beacon_kit_android.dart';
import 'src/scan_permission_status.dart';

export 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

export 'src/method_channel_beacon_kit_android.dart';
export 'src/scan_permission_status.dart';

/// Facade ของแพ็กเกจนี้ + จุด register เข้ากับสัญญากลาง
///
/// เมธอดเรื่องสิทธิ์อยู่ที่นี่ **ไม่ได้อยู่ใน `BeaconKitPlatform`** โดยตั้งใจ —
/// โมเดลสิทธิ์ของ Android (runtime permission หลายตัว + สถานะ "ไม่ถามอีกแล้ว")
/// ไม่มีอะไรเทียบตรงตัวบน iOS การยัดขึ้นสัญญากลางจะทำให้ iOS ต้องมีเมธอดที่
/// ตอบไม่ตรงความจริง (ADR-13)
class BeaconKitAndroid {
  const BeaconKitAndroid();

  static final MethodChannelBeaconKitAndroid _platform =
      MethodChannelBeaconKitAndroid();

  /// Flutter เรียกให้อัตโนมัติตอนแอปเริ่ม (ผ่าน `dartPluginClass` ใน pubspec)
  /// เฉพาะตอนรันบน Android จริง — จึงไม่ต้องมี `if (Platform.isAndroid)` ที่ไหน
  static void registerWith() {
    BeaconKitPlatform.instance = _platform;
  }

  /// ขอสิทธิ์ `BLUETOOTH_SCAN` + `ACCESS_FINE_LOCATION`
  ///
  /// ต้องได้ทั้งคู่ถึงจะสแกนแล้วเห็น beacon — เหตุผลและ citation อยู่ใน ADR-12
  /// (สรุป: `BLUETOOTH_SCAN` คือสิทธิ์สแกน ส่วน `ACCESS_FINE_LOCATION` จำเป็น
  /// เพราะ use case ของเราคือการอนุมานตำแหน่ง จึงใช้ทางลัด `neverForLocation`
  /// ไม่ได้ — และทางลัดนั้นยังทำให้ beacon บางตัวถูกกรองทิ้งด้วย)
  Future<ScanPermissionStatus> requestScanPermissions() =>
      _platform.requestScanPermissions();

  /// อ่านสถานะปัจจุบันโดยไม่แสดง prompt
  Future<ScanPermissionStatus> getScanPermissionStatus() =>
      _platform.getScanPermissionStatus();

  /// พาผู้ใช้ไปหน้า Settings ของแอป — ใช้เมื่อสถานะเป็น
  /// [ScanPermissionStatus.permanentlyDenied] ซึ่งขอสิทธิ์ซ้ำไม่มีประโยชน์แล้ว
  Future<void> openAppSettings() => _platform.openAppSettings();
}
