import 'package:async/async.dart';
import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';

import 'beacon_adapter.dart';

/// Registry กลางของ [BeaconAdapter] ทุกตัวที่แอปลงทะเบียนไว้ — จุดเดียวที่แอปต้อง
/// รู้จัก ไม่ต้องเห็นคลาสของยี่ห้อใดโดยตรง (ตรงตามหลัก facade)
///
/// อ้างอิง: ARCHITECTURE.md หัวข้อ "Dart API หลัก (`beacon_kit`)"
class BeaconManager {
  BeaconManager._();

  static final List<BeaconAdapter> _adapters = [];

  /// ลงทะเบียน adapter หนึ่งตัวเพื่อให้ [scanAll] รวม stream ของมันด้วย
  static void register(BeaconAdapter adapter) => _adapters.add(adapter);

  /// ล้าง adapter ที่ลงทะเบียนไว้ทั้งหมด — ใช้สำหรับเทสต์/example เพื่อรีเซ็ต
  /// state ระหว่าง run
  static void unregisterAll() => _adapters.clear();

  /// รวม [BeaconAdapter.scan] stream ของทุก adapter ที่ลงทะเบียนไว้เป็น stream
  /// เดียว — **ไม่ dedupe** ในนี้ ปล่อยให้ผู้เรียกที่ต้องการ "รายการล่าสุด" ไปทำ
  /// `Map<(DeviceIdKind, String), BeaconAdvertisement>` เอง โดย key คู่
  /// `(deviceId.kind, deviceId.value)` เสมอ (ตาม ADR-1 — ห้าม dedupe ข้าม kind)
  static Stream<BeaconAdvertisement> scanAll() {
    if (_adapters.isEmpty) return const Stream.empty();
    return StreamGroup.merge(_adapters.map((adapter) => adapter.scan()));
  }
}
