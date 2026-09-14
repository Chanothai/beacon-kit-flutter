/// Snippet สำหรับ README §2(d) — เริ่มเฝ้า region แล้วฟัง enter/exit
///
/// API แยกกันจริงตามแพลตฟอร์มตอนนี้ (ไม่มี unified facade — ดู ADR-13 หัวข้อ 4
/// ใน ARCHITECTURE.md ซึ่งยังไม่ทำ) จึงต้องเช็ค [Platform] ก่อนเลือกเส้นทาง
/// เหมือนที่ `example/lib/main.dart` ทำจริง (ดูตัวแปร
/// `_splitByPlatformUntilAdr13Step4`)
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:beacon_kit/beacon_kit.dart';
import 'package:beacon_kit_android/beacon_kit_android.dart'
    show AndroidBeaconRegion, BeaconKitAndroid;

/// UUID ตัวอย่างเท่านั้น — **ห้าม hardcode UUID จริงของ BigC** ในโค้ด (ตาม ADR-5)
/// แอปจริงต้องอ่านค่านี้จาก config ที่ไม่ถูก commit เข้า repo
const String _proximityUuid = '<PROXIMITY_UUID>';

/// เริ่มเฝ้า region เดียวกันบนทั้งสองแพลตฟอร์ม แล้วคืน subscription ให้ผู้เรียก
/// ปิดเอง ([StreamSubscription.cancel]) เมื่อไม่ต้องการเฝ้าแล้ว
Future<StreamSubscription<Object?>> runQuickstart() async {
  if (Platform.isIOS) {
    final adapter = GenericIBeaconEddystoneAdapter(
      iBeaconRegions: const [
        IBeaconRegionConfig(identifier: 'store-default', uuid: _proximityUuid),
      ],
    );
    await adapter.startIBeaconMonitoring();
    return adapter.regionStateEvents.listen((event) {
      // event.state คือ enter/exit/unknown ดิบจาก CoreLocation — ไม่มี
      // debounce ใด ๆ ชั้นกรองเป็นหน้าที่ host app (ดู README §3 แถว
      // Debounce/visit/session)
    });
  }

  if (Platform.isAndroid) {
    final beaconKitAndroid = const BeaconKitAndroid();
    await beaconKitAndroid.startBackgroundRegionMonitoring(
      regions: const [
        // ระบุ major ก่อนเสมอถ้าจะระบุ minor — AndroidBeaconRegion ยืนยัน
        // (assert) ว่าระบุ minor โดยไม่มี major ไม่ได้
        AndroidBeaconRegion(identifier: 'store-default', uuid: _proximityUuid),
      ],
    );
    return beaconKitAndroid.backgroundRegionEvents.listen((event) {
      // event.state คือ enter/exit ที่ SDK คำนวณเองจากความเงียบ/ไม่เงียบของผล
      // สแกน (ไม่ใช่ความจริงจากระบบโดยตรง — ดู dartdoc ของ
      // AndroidBackgroundRegionEvent.fromBackgroundProcess)
    });
  }

  throw UnsupportedError('beacon_kit รองรับเฉพาะ iOS และ Android');
}
