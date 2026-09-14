# beacon_kit

ส่วนหนึ่งของ federated plugin `beacon_kit` — facade เดียวที่แอปเรียกใช้ ไม่เห็น
คลาสของยี่ห้อใดหรือของแพลตฟอร์มใดโดยตรง

## ใครควร depend ตรงนี้

ทุกแอปที่ใช้ `beacon_kit` — ดู [README หลัก](../../README.md) สำหรับวิธีติดตั้ง
และตัวอย่างการใช้งานเต็ม ๆ

**ข้อยกเว้น:** แอปที่ต้องการ background region monitoring บน Android ต้อง
depend `beacon_kit_android` ตรง ๆ เพิ่มด้วย (ดู
[README ของ `beacon_kit_android`](../beacon_kit_android/README.md))

## เอกสารหลัก

- [README หลัก](../../README.md) — วิธีใช้งานทั่วไป
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) — เหตุผลของ federated plugin pattern
