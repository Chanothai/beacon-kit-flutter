// Helper สำหรับโหลด ADV packet fixture จาก docs/fixtures/*.json มาใช้ใน
// ibeacon_parser_test.dart / eddystone_parser_test.dart
//
// รูปแบบไฟล์ fixture: ดู docs/fixtures/README.md (หัวข้อ "รูปแบบไฟล์" +
// โน้ตท้ายไฟล์เรื่อง raw_hex ของ beacon_kit sprint นี้)
//
// เป็น pure Dart (dart:io / dart:convert เท่านั้น) ไม่พึ่ง Flutter binding
// เพราะ IBeaconParser / EddystoneParser เป็น pure function ล้วน ๆ

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// หนึ่ง fixture case ที่โหลดมาจากไฟล์ JSON ใน docs/fixtures/
class Fixture {
  final String name;
  final String source;
  final String sourceDetail;
  final String parser; // "ibeacon" | "eddystone"
  final String rawHex;
  final Map<String, dynamic> expect;

  Fixture({
    required this.name,
    required this.source,
    required this.sourceDetail,
    required this.parser,
    required this.rawHex,
    required this.expect,
  });

  factory Fixture.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as String;
    // นโยบายหลักของโปรเจกต์ (docs/fixtures/README.md): ห้ามใส่ source: captured
    // ถ้าไม่ได้จับจากอุปกรณ์จริง — fixture ทั้งหมดในสปรินต์นี้ยังไม่มี K9P จริงอยู่
    // ตรงหน้า จึงต้องเป็น derived_from_sdk_source หรือ vendor_doc เท่านั้น
    if (source == 'captured') {
      throw StateError(
        "Fixture '${json['name']}' ประกาศ source: captured แต่ QA agent "
        'ไม่มีฮาร์ดแวร์จริงให้จับข้อมูล — ผิดนโยบายของ docs/fixtures/README.md',
      );
    }
    return Fixture(
      name: json['name'] as String,
      source: source,
      sourceDetail: json['source_detail'] as String,
      parser: json['parser'] as String,
      rawHex: json['raw_hex'] as String,
      expect: json['expect'] as Map<String, dynamic>,
    );
  }

  /// แปลง raw_hex (อาจว่างเปล่า) เป็น Uint8List — byte ที่ป้อนตรงเข้า parser
  Uint8List get bytes {
    if (rawHex.isEmpty) return Uint8List(0);
    assert(rawHex.length.isEven, 'raw_hex ต้องมีจำนวนตัวอักษรคู่เสมอ: $name');
    final out = Uint8List(rawHex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(rawHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

/// หา docs/fixtures/ โดยไล่ขึ้นจาก cwd — ทำแบบนี้เพื่อให้ทดสอบผ่านได้ไม่ว่าจะรัน
/// `flutter test` จาก root ของ package นี้เอง หรือจาก root ของ repo ทั้งก้อน
Directory _findFixturesDir() {
  var dir = Directory.current;
  while (true) {
    final candidate = Directory('${dir.path}/docs/fixtures');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'ไม่พบ docs/fixtures/ เมื่อไล่ค้นขึ้นไปจาก ${Directory.current.path} — '
        'ต้องรันเทสต์นี้จากภายใน repo beacon-kit',
      );
    }
    dir = parent;
  }
}

/// โหลด fixture ทุกไฟล์ใน docs/fixtures/ ที่ field "parser" ตรงกับที่ระบุ
/// (ไม่รบกวน fixture อื่น ๆ ที่ไม่เกี่ยวกับ IBeaconParser/EddystoneParser เช่น
/// Ksensor ในอนาคต)
List<Fixture> loadFixturesFor(String parser) {
  final dir = _findFixturesDir();
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final fixtures = <Fixture>[];
  for (final file in files) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) continue;
    if (decoded['parser'] != parser) continue;
    fixtures.add(Fixture.fromJson(decoded));
  }
  return fixtures;
}
