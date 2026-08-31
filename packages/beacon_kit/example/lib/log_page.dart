import 'dart:async';

import 'package:flutter/material.dart';

import 'diagnostics/evidence_log_line.dart';
import 'diagnostics/region_event_log.dart';

/// หน้าดู log ของ region enter/exit ที่บันทึกไว้ พร้อมปุ่มล้างเพื่อเริ่มรอบทดสอบใหม่
class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.log, required this.regionEvents});

  final RegionEventLog log;

  /// stream ของ region event — ใช้เป็นตัว **trigger ให้อ่านไฟล์ใหม่** เมื่อมี
  /// event เข้ามาขณะเปิดหน้านี้ค้างไว้
  ///
  /// จงใจไม่เอาข้อมูลจาก stream มาแสดงตรง ๆ แต่ให้ไปอ่านไฟล์ซ้ำแทน เพราะหน้านี้
  /// มีหน้าที่แสดง **สิ่งที่อยู่ในไฟล์จริง** ถ้าเอาจาก stream มาต่อท้ายในหน่วยความจำ
  /// หน้าจอจะดูเหมือนมีบรรทัดครบทั้งที่การเขียนไฟล์อาจล้มเหลว (เช่นเครื่องล็อก
  /// แล้ว Data Protection บล็อก — ดูเช็คลิสต์หัวข้อ 13) ซึ่งจะกลบปัญหาที่เรา
  /// ต้องการจับพอดี
  ///
  /// ชนิดเป็น `Object?` เพราะสองแพลตฟอร์มส่ง event คนละชนิด
  /// (`IBeaconRegionStateEvent` จาก CoreLocation ฝั่ง iOS ·
  /// `AndroidBackgroundRegionEvent` ที่เราคำนวณเองฝั่ง Android — ADR-14 อธิบายว่า
  /// ทำไมสองอย่างนี้ไม่ใช่ชนิดเดียวกัน) หน้านี้ไม่ต้องรู้ว่าเป็นอันไหน เพราะใช้มัน
  /// เป็นแค่สัญญาณให้ไปอ่านไฟล์ใหม่ — **เนื้อหาที่แสดงมาจากไฟล์เสมอ**
  final Stream<Object?> regionEvents;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<String>? _lines;
  String? _path;
  String? _error;
  StreamSubscription<Object?>? _subscription;
  DateTime? _lastReloadedAt;

  @override
  void initState() {
    super.initState();
    _reload();
    // อัปเดตอัตโนมัติเมื่อมี event ใหม่ ระหว่างเปิดหน้านี้ค้างไว้ — สำคัญตอนทดสอบ
    // foreground เพราะผู้ทดสอบถือเครื่องเปิดหน้านี้อยู่ ถ้าไม่อัปเดตเองจะเข้าใจผิด
    // ว่าไม่มี event เกิดขึ้น ทั้งที่มันเขียนลงไฟล์ไปแล้ว
    _subscription = widget.regionEvents.listen(
      (_) => _reload(),
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final lines = await widget.log.read();
      final path = await widget.log.path();
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _path = path;
        _error = null;
        _lastReloadedAt = DateTime.now();
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ล้าง log ทั้งหมด?'),
        content: const Text(
          'หลักฐานการทดสอบรอบก่อนจะหายถาวร กู้คืนไม่ได้ — '
          'ทำเมื่อจะเริ่มรอบทดสอบใหม่เท่านั้น',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ล้าง'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.log.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Region event log'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'โหลดใหม่',
          ),
          IconButton(
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'ล้าง log',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_path != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ไฟล์: $_path',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${lines?.length ?? 0} บรรทัด · อ่านไฟล์ล่าสุด '
                    '${_lastReloadedAt?.toIso8601String().substring(11, 19) ?? '-'}'
                    ' · อัปเดตอัตโนมัติเมื่อมี event ใหม่',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (_error != null)
            Container(
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(12),
              child: Text('อ่าน log ไม่ได้: $_error'),
            ),
          const Divider(height: 1),
          Expanded(
            child: switch (lines) {
              null => const Center(child: CircularProgressIndicator()),
              [] => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'ยังไม่มี event ที่บันทึกไว้\n\n'
                    'รูปแบบแต่ละบรรทัด:\n'
                    'เวลา ISO8601 พร้อม timezone / ตัวระบุ process / '
                    'ชนิด event / region / สถานะแอป / สัญญาณดิบ',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              _ => ListView.separated(
                itemCount: lines.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _LogTile(line: lines[index]),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final entry = EvidenceLogLine.tryParse(line);
    // บรรทัดที่ฟอร์แมตไม่ตรงจนแยกคอลัมน์ไม่ได้ ให้แสดงดิบ ๆ ดีกว่าซ่อนทิ้ง
    // เพราะมันคือหลักฐานที่อาจสำคัญ
    if (entry == null) {
      return ListTile(title: Text(line, style: _mono(context)));
    }

    final isRelaunch = entry.isFromRelaunchedProcess;
    // `processId` ที่แสดงชัดคือสิ่งที่ทำให้ผู้ทดสอบตอบได้ทันทีบนหน้าจอเครื่องว่า
    // บรรทัดกลุ่มนี้มาจาก process เดียวกันหรือคนละ process โดยไม่ต้อง export
    // ไฟล์ออกมาเทียบทีหลัง — คำถามที่รอบทดสอบก่อนหน้าตอบไม่ได้เลย
    final processLabel = entry.processId ?? 'ไม่มี pid (ไฟล์รูปแบบเก่า)';
    return ListTile(
      leading: Icon(switch (entry.event) {
        'enter' => Icons.login,
        'exit' => Icons.logout,
        'launch' => Icons.play_circle_outline,
        _ => Icons.circle_outlined,
      }, color: isRelaunch ? Theme.of(context).colorScheme.primary : null),
      title: Text(
        '${entry.event} — ${entry.regionIdentifier}',
        style: _mono(context),
      ),
      subtitle: Text(
        '${entry.timestamp}\npid=$processLabel · ${entry.conclusion}\n'
        '${entry.rawSignals}',
        style: _mono(context),
      ),
      isThreeLine: true,
      // ไฮไลต์เคสที่การทดสอบเบื้องหลังต้องพิสูจน์ ให้เห็นได้ทันทีตอนเลื่อนดู log ยาว ๆ
      trailing: isRelaunch
          ? Chip(
              label: const Text('relaunched'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            )
          : null,
    );
  }

  TextStyle? _mono(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'Courier');
}
