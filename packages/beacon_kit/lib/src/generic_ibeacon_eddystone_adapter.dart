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
    //
    // ข้อควรระวังที่เคยทำให้เกิดบั๊กจริง (ดู `_failAndTearDown`): ถ้า controller
    // ตัวเดิมยังมี listener ค้างอยู่ การ listen รอบถัดไปจะทำให้จำนวนผู้ฟังขยับ
    // 1 -> 2 ซึ่ง **ไม่ยิง onListen** แปลว่าจะไม่มีการเรียก native start อีกเลย
    // เงียบ ๆ — controller ที่ start ไม่สำเร็จจึงต้องถูกรื้อทิ้งเสมอ ห้ามปล่อยค้าง
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
      await _failAndTearDown(controller);
    }
  }

  /// รื้อ controller ที่ native start ล้มเหลวทิ้งให้หมด แล้วปิด stream
  ///
  /// **ทำไมต้องรื้อ ไม่ใช่แค่ addError แล้วปล่อยไว้** — บั๊กที่เจอจากการทดสอบบน
  /// iPhone จริง (รอบ 2, 27 ส.ค. 2026): เดิมเมื่อ start ล้มเหลว (เช่นผู้ใช้กด
  /// Don't Allow) โค้ดแค่ `addError` แล้วจบ ทำให้ `_controller` ตัวเดิมยังอยู่และ
  /// ยังมี listener ของแอปค้างอยู่ 1 ตัว (การ addError ไม่ปิด stream และไม่ยกเลิก
  /// subscription) พอผู้ใช้กด Start scan ครั้งถัดไป `scan()` จะ `??=` เจอ
  /// controller ตัวเดิม แล้ว listener ขยับ 1 -> 2 ซึ่ง **onListen ไม่ยิง** →
  /// `_startScanning()` ไม่ถูกเรียก → ไม่มีการเรียก native เลยแม้แต่ครั้งเดียว
  /// → หน้าจอเงียบสนิท ไม่มี error ไม่ crash และจะเป็นแบบนี้ตลอดไปจนกว่าจะ
  /// force quit แอป (สถานะค้างในหน่วยความจำ ไม่ใช่ปัญหา permission ของ OS)
  ///
  /// การปิด controller ทำให้ listener ที่ค้างอยู่ได้ `done` และถูกเก็บกวาด
  /// การเรียก `scan()` ครั้งถัดไปจึงสร้าง controller ใหม่และ onListen ยิงตามปกติ
  Future<void> _failAndTearDown(
    StreamController<BeaconAdvertisement> controller,
  ) async {
    // ถ้ามีใครรื้อ/สลับ controller ไปแล้วระหว่างนี้ อย่าไปยุ่งกับของคนอื่น
    if (!identical(_controller, controller)) return;

    await _stopScanning();
    if (!controller.isClosed) await controller.close();
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

  /// event enter/exit/unknown ของ region ตาม ARCHITECTURE.md ADR-6 — **ไม่ใช่**
  /// ส่วนหนึ่งของ [BeaconAdapter] interface กลาง (ตั้งใจ) เพราะ region
  /// monitoring แบบ enter/exit เป็นกลไกเฉพาะของ CoreLocation บน iOS เท่านั้น
  /// ยังไม่มี contract ฝั่ง Android ที่เทียบเท่า (Android deferred ตาม
  /// SPRINT.md) การใส่ลง [BeaconAdapter] ตอนนี้จะบังคับให้ Android adapter ใน
  /// อนาคตต้อง implement getter ที่ยังไม่มีความหมายจริงบนแพลตฟอร์มนั้น จึงเปิด
  /// เป็น getter เพิ่มเติมเฉพาะของ adapter นี้แทน — ผู้เรียกที่ต้องการ enter/exit
  /// ต้อง cast/reference เป็น [GenericIBeaconEddystoneAdapter] ตรง ๆ (ไม่ผ่าน
  /// [BeaconAdapter] abstraction)
  ///
  /// ยังไม่ต่อเข้ากับ [scan]/[BeaconManager.scanAll] — นอกสโคป B5/B6 ตาม
  /// `SPRINT.md` (สโคปของสปรินต์นี้คือ code-complete ของ region monitoring
  /// เท่านั้น ไม่รวมการต่อสาย UI ใน example app) ตัดสินใจเปิด getter นี้ไว้ที่
  /// ระดับ `beacon_kit` (public API) แทนที่จะหยุดไว้แค่ `beacon_kit_ios` เพื่อ
  /// ให้ทดสอบ end-to-end บนอุปกรณ์จริงได้ทันทีที่ต้องการโดยไม่ต้องรอรอบถัดไป
  /// มาเปิด API เพิ่ม — ถ้อยคำนี้เป็นการอธิบายเหตุผลของผู้เขียนโค้ดเอง
  /// ไม่ใช่คำพูดที่คัดลอกมาจาก `SPRINT.md` ตรง ๆ
  Stream<IBeaconRegionStateEvent> get regionStateEvents =>
      _platform.regionStateEvents;

  /// B6: query ระดับสิทธิ์ location ปัจจุบัน (`always`/`whenInUse`/
  /// `insufficient`) ที่มีผลต่อว่า background wake หลังแอปโดน terminate จะ
  /// ทำงานได้จริงหรือไม่ — ดูเหตุผลเต็มที่ [IBeaconAuthorizationLevel]
  Future<IBeaconAuthorizationLevel> getIBeaconAuthorizationLevel() =>
      _platform.getIBeaconAuthorizationLevel();
}
