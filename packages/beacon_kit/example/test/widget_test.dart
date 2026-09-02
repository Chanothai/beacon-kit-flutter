// Widget test พื้นฐานของ `beacon_kit` example app
//
// หมายเหตุ (SPRINT.md, งานที่ 3): `_ScanPageState` สร้าง
// `GenericIBeaconEddystoneAdapter` เองภายใน (ไม่มีช่องทาง inject mock adapter/
// platform จาก constructor ของ `ScanPage`/`BeaconKitExampleApp`) ทำให้เทสต์
// interaction เต็มรูป (กดปุ่ม start scan แล้วรอ platform channel ตอบจริง) ทำใน
// widget test ระดับนี้ไม่ได้โดยไม่แตะ `lib/main.dart` (นอกสโคปที่ได้รับมอบหมาย
// รอบนี้) — เทสต์นี้จึงครอบคลุมเฉพาะ initial render + สถานะปุ่มเริ่มต้น ซึ่งเป็น
// สิ่งที่ทำได้แน่นอนโดยไม่ต้องพึ่ง platform channel/ฮาร์ดแวร์ ตามแนวทาง fallback
// ที่ระบุไว้ในบรีฟ
library;

import 'package:beacon_kit/beacon_kit.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// channel ที่ `ExampleDiagnostics` ใช้ — ต้องตรงกับฝั่ง native ทั้งสองแพลตฟอร์ม
const MethodChannel _diagnosticsChannel = MethodChannel(
  'beacon_kit_example/diagnostics',
);

/// ตอบแทน native ให้เฉพาะเมธอดที่ panel ใช้ ที่เหลือคืน `null`
///
/// ไม่ mock ทั้งแอป **โดยตั้งใจ** — เทสต์ชุดนี้พิสูจน์แค่ว่าหน้าจอแปลคำตอบของ
/// native ถูกต้อง ไม่ได้พิสูจน์ว่า native ทำงานถูก (อันนั้นพิสูจน์ด้วยปุ่มบน
/// เครื่องจริง ซึ่งเป็นเหตุผลที่ปุ่มนี้มีอยู่)
void _mockDiagnostics({
  String? logWriteError,
  Map<String, Object?>? selfTestResult,
  bool throwOnRead = false,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_diagnosticsChannel, (call) async {
        switch (call.method) {
          case 'getLogWriteError':
            if (throwOnRead) {
              throw PlatformException(code: 'CHANNEL_UNAVAILABLE');
            }
            return logWriteError;
          case 'runEvidenceLogSelfTest':
            return selfTestResult;
          default:
            return null;
        }
      });
}

Map<String, Object?> _selfTestMap({
  String? errorBeforeWrite,
  String? errorAfterWrite,
  String? readError,
  bool readBackMatches = true,
  String line = 'LINE',
}) => <String, Object?>{
  'path': '/data/user/0/com.beaconkit.example/files/region_events.log',
  'errorBeforeWrite': errorBeforeWrite,
  'writtenLine': line,
  'errorAfterWrite': errorAfterWrite,
  'fileExists': true,
  'fileSizeBytes': 128,
  'lineCount': 3,
  'readBackLine': line,
  'readBackMatches': readBackMatches,
  'readError': readError,
};

