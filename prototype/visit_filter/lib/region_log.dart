/// ตัวอ่านไฟล์หลักฐานใน `docs/test-data/` — เครื่องมือประกอบ ไม่ใช่ชั้นกรอง
///
/// แยก library ออกมาเพราะพึ่ง `dart:io` ส่วน `visit_filter.dart` เป็น Dart ล้วน
/// ที่รันที่ไหนก็ได้และพอร์ตไป Kotlin/Swift ได้ตรง ๆ
library;

export 'src/region_log.dart';
