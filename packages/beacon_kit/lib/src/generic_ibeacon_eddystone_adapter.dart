import 'dart:async';

import 'package:beacon_kit_ios/beacon_kit_ios.dart';

import 'beacon_adapter.dart';
import 'ibeacon_region_config.dart';

/// Service UUID มาตรฐานของ Eddystone (`0xFEAA`) — ตาม ARCHITECTURE.md ADR-3
/// (`EddystoneParser` parse service data ของ service นี้)
const String _eddystoneServiceUuid = '0000feaa-0000-1000-8000-00805f9b34fb';

/// broadcast-only adapter ตาม ARCHITECTURE.md หัวข้อ "Adapter ที่ implement
/// รอบแรก" — ใช้ได้กับ beacon ทุกยี่ห้อที่ broadcast มาตรฐานเปิด
/// (iBeacon/Eddystone) ไม่ผูกกับยี่ห้อใดยี่ห้อหนึ่ง
///
/// รอบนี้ wrap เฉพาะ iOS (`beacon_kit_ios`) เท่านั้น — Android ยังไม่ implement
/// (deferred สปรินต์หน้า เพราะ ADR ท้าย ARCHITECTURE.md สลับให้ iOS มาก่อน)
class GenericIBeaconEddystoneAdapter implements BeaconAdapter {
  GenericIBeaconEddystoneAdapter({
    required this.iBeaconRegions,
    this.scanEddystone = true,
    BeaconKitIos? platform,
  }) : _platform = platform ?? const BeaconKitIos();

  /// region ของ iBeacon ที่ adapter นี้เฝ้าฟัง (ตามที่กำหนดตอนสร้าง instance)
  final List<IBeaconRegionConfig> iBeaconRegions;

  /// ถ้า `true` (ค่าเริ่มต้น) จะสแกน Eddystone (service `0xFEAA`) ผ่าน
  /// CoreBluetooth เพิ่มเติม นอกเหนือจาก iBeacon ranging ผ่าน CoreLocation
  final bool scanEddystone;

  final BeaconKitIos _platform;

  StreamController<BeaconAdvertisement>? _controller;
  StreamSubscription<BeaconAdvertisement>? _rangingSubscription;
  StreamSubscription<BeaconAdvertisement>? _rawSubscription;

  @override
  String get vendorId => 'generic_ibeacon_eddystone';

  @override
  bool get supportsConnect => false;

  @override
  Stream<BeaconAdvertisement> scan() {
    // broadcast controller เดียว re-use ข้ามการ listen หลายครั้ง — onListen จะ
    // ยิงเฉพาะตอนจำนวนผู้ฟังขยับจาก 0 -> 1 และ onCancel ยิงตอนขยับกลับเป็น 0
    // เพื่อไม่ให้เริ่ม/หยุด native scan ซ้ำซ้อนโดยไม่จำเป็น
    _controller ??= StreamController<BeaconAdvertisement>.broadcast(
      onListen: _startScanning,
      onCancel: _stopScanning,
    );
    return _controller!.stream;
  }

  Future<void> _startScanning() async {
    final controller = _controller;
    if (controller == null) return;

    _rangingSubscription = _platform.iBeaconRangingEvents.listen(
      controller.add,
      onError: controller.addError,
    );
    if (scanEddystone) {
      _rawSubscription = _platform.rawAdvertisementEvents.listen(
        controller.add,
        onError: controller.addError,
      );
    }

    try {
      await _platform.startIBeaconMonitoring(
        iBeaconRegions
            .map(
              (region) => IBeaconRegionRequest(
                identifier: region.identifier,
                uuid: region.uuid,
                major: region.major,
                minor: region.minor,
              ),
            )
            .toList(),
      );
      if (scanEddystone) {
        await _platform.startBluetoothScan([_eddystoneServiceUuid]);
      }
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  Future<void> _stopScanning() async {
    await _rangingSubscription?.cancel();
    _rangingSubscription = null;
    await _rawSubscription?.cancel();
    _rawSubscription = null;
    _controller = null;

    // สำคัญ — ห้าม leak การสแกนค้างไว้เมื่อไม่มีคนฟัง stream แล้ว ปิด native
    // scan เสมอแม้ stop จะ throw ก็ไม่ rethrow เพราะไม่มีผู้ฟังให้ forward
    // error ไปหาแล้ว (controller ถูกเคลียร์ไปแล้วด้านบน)
    try {
      await _platform.stopIBeaconMonitoring(
        iBeaconRegions.map((region) => region.identifier).toList(),
      );
    } catch (_) {
      // ไม่มีผู้ฟังอยู่แล้ว — กลืน error ไม่ rethrow
    }
    if (scanEddystone) {
      try {
        await _platform.stopBluetoothScan();
      } catch (_) {
        // เช่นเดียวกัน
      }
    }
  }

  @override
  Future<BeaconConnection> connect({
    required String macAddress,
    required String password,
    Duration timeout = const Duration(seconds: 15),
  }) {
    throw UnsupportedError(
      '$vendorId ไม่รองรับ connect (supportsConnect=false, broadcast-only)',
    );
  }
}
