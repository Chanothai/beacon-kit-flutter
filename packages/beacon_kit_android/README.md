# beacon_kit_android

ส่วนหนึ่งของ federated plugin `beacon_kit` — implementation ฝั่ง Android (Kotlin)

## ใครควร depend ตรงนี้

**แอปที่ต้องการ background region monitoring บน Android ต้อง depend package
นี้ตรง ๆ เพิ่มจาก `beacon_kit`** — `BeaconKitAndroid` (permission methods,
background region monitoring) ไม่ได้ถูกยกขึ้นสัญญากลาง
(`beacon_kit_platform_interface`) เพราะ Android ทำไม่ได้เทียบเท่า iOS ในเส้นทาง
นี้ ดูตัวอย่างการเรียกที่ [README หลัก](../../README.md) §Quick start

แอปที่ใช้แค่การสแกนตอนเปิดแอปอยู่ (ไม่ต้องการ background) ไม่ต้อง depend
package นี้ตรง ๆ — `beacon_kit` เพียงพอ

## เอกสารหลัก

- [README หลัก](../../README.md) — วิธีใช้งานทั่วไป
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) — เหตุผลของ federated plugin pattern
