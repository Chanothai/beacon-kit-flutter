import 'dart:async';
import 'dart:io' show Platform;

import 'package:beacon_kit/beacon_kit.dart';
import 'package:beacon_kit_android/beacon_kit_android.dart'
    show
        AndroidBackgroundMonitoringResult,
        AndroidBackgroundMonitoringStatus,
        AndroidBackgroundRegionEvent,
        AndroidBeaconRegion,
        AndroidRegionState,
        BeaconKitAndroid,
        ScanPermissionStatus;
import 'package:flutter/material.dart';

import 'diagnostics/launch_context.dart';
import 'diagnostics/region_event_log.dart';
import 'log_page.dart';

/// UUID ค่าโรงงานของ K9P (ผู้ใช้ให้มาตรงในบรีฟ ไม่ใช่ secret — เป็น UUID
/// สาธารณะที่ K9P broadcast ออกมา ไม่ใช่ password) ใช้เป็น region เริ่มต้นของ
/// demo นี้เท่านั้น
const String _k9pDefaultUuid = '7777772E-6B6B-6D63-6E2E-636F6D000001';

/// Service UUID ของ Eddystone (`0xFEAA`)
const String _eddystoneServiceUuid = '0000feaa-0000-1000-8000-00805f9b34fb';

/// ⚠️ **หนี้ทางเทคนิคชั่วคราว — ตั้งใจให้อยู่ในไฟล์นี้ไฟล์เดียว**
///
/// การแยกตามแพลตฟอร์มอยู่ใน example app เท่านั้น **ห้ามมีใน `beacon_kit`**
/// (ตรวจได้ด้วย `grep -rn "Platform.is" packages/beacon_kit/lib` ต้องไม่เจอ)
///
/// **ทำไมยังต้องมี:** ADR-13 ยกขึ้นเป็นสัญญากลางเฉพาะเส้นทางสแกน advertisement ดิบ
/// (3 เมธอด) ส่วนเส้นทาง iBeacon ของ iOS (region monitoring / authorization level)
/// ยังคงอยู่ที่ `beacon_kit_ios` เพราะยังไม่ยืนยันว่า Android มีอะไรเทียบเท่า
/// (ADR-9) — หน้าจอนี้จึงต้องรู้เองว่าจะเดินทางไหน
///
/// **แผนกำจัด:** ADR-13 หัวข้อ 4 — เมื่อก้อนที่ 2 (ทำงานเบื้องหลัง) ตอบได้ว่า
/// Android ทำอะไรได้บ้าง ให้ยกเส้นทาง iBeacon ขึ้นเป็นสัญญากลางด้วยชื่อที่เป็นกลาง
/// แล้วลบตัวแปรนี้ทิ้ง
final bool _splitByPlatformUntilAdr13Step4 = Platform.isAndroid;

void main() {
  runApp(const BeaconKitExampleApp());
}

class BeaconKitExampleApp extends StatelessWidget {
  const BeaconKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'beacon_kit example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const ScanPage(),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final GenericIBeaconEddystoneAdapter _adapter =
      GenericIBeaconEddystoneAdapter(
        iBeaconRegions: const [
          IBeaconRegionConfig(identifier: 'k9p-default', uuid: _k9pDefaultUuid),
        ],
      );

  StreamSubscription<BeaconAdvertisement>? _subscription;
  StreamSubscription<IBeaconRegionStateEvent>? _regionSubscription;

  // ---- เฝ้า region เบื้องหลังฝั่ง Android (ADR-14) ----
  //
  // **ตัวแปรคนละชุดกับฝั่ง iOS โดยตั้งใจ** ไม่ใช่เพราะขี้เกียจรวม — สองเส้นทางนี้
  // ให้ข้อมูลคนละคุณภาพ (ระบบคำนวณให้ vs เราคำนวณเอง) การรวมตัวแปรจะทำให้หน้าจอ
  // แสดงเลขเดียวกันโดยที่คนอ่านไม่รู้ว่ามาจากกลไกคนละแบบ
  StreamSubscription<AndroidBackgroundRegionEvent>?
  _androidBackgroundSubscription;
  AndroidBackgroundMonitoringStatus? _androidBackgroundStatus;
  AndroidBackgroundMonitoringResult? _androidBackgroundStartResult;
  String? _lastAndroidBackgroundEvent;

