import 'dart:typed_data';

import '../entities/eddystone_frame.dart';
import 'parse_result.dart';

/// ตาราง encoding ของ Eddystone-URL suffix (byte 0x00-0x0D) ตาม spec
/// https://github.com/google/eddystone/blob/master/eddystone-url/README.md
const List<String> _urlSuffixEncoding = [
  '.com/',
  '.org/',
  '.edu/',
  '.net/',
  '.info/',
  '.biz/',
  '.gov/',
  '.com',
  '.org',
  '.edu',
  '.net',
  '.info',
  '.biz',
  '.gov',
];

/// ตาราง scheme prefix ของ Eddystone-URL (byte 0x00-0x03) ตาม spec เดียวกัน
const List<String> _urlSchemePrefixes = [
  'http://www.',
  'https://www.',
  'http://',
  'https://',
];

/// Parse Eddystone service data (จาก service UUID 0000FEAA-...) — pure function
/// ไม่ผูก platform ใด ๆ เรียกได้ทั้ง Android (raw ADV) และ iOS (CoreBluetooth raw
/// service data — Eddystone ไม่ถูก OS mask เหมือน iBeacon เพราะไม่ใช่ Apple format)
///
/// [serviceData] คือ payload ของ Eddystone service data ที่**ตัด 2-byte service
/// UUID (0xFEAA) ออกไปแล้ว** เริ่มต้นด้วย frame-type byte ทันที (0x00/0x10/0x20/0x30)
/// — ตรงกับที่ CoreBluetooth ให้ผ่าน `CBAdvertisementDataServiceDataKey` dict
/// (ดู ARCHITECTURE.md, ADR-4 event channel #2)
///
/// Eddystone-EID (0x30) ยังไม่ implement decode logic ในรอบนี้ (ต้องมี key exchange
/// กับ trusted resolver ก่อนถอดค่าได้จริง) — คืน [ParseFailureReason.unsupportedFrameType]
/// เสมอ
final class EddystoneParser {
  const EddystoneParser._();

  static const int _uidFrameLength = 20;
  static const int _tlmFrameLength = 14;
  static const int _urlFrameMinLength = 3;
  static const int _urlFrameMaxLength = 20;

  static const int _frameTypeUid = 0x00;
  static const int _frameTypeUrl = 0x10;
  static const int _frameTypeTlm = 0x20;
  static const int _frameTypeEid = 0x30;

  static ParseResult<EddystoneFrame> parse(Uint8List serviceData) {
    if (serviceData.isEmpty) {
      return const ParseFailure(
        ParseFailureReason.tooShort,
        detail: 'empty input, expected at least 1 byte for frame type',
      );
    }

    final frameType = serviceData[0];
    switch (frameType) {
      case _frameTypeUid:
        return _parseUid(serviceData);
      case _frameTypeUrl:
        return _parseUrl(serviceData);
      case _frameTypeTlm:
        return _parseTlm(serviceData);
      case _frameTypeEid:
        return const ParseFailure(
          ParseFailureReason.unsupportedFrameType,
          detail:
              'Eddystone-EID (0x30) decode ยังไม่ implement ในรอบนี้ — '
              'ต้องมี key exchange กับ trusted resolver ก่อน',
        );
      default:
        return ParseFailure(
          ParseFailureReason.invalidFrameType,
          detail:
              'unrecognized frame type byte: 0x'
              '${frameType.toRadixString(16).padLeft(2, '0')}',
        );
    }
  }

