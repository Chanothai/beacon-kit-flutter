/// สัญญากลางของชั้นกรอง visit — ตัวสร้างและตัวเล่นไฟล์ `spec/visit_filter/vectors.json`
///
/// แยก library ออกจาก `visit_filter.dart` เพราะ **ไม่ใช่ส่วนหนึ่งของชั้นกรอง**
/// port ฝั่ง Kotlin/Swift ไม่ต้องพอร์ตไฟล์พวกนี้ ต้องพอร์ตแค่ตัวอ่านไฟล์ vector
library;

export 'src/conformance.dart';
export 'src/conformance_cases.dart';
export 'src/vector_document.dart';
