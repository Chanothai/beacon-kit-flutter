/// ระดับสิทธิ์ location ปัจจุบันที่มีผลต่อ iBeacon monitoring — ตาม
/// ARCHITECTURE.md ADR-6 หัวข้อ 3 และ 5 (B6)
///
/// **ทำไมต้องมี type นี้แยกจาก error code ของ `startIBeaconMonitoring`:**
/// `startIBeaconMonitoring` คืน `void`/`PlatformException` เท่านั้น (ADR-6
/// หัวข้อ 2 ล็อก signature เดิมไว้ ไม่ให้แก้) แต่ `.authorizedWhenInUse` กับ
/// `.authorizedAlways` ต่าง**ทำให้ start สำเร็จเหมือนกันทั้งคู่** (ranging/
/// monitoring เริ่มทำงานได้ทั้งสองระดับ — ต่างกันแค่เรื่อง background wake หลัง
/// แอปโดน terminate ที่ต้องมี Always เท่านั้น) ถ้า caller รู้แค่ว่า
/// `startIBeaconMonitoring` สำเร็จ (`null`) จะเข้าใจผิดได้ง่ายว่า background
/// monitoring ทำงานได้เต็มรูปทั้งที่จริงอาจได้แค่ whenInUse — ต้อง query ระดับ
/// สิทธิ์จริงแยกต่างหากผ่าน `getIBeaconAuthorizationLevel()`
///
/// **[whenInUse] ครอบคลุมทั้ง "Allow Once" ชั่วคราวและ "When In Use" ถาวร —
/// ตั้งใจไม่แยกย่อย:** ยืนยันจาก Apple docs (ARCHITECTURE.md ADR-6 หัวข้อ 5) ว่า
/// `CLAuthorizationStatus` ไม่มีเคส "Allow Once" แยก ทั้งสองกรณีรายงานเป็น
/// `.authorizedWhenInUse` เหมือนกัน native จึงแยกไม่ได้จริง การตั้งชื่อ enum
/// แยกย่อยเป็น "allowOnce"/"whenInUsePermanent" จะสร้างภาพลวงว่าระบบรู้ในสิ่งที่
/// ไม่รู้ — ผู้เรียกที่ต้องการ background wake ที่มั่นใจได้ ต้องเช็คแค่
/// `== IBeaconAuthorizationLevel.always` เท่านั้น ไม่ว่า whenInUse จะมาจากเคส
/// ไหนก็ตาม
enum IBeaconAuthorizationLevel {
  /// Always — background wake หลังแอปโดน terminate ทำงานได้ (ranging + region
  /// monitoring ครบ ตาม ADR-6 หัวข้อ 3)
  always,

  /// When In Use (ถาวรหรือ Allow Once ชั่วคราว แยกไม่ออกจากค่านี้อย่างเดียว) —
  /// ทำงานได้เฉพาะตอนแอปยัง foreground/suspended เท่านั้น **ไม่ปลุกแอปที่ถูก
  /// terminate**
  whenInUse,

  /// notDetermined/denied/restricted — ไม่มีการ monitor ใด ๆ เกิดขึ้นเลย
  insufficient,
}

/// แปลงค่า string ที่ native ส่งมา (`"always" | "whenInUse" | "insufficient"`)
/// เป็น [IBeaconAuthorizationLevel] — ค่าที่ไม่รู้จักถือว่า [insufficient] เพื่อ
/// ความปลอดภัย (ไม่สมมติว่าปลอดภัยกว่าความจริง)
IBeaconAuthorizationLevel parseIBeaconAuthorizationLevel(String value) {
  switch (value) {
    case 'always':
      return IBeaconAuthorizationLevel.always;
    case 'whenInUse':
      return IBeaconAuthorizationLevel.whenInUse;
    default:
      return IBeaconAuthorizationLevel.insufficient;
  }
}
