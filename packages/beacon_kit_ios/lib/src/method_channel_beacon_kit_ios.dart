import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'beacon_kit_ios_platform.dart';
import 'ibeacon_authorization_level.dart';
import 'ibeacon_region_request.dart';
import 'ibeacon_region_state_event.dart';

/// Service UUID เต็มรูปของ Eddystone (`0000FEAA-...`) ตัวพิมพ์เล็ก — ตรงกับ key ที่
/// `RawAdvertisementScanner.swift` ใช้ใส่ใน `serviceData` map (ดู ARCHITECTURE.md,
/// ADR-4 event channel #2)
const String _eddystoneServiceUuid = '0000feaa-0000-1000-8000-00805f9b34fb';

/// Implementation ของ [BeaconKitIosPlatform] ที่คุยกับ native (Swift) ผ่าน 1 method
/// channel + 3 event channel ตาม `beacon_kit_ios/methods`,
/// `beacon_kit_ios/ibeacon_ranging_events`, `beacon_kit_ios/raw_advertisement_events`,
/// `beacon_kit_ios/region_state_events` (ADR-6)
///
/// อ้างอิง: ARCHITECTURE.md, ADR-4 "iOS platform channel contract", ADR-6 "จาก
/// ranging-only เป็น region monitoring (enter/exit)"
class MethodChannelBeaconKitIos extends BeaconKitIosPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('beacon_kit_ios/methods');

  /// Event channel ของ iBeacon ranging (CoreLocation path)
  @visibleForTesting
  final iBeaconRangingEventChannel = const EventChannel(
    'beacon_kit_ios/ibeacon_ranging_events',
  );

  /// Event channel ของ raw CoreBluetooth advertisement (non-iBeacon path)
  @visibleForTesting
  final rawAdvertisementEventChannel = const EventChannel(
    'beacon_kit_ios/raw_advertisement_events',
  );

  /// Event channel ของ region enter/exit/unknown state (ADR-6) — แยกจาก
  /// [iBeaconRangingEventChannel] โดยตั้งใจ เพราะยิงถี่ต่างกันมาก (ดู
  /// ARCHITECTURE.md ADR-6 หัวข้อ 2)
  @visibleForTesting
  final regionStateEventChannel = const EventChannel(
    'beacon_kit_ios/region_state_events',
  );

  Stream<BeaconAdvertisement>? _iBeaconRangingEvents;
  Stream<BeaconAdvertisement>? _rawAdvertisementEvents;
  Stream<IBeaconRegionStateEvent>? _regionStateEvents;

  @override
  Future<void> startIBeaconMonitoring(
    List<IBeaconRegionRequest> regions,
  ) async {
    try {
      await methodChannel.invokeMethod<void>('startIBeaconMonitoring', {
        'regions': regions.map((region) => region.toMap()).toList(),
      });
    } on PlatformException {
      // ไม่แปลง error code — ให้ code จาก native (TOO_MANY_REGIONS,
      // INVALID_REGION_UUID, LOCATION_PERMISSION_DENIED) ผ่านไปถึงผู้เรียกตรง ๆ
      rethrow;
    }
  }

  @override
  Future<void> stopIBeaconMonitoring([List<String>? identifiers]) {
    return methodChannel.invokeMethod<void>('stopIBeaconMonitoring', {
      'identifiers': identifiers,
    });
  }

  @override
  Future<void> startBluetoothScan(List<String> serviceUuids) async {
    try {
      await methodChannel.invokeMethod<void>('startBluetoothScan', {
        'serviceUuids': serviceUuids,
      });
    } on PlatformException {
      // ไม่แปลง error code — ให้ code จาก native (INVALID_ARGUMENT,
      // BLUETOOTH_UNAVAILABLE, BLUETOOTH_PERMISSION_DENIED) ผ่านไปถึงผู้เรียกตรง ๆ
      rethrow;
    }
  }

  @override
  Future<void> stopBluetoothScan() {
    return methodChannel.invokeMethod<void>('stopBluetoothScan');
  }

  @override
  Stream<BeaconAdvertisement> get iBeaconRangingEvents {
    return _iBeaconRangingEvents ??= iBeaconRangingEventChannel
        .receiveBroadcastStream()
        .expand<BeaconAdvertisement>(_flattenIBeaconRangingBatch);
  }

  @override
  Stream<BeaconAdvertisement> get rawAdvertisementEvents {
    return _rawAdvertisementEvents ??= rawAdvertisementEventChannel
        .receiveBroadcastStream()
        .map<BeaconAdvertisement>(_mapRawAdvertisementEvent);
  }

  @override
  Stream<IBeaconRegionStateEvent> get regionStateEvents {
    return _regionStateEvents ??= regionStateEventChannel
        .receiveBroadcastStream()
        .map<IBeaconRegionStateEvent>(_mapRegionStateEvent);
  }

  @override
  Future<IBeaconAuthorizationLevel> getIBeaconAuthorizationLevel() async {
    final value = await methodChannel.invokeMethod<String>(
      'getIBeaconAuthorizationLevel',
    );
    // native ไม่ throw สำหรับ method นี้ (ดูคอมเมนต์ใน
    // IBeaconRangingManager.currentAuthorizationLevel) แต่ invokeMethod เป็น
    // async ที่คืน nullable เสมอในทางทฤษฎี — ถ้าเจอ null จริง (เช่น mock ที่ไม่
    // สมบูรณ์ตอนเทสต์) ถือว่า insufficient เพื่อความปลอดภัย ไม่สมมติว่าดีกว่า
    // ความจริง
    return parseIBeaconAuthorizationLevel(value ?? '');
  }

  /// Event channel #1 ยิง 1 event ต่อ native `didRange` callback 1 ครั้ง เป็น
  /// `List<Map>` — ฝั่ง Dart เป็นคน flatten เป็น [BeaconAdvertisement] ทีละตัว
  /// (ไม่ flatten ที่ Swift ตาม ADR-4)
  Iterable<BeaconAdvertisement> _flattenIBeaconRangingBatch(dynamic event) {
    final batch = (event as List<dynamic>).cast<Map<dynamic, dynamic>>();
    return batch.map(_mapIBeaconRangingEntry);
  }

  BeaconAdvertisement _mapIBeaconRangingEntry(Map<dynamic, dynamic> entry) {
    final uuid = entry['uuid'] as String;
    final major = entry['major'] as int;
    final minor = entry['minor'] as int;
    final rssi = entry['rssi'] as int;
    final proximityString = entry['proximity'] as String;
    final timestampMs = entry['timestamp'] as int;

    return BeaconAdvertisement(
      deviceId: BeaconDeviceId(
        value: '$uuid:$major:$minor',
        kind: DeviceIdKind.iBeaconLogicalId,
      ),
      rssi: rssi,
      source: AdvertisementSource.coreLocation,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
      ibeaconUuid: uuid,
      ibeaconMajor: major,
      ibeaconMinor: minor,
      proximity: _parseProximity(proximityString),
    );
  }

  BeaconProximity _parseProximity(String value) {
    switch (value) {
      case 'immediate':
        return BeaconProximity.immediate;
      case 'near':
        return BeaconProximity.near;
      case 'far':
        return BeaconProximity.far;
      default:
        return BeaconProximity.unknown;
    }
  }

  /// Event channel #2 ยิง 1 event ต่อ native `didDiscover` callback 1 ครั้ง เป็น
  /// `Map` เดียว (ไม่ใช่ batch) — ถอด Eddystone service data ด้วย [EddystoneParser]
  /// ถ้าเจอ ถ้าไม่เจอหรือ parse ไม่สำเร็จก็ยังส่ง [BeaconAdvertisement] ออกโดย
  /// `raw = {}` และ `rawBytes = null` (ไม่ drop event เพราะ RSSI/peripheral id
  /// ยังมีประโยชน์)
  BeaconAdvertisement _mapRawAdvertisementEvent(dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    final peripheralId = map['peripheralId'] as String;
    final rssi = map['rssi'] as int;
    final timestampMs = map['timestamp'] as int;
    final serviceData = map['serviceData'] as Map<dynamic, dynamic>?;

    var raw = const <String, dynamic>{};
    Uint8List? rawBytes;

    final eddystoneRaw = serviceData?[_eddystoneServiceUuid];
    if (eddystoneRaw != null) {
      final bytes = _toUint8List(eddystoneRaw);
      final parseResult = EddystoneParser.parse(bytes);
      if (parseResult is ParseSuccess<EddystoneFrame>) {
        raw = <String, dynamic>{'eddystone': parseResult.value};
        rawBytes = bytes;
      }
    }

    return BeaconAdvertisement(
      deviceId: BeaconDeviceId(
        value: peripheralId,
        kind: DeviceIdKind.coreBluetoothPeripheralId,
      ),
      rssi: rssi,
      source: AdvertisementSource.coreBluetooth,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
      raw: raw,
      rawBytes: rawBytes,
    );
  }

  /// Event channel #3 (ADR-6) ยิง 1 event ต่อ native เรียกครั้งหนึ่ง (ไม่ใช่
  /// batch เหมือน ranging) — payload shape ตาม ARCHITECTURE.md ADR-6 หัวข้อ 2
  IBeaconRegionStateEvent _mapRegionStateEvent(dynamic event) {
    final map = event as Map<dynamic, dynamic>;
    return IBeaconRegionStateEvent(
      regionIdentifier: map['regionIdentifier'] as String,
      uuid: map['uuid'] as String,
      major: map['major'] as int?,
      minor: map['minor'] as int?,
      state: _parseRegionState(map['state'] as String),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int,
        isUtc: true,
      ),
    );
  }

  IBeaconRegionState _parseRegionState(String value) {
    switch (value) {
      case 'enter':
        return IBeaconRegionState.enter;
      case 'exit':
        return IBeaconRegionState.exit;
      default:
        return IBeaconRegionState.unknown;
    }
  }

  Uint8List _toUint8List(dynamic value) {
    if (value is Uint8List) {
      return value;
    }
    return Uint8List.fromList((value as List<dynamic>).cast<int>());
  }
}
