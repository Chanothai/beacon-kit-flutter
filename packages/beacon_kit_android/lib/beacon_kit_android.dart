/// `beacon_kit_android` — Android platform implementation ของ `beacon_kit`
/// federated plugin
///
/// ## ขอบเขตของแพ็กเกจนี้: สองเส้นทางที่แยกกัน
///
/// 1. **สแกนตอนแอปเปิดอยู่** (ADR-12) — ผ่านสัญญากลาง [BeaconKitPlatform]
///    (`startBluetoothScan` / `rawAdvertisementEvents`)
/// 2. **เฝ้า region เบื้องหลัง** (ADR-14) — อยู่ที่แพ็กเกจนี้ **ไม่ได้ยกขึ้นสัญญา
///    กลาง** เพราะตอบตารางคำถามของ ADR-9 แล้วพบว่า **Android ทำไม่ได้เทียบเท่า iOS**
///
/// ตาม ADR-13 หัวข้อ 4 ข้อ 3: เมื่อพบว่าทำไม่ได้เทียบเท่า ให้แยกเป็นความสามารถ
/// คนละชื่อตามที่แต่ละแพลตฟอร์มทำได้จริง แล้วให้แอปเลือกเองอย่างรู้ตัว —
/// ไม่ใช่ดัดให้ดูเหมือนกันแล้วปล่อยให้ไปเจอความจริงหน้างาน
library;

import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

import 'src/android_background_region.dart';
import 'src/method_channel_beacon_kit_android.dart';
import 'src/scan_permission_status.dart';

export 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

export 'src/android_background_region.dart';
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

  // ---- เฝ้า region เบื้องหลัง (ADR-14) ----
  //
  // อยู่ที่นี่ ไม่ใช่ที่ `BeaconKitPlatform` เพราะ Android ทำไม่ได้เทียบเท่า iOS
  // การยกขึ้นสัญญากลางจะทำให้ผู้เรียกเข้าใจว่าได้พฤติกรรมเดียวกันทั้งสองแพลตฟอร์ม
  // ทั้งที่ไม่ใช่ — ข้อห้ามที่ ADR-9 เขียนดักไว้ตั้งแต่ก่อนเริ่มงาน Android

  /// เริ่มเฝ้า region เบื้องหลัง — **อ่านตารางสัญญา/ไม่สัญญาใน
  /// [MethodChannelBeaconKitAndroid.startBackgroundRegionMonitoring] ก่อนใช้**
  Future<AndroidBackgroundMonitoringResult> startBackgroundRegionMonitoring({
    required List<AndroidBeaconRegion> regions,
    int exitTimeoutSeconds = 30,
  }) => _platform.startBackgroundRegionMonitoring(
    regions: regions,
    exitTimeoutSeconds: exitTimeoutSeconds,
  );

  Future<void> stopBackgroundRegionMonitoring() =>
      _platform.stopBackgroundRegionMonitoring();

  /// สถานะที่ **แอปเราเองจำไว้** ไม่ใช่ความจริงจากระบบ —
  /// ดูคำเตือนใน [AndroidBackgroundMonitoringStatus]
  Future<AndroidBackgroundMonitoringStatus>
  getBackgroundRegionMonitoringStatus() =>
      _platform.getBackgroundRegionMonitoringStatus();

  /// enter/exit ที่ **เราคำนวณเอง** จากการเห็น/ไม่เห็นผลสแกน
  Stream<AndroidBackgroundRegionEvent> get backgroundRegionEvents =>
      _platform.backgroundRegionEvents;
}
