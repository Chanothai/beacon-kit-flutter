import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
import 'package:flutter/services.dart';

import 'android_background_region.dart';
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

  /// ช่องของ enter/exit ที่คำนวณเบื้องหลัง — **แยกจากช่อง advertisement ดิบ**
  ///
  /// เหตุผลเดียวกับที่ ADR-6 แยกฝั่ง iOS: advertisement ดิบมาถี่มาก ส่วน enter/exit
  /// นาน ๆ ครั้ง ถ้ารวมช่องเดียวกัน ผู้ฟังที่สนใจแค่ enter/exit ต้อง deserialize
  /// ทุก event แล้วกรองทิ้งตลอดเวลาที่แอปทำงาน
  static const EventChannel _backgroundRegionChannel = EventChannel(
    'beacon_kit_android/background_region_events',
  );

  Stream<BeaconAdvertisement>? _rawAdvertisementEvents;
  Stream<AndroidBackgroundRegionEvent>? _backgroundRegionEvents;

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

  /// เริ่มเฝ้า region เบื้องหลัง — **อ่าน ADR-14 ก่อนใช้**
  ///
  /// ## สิ่งที่เมธอดนี้สัญญา และสิ่งที่มันไม่สัญญา
  ///
  /// | สัญญา | ไม่สัญญา |
  /// |---|---|
  /// | รอดข้ามการปัดแอปทิ้งจากรายการแอป (ระบบสร้าง process ใหม่มาส่ง event ให้) | **ไม่รอดข้าม force-stop** — ไม่มีทางแก้ด้วยโค้ด |
  /// | ลงทะเบียนใหม่เองหลังรีบูต (ผ่าน `BOOT_COMPLETED`) | ช่วงหลังรีบูตจนถึงผู้ใช้ปลดล็อกครั้งแรก **ไม่ได้เฝ้าอะไรเลย** |
  /// | ไม่มี notification ค้างให้ผู้ใช้เห็น | จึงไม่ได้ความถี่การสแกนระดับ foreground |
  /// | `exit` ถูกยิงเมื่อไม่เห็นครบ [exitTimeoutSeconds] | **ไม่สัญญาว่าจะยิงภายในเวลานั้น** — ดูข้างล่าง |
  ///
  /// ## [exitTimeoutSeconds] เป็นขั้นต่ำ ไม่ใช่เวลาที่จะได้จริง
  ///
  /// exit ถูกประกาศด้วยนาฬิกาปลุกของระบบ ซึ่ง `AlarmManager.setAndAllowWhileIdle`
  /// ระบุเองว่า "it will not dispatch these alarms more than about every minute...
  /// when in low-power idle modes this duration may be significantly longer, such
  /// as 15 minutes" (`AlarmManager.java:1286-1289`) — ตั้ง 30 วินาทีจึงไม่ได้แปลว่า
  /// จะได้ exit ภายใน 30 วินาที โดยเฉพาะตอนเครื่องอยู่ใน Doze
  ///
  /// ## ทำไมค่านี้ปรับได้ ต่างจาก iOS
  ///
  /// **นี่คือข้อดีที่ตั้งใจใช้ ไม่ใช่ผลข้างเคียง** ฝั่ง iOS ค่าหน่วงก่อนประกาศ exit
  /// เป็นของระบบ ปรับไม่ได้ และ ADR-11 ค้นแล้วไม่พบเอกสาร Apple ที่ระบุค่าหรือบอกว่า
  /// ปรับได้ — เราวัดได้เองว่า ~30 วินาที เท่านั้น ฝั่งนี้เราคุมเองได้ จึงจูนจาก
  /// ข้อมูลสาขาจริงตาม ADR-11 หัวข้อ 8 ได้ **โดยไม่ต้องรอ Apple**
  ///
  /// ค่าเริ่มต้น 30 วินาทีเลือกให้ตรงกับสิ่งที่วัดได้จาก iOS โดยตั้งใจ เพื่อให้ผล
  /// รอบทดสอบแรกของสองแพลตฟอร์มเทียบกันได้ ไม่ใช่ต่างกันเพราะตั้งค่าคนละแบบ
  ///
  /// **ห้ามส่งค่าที่ hard-code ไว้ใน business logic** — ADR-11 หัวข้อ 5 ระบุว่า
  /// ค่าเหล่านี้เป็นการตัดสินใจทางธุรกิจบนข้อมูลเทคนิค ต้องมาจาก config ของแอป
  Future<AndroidBackgroundMonitoringResult> startBackgroundRegionMonitoring({
    required List<AndroidBeaconRegion> regions,
    int exitTimeoutSeconds = 30,
  }) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'startBackgroundRegionMonitoring',
      {
        'regions': regions.map((r) => r.toMap()).toList(),
        'exitTimeoutSeconds': exitTimeoutSeconds,
      },
    );
    return AndroidBackgroundMonitoringResult.fromMap(raw ?? const {});
  }

  /// ถอนการเฝ้าทั้งหมด และล้างสถานะ + คิว event ที่ยังไม่ได้ส่ง
  ///
  /// **ไม่ถูกเรียกอัตโนมัติตอนแอปปิด** โดยตั้งใจ — การเฝ้าเบื้องหลังต้องอยู่ต่อ
  /// หลังผู้ใช้ปิดแอป ซึ่งเป็นเหตุผลทั้งหมดที่มันมีอยู่
  Future<void> stopBackgroundRegionMonitoring() =>
      _methodChannel.invokeMethod<void>('stopBackgroundRegionMonitoring');

  /// สถานะที่ **แอปเราเองจำไว้** — ดูคำเตือนใน [AndroidBackgroundMonitoringStatus]
  Future<AndroidBackgroundMonitoringStatus>
  getBackgroundRegionMonitoringStatus() async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'getBackgroundRegionMonitoringStatus',
    );
    return AndroidBackgroundMonitoringStatus.fromMap(raw ?? const {});
  }

  /// enter/exit จากเส้นทางเบื้องหลัง
  ///
  /// **event ที่เกิดตอนไม่มี Flutter engine ถูกคิวไว้ในดิสก์ฝั่ง native** และถูกส่ง
  /// ออกมาทั้งชุดทันทีที่มีคน subscribe — ผู้ฟังจึงอาจได้ event ที่ `timestamp`
  /// เก่ากว่าตอนนี้หลายชั่วโมง **ห้ามใช้ `DateTime.now()` แทน `event.timestamp`**
  /// ไม่งั้นสถิติทั้งหมดจะกองอยู่ที่ "ตอนเปิดแอป" ซึ่งผิดความจริงทั้งชุด
  ///
  /// **ไม่กรอง flapping ให้** ตาม ADR-11 หัวข้อ 7: SDK มีหน้าที่รายงานสิ่งที่เกิดขึ้น
  /// อย่างซื่อสัตย์ การกรองเป็นหน้าที่ของแอป (ผ่าน utility ที่เลือกใช้ได้)
  Stream<AndroidBackgroundRegionEvent> get backgroundRegionEvents =>
      _backgroundRegionEvents ??= _backgroundRegionChannel
          .receiveBroadcastStream()
          .map(AndroidBackgroundRegionEvent.tryParse)
          .where((event) => event != null)
          .cast<AndroidBackgroundRegionEvent>();

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
