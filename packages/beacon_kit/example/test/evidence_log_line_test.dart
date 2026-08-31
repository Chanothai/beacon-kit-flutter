import 'package:example/diagnostics/evidence_log_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// เทสต์รูปแบบบรรทัดของไฟล์หลักฐาน
///
/// **ทำไมถึงคุ้มค่าที่จะมีเทสต์:** ไฟล์นี้คือหลักฐานเดียวของรอบทดสอบที่เกิดตอนไม่มี
/// ใครดูหน้าจอ ถ้าตัวอ่านเพี้ยน ข้อมูลที่เก็บมาทั้งคืนจะถูกตีความผิด และเราจะไม่รู้
/// ว่าผิด เพราะไม่มีอะไรให้เทียบ
///
/// เขียนเป็น pure Dart ล้วน ไม่แตะ platform channel — ตรงกับสิ่งที่ทดสอบได้จริง
void main() {
  group('รูปแบบใหม่ 6 คอลัมน์ (ตั้งแต่ ADR-14)', () {
    const line =
        '2026-08-31T22:15:04.123+07:00\ta1b2c3d4\tenter\tk9p-default\t'
        'relaunchedFromTerminated\t'
        'everForeground=false activities=0 state=noActivityEver '
        'importance=service doze=false battOpt=optimized pid=9871 uptime=0.4s';

    test('แยกครบทุกคอลัมน์ตามลำดับ', () {
      final entry = EvidenceLogLine.tryParse(line)!;

      expect(entry.timestamp, '2026-08-31T22:15:04.123+07:00');
      expect(entry.processId, 'a1b2c3d4');
      expect(entry.event, 'enter');
      expect(entry.regionIdentifier, 'k9p-default');
      expect(entry.conclusion, 'relaunchedFromTerminated');
      expect(entry.rawSignals, contains('importance=service'));
    });

    test('บอกได้ว่า event เกิดตอน process ไม่เคยมี UI', () {
      expect(EvidenceLogLine.tryParse(line)!.isFromRelaunchedProcess, isTrue);
    });

    test('บรรทัด launch คือหลักฐานตรงว่า process ถูกสร้างใหม่', () {
      // ก่อนมีคอลัมน์ processId คำถามนี้ตอบได้ด้วยการเดาจาก uptime เท่านั้น ซึ่ง
      // ผิดได้ทั้งสองทาง (ดูเอกสารใน BackgroundEvidenceLog.processId)
      final launch = EvidenceLogLine.tryParse(
        '2026-08-31T22:15:04.000+07:00\tdeadbeef\tlaunch\t-\tforeground\t'
        'uptime=0.0s restoredRegions=[k9p-default]',
      )!;

      expect(launch.marksNewProcess, isTrue);
      expect(EvidenceLogLine.tryParse(line)!.marksNewProcess, isFalse);
    });

    test('สองบรรทัดที่ processId ต่างกัน = คนละ process แน่นอน', () {
      final a = EvidenceLogLine.tryParse(line)!;
      final b = EvidenceLogLine.tryParse(
        line.replaceFirst('a1b2c3d4', '00ff00ff'),
      )!;

      expect(a.processId, isNot(b.processId));
    });
  });

  group('รูปแบบเก่า 5 คอลัมน์ — ต้องอ่านได้ต่อไป', () {
    // `docs/test-data/2026-08-30_overnight_region_flapping.log` เป็นหลักฐานดิบของ
    // รอบทดสอบข้ามคืนที่ ADR-11 ทั้งฉบับตั้งอยู่บนมัน **ห้ามแก้ไฟล์นั้นให้เข้ารูปแบบ
    // ใหม่** — การแก้หลักฐานย้อนหลังทำให้มันเชื่อถือไม่ได้ ตัวอ่านจึงต้องรับได้ทั้งคู่
    const legacy =
        '2026-08-31T05:12:44.001+07:00\texit\tk9p-default\t'
        'relaunchedFromTerminated\t'
        'launchKey=true everActive=false state=background uptime=1201.3s';

    test('ยังแยกคอลัมน์ได้ถูกต้อง', () {
      final entry = EvidenceLogLine.tryParse(legacy)!;

      expect(entry.event, 'exit');
      expect(entry.regionIdentifier, 'k9p-default');
      expect(entry.conclusion, 'relaunchedFromTerminated');
      expect(entry.rawSignals, startsWith('launchKey=true'));
    });

    test('processId เป็น null = "ไม่รู้" ไม่ใช่ "process เดิม"', () {
      // ถ้าเติมค่าปลอมลงไป ผู้อ่านจะสรุปว่าไฟล์เก่าทั้งไฟล์มาจาก process เดียวกัน
      // ซึ่งไฟล์จริงพิสูจน์แล้วว่าไม่ใช่ (มี 4 บรรทัด launch)
      expect(EvidenceLogLine.tryParse(legacy)!.processId, isNull);
    });
  });

  group('การแยกรุ่นไฟล์', () {
    test('คอลัมน์ที่ 2 ที่ไม่ใช่เลขฐานสิบหก 8 ตัว ถือเป็นรูปแบบเก่า', () {
      // คอลัมน์ที่ 2 ของไฟล์เก่าคือชื่อ event ซึ่งไม่มีทางตรงกับรูปแบบของ
      // processId — จึงแยกได้แน่นอนโดยไม่ต้องพึ่งจำนวนคอลัมน์ที่อาจเพี้ยนได้
      final entry = EvidenceLogLine.tryParse(
        '2026-08-31T05:12:44.001+07:00\tenter\tregion\tfg\traw\textra',
      )!;

      expect(entry.processId, isNull);
      expect(entry.event, 'enter');
    });

    test('ตัวพิมพ์ใหญ่ไม่ถือเป็น processId — native เขียนพิมพ์เล็กเสมอ', () {
      final entry = EvidenceLogLine.tryParse(
        '2026-08-31T05:12:44.001+07:00\tA1B2C3D4\tenter\tregion\tfg\traw',
      )!;

      expect(entry.processId, isNull);
    });
  });

  group('บรรทัดที่ผิดรูปแบบ', () {
    test('น้อยกว่า 4 คอลัมน์ → null เพื่อให้ผู้เรียกแสดงบรรทัดดิบแทน', () {
      // แสดงดิบดีกว่าซ่อนทิ้ง — บรรทัดที่อ่านไม่ออกก็ยังเป็นหลักฐาน และการที่มัน
      // อ่านไม่ออกเองก็เป็นข้อมูล (เช่นไฟล์ถูกเขียนทับกลางคันเพราะ process ถูกฆ่า)
      expect(EvidenceLogLine.tryParse(''), isNull);
      expect(EvidenceLogLine.tryParse('a\tb\tc'), isNull);
    });
  });
}
