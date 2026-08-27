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
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(BeaconManager.unregisterAll);

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
}
