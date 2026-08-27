// Test ของ EddystoneParser (ARCHITECTURE.md ADR-3) — pure Dart, ไม่พึ่ง Flutter
// binding เพราะ parser เป็น pure function ล้วน ๆ (byte array เข้า → object ออก)
//
// ทุกเคสโหลดจาก docs/fixtures/eddystone_*.json (field "parser": "eddystone")
// ครอบคลุม UID / URL / TLM (ปกติ + พัง), EID (unsupported เสมอ), byte แรกไม่รู้จัก
// (invalidFrameType), และ input ว่างเปล่า (tooShort) — ดู docs/fixtures/README.md
//
// เหตุผลที่เคส "TLM ความยาวขาดกลาง time-since-power-on field"
// (eddystone_tlm_partial_time_field.json) คาดหวัง reason=tooShort ไม่ใช่
// truncatedField: ทุก Eddystone frame type ที่ parser นี้ decode (UID/URL/TLM)
// มีความยาวรวมที่ตรวจสอบได้ตั้งแต่ byte แรกโดยไม่ต้อง parse เข้าไปในตัว field —
// UID และ TLM มีความยาว fixed เป๊ะต่อ frame (20 และ 14 bytes ตามลำดับ) ส่วน URL
// แม้ suffix จะยาวไม่คงที่ แต่ก็ไม่มี length-prefix ของ field ย่อยที่ทำให้ parse
// แล้วเจอ "field ขาดกลางคัน" ได้ระหว่างทาง (ทุก byte ที่เหลือหลัง scheme byte
// ถือเป็นส่วนหนึ่งของ suffix เสมอ) ดังนั้นความยาวรวมผิดของทั้งสามฟอร์แมตนี้จับได้
// จากการเช็คความยาวรวมทั้งก้อนตั้งแต่ต้น (tooShort/tooLong) — reason=truncatedField
// ตาม ADR-3 มีไว้สำหรับกรณีที่ parser ต้อง parse ลึกเข้าไปใน field ที่มี
// length-indicator ของตัวเองก่อนถึงจะรู้ว่าขาด ซึ่งไม่มีในทั้ง 3 frame type ที่
// implement รอบนี้
//
// สถานะ: เขียนตาม contract ใน ARCHITECTURE.md ADR-3 ล้วน ๆ ยังไม่ได้ยืนยันว่า
// รันผ่านจริง เพราะรอ flutter-dev agent implement
// lib/src/parsers/eddystone_parser.dart (ดูผลการรันจริงในสรุปงานของ QA agent)

import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_loader.dart';

void main() {
  final fixtures = loadFixturesFor('eddystone');

  test('มี fixture ของ eddystone ครบ UID/URL/TLM (ปกติ+พัง) + EID + unknown-type + empty', () {
    expect(fixtures.length, greaterThanOrEqualTo(14));
  });

  for (final fx in fixtures) {
    test('${fx.name} (source: ${fx.source})', () {
      final result = EddystoneParser.parse(fx.bytes);
      final expectResult = fx.expect['result'] as String;

      switch (expectResult) {
        case 'success':
          expect(
            result,
            isA<ParseSuccess<EddystoneFrame>>(),
            reason:
                'คาดหวังว่า parse สำเร็จ แต่ได้ $result\n'
                'fixture: ${fx.sourceDetail}',
          );
          final frame = (result as ParseSuccess<EddystoneFrame>).value;
          final frameType = fx.expect['frame_type'] as String;
          final expectedFrame = fx.expect['frame'] as Map<String, dynamic>;
          _expectFrameMatches(frameType, frame, expectedFrame, fx);
          break;

        case 'failure':
          expect(
            result,
            isA<ParseFailure<EddystoneFrame>>(),
            reason:
                'คาดหวังว่า parse ล้มเหลว แต่ได้ $result\n'
                'fixture: ${fx.sourceDetail}',
          );
          final failure = result as ParseFailure<EddystoneFrame>;
          final expectedReason = fx.expect['reason'] as String;
          expect(
            failure.reason.name,
            expectedReason,
            reason:
                'ParseFailureReason ไม่ตรงตามที่ fixture คาดหวัง — ได้ '
                '${failure.reason.name} (detail: ${failure.detail})\n'
                'fixture: ${fx.sourceDetail}',
          );
          break;

        default:
          fail(
            "fixture ${fx.name} มี expect.result ที่ไม่รู้จัก: $expectResult",
          );
      }
    });
  }
}

void _expectFrameMatches(
  String frameType,
  EddystoneFrame frame,
  Map<String, dynamic> expectedFrame,
  Fixture fx,
) {
  switch (frameType) {
    case 'uid':
      expect(frame, isA<EddystoneUidFrame>(), reason: fx.sourceDetail);
      final uid = frame as EddystoneUidFrame;
      expect(uid.txPower, expectedFrame['tx_power'], reason: 'txPower');
      expect(
        uid.namespaceId,
        expectedFrame['namespace_id'],
        reason: 'namespaceId',
      );
      expect(
        uid.instanceId,
        expectedFrame['instance_id'],
        reason: 'instanceId',
      );
      break;

    case 'url':
      expect(frame, isA<EddystoneUrlFrame>(), reason: fx.sourceDetail);
      final url = frame as EddystoneUrlFrame;
      expect(url.txPower, expectedFrame['tx_power'], reason: 'txPower');
      expect(url.url, expectedFrame['url'], reason: 'url');
      break;

    case 'tlm':
      expect(frame, isA<EddystoneTlmFrame>(), reason: fx.sourceDetail);
      final tlm = frame as EddystoneTlmFrame;
      expect(tlm.version, expectedFrame['version'], reason: 'version');
      expect(
        tlm.batteryVoltageMv,
        expectedFrame['battery_voltage_mv'],
        reason: 'batteryVoltageMv',
      );
      final expectedTempC = expectedFrame['temperature_c'];
      if (expectedTempC == null) {
        expect(
          tlm.temperatureC,
          isNull,
          reason: 'temperatureC ต้องเป็น null เมื่อ raw temperature == 0x8000',
        );
      } else {
        expect(tlm.temperatureC, expectedTempC, reason: 'temperatureC');
      }
      expect(
        tlm.advertisingPduCount,
        expectedFrame['advertising_pdu_count'],
        reason: 'advertisingPduCount',
      );
      expect(
        tlm.timeSincePowerOn,
        Duration(milliseconds: expectedFrame['time_since_power_on_ms'] as int),
        reason: 'timeSincePowerOn',
      );
      break;

    default:
      fail('fixture ${fx.name} มี expect.frame_type ที่ไม่รู้จัก: $frameType');
  }
}