  /// จำนวน event ที่เกิดตอน process **ยังไม่เคยมี UI** — ตัวเลขที่ต้องมากกว่า 0
  /// จึงจะพูดได้ว่าการทำงานเบื้องหลังทำงานจริง
  int _androidBackgroundOriginEvents = 0;

  // ---- เครื่องมือสำหรับพิสูจน์ B5/B6 (อยู่ใน example app เท่านั้น) ----
  final RegionEventLog _log = const RegionEventLog();
  final ExampleDiagnostics _diagnostics = const ExampleDiagnostics();

  IBeaconAuthorizationLevel? _authorizationLevel;
  bool _isMonitoringRegions = false;
  String? _lastRegionEvent;

  // ---- ตัวนับ region event แบบ realtime (สำหรับทดสอบ foreground) ----
  // มีไว้เพื่อให้เห็นผลทันทีบนหน้าจอ **โดยไม่ต้องพึ่ง notification** เลย
  // การทดสอบรอบก่อนสับสนเพราะ foreground ไม่มี notification ขึ้น (iOS ไม่แสดงให้
  // ถ้าแอปไม่ implement willPresent) ทำให้ดูเหมือนไม่มี event เกิดขึ้นทั้งที่มี
  int _enterCount = 0;
  int _exitCount = 0;
  DateTime? _lastEventAt;

