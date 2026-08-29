import 'package:flutter/material.dart';

import 'diagnostics/region_event_log.dart';

/// หน้าดู log ของ region enter/exit ที่บันทึกไว้ พร้อมปุ่มล้างเพื่อเริ่มรอบทดสอบใหม่
class LogPage extends StatefulWidget {
  const LogPage({super.key, required this.log});

  final RegionEventLog log;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<String>? _lines;
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
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
              child: Text(
                'ไฟล์: $_path',
                style: Theme.of(context).textTheme.bodySmall,
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
                    'เวลา ISO8601 พร้อม timezone / ชนิด event / region / '
                    'สถานะแอป / สัญญาณดิบ',
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
    final parts = line.split('\t');
    // บรรทัดที่ฟอร์แมตไม่ตรง (เช่นไฟล์เก่าคนละเวอร์ชัน) ให้แสดงดิบ ๆ
    // ดีกว่าซ่อนทิ้ง เพราะมันคือหลักฐานที่อาจสำคัญ
    if (parts.length < 5) {
      return ListTile(title: Text(line, style: _mono(context)));
    }

    final isRelaunch = parts[3] == 'relaunchedFromTerminated';
    return ListTile(
      leading: Icon(
        parts[1] == 'enter' ? Icons.login : Icons.logout,
        color: isRelaunch ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text('${parts[1]} — ${parts[2]}', style: _mono(context)),
      subtitle: Text('${parts[0]}\n${parts[4]}', style: _mono(context)),
      isThreeLine: true,
      // ไฮไลต์เคสที่ B5 ต้องพิสูจน์ ให้เห็นได้ทันทีตอนเลื่อนดู log ยาว ๆ
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
