import 'dart:async';

import 'package:beacon_kit/beacon_kit.dart';
import 'package:flutter/material.dart';

import 'diagnostics/launch_context.dart';
import 'diagnostics/region_event_log.dart';
import 'log_page.dart';

/// UUID ค่าโรงงานของ K9P (ผู้ใช้ให้มาตรงในบรีฟ ไม่ใช่ secret — เป็น UUID
/// สาธารณะที่ K9P broadcast ออกมา ไม่ใช่ password) ใช้เป็น region เริ่มต้นของ
/// demo นี้เท่านั้น
const String _k9pDefaultUuid = '7777772E-6B6B-6D63-6E2E-636F6D000001';

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

  /// บันทึกหลักฐาน + ยิง notification ทุกครั้งที่เข้า/ออก region
  ///
  /// ลำดับสำคัญ: **เขียน log ก่อน** แล้วค่อยยิง notification เพราะ log คือหลักฐาน
  /// ที่ต้องรอด ส่วน notification เป็นแค่สัญญาณให้คนเห็น ถ้าเวลาที่ระบบให้หมดก่อน
  /// อย่างน้อยหลักฐานต้องลงดิสก์แล้ว
  Future<void> _onRegionEvent(IBeaconRegionStateEvent event) async {
    // อัปเดตตัวนับ**ก่อน** await ใด ๆ เพื่อให้หน้าจอขยับทันทีที่ event มาถึง
    // ไม่ต้องรอ native ตอบเรื่อง diagnostics หรือรอเขียนไฟล์เสร็จ
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

    try {
      await _log.append(event, diagnostics);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'เขียน log ไม่สำเร็จ: $error');
      }
    }

    final context = diagnostics.context.name;
    try {
      await _diagnostics.postNotification(
        title: 'Region ${event.state.name}: ${event.regionIdentifier}',
        body: 'สถานะแอป: $context',
      );
    } on Object {
      // notification ล้มเหลวไม่ควรทำให้ทั้ง flow พัง — log ที่เขียนไปแล้วยังเป็น
      // หลักฐานที่ใช้ได้ (เช่นผู้ใช้ไม่ได้อนุญาต notification)
    }

    if (!mounted) return;
    setState(() {
      _lastRegionEvent =
          '${event.state.name} ${event.regionIdentifier} ($context)';
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

  Future<void> _stopScan() async {
    await _subscription?.cancel();
    _subscription = null;
    setState(() => _isScanning = false);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _regionSubscription?.cancel();
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
    final isCoreLocation =
        advertisement.source == AdvertisementSource.coreLocation;
    final eddystone = advertisement.raw['eddystone'];

    return ListTile(
      leading: Icon(isCoreLocation ? Icons.location_on : Icons.bluetooth),
      title: Text(advertisement.deviceId.value),
      subtitle: Text(_subtitleFor(advertisement, eddystone)),
      trailing: Text('${advertisement.rssi} dBm'),
    );
  }

  String _subtitleFor(BeaconAdvertisement advertisement, Object? eddystone) {
    final sourceLabel = switch (advertisement.source) {
      AdvertisementSource.coreLocation => 'iBeacon (CoreLocation)',
      AdvertisementSource.coreBluetooth => 'CoreBluetooth',
      AdvertisementSource.android => 'Android',
    };

    if (advertisement.source == AdvertisementSource.coreLocation) {
      return '$sourceLabel\n'
          'uuid: ${advertisement.ibeaconUuid}, '
          'major: ${advertisement.ibeaconMajor}, '
          'minor: ${advertisement.ibeaconMinor}\n'
          'proximity: ${advertisement.proximity?.name ?? 'unknown'}';
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
