// Test ของ IBeaconParser (ARCHITECTURE.md ADR-3) — pure Dart, ไม่พึ่ง Flutter
// binding เพราะ parser เป็น pure function ล้วน ๆ (byte array เข้า → object ออก)
//
// ทุกเคสโหลดจาก docs/fixtures/ibeacon_*.json (field "parser": "ibeacon")
// ครอบคลุมทั้งเคสปกติและเคสพัง — ดู docs/fixtures/README.md
//
// สถานะ: เขียนตาม contract ใน ARCHITECTURE.md ADR-3 ล้วน ๆ ยังไม่ได้ยืนยันว่า
// รันผ่านจริง เพราะรอ flutter-dev agent implement lib/src/parsers/ibeacon_parser.dart
// (ดูรายละเอียดผลการรันจริงในสรุปงานของ QA agent)

import 'package:beacon_kit_platform_interface/beacon_kit_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixture_loader.dart';

void main() {
  final fixtures = loadFixturesFor('ibeacon');

  test('มี fixture ของ ibeacon อย่างน้อย 5 เคส (ปกติ 1 + พัง 4 ตามที่ QA sprint กำหนด)', () {
    expect(fixtures.length, greaterThanOrEqualTo(5));
  });

  for (final fx in fixtures) {
    test('${fx.name} (source: ${fx.source})', () {
      final result = IBeaconParser.parse(fx.bytes);
      final expectResult = fx.expect['result'] as String;

      switch (expectResult) {
        case 'success':
          expect(
            result,
            isA<ParseSuccess<IBeaconFrame>>(),
            reason:
                'คาดหวังว่า parse สำเร็จ แต่ได้ $result\n'
                'fixture: ${fx.sourceDetail}',
          );
          final frame = (result as ParseSuccess<IBeaconFrame>).value;
          final expectedFrame = fx.expect['frame'] as Map<String, dynamic>;
          expect(frame.uuid, expectedFrame['uuid'], reason: 'uuid');
          expect(frame.major, expectedFrame['major'], reason: 'major');
          expect(frame.minor, expectedFrame['minor'], reason: 'minor');
          expect(frame.txPower, expectedFrame['tx_power'], reason: 'txPower');
          break;

        case 'failure':
          expect(
            result,
            isA<ParseFailure<IBeaconFrame>>(),
            reason:
                'คาดหวังว่า parse ล้มเหลว แต่ได้ $result\n'
                'fixture: ${fx.sourceDetail}',
          );
          final failure = result as ParseFailure<IBeaconFrame>;
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
