/// Test ของ [estimateDistanceMeters] — pure function ล้วน: byte/ตัวเลขเข้า →
/// ตัวเลขออก ไม่มี I/O ไม่แตะ BLE API ใด ๆ ตาม dartdoc ของฟังก์ชันเอง
///
/// ค่าทดสอบทั้งหมดใน**ไฟล์นี้เป็นค่าสังเคราะห์ (synthetic) ล้วน ๆ** ที่คำนวณจากสูตร
/// log-distance path loss โดยตรง (ยืนยันสูตรที่ ARCHITECTURE.md ADR-19 หัวข้อ 4/8 และ
/// `docs/sources/rssi_path_loss_model.md`) — **ไม่ใช้ log จริงจาก `docs/test-data/`**
/// เพราะไฟล์เหล่านั้นเป็น log เหตุการณ์ระดับ region enter/exit ของ ADR-16/ADR-17
/// (`docs/test-data/README.md` ระบุคอลัมน์ไว้ตรง ๆ: iOS มีแค่ `launchKey`/`everActive`/
/// `state`/`uptime`/`monitoredRegions`, Android มีแค่ `procUuid`/`pid`/`uptimeMs`/
/// `receiverEntry`/ฯลฯ) — **ไม่มีคอลัมน์ RSSI รายบรรทัดเลยสักไฟล์** จึงไม่มีทางใช้เป็น
/// input ของฟังก์ชันระดับ RSSI→ระยะทางนี้ได้ ไม่ว่าจะพยายามแปลงยังไงก็ตาม
library;

import 'package:beacon_kit/beacon_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('estimateDistanceMeters', () {
    test('txPower -59, rssi -75, n 2.5 ให้ระยะ ~4.4 เมตร (ค่าที่รู้คำตอบล่วงหน้าจากสูตร '
        'log-distance path loss ตรง ๆ: d = 10^((txPower-rssi)/(10n)))', () {
      final meters = estimateDistanceMeters(
        rssi: -75,
        txPower: -59,
        pathLossExponent: 2.5,
      );
      // ค่าจริงคือ 4.36515...  ห่างจาก 4.4 ราว 0.035 ซึ่งอยู่ใน tolerance 0.05
      // ที่โจทย์ระบุ — ยืนยันด้วย python คู่ขนานตอนออกแบบเทสต์นี้แล้ว
      expect(meters, closeTo(4.4, 0.05));
    });

    test('rssi เท่ากับ txPower พอดี ให้ระยะ 1.0 เมตรเป๊ะ (ระยะอ้างอิง d0 ของโมเดล)', () {
      final meters = estimateDistanceMeters(
        rssi: -59,
        txPower: -59,
        pathLossExponent: 2.5,
      );
      expect(meters, 1.0);
    });

    test('rssi เท่ากับ txPower พอดี ให้ 1.0 เมตรเป๊ะ ไม่ว่า pathLossExponent จะเป็นเท่าไหร่ '
        '(เลขชี้กำลังของ 0 คือ 1 เสมอ — สมบัติทางคณิตศาสตร์ของสูตร ไม่ใช่ค่าที่ผูกกับ n '
        'ตัวใดตัวหนึ่ง)', () {
      for (final n in [1.6, 2.0, 2.5, 3.0, 6.0]) {
        expect(
          estimateDistanceMeters(rssi: -70, txPower: -70, pathLossExponent: n),
          1.0,
        );
      }
    });
  });
}
