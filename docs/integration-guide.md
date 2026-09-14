# Integration guide

เอกสารนี้ขยาย `README.md` ในส่วนที่ลึกเกินไปสำหรับหน้าแรก — สิ่งที่ host app
ต้องทำเองรอบ `beacon_kit` ทั้งหมด SDK นี้ให้แค่ **event ดิบ** เท่านั้น

## 1. Setup ทีละขั้น

### iOS

ใส่ key เหล่านี้ใน `Info.plist` ของแอป (ตัวอย่างครบใน
[`packages/beacon_kit/example/ios/Runner/Info.plist`](../packages/beacon_kit/example/ios/Runner/Info.plist)):

| Key | จำเป็นเมื่อ |
|---|---|
| `NSLocationWhenInUseUsageDescription` | สแกน iBeacon ขณะใช้งานแอป |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | ต้องการ background region monitoring |
| `NSBluetoothAlwaysUsageDescription` | สแกน non-iBeacon (Eddystone) ผ่าน CoreBluetooth |
| `UIBackgroundModes` = `location`, `bluetooth-central` | ทำงานต่อเนื่องตอน background |

iOS ไม่ให้แอปขอสิทธิ์ Always ซ้ำเองหลังผู้ใช้เลือก When In Use ไปแล้ว — ถ้าต้องการ
Always ต้องพาผู้ใช้ไปที่ Settings เอง (ยืนยันจาก
[`example/lib/main.dart:1180-1181`](../packages/beacon_kit/example/lib/main.dart#L1180-L1181)
ซึ่งเป็นสิ่งที่ example ทำจริงตอนนี้ ไม่ใช่ progressive request อัตโนมัติ)

### Android

สิทธิ์ที่ plugin ประกาศให้เองใน manifest แล้ว (ยืนยันจาก
[`AndroidManifest.xml`](../packages/beacon_kit_android/android/src/main/AndroidManifest.xml)):

| สิทธิ์ | ประเภท | หมายเหตุ |
|---|---|---|
| `BLUETOOTH_SCAN` | runtime (Android 12+) | ต้องขอเองผ่าน `requestScanPermissions()` |
| `ACCESS_FINE_LOCATION` | runtime | จำเป็นเสมอ — ไม่ใช้ flag `neverForLocation` เพราะ use case คือการอนุมานตำแหน่งตรงตัว |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` | install-time (maxSdk 30) | เครื่องต่ำกว่า Android 12 เท่านั้น |
| `RECEIVE_BOOT_COMPLETED` | install-time | ลงทะเบียน region ใหม่หลังรีบูต |

`POST_NOTIFICATIONS` (จำเป็นบน Android 13+) **ไม่ได้อยู่ในสิทธิ์ของ plugin เลย** —
เป็นหน้าที่ host app ขอเอง โค้ดตัวอย่างจริงอยู่ที่
[`example/.../MainActivity.kt:189-232`](../packages/beacon_kit/example/android/app/src/main/kotlin/com/beaconkit/example/MainActivity.kt#L189-L232)
และ [`AndroidManifest.xml:15`](../packages/beacon_kit/example/android/app/src/main/AndroidManifest.xml#L15)
ของ example app เอง (ไม่ใช่ของ plugin)

แอปที่ต้องการ background region monitoring บน Android ต้อง depend
`beacon_kit_android` ตรง ๆ เพิ่มจาก `beacon_kit` เพราะ `BeaconKitAndroid`
ไม่ได้ยกขึ้นสัญญากลาง (platform interface) — ดูตัวอย่างใน `README.md` §Quick start

## 2. Flow สองชั้น — region ก่อน แล้วค่อย proximity

1. **ชั้น 1: region enter/exit** — หยาบ บอกแค่ "อยู่ในระยะรับสัญญาณของ region
   นี้หรือไม่" ทำงานได้ทั้ง foreground/background บนทั้งสองแพลตฟอร์ม
   ([ADR-6](../ARCHITECTURE.md#adr-6-จาก-ranging-only-เป็น-region-monitoring-enterexit--เพิ่ม-28-สค-2026))
2. **ชั้น 2: proximity (`ProximityGate`)** — ละเอียดกว่า ตัดสิน bucket
   (`immediate`/`near`/`far`/`unknown`) จาก RSSI ของแต่ละ sample ที่ไหลเข้ามา
   *หลังจาก* ชั้น 1 ยืนยันว่าอยู่ใน region แล้วเท่านั้น ไม่ใช่ตัวแทนของชั้น 1
   ([ADR-19](../ARCHITECTURE.md#adr-19-proximitygate--ชั้นตัดสินใจ-ใกล้พอหรือยัง-จาก-rssiproximity-ระดับ-dart-เพิ่ม-8-กย-2026))

ชั้น 2 ต้องมี sample ไหลเข้ามาก่อนเสมอ — ถ้าไม่มีการ scan/ranging อยู่แล้ว
`ProximityGate` จะไม่มีอะไรให้ตัดสิน

## 3. Notification สองระดับ — ทำไม iOS กับ Android ต่างกัน

แนวคิดที่ใช้ทั้งสองแพลตฟอร์ม: แจ้งเตือนทั่วไปตอน **enter** region (ชั้น 1) กับ
แจ้งเตือนเจาะจงกว่าตอนเข้าสู่ bucket **near**/`immediate` (ชั้น 2) — ตัวกรองว่าจะ
แจ้งเตือนเมื่อไรอยู่ที่ **example app ไม่ใช่ SDK** ทั้งคู่

พฤติกรรมของชั้น 2 ตอน background ไม่เท่ากันระหว่างสองแพลตฟอร์มโดยธรรมชาติของ
แพลตฟอร์มเอง ไม่ใช่ทางเลือกของ SDK:

- **Android** ([ADR-20](../ARCHITECTURE.md#adr-20-proximitygate-ตอนแอปไม่ทำงาน--port-ตรรกะเป็น-kotlin-ใน-beaconscanreceiver-เพิ่ม-9-กย-2026)) —
  RSSI มาพร้อมกับ `ScanResult` ที่ระบบส่งให้อยู่แล้วตอน background จึงคำนวณ bucket
  ได้เต็มรูปแบบเหมือนตอน foreground คีย์ของบีคอนอ่านจากเฟรมจริง (ไม่ใช่จาก region
  spec ที่ลงทะเบียนไว้)
- **iOS** ([ADR-21](../ARCHITECTURE.md#adr-21-proximitygate-ฝั่ง-ios--port-เป็น-swift-ใน-ibeaconrangingmanager-เพิ่ม-10-กย-2026),
  [ADR-22](../ARCHITECTURE.md#adr-22-ชั้นที่-2-ตอน-background--proximitygate-ตัวที่สองที่ตั้งค่าแบบ-passthrough-เพิ่ม-10-กย-2026)) —
  CoreLocation ให้ sample เบื้องหลังในอัตราที่ต่างจาก foreground มาก ค่า default
  ของ ADR-19 §8 (ออกแบบมาสำหรับ foreground) ใช้ไม่ได้กับอัตรานั้น ชั้น 2 ตอน
  background บน iOS จึงเป็น **`ProximityGate` instance ที่สอง ตั้งค่าแบบ
  passthrough** (ผ่อน `windowSize`/`dwellSamples` และปิด `staleAfter` เพราะ
  สัญญาณ "หายจริง" ของ background ใช้ `didExitRegion` จาก iOS เองแทน) —
  **ARCHITECTURE.md ADR-22 ระบุไว้ตรง ๆ ว่า latency ของชั้นนี้ไม่เสถียรและห้าม
  สัญญาตัวเลขใด ๆ กับ product** — เอกสารนี้จึงไม่ลอกตัวเลขมาด้วยเหตุผลเดียวกัน

## 4. Outbox pattern (at-least-once)

**ไม่มีโค้ดของเรื่องนี้ใน `beacon_kit` เลย** (ไม่มี dependency เครือข่ายใด ๆ ใน
`packages/beacon_kit/pubspec.yaml`) — คำแนะนำสถาปัตยกรรมสำหรับ host app เท่านั้น:

- เขียน event ที่จะส่งขึ้น server ลง queue ในเครื่องก่อนเสมอ (ห้ามพึ่งพา
  network call สำเร็จภายใน callback ของ SDK โดยตรง — callback อาจถูกเรียกตอน
  background ที่เวลาทำงานถูกจำกัด)
- ผูก **idempotency key** กับแต่ละ event (เช่น `regionIdentifier` + timestamp)
  เพราะ retry ของ at-least-once queue ทำให้ event เดิมถูกส่งซ้ำได้
- ฝั่งที่ดันคิวออกจริง: `WorkManager` บน Android, background `URLSession`
  (หรือ `BGTaskScheduler`) บน iOS — ทั้งคู่เป็นกลไกของระบบที่ทนต่อแอปถูกฆ่าได้
  ดีกว่าการยิง network เองตรง ๆ ใน callback

## 5. Mapping table (major/minor → สาขา/โซน) + cache

**ไม่มีโค้ดรองรับเรื่องนี้ใน `beacon_kit` เลยเช่นกัน** — SDK ให้แค่ major/minor
ดิบ การแปลเป็นชื่อสาขา/โซนเป็นหน้าที่ host app ทั้งหมด อ้างอิง UUID scheme กลาง
ได้จาก [ADR-5](../ARCHITECTURE.md#adr-5-bigc-id-scheme-สำหรับ-multi-vendor-provisioning-เพิ่ม-28-สค-2026)
และ [`docs/sources/bigc_provisioning.md`](sources/bigc_provisioning.md) — แนะนำ
cache ตารางนี้ไว้ในเครื่อง (ไม่ต้อง round-trip ไป server ทุกครั้งที่มี event เข้ามา)
แล้ว invalidate เมื่อมีการเพิ่ม/ย้ายบีคอนเท่านั้น

## 6. Consent / PDPA

ข้อมูลตำแหน่งที่ SDK ส่งให้ (region ที่อยู่ใกล้, ระยะโดยประมาณ) เข้าข่ายข้อมูล
ส่วนบุคคลตามกฎหมายคุ้มครองข้อมูลส่วนบุคคล — **ไม่มีเอกสาร PDPA เฉพาะของ
โปรเจกต์นี้อยู่ในตอนนี้** และไม่ใช่ขอบเขตของ SDK repo นี้ที่จะกำหนด กลไกขอ
ความยินยอม/แจ้งวัตถุประสงค์เป็นหน้าที่ host app ทั้งหมด — ปรึกษาทีมกฎหมาย/
compliance ของบริษัทก่อนเก็บหรือส่งข้อมูลตำแหน่งขึ้น server จริง

## 7. ตัวอย่างค่าเริ่มต้นของ `ProximityGate` (ADR-19 §8)

ค่าเหล่านี้คือ**ค่าตั้งต้นสำหรับ POC เท่านั้น** — คัดจาก
[`packages/beacon_kit/example/lib/main.dart:42-62`](../packages/beacon_kit/example/lib/main.dart#L42-L62):

| พารามิเตอร์ (ค่าอ้างอิงฝั่ง Dart — foreground) | ค่าตั้งต้น |
|---|---|
| `enterMeters` | 3.0 |
| `exitMeters` | 5.0 |
| `immediateMeters` | 1.0 |
| `windowSize` | 5 |
| `dwellSamples` | 3 |
| `pathLossExponent` | 2.5 |
| `staleAfter` | 10 วินาที |

ชั้น background ใช้ค่าคนละชุดต่อแพลตฟอร์ม (ดูหัวข้อ 3 ด้านบน) — ตัวอย่างเช่น
`staleAfterMillis` บน Android ตั้งเป็น `60_000L`
([`ProximityGate.kt:199`](../packages/beacon_kit_android/android/src/main/kotlin/com/bigc/beacon_kit_android/ProximityGate.kt#L199))
ขณะที่ฝั่ง Swift ตั้งเป็น 24 ชั่วโมง = ปิด stale โดยพฤตินัย
([`IBeaconRangingManager.swift:883`](../packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift#L883))

**ยังไม่ผ่านการ calibrate กับสาขาจริง — ห้ามใช้เป็นค่า production โดยไม่ผ่านรอบ
เก็บข้อมูลภาคสนามก่อน** (คำเตือนนี้มาจาก
[ARCHITECTURE.md ADR-19 §8](../ARCHITECTURE.md#8-ค่าตั้งต้นของ-sdk-สำหรับ-poc--ไม่ใช่ค่าที่ได้จากภาคสนาม)
ตรง ๆ ไม่ใช่คำเตือนที่เอกสารนี้เติมเอง)

---

ดู [`README.md`](../README.md) สำหรับภาพรวมสั้น และ
[`ARCHITECTURE.md`](../ARCHITECTURE.md) สำหรับ ADR ฉบับเต็มของทุกหัวข้อข้างบน
