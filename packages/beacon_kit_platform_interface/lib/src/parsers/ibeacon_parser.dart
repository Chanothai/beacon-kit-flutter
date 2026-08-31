import 'dart:typed_data';

import '../entities/ibeacon_frame.dart';
import 'parse_result.dart';

/// Parse Apple manufacturer-specific data (company ID 0x004C, frame prefix 0x02 0x15)
/// เป็น [IBeaconFrame] — byte layout ยืนยันแล้วจากการเทียบ KBUtility.java (KKM SDK)
/// กับ BeaconParser.kt (Flutter plugin สาธารณะ) ดูหัวข้อ "ข้อค้นพบสำคัญ: iBeacon
/// เป็นฟอร์แมตมาตรฐานตัวเดียว" ใน ARCHITECTURE.md
///
/// **เรียกใช้บน Android เท่านั้น** — ห้ามเรียกจากโค้ด iOS เพราะ:
/// - CoreBluetooth บน iOS mask manufacturer data ของ iBeacon ทิ้งตั้งแต่ระดับ OS
///   (เห็นแค่ peripheral identifier + RSSI ไม่มี byte ให้ parse เลย)
/// - iBeacon บน iOS มาทาง CoreLocation ซึ่งถอด uuid/major/minor ให้เป็น typed field
///   อยู่แล้วโดย OS โดยตรง ไม่ผ่านการ parse byte ใด ๆ ในฝั่ง Dart (ดู ADR-2,
///   AdvertisementSource.osDecoded)
/// เรียก parser ตัวนี้บน iOS จะไม่มี manufacturerData ที่ valid ให้ป้อนเข้ามาตั้งแต่ต้น
///
/// สปรินต์หน้า (Android) — ถ้าใช้ Android `ScanRecord.getManufacturerSpecificData(0x004C)`
/// ซึ่ง Android SDK จะ**ตัด company ID ออกไปแล้ว** โค้ดฝั่ง Android platform channel
/// ต้องต่อ `[0x4C, 0x00]` กลับเข้าไปข้างหน้าก่อนเรียกฟังก์ชันนี้ เพราะ [parse] คาดหวัง
/// [manufacturerData] เป็น AD structure value เต็มของ type 0xFF รวม company ID
/// prefix ด้วย (ความยาวรวมต้องเป็น 25 bytes พอดี)
///
/// Byte layout ที่คาดหวัง (25 bytes พอดี):
/// - byte\[0:2) = company ID, little-endian = `0x4C 0x00` (Apple)
/// - byte\[2] = `0x02` (iBeacon type)
/// - byte\[3] = `0x15` (length = 21, คงที่)
/// - byte\[4:20) = UUID 16 bytes
/// - byte\[20:22) = major, big-endian
/// - byte\[22:24) = minor, big-endian
/// - byte\[24] = txPower, signed 8-bit
final class IBeaconParser {
  const IBeaconParser._();

  static const int _expectedLength = 25;

  static ParseResult<IBeaconFrame> parse(Uint8List manufacturerData) {
    final length = manufacturerData.length;

    if (length < _expectedLength) {
      return ParseFailure(
        ParseFailureReason.tooShort,
        detail: 'expected total length $_expectedLength bytes, got $length',
      );
    }
    if (length > _expectedLength) {
      return ParseFailure(
        ParseFailureReason.tooLong,
        detail: 'expected total length $_expectedLength bytes, got $length',
      );
    }

    final companyIdOk =
        manufacturerData[0] == 0x4C && manufacturerData[1] == 0x00;
    final iBeaconPrefixOk =
        manufacturerData[2] == 0x02 && manufacturerData[3] == 0x15;
    if (!companyIdOk || !iBeaconPrefixOk) {
      return const ParseFailure(
        ParseFailureReason.invalidPrefix,
        detail: 'expected company ID 4C 00 and frame prefix 02 15 at byte[0:4)',
      );
    }

    try {
      final uuidBytes = manufacturerData.sublist(4, 20);
      final uuid = _formatUuid(uuidBytes);

      final major = (manufacturerData[20] << 8) | manufacturerData[21];
      final minor = (manufacturerData[22] << 8) | manufacturerData[23];
      final txPower = manufacturerData[24].toSigned(8);

      return ParseSuccess(
        IBeaconFrame(uuid: uuid, major: major, minor: minor, txPower: txPower),
      );
    } on RangeError catch (e) {
      return ParseFailure(ParseFailureReason.truncatedField, detail: '$e');
    }
  }

  static String _formatUuid(List<int> bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