/// เปิด panel ให้เห็นรายละเอียดข้างใน (`ExpansionTile` ปิดอยู่ตอนแรก)
Future<void> _openEvidencePanel(WidgetTester tester) async {
  await tester.tap(find.text('เครื่องมือวัด: evidence log'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    BeaconManager.unregisterAll();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_diagnosticsChannel, null);
  });

  testWidgets('BeaconKitExampleApp build ได้โดยไม่ crash และแสดง initial state '
      'ถูกต้อง (title, ปุ่ม start/stop, รายการว่าง)', (tester) async {
    await tester.pumpWidget(const BeaconKitExampleApp());
    await tester.pump();

    expect(find.text('beacon_kit example'), findsOneWidget);
    expect(find.text('Start scan'), findsOneWidget);
    expect(find.text('Stop scan'), findsOneWidget);
    expect(find.text('No beacons found yet'), findsOneWidget);
    // ยังไม่เริ่ม scan -> ไม่มี error banner
    expect(find.textContaining('Error:'), findsNothing);
  });

  testWidgets(
    'ก่อนกด start scan: ปุ่ม Start scan กดได้, ปุ่ม Stop scan ถูกปิดใช้งานไว้ '
    '(ยังไม่มี subscription ให้ยกเลิก)',
    (tester) async {
      await tester.pumpWidget(const BeaconKitExampleApp());
      await tester.pump();

      final startButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start scan'),
      );
      final stopButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Stop scan'),
      );

      expect(startButton.onPressed, isNotNull);
      expect(stopButton.onPressed, isNull);
    },
  );

  testWidgets(
    'unmount widget (dispose) ได้โดยไม่ crash เมื่อยังไม่เคยเริ่ม scan',
    (tester) async {
      await tester.pumpWidget(const BeaconKitExampleApp());
      await tester.pump();

      // pump widget อื่นทับ -> เดิม unmount -> เรียก dispose() ของ _ScanPageState
      // (ยกเลิก subscription ที่เป็น null + BeaconManager.unregisterAll())
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  group('panel เครื่องมือวัด evidence log', () {
    /// **กรณีที่อันตรายที่สุด ต้องไม่ถูกแสดงเป็น "ปกติ"** — ถามฝั่ง native ไม่ได้
    /// เลย ต่างจาก "ถามแล้ว native บอกว่าไม่มี error" โดยสิ้นเชิง ถ้าสองอันนี้
    /// แสดงเหมือนกัน หน้าจอจะรับรองว่าเขียน log ได้ทั้งที่ยังไม่เคยได้คำตอบ
    testWidgets('ถาม native ไม่ได้ ต้องไม่แสดงว่า "ไม่มี error"', (
      tester,
    ) async {
      // จำลองกรณีที่ฝั่ง native ตอบไม่ได้ (channel ยังไม่พร้อม / เมธอดหาย)
      _mockDiagnostics(throwOnRead: true);

      await tester.pumpWidget(const BeaconKitExampleApp());
      await tester.pumpAndSettle();
      await _openEvidencePanel(tester);

      expect(find.textContaining('ถาม native ไม่ได้'), findsOneWidget);
      expect(find.text('ไม่มี'), findsNothing);
    });

    testWidgets('error ที่ค้างจากรอบเบื้องหลังขึ้นบนหัว panel ตั้งแต่เปิดแอป', (
      tester,
    ) async {
      _mockDiagnostics(logWriteError: 'IOException: ENOSPC');

      await tester.pumpWidget(const BeaconKitExampleApp());
      await tester.pumpAndSettle();

      // ต้องเห็นโดยไม่ต้องกางอะไรเลย — ผู้ทดสอบอาจไม่รู้ว่ามี panel นี้อยู่
      expect(
        find.textContaining(
          'native เคยเขียน log ไม่สำเร็จ: IOException: ENOSPC',
        ),
        findsOneWidget,
      );
    });

    testWidgets('กดปุ่มแล้วผ่าน: แสดงบรรทัดที่อ่านกลับมาได้จริง', (
      tester,
    ) async {
      _mockDiagnostics(
        selfTestResult: _selfTestMap(line: '2026-09-01\ta1b2c3d4\tselftest'),
      );

      await tester.pumpWidget(const BeaconKitExampleApp());
      await tester.pumpAndSettle();
      await _openEvidencePanel(tester);

      await tester.tap(find.text('ทดสอบเขียน 1 บรรทัด'));
      await tester.pumpAndSettle();

      expect(find.textContaining('เขียนแล้วอ่านกลับได้ตรง'), findsOneWidget);
      expect(find.textContaining('ตรงกับบรรทัดที่เพิ่งเขียน'), findsOneWidget);
      expect(
        find.textContaining('2026-09-01\ta1b2c3d4\tselftest'),
        findsOneWidget,
      );
    });

    /// เขียนไม่ได้ต้อง **ไม่** ถูกกลบด้วยหน้าตาที่ดูปกติ — นี่คือความล้มเหลว
    /// แบบเงียบที่ปุ่มนี้มีไว้จับพอดี
    testWidgets('กดปุ่มแล้วเขียนไม่ได้: ขึ้นสาเหตุจริง ไม่ใช่แค่ "ไม่ผ่าน"', (
      tester,
    ) async {
      _mockDiagnostics(
        selfTestResult: _selfTestMap(
          errorAfterWrite: 'FileNotFoundException: EACCES (Permission denied)',
          readBackMatches: false,
        ),
      );

      await tester.pumpWidget(const BeaconKitExampleApp());
      await tester.pumpAndSettle();
      await _openEvidencePanel(tester);

      await tester.tap(find.text('ทดสอบเขียน 1 บรรทัด'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('FileNotFoundException: EACCES'),
        findsWidgets,
      );
    });

    /// **ดักการลบหลักฐานทิ้ง** — `append()` ที่สำเร็จตั้ง `lastError` เป็น null
    /// ถ้าหน้าจอไปถามซ้ำหลังเขียน error ที่รอมาทั้งคืนจะหายไปตอนกำลังจะได้อ่าน
    testWidgets('self-test ที่สำเร็จต้องไม่ลบ error ของรอบก่อนออกจากหน้าจอ', (
      tester,
    ) async {
      _mockDiagnostics(
        logWriteError: null,
        selfTestResult: _selfTestMap(errorBeforeWrite: 'IOException: ENOSPC'),
      );

      await tester.pumpWidget(const BeaconKitExampleApp());
      await tester.pumpAndSettle();
      await _openEvidencePanel(tester);

      await tester.tap(find.text('ทดสอบเขียน 1 บรรทัด'));
      await tester.pumpAndSettle();

      expect(find.textContaining('IOException: ENOSPC'), findsWidgets);
    });
  });
}
