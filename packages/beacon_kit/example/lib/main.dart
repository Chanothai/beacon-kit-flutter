import 'dart:async';

import 'package:beacon_kit/beacon_kit.dart';
import 'package:flutter/material.dart';

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

  /// รายการ beacon ล่าสุด key ด้วย `'${deviceId.kind}:${deviceId.value}'`
  /// (dedup ตามคู่ kind+value ตาม ADR-1 — ห้ามเทียบข้าม kind)
  final Map<String, BeaconAdvertisement> _beacons = {};

  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    BeaconManager.register(_adapter);
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
