// สร้างไฟล์ conformance vector ที่ทั้งสามภาษาต้องให้ผลตรงกัน
//
//   dart run bin/generate_vectors.dart
//
// ไฟล์ผลลัพธ์ `spec/visit_filter/vectors.json` **ต้อง commit ทุกครั้ง** — มันคือ
// สัญญา ไม่ใช่ build artifact · เทสต์ `conformance_test.dart` จะล้มถ้าไฟล์ที่
// commit ไว้ไม่ตรงกับพฤติกรรมของโค้ดปัจจุบัน
import 'dart:convert';
import 'dart:io';

import 'package:visit_filter_prototype/conformance.dart';

const String repoRoot = '../..';
const String outputPath = '../../spec/visit_filter/vectors.json';

void main() {
  final document = buildVectorDocument(repoRoot: repoRoot);
  const encoder = JsonEncoder.withIndent('  ');
  File(outputPath).writeAsStringSync('${encoder.convert(document)}\n');
  final cases = (document['cases']! as List<Object?>).length;
  stdout.writeln('เขียน $outputPath แล้ว — $cases เคส');
}