  static ParseResult<EddystoneFrame> _parseUid(Uint8List data) {
    final length = data.length;
    if (length < _uidFrameLength) {
      return ParseFailure(
        ParseFailureReason.tooShort,
        detail: 'expected total length $_uidFrameLength bytes, got $length',
      );
    }
    if (length > _uidFrameLength) {
      return ParseFailure(
        ParseFailureReason.tooLong,
        detail: 'expected total length $_uidFrameLength bytes, got $length',
      );
    }

    try {
      final txPower = data[1].toSigned(8);
      final namespaceId = _bytesToHex(data.sublist(2, 12));
      final instanceId = _bytesToHex(data.sublist(12, 18));
      // byte[18:20) = reserved, อ่านผ่านเฉยๆ ไม่เก็บ

      return ParseSuccess(
        EddystoneUidFrame(
          namespaceId: namespaceId,
          instanceId: instanceId,
          txPower: txPower,
        ),
      );
    } on RangeError catch (e) {
      return ParseFailure(ParseFailureReason.truncatedField, detail: '$e');
    }
  }

  static ParseResult<EddystoneFrame> _parseUrl(Uint8List data) {
    final length = data.length;
    if (length < _urlFrameMinLength) {
      return ParseFailure(
        ParseFailureReason.tooShort,
        detail: 'expected at least $_urlFrameMinLength bytes, got $length',
      );
    }
    if (length > _urlFrameMaxLength) {
      return ParseFailure(
        ParseFailureReason.tooLong,
        detail: 'expected at most $_urlFrameMaxLength bytes, got $length',
      );
    }

    try {
      final txPower = data[1].toSigned(8);
      final schemeByte = data[2];
      if (schemeByte < 0 || schemeByte >= _urlSchemePrefixes.length) {
        return ParseFailure(
          ParseFailureReason.invalidPrefix,
          detail:
              'invalid URL scheme prefix byte: 0x'
              '${schemeByte.toRadixString(16).padLeft(2, '0')}',
        );
      }

      final buffer = StringBuffer(_urlSchemePrefixes[schemeByte]);
      for (var i = 3; i < length; i++) {
        final byte = data[i];
        if (byte >= 0 && byte < _urlSuffixEncoding.length) {
          buffer.write(_urlSuffixEncoding[byte]);
        } else {
          buffer.writeCharCode(byte);
        }
      }

      return ParseSuccess(
        EddystoneUrlFrame(txPower: txPower, url: buffer.toString()),
      );
    } on RangeError catch (e) {
      return ParseFailure(ParseFailureReason.truncatedField, detail: '$e');
    }
  }

  static ParseResult<EddystoneFrame> _parseTlm(Uint8List data) {
    final length = data.length;
    if (length < _tlmFrameLength) {
      return ParseFailure(
        ParseFailureReason.tooShort,
        detail: 'expected total length $_tlmFrameLength bytes, got $length',
      );
    }
    if (length > _tlmFrameLength) {
      return ParseFailure(
        ParseFailureReason.tooLong,
        detail: 'expected total length $_tlmFrameLength bytes, got $length',
      );
    }

    try {
      final version = data[1];

      final batteryVoltageMv = ((data[2] << 8) | data[3]).toDouble();

      final rawTemp = _toSigned16(((data[4] << 8) | data[5]));
      final double? temperatureC =
          rawTemp ==
              -32768 // 0x8000 as signed 16
          ? null
          : rawTemp / 256.0;

      final advertisingPduCount =
          (data[6] << 24) | (data[7] << 16) | (data[8] << 8) | data[9];

      final timeSincePowerOnRaw =
          (data[10] << 24) | (data[11] << 16) | (data[12] << 8) | data[13];
      final timeSincePowerOn = Duration(
        milliseconds: timeSincePowerOnRaw * 100,
      );

      return ParseSuccess(
        EddystoneTlmFrame(
          version: version,
          batteryVoltageMv: batteryVoltageMv,
          temperatureC: temperatureC,
          advertisingPduCount: advertisingPduCount,
          timeSincePowerOn: timeSincePowerOn,
        ),
      );
    } on RangeError catch (e) {
      return ParseFailure(ParseFailureReason.truncatedField, detail: '$e');
    }
  }

  static int _toSigned16(int value) {
    final masked = value & 0xFFFF;
    return masked >= 0x8000 ? masked - 0x10000 : masked;
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
