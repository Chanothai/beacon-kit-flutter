# beacon_kit_platform_interface

ส่วนหนึ่งของ federated plugin `beacon_kit` — สัญญา method channel กลาง
(federated plugin contract) ที่ `beacon_kit_android`/`beacon_kit_ios` implement

## ใครควร depend ตรงนี้

ปกติแอปไม่ต้อง depend package นี้ตรง ๆ — ใช้ `beacon_kit` (ดู
[README หลัก](../beacon_kit/README.md)) ซึ่งดึง `beacon_kit_platform_interface`
เข้ามาให้เอง

## เอกสารหลัก

- [`beacon_kit` README](../beacon_kit/README.md) — วิธีใช้งานทั่วไป
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) — เหตุผลของ federated plugin pattern
