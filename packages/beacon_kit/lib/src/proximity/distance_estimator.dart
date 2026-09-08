import 'dart:math' as math;

/// ประมาณระยะทาง (เมตร) จาก RSSI + txPower ด้วย log-distance path loss model
/// — pure function ล้วน: byte/ตัวเลขเข้า → ตัวเลขออก ไม่มี I/O ไม่แตะ BLE API
/// ใด ๆ เพื่อให้ทดสอบด้วย fixture ได้ 100% โดยไม่ต้องมีอุปกรณ์จริง
///
/// สูตร: `d = 10 ^ ((txPower − rssi) / (10 × n))` โดย `n` คือ [pathLossExponent]
/// — จัดรูปจากสมการ log-distance path loss ของ Rappaport §4.11.3 (ยืนยันแหล่งที่มา
/// ที่ `docs/sources/rssi_path_loss_model.md` หัวข้อ 1-2)
///
/// อ้างอิง: ARCHITECTURE.md ADR-19 หัวข้อ 4 ข้อ 2 (ลำดับการตัดสินที่ต้องคำนวณ
/// ระยะเมื่อ `proximity` เป็น `null` แต่ `rssi`/`ibeaconTxPower` มีครบ)
///
/// **[pathLossExponent] เป็น required parameter โดยตั้งใจ — ห้ามมี default ซ่อน
/// อยู่ในฟังก์ชันนี้:** `docs/sources/rssi_path_loss_model.md` หัวข้อ 1 ยืนยันว่า
/// ค่า `n` ผันผวนตามสถานที่จริงมาก (n=2.30 กับ n=2.98 จากสอง office ที่วัดจริง
/// คนละแห่ง, ช่วงกว้าง 1.6–6 ตามที่ Rappaport ระบุ) การใส่ default ในฟังก์ชัน
/// ระดับ pure นี้จะเป็นการกลืนการตัดสินใจทางธุรกิจ/สถานที่ไปแบบเงียบ ๆ โดยผู้เรียก
/// ไม่รู้ตัว — ผู้เรียก (`ProximityGate`) ต้องเป็นคนตัดสินใจค่านี้เองเสมอ (ค่า
/// default ระดับ POC ตาม ADR-19 §8 อยู่ที่ตัว `ProximityGate` เท่านั้น ไม่ใช่ที่นี่)
///
/// **ข้อจำกัดของโมเดล (ต้องอ่านก่อนใช้ผลลัพธ์):** ค่าที่คืนกลับ**ไม่ใช่ระยะทางที่
/// แม่นยำ** เป็นแค่ค่าประมาณจากคณิตศาสตร์ของโมเดล — ที่ระยะไกล (เช่น 9m เทียบกับ
/// 11m) ผลต่าง RSSI ระหว่างสองระยะจมอยู่ใต้ noise ตามธรรมชาติของสัญญาณ แยกแยะไม่ได้
/// จริง (ดู `docs/sources/rssi_path_loss_model.md` หัวข้อ 3) ห้ามใช้ค่าตัวเลขที่ได้
/// จากฟังก์ชันนี้ไปแสดงผลราวกับเป็นตำแหน่งที่แม่นยำ — เหตุผลเดียวกับที่ ADR-19
/// หัวข้อ 2 เลือกแสดงผลเป็น bucket (`BeaconProximity`) แทนตัวเลขเมตรตรง ๆ
double estimateDistanceMeters({
  required int rssi,
  required int txPower,
  required double pathLossExponent,
}) {
  return math.pow(10, (txPower - rssi) / (10 * pathLossExponent)).toDouble();
}