  /// รายการ beacon ล่าสุด key ด้วย `'${deviceId.kind}:${deviceId.value}'`
  /// (dedup ตามคู่ kind+value ตาม ADR-1 — ห้ามเทียบข้าม kind)
  final Map<String, BeaconAdvertisement> _beacons = {};

  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    BeaconManager.register(_adapter);
    if (_splitByPlatformUntilAdr13Step4) {
      // ทุกอย่างข้างล่างนี้เป็นเส้นทาง iBeacon ของ iOS ล้วน (region monitoring,
      // ระดับสิทธิ์ location) — Android มีเส้นทางเบื้องหลังของตัวเองที่คนละกลไก
      // (ADR-14) จึงแยกไปตั้งต้นคนละทาง ไม่ใช่เรียกของ iOS แล้วหวังว่าจะได้ผล
      _listenToAndroidBackgroundEvents();
      unawaited(_refreshAndroidBackgroundStatus());
      return;
    }
    // เริ่มฟัง region event ทันทีตั้งแต่แอปเปิด **ไม่รอให้ผู้ใช้กดปุ่ม** —
    // จำเป็นสำหรับ B5: ตอน iOS ปลุก process ที่ถูกฆ่าขึ้นมาส่ง event ไม่มีใคร
    // มากดปุ่มให้ ถ้าเริ่มฟังตอนกดปุ่มเท่านั้น event นั้นจะหายไปเงียบ ๆ
    _listenToRegionEvents();
    _refreshAuthorizationLevel();
    unawaited(_diagnostics.requestNotificationAuthorization());
  }

  void _listenToRegionEvents() {
    _regionSubscription = _adapter.regionStateEvents.listen(
      _onRegionEvent,
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _errorMessage = 'region event error: $error');
      },
    );
  }

  /// อัปเดตหน้าจอเมื่อเข้า/ออก region
  ///
  /// **ไม่เขียน log และไม่ยิง notification ตรงนี้แล้ว** — ทั้งสองอย่างย้ายไปอยู่ฝั่ง
  /// native (`AppDelegate.recordRegionEvent`) ตั้งแต่ ADR-10 เพราะเส้นทางนี้ทำงานได้
  /// ก็ต่อเมื่อ Flutter engine มีชีวิตอยู่ ซึ่งไม่จริงในเคสที่ B5 ต้องการพิสูจน์พอดี
  /// (iOS ปลุก process ที่ถูกฆ่าขึ้นมาส่ง event โดยไม่สร้าง UI)
  ///
  /// เหลือไว้เฉพาะสิ่งที่**ต้อง**อยู่ฝั่ง Dart คือการอัปเดต widget — และจงใจไม่เขียน
  /// log ซ้ำจากทางนี้ เพื่อให้มีผู้เขียนรายเดียว ไม่งั้นตอน foreground จะได้สอง
  /// บรรทัดต่อหนึ่ง event แล้วนับผลผิด
  Future<void> _onRegionEvent(IBeaconRegionStateEvent event) async {
    // อัปเดตตัวนับ**ก่อน** await ใด ๆ เพื่อให้หน้าจอขยับทันทีที่ event มาถึง
    // ไม่ต้องรอ native ตอบเรื่อง diagnostics
    if (mounted) {
      setState(() {
        switch (event.state) {
          case IBeaconRegionState.enter:
            _enterCount++;
          case IBeaconRegionState.exit:
            _exitCount++;
          case IBeaconRegionState.unknown:
            break;
        }
        _lastEventAt = DateTime.now();
      });
    }

    final diagnostics = await _diagnostics.getLaunchDiagnostics();
    // ดึง error ของการเขียน log ฝั่ง native ขึ้นมาแสดง — ถ้าไม่ดึง ความล้มเหลวจะ
    // เงียบสนิทและกลายเป็น "ไม่มีบรรทัดใน log" ซึ่งแยกไม่ออกจาก "แอปไม่ถูกปลุก"
    final logError = await _diagnostics.getLogWriteError();

    if (!mounted) return;
    setState(() {
      _lastRegionEvent =
          '${event.state.name} ${event.regionIdentifier} '
          '(${diagnostics.context.name})';
      if (logError != null) {
        _errorMessage = 'native เขียน log ไม่สำเร็จ: $logError';
      }
    });
  }

  Future<void> _refreshAuthorizationLevel() async {
    try {
      final level = await _adapter.getIBeaconAuthorizationLevel();
      if (!mounted) return;
      setState(() => _authorizationLevel = level);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'อ่านสิทธิ์ไม่ได้: $error');
    }
  }

  /// เริ่ม region monitoring (enter/exit) — คนละอย่างกับ "Start scan" ที่เป็น
  /// ranging สำหรับดูรายการ beacon แบบ realtime
  ///
  /// การเรียก `startIBeaconMonitoring` ฝั่ง native สั่งทั้ง `startMonitoring(for:)`
  /// และ `startRangingBeacons(satisfying:)` — ปุ่มนี้จึงเป็นทางที่ทำให้ region
  /// ถูกลงทะเบียนกับ CoreLocation จริงโดยไม่ต้องเปิดหน้ารายการค้างไว้
  Future<void> _startRegionMonitoring() async {
    setState(() => _errorMessage = null);
    try {
      await _adapter.startIBeaconMonitoring();
      if (!mounted) return;
      setState(() => _isMonitoringRegions = true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เริ่ม region monitoring ไม่ได้: $error');
    }
    await _refreshAuthorizationLevel();
  }

  void _startScan() {
    if (_splitByPlatformUntilAdr13Step4) {
      unawaited(_startAndroidScan());
      return;
    }
    setState(() {
      _errorMessage = null;
      _isScanning = true;
    });
    _subscription = BeaconManager.scanAll().listen(
      (advertisement) {
        final key =
            '${advertisement.deviceId.kind}:${advertisement.deviceId.value}';
        setState(() => _beacons[key] = advertisement);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = error.toString();
          _isScanning = false;
        });
      },
      // adapter ปิด stream ให้เมื่อ native start ล้มเหลว — ต้องทิ้ง subscription
      // ที่ตายแล้วตรงนี้ ไม่งั้นจะถือ handle ค้างไว้เฉย ๆ และกด Start ครั้งถัดไป
      // จะทับ field เดิมโดยที่ตัวเก่าไม่เคยถูกเก็บกวาด
      onDone: () {
        _subscription = null;
        if (!mounted) return;
        setState(() => _isScanning = false);
      },
    );
  }

  /// เส้นทางของ Android — ใช้ **สัญญากลาง** `BeaconKitPlatform` ล้วน ไม่ผ่าน
  /// `GenericIBeaconEddystoneAdapter` เพราะ adapter ตัวนั้นเรียก iBeacon region
  /// monitoring ของ iOS ซึ่งยังไม่มีอะไรเทียบเท่าบน Android (ADR-9)
  ///
  /// บน Android เห็น iBeacon ผ่านเส้นทาง raw ได้เลย เพราะ Android ไม่ mask
  /// manufacturer data เหมือน iOS — `IBeaconParser` ตัวเดียวกับที่มีอยู่แล้วเป็นคน
  /// ถอด (**นี่คือครั้งแรกที่ parser ตัวนั้นถูกใช้งานจริง** บน iOS ไม่เคยถูกเรียก
  /// เลยเพราะ CoreLocation ถอดให้ก่อน)
  Future<void> _startAndroidScan() async {
    setState(() {
      _errorMessage = null;
      _beacons.clear();
    });

    const beaconKitAndroid = BeaconKitAndroid();
    final ScanPermissionStatus status;
    try {
      status = await beaconKitAndroid.requestScanPermissions();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'ขอสิทธิ์ไม่สำเร็จ: $error');
      return;
    }
    if (!mounted) return;

    // แต่ละสถานะมีทางออกของตัวเองชัดเจน **ห้ามมีเคสที่เงียบแล้วไม่ทำอะไรเลย** —
    // บทเรียนตรงจากบั๊กบน iOS รอบ 2 ที่กด Start แล้วไม่มีอะไรเกิดขึ้นและไม่มี error
    switch (status) {
      case ScanPermissionStatus.granted:
        break;
      case ScanPermissionStatus.permanentlyDenied:
        setState(
          () => _errorMessage =
              'สิทธิ์ถูกปฏิเสธถาวร — ขอซ้ำไม่มีผลแล้ว กำลังพาไปหน้า Settings',
        );
        await beaconKitAndroid.openAppSettings();
        return;
      case ScanPermissionStatus.denied:
      case ScanPermissionStatus.notDetermined:
        setState(
          () => _errorMessage =
              'ต้องให้สิทธิ์ Bluetooth (สแกน) และ Location ถึงจะสแกนได้',
        );
        return;
    }

    setState(() => _isScanning = true);
    _subscription = BeaconKitPlatform.instance.rawAdvertisementEvents.listen(
      (advertisement) {
        final key =
            '${advertisement.deviceId.kind}:${advertisement.deviceId.value}';
        setState(() => _beacons[key] = advertisement);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _errorMessage = error.toString();
          _isScanning = false;
        });
      },
    );

    try {
      await BeaconKitPlatform.instance.startBluetoothScan([
        _eddystoneServiceUuid,
      ]);
    } on Object catch (error) {
      await _subscription?.cancel();
      _subscription = null;
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isScanning = false;
      });
    }
  }

  // ---- เฝ้า region เบื้องหลังฝั่ง Android (ADR-14) ----

  /// เริ่มฟัง **ตั้งแต่แอปเปิด ไม่รอให้ผู้ใช้กดปุ่ม**
  ///
  /// จำเป็นด้วยเหตุผลเดียวกับฝั่ง iOS (ADR-10): event ที่ถูกคิวไว้ตอนแอปปิดอยู่จะ
  /// ถูกปล่อยออกมาทั้งชุดทันทีที่มีคน subscribe ถ้าเริ่มฟังตอนกดปุ่มเท่านั้น
  /// **หลักฐานที่รอมาทั้งคืนจะหายไปเงียบ ๆ** ก่อนที่ใครจะได้เห็น
  void _listenToAndroidBackgroundEvents() {
    _androidBackgroundSubscription = const BeaconKitAndroid()
        .backgroundRegionEvents
        .listen(
          _onAndroidBackgroundEvent,
          onError: (Object error) {
            if (!mounted) return;
            setState(
              () => _errorMessage = 'background region event error: $error',
            );
          },
        );
  }

  void _onAndroidBackgroundEvent(AndroidBackgroundRegionEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.state) {
        case AndroidRegionState.enter:
          _enterCount++;
        case AndroidRegionState.exit:
          _exitCount++;
      }
      if (event.fromBackgroundProcess) _androidBackgroundOriginEvents++;
      // แสดง `event.timestamp` ไม่ใช่ `DateTime.now()` — event ที่ถูกคิวไว้อาจเก่า
      // กว่าตอนนี้หลายชั่วโมง ถ้าแสดงเวลาปัจจุบันจะดูเหมือนทุกอย่างเพิ่งเกิดตอน
      // เปิดแอป ซึ่งกลบสิ่งที่การทดสอบต้องการวัดพอดี
      _lastEventAt = event.timestamp;
      _lastAndroidBackgroundEvent =
          '${event.state.name} ${event.regionIdentifier} '
          '(${event.fromBackgroundProcess ? "process เบื้องหลัง" : "process ที่มี UI"})';
    });
  }

  Future<void> _refreshAndroidBackgroundStatus() async {
    try {
      final status = await const BeaconKitAndroid()
          .getBackgroundRegionMonitoringStatus();
      if (!mounted) return;
      setState(() => _androidBackgroundStatus = status);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'อ่านสถานะเบื้องหลังไม่ได้: $error');
    }
  }

  /// ค่า N ที่ใช้ในเดโม — "ไม่เห็นกี่วินาทีถือว่าออกจาก region"
  ///
  /// **ตั้งใจให้อยู่ในแอป ไม่ใช่ใน SDK** ตาม ADR-11 หัวข้อ 7: ค่านี้เป็นการตัดสินใจ
  /// ทางธุรกิจบนข้อมูลเทคนิค SDK ไม่รู้ว่า "เข้าสาขา" แปลว่าอะไรในเชิงธุรกิจ
  ///
  /// 30 วินาทีเลือกให้ตรงกับค่าหน่วงที่ **วัดได้จากพฤติกรรมของ iOS** ในการทดสอบ
  /// ข้ามคืน 30-31 ส.ค. 2026 (ADR-11 หัวข้อ 2) เพื่อให้ผลรอบทดสอบแรกของสอง
  /// แพลตฟอร์มเทียบกันได้ — ไม่ใช่ค่าที่เหมาะกับ production
  static const int _androidExitTimeoutSeconds = 30;

  Future<void> _startAndroidBackgroundMonitoring() async {
    setState(() => _errorMessage = null);

    const beaconKitAndroid = BeaconKitAndroid();
    // ต้องมีสิทธิ์ก่อน ไม่งั้นการลงทะเบียนจะล้มเหลวทุก region และผู้ใช้จะเห็นแค่
    // ตาราง failed ที่ไม่บอกว่าต้องทำอะไรต่อ
    final status = await beaconKitAndroid.requestScanPermissions();
    if (!mounted) return;
    if (status != ScanPermissionStatus.granted) {
      setState(
        () => _errorMessage =
            'ต้องให้สิทธิ์ Bluetooth (สแกน) และ Location ก่อนถึงจะเฝ้าเบื้องหลังได้ '
            '(สถานะตอนนี้: ${status.name})',
      );
      return;
    }

    try {
      final result = await beaconKitAndroid.startBackgroundRegionMonitoring(
        regions: const [
          AndroidBeaconRegion(identifier: 'k9p-default', uuid: _k9pDefaultUuid),
        ],
        exitTimeoutSeconds: _androidExitTimeoutSeconds,
      );
      if (!mounted) return;
      setState(() {
        _androidBackgroundStartResult = result;
        // แสดงความล้มเหลวรายอันเป็น error ทันที ไม่ปล่อยให้ต้องไปสังเกตเอาเองว่า
        // ทำไมไม่มี event — "เงียบแล้วไม่รู้ว่าเงียบเพราะอะไร" คือปัญหาที่เสียเวลา
        // ไปทั้งรอบทดสอบมาแล้ว (ADR-10)
        if (result.failed.isNotEmpty) {
          _errorMessage = 'ลงทะเบียนไม่สำเร็จ: ${result.failed}';
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เริ่มเฝ้าเบื้องหลังไม่ได้: $error');
    }
    await _refreshAndroidBackgroundStatus();
  }

  Future<void> _stopAndroidBackgroundMonitoring() async {
    try {
      await const BeaconKitAndroid().stopBackgroundRegionMonitoring();
      if (!mounted) return;
      setState(() => _androidBackgroundStartResult = null);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'หยุดเฝ้าเบื้องหลังไม่ได้: $error');
    }
    await _refreshAndroidBackgroundStatus();
  }

  Future<void> _stopScan() async {
    await _subscription?.cancel();
    _subscription = null;
    if (_splitByPlatformUntilAdr13Step4) {
      try {
        await BeaconKitPlatform.instance.stopBluetoothScan();
      } on Object {
        // หยุดไม่สำเร็จไม่ควรทำให้ UI ค้างอยู่ในสถานะ "กำลังสแกน"
      }
    }
    if (!mounted) return;
    setState(() => _isScanning = false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _regionSubscription?.cancel();
    // ยกเลิกเฉพาะ **การฟัง** ไม่ได้สั่งหยุดเฝ้า — การเฝ้าเบื้องหลังต้องอยู่ต่อ
    // หลังหน้าจอนี้ถูกทิ้ง ซึ่งเป็นเหตุผลทั้งหมดที่มันมีอยู่
    _androidBackgroundSubscription?.cancel();
    BeaconManager.unregisterAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final beacons = _beacons.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(title: const Text('beacon_kit example')),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text(
                'Error: $_errorMessage',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _isScanning ? null : _startScan,
                    child: const Text('Start scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isScanning ? _stopScan : null,
                    child: const Text('Stop scan'),
                  ),
                ),
              ],
            ),
          ),
          if (_splitByPlatformUntilAdr13Step4)
            _AndroidBackgroundPanel(
              status: _androidBackgroundStatus,
              startResult: _androidBackgroundStartResult,
              lastEvent: _lastAndroidBackgroundEvent,
              enterCount: _enterCount,
              exitCount: _exitCount,
              backgroundOriginEvents: _androidBackgroundOriginEvents,
              lastEventAt: _lastEventAt,
              exitTimeoutSeconds: _androidExitTimeoutSeconds,
              onStart: _startAndroidBackgroundMonitoring,
              onStop: _stopAndroidBackgroundMonitoring,
              onRefresh: _refreshAndroidBackgroundStatus,
              onOpenLog: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogPage(
                    log: _log,
                    regionEvents:
                        const BeaconKitAndroid().backgroundRegionEvents,
                  ),
                ),
              ),
            ),
          if (!_splitByPlatformUntilAdr13Step4)
            _BackgroundTestPanel(
              authorizationLevel: _authorizationLevel,
              isMonitoringRegions: _isMonitoringRegions,
              lastRegionEvent: _lastRegionEvent,
              onStartRegionMonitoring: _startRegionMonitoring,
              onRefreshAuthorization: _refreshAuthorizationLevel,
              enterCount: _enterCount,
              exitCount: _exitCount,
              lastEventAt: _lastEventAt,
              onOpenLog: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LogPage(
                    log: _log,
                    regionEvents: _adapter.regionStateEvents,
                  ),
                ),
              ),
            ),
          Expanded(
            child: beacons.isEmpty
                ? const Center(child: Text('No beacons found yet'))
                : ListView.separated(
                    itemCount: beacons.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _BeaconTile(beacons[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _BeaconTile extends StatelessWidget {
  const _BeaconTile(this.advertisement);

  final BeaconAdvertisement advertisement;

  @override
  Widget build(BuildContext context) {
    final isOsDecoded = advertisement.source == AdvertisementSource.osDecoded;
    final eddystone = advertisement.raw['eddystone'];

    return ListTile(
      leading: Icon(isOsDecoded ? Icons.location_on : Icons.bluetooth),
      title: Text(advertisement.deviceId.value),
      subtitle: Text(_subtitleFor(advertisement, eddystone)),
      trailing: Text('${advertisement.rssi} dBm'),
    );
  }

  String _subtitleFor(BeaconAdvertisement advertisement, Object? eddystone) {
    final sourceLabel = switch (advertisement.source) {
      AdvertisementSource.osDecoded => 'iBeacon (OS ถอดให้)',
      AdvertisementSource.rawParsed => 'raw ADV (Dart parser ถอด)',
    };

    if (advertisement.source == AdvertisementSource.osDecoded) {
      return '$sourceLabel\n'
          'uuid: ${advertisement.ibeaconUuid}, '
          'major: ${advertisement.ibeaconMajor}, '
          'minor: ${advertisement.ibeaconMinor}\n'
          'proximity: ${advertisement.proximity?.name ?? 'unknown'}';
    }

    // บน Android เส้นทาง raw เห็น iBeacon ได้ (Android ไม่ mask เหมือน iOS)
    // จึงต้องแสดง uuid/major/minor ตรงนี้ด้วย ไม่งั้นหน้าจอสองเครื่องจะดูไม่
    // เหมือนกันทั้งที่เป็น beacon ตัวเดียวกัน
    if (advertisement.ibeaconUuid != null) {
      return '$sourceLabel\n'
          'uuid: ${advertisement.ibeaconUuid}, '
          'major: ${advertisement.ibeaconMajor}, '
          'minor: ${advertisement.ibeaconMinor}\n'
          'txPower: ${advertisement.ibeaconTxPower} dBm';
    }

    if (eddystone != null) {
      return '$sourceLabel\neddystone: $eddystone';
    }

    return sourceLabel;
  }
}

/// แผงเครื่องมือสำหรับทดสอบ B5/B6 บนอุปกรณ์จริง — **อยู่ใน example app เท่านั้น**
///
/// แยกจากส่วนแสดงรายการ beacon เพราะเป็นคนละงาน: ส่วนบนคือ ranging (ดู beacon
/// แบบ realtime ตอนแอปเปิดอยู่) ส่วนนี้คือ region monitoring (enter/exit ที่ต้อง
/// ทำงานตอนแอปปิด) ซึ่งเป็นสิ่งที่สปรินต์นี้ต้องพิสูจน์
class _BackgroundTestPanel extends StatelessWidget {
  const _BackgroundTestPanel({
    required this.authorizationLevel,
    required this.isMonitoringRegions,
    required this.lastRegionEvent,
    required this.enterCount,
    required this.exitCount,
    required this.lastEventAt,
    required this.onStartRegionMonitoring,
    required this.onRefreshAuthorization,
    required this.onOpenLog,
  });

  final IBeaconAuthorizationLevel? authorizationLevel;
  final bool isMonitoringRegions;
  final String? lastRegionEvent;
  final int enterCount;
  final int exitCount;
  final DateTime? lastEventAt;
  final Future<void> Function() onStartRegionMonitoring;
  final Future<void> Function() onRefreshAuthorization;
  final VoidCallback onOpenLog;

  @override
  Widget build(BuildContext context) {
    final level = authorizationLevel;
    // B6: ถ้าไม่ใช่ always แปลว่า wake-from-terminate จะไม่ทำงาน ต้องบอกให้ชัด
    // ก่อนที่ผู้ทดสอบจะเสียเวลาทั้งรอบไปกับการรอ event ที่ไม่มีวันมา
    final isAlways = level == IBeaconAuthorizationLevel.always;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Background region monitoring (B5/B6)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isAlways ? Icons.check_circle : Icons.warning_amber,
                  size: 18,
                  color: isAlways
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(switch (level) {
                    null => 'สิทธิ์: กำลังตรวจสอบ…',
                    IBeaconAuthorizationLevel.always =>
                      'สิทธิ์: Always — พร้อมทดสอบ wake-from-terminate',
                    IBeaconAuthorizationLevel.whenInUse =>
                      'สิทธิ์: When In Use — แอปจะไม่ถูกปลุกตอนถูก kill',
                    IBeaconAuthorizationLevel.insufficient =>
                      'สิทธิ์: ไม่พอ — region monitoring จะไม่ทำงาน',
                  }, style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
            if (!isAlways && level != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'ต้องไปตั้งเป็น "Always" ที่ Settings > แอปนี้ > Location '
                  '(iOS ไม่ให้แอปขอ Always ซ้ำหลังผู้ใช้เลือกไปแล้ว)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: onStartRegionMonitoring,
                  child: Text(
                    isMonitoringRegions
                        ? 'ลงทะเบียน region ใหม่อีกครั้ง'
                        : 'Start region monitoring',
                  ),
                ),
                OutlinedButton(
                  onPressed: onRefreshAuthorization,
                  child: const Text('เช็คสิทธิ์ใหม่'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenLog,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('ดู log'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            // ตัวนับ realtime — เห็นผลได้ทันทีแม้ notification ไม่ขึ้น
            Row(
              children: [
                _EventCounter(
                  icon: Icons.login,
                  label: 'enter',
                  count: enterCount,
                ),
                const SizedBox(width: 16),
                _EventCounter(
                  icon: Icons.logout,
                  label: 'exit',
                  count: exitCount,
                ),
                const Spacer(),
                Text(
                  lastEventAt == null
                      ? 'ยังไม่มี event'
                      : 'ล่าสุด ${lastEventAt!.toIso8601String().substring(11, 19)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (lastRegionEvent != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  lastRegionEvent!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ตัวนับ event หนึ่งชนิด แสดงตัวเลขใหญ่พอให้เห็นจากระยะแขนตอนถือเครื่องเดินทดสอบ
class _EventCounter extends StatelessWidget {
  const _EventCounter({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// แผงเครื่องมือทดสอบการทำงานเบื้องหลัง **ฝั่ง Android** — อยู่ใน example app เท่านั้น
///
/// ## ทำไมไม่ใช้แผงเดียวกับ iOS
///
/// สองแพลตฟอร์มทำคนละอย่าง ADR-14 หัวข้อ 1 สรุปไว้ และหน้าจอต้องสะท้อนความจริงนั้น
/// ไม่ใช่ทำให้ดูเหมือนกันเพื่อความสวยงาม:
///
/// - iOS แสดง **ระดับสิทธิ์ location** (`always`/`whenInUse`) ซึ่งไม่มีความหมาย
///   บน Android · Android แสดง **ค่า N ของ exit** ซึ่งไม่มีบน iOS
/// - iOS แสดง `monitoredRegions` ที่ **ระบบ** ตอบ · Android แสดงรายการที่
///   **เราเองจำไว้** ซึ่งอาจไม่ตรงกับความจริงหลัง force-stop
///
/// ถ้ายัดสองอย่างนี้ลงแผงเดียวกัน คนอ่านหน้าจอจะสรุปว่าสองแพลตฟอร์มให้ข้อมูล
/// คุณภาพเดียวกัน ซึ่งเป็นสิ่งที่ ADR-9 สั่งห้ามไว้ตรง ๆ
class _AndroidBackgroundPanel extends StatelessWidget {
  const _AndroidBackgroundPanel({
    required this.status,
    required this.startResult,
    required this.lastEvent,
    required this.enterCount,
    required this.exitCount,
    required this.backgroundOriginEvents,
    required this.lastEventAt,
    required this.exitTimeoutSeconds,
    required this.onStart,
    required this.onStop,
    required this.onRefresh,
    required this.onOpenLog,
  });

  final AndroidBackgroundMonitoringStatus? status;
  final AndroidBackgroundMonitoringResult? startResult;
  final String? lastEvent;
  final int enterCount;
  final int exitCount;
  final int backgroundOriginEvents;
  final DateTime? lastEventAt;
  final int exitTimeoutSeconds;
  final Future<void> Function() onStart;
  final Future<void> Function() onStop;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenLog;

  @override
  Widget build(BuildContext context) {
    final isActive = status?.isActive ?? false;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'เฝ้า region เบื้องหลัง (Android)',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            // ข้อความนี้ต้องอยู่บนหน้าจอ ไม่ใช่แค่ในเอกสาร — คนที่ทดสอบเป็นคนแรก
            // ที่จะสรุปผล และเขาต้องเห็นข้อจำกัดพร้อมกับตัวเลข
            Text(
              'กลไกคนละอย่างกับ iOS: enter/exit คำนวณเองจากการเห็น/ไม่เห็นผลสแกน '
              '· ไม่รอด force-stop · หลังรีบูตต้องรอผู้ใช้ปลดล็อกก่อน',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(),
            _row('สั่งเฝ้าอยู่หรือไม่', isActive ? 'ใช่' : 'ไม่'),
            _row(
              'region ที่จำไว้',
              status?.regionIdentifiers.join(', ').ifEmpty('—') ?? '—',
            ),
            _row('ไม่เห็นกี่วินาทีถือว่าออก', '$exitTimeoutSeconds วินาที'),
            if (status != null && status!.queuedEventCount > 0)
              _row(
                'event ที่คิวไว้ตอนไม่มี engine',
                '${status!.queuedEventCount}',
              ),
            if (startResult != null)
              _row(
                'ผลลงทะเบียนล่าสุด',
                'สำเร็จ ${startResult!.registered.length}'
                    '${startResult!.failed.isEmpty ? "" : " · ล้มเหลว ${startResult!.failed}"}',
              ),
            const Divider(),
            _row('enter / exit ที่เห็นในรอบนี้', '$enterCount / $exitCount'),
            // ตัวเลขที่สำคัญที่สุดของทั้งสปรินต์ — ถ้าเป็น 0 แปลว่ายังพิสูจน์
            // ไม่ได้ว่าอะไรทำงานเบื้องหลัง ไม่ว่าตัวเลขอื่นจะสวยแค่ไหน
            _row(
              'ในนั้นเกิดตอน process ไม่มี UI',
              '$backgroundOriginEvents',
              emphasise: backgroundOriginEvents > 0,
            ),
            if (lastEvent != null) _row('event ล่าสุด', lastEvent!),
            if (lastEventAt != null)
              _row('เวลาที่ native บันทึก', '$lastEventAt'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: isActive ? null : () => onStart(),
                  child: const Text('เริ่มเฝ้าเบื้องหลัง'),
                ),
                OutlinedButton(
                  onPressed: isActive ? () => onStop() : null,
                  child: const Text('หยุดเฝ้า'),
                ),
                TextButton(
                  onPressed: () => onRefresh(),
                  child: const Text('รีเฟรชสถานะ'),
                ),
                TextButton(onPressed: onOpenLog, child: const Text('ดู log')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool emphasise = false}) {
    return Builder(
      builder: (context) {
        final style = Theme.of(context).textTheme.bodySmall;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 4, child: Text(label, style: style)),
              Expanded(
                flex: 5,
                child: Text(
                  value,
                  style: emphasise
                      ? style?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : style,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

extension _IfEmpty on String {
  /// คืน [fallback] เมื่อสตริงว่าง — กันช่องว่างเปล่าบนหน้าจอที่แยกไม่ออกว่า
  /// "ไม่มีข้อมูล" หรือ "โหลดไม่สำเร็จ"
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
