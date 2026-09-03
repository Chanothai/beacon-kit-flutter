# iOS Broadcast Scanning — Hardware-in-the-loop Checklist

> ## 📍 ไฟล์นี้เป็น "เจ้าของสถานะ" ของทุกเคสทดสอบ
>
> **ผ่าน / ไม่ผ่าน / ยังไม่ทดสอบ / ตัวเลขที่วัดได้ ทั้งหมดบันทึกที่ไฟล์นี้ที่เดียว**
>
> ถ้าจะ **ลงมือทดสอบ** ให้เปิด
> [`ios_device_test_runbook.md`](./ios_device_test_runbook.md) แทน — ไฟล์นั้นเป็น
> เจ้าของ**ขั้นตอน** เขียนสำหรับคนที่ถืออุปกรณ์อยู่หน้างาน และ**ห้ามมีสถานะอยู่ในนั้น
> เลย** เพื่อไม่ให้สองไฟล์บันทึกเรื่องเดียวกันแล้วไม่ตรงกัน (CONTRIBUTING ข้อ 8)
>
> เลขข้อในไฟล์นี้คือเลขที่ runbook อ้างถึง — ถ้าเพิ่มข้อใหม่ ต้องอัปเดตตารางลำดับ
> ใน runbook §1 ด้วย

**Track:** B (ต้องมีฮาร์ดแวร์จริงถึงจะ "ยืนยัน" ได้ — ดู `SPRINT.md`)

**สถานะก่อนรันเช็คลิสต์นี้:** `beacon_kit_ios` + `beacon_kit` + `beacon_kit/example`
เป็น **code-complete, unverified** — `flutter analyze` สะอาด, unit/widget test
(mock ที่ระดับ platform/method channel เอง ดู `packages/beacon_kit_ios/test/`,
`packages/beacon_kit/test/`) ผ่านหมด, และ `flutter build ios --debug
--no-codesign` คอมไพล์ Swift ผ่าน Xcode จริงแล้ว — **แต่ยังไม่เคยรันบนอุปกรณ์จริง
กับ K9P เลย** ห้ามอ้างว่า "ใช้งานได้จริง/ทดสอบผ่านแล้ว" จนกว่าจะทำเช็คลิสต์นี้ครบ
พร้อมหลักฐาน (log จากเครื่องจริง หรือคนยืนยัน) ตามข้อห้ามเด็ดขาดข้อ 1-2 ของ
`SPRINT.md`

## ข้อกำหนดก่อนเริ่ม (ห้ามข้าม)

- **ห้ามใช้ iOS Simulator เด็ดขาด** — Simulator ไม่มี Bluetooth radio จริง จำลอง
  CoreBluetooth central scan ไม่ได้เลย (ดู `SPRINT.md` ตาราง Track B แถว "iOS
  platform channel") ต้องใช้ **iPhone จริง** เท่านั้น เสียบสายหรือรันผ่าน
  wireless debugging ก็ได้ แต่ต้องเป็นอุปกรณ์จริง
- ต้องมี K9P จริงอย่างน้อย 1 ตัว, แบตเตอรี่พอ, รู้ค่า factory default ของ UUID ที่
  broadcast (`7777772E-6B6B-6D63-6E2E-636F6D000001` ตามที่ระบุใน
  `packages/beacon_kit/example/lib/main.dart`)
- เปิด Xcode console (หรือ `flutter logs` / `idevicesyslog`) ควบคู่ไปด้วยทุกขั้น
  ตอน เพื่อดู log ฝั่ง native (`BeaconKitIosPlugin.swift`) เวลาเกิด error หรือ
  พฤติกรรมที่ UI มองไม่เห็นตรง ๆ (เช่น background mode)
- รันจาก `packages/beacon_kit/example` ด้วย `flutter run --release` หรือ
  `--debug` บนอุปกรณ์จริง (`flutter devices` ต้องเห็น physical iPhone ไม่ใช่
  simulator ในรายการก่อนรัน)

## ผลลัพธ์ที่ต้องบันทึกหลังทำเช็คลิสต์นี้เสร็จ

สำหรับแต่ละข้อด้านล่าง บันทึก: ผ่าน/ไม่ผ่าน, วันที่ทดสอบ, รุ่น iOS/iPhone,
รุ่น/firmware K9P, และ log หรือภาพหน้าจอเป็นหลักฐานประกอบ ถ้าข้อไหนไม่ผ่าน
ห้ามแก้ `lib/`/native code เอง (QA ไม่แก้โค้ด) ให้รายงานกลับ `flutter-dev`
พร้อมขั้นตอน reproduce ที่ชัดเจน

---

## 1. Permission prompt ครั้งแรก

- [ ] ลบแอปออกจากเครื่อง (หรือใช้เครื่องที่ยังไม่เคย grant permission) แล้วรันแอป
      ใหม่ กด "Start scan" ครั้งแรก
- [ ] ต้องเห็น **prompt ของ OS จริง** ขอ Location permission (When In Use หรือ
      Always ตามที่ `Info.plist`/native code ร้องขอ) ขึ้นมา — ไม่ crash ระหว่างรอ
      user ตอบ
- [ ] ต้องเห็น prompt ขอ Bluetooth permission (ถ้า iOS เวอร์ชันนั้นแยก prompt
      ออกจาก Location) ขึ้นมาเช่นกัน
- [ ] กด "Allow"/"Don't Allow" ทั้งสองแบบ แล้วตรวจว่าแอปไม่ crash ทั้งสองเคส —
      เคส "Don't Allow" ต้องเห็น error banner ในหน้า example app (คาดว่า
      `LOCATION_PERMISSION_DENIED` หรือ `BLUETOOTH_PERMISSION_DENIED` ตาม ADR-4
      ใน `ARCHITECTURE.md`)

### 🐞 บั๊กที่เจอจากการทดสอบบน iPhone จริง — รอบที่ 1 (27 ส.ค. 2026)

**รายงานโดย:** ผู้ใช้ (เจ้าของโปรเจกต์) จากการรันบนเครื่องจริง — ไม่ใช่ผลจาก unit
test หรือการวิเคราะห์โค้ด นี่เป็นหลักฐานระดับ "ทดสอบจริง" ตาม `SPRINT.md`

**อาการ:** เปิดแอปครั้งแรกบนเครื่องที่ยังไม่เคย grant permission แล้วกด Start scan
→ system prompt ขึ้นถูกต้อง แต่ **ต่อให้กด Allow ranging ก็ไม่เริ่ม** ต้องกด Start
scan ซ้ำอีกรอบถึงจะทำงาน

**สาเหตุ:** `IBeaconRangingManager.startMonitoring()` เรียก
`requestAlwaysAuthorization()` แล้วอ่าน authorization status ต่อทันทีแบบ
synchronous ซึ่ง**ยังเป็น `.notDetermined` เสมอ** เพราะ prompt เพิ่งขึ้นบนจอ ผู้ใช้
ยังไม่ทันกดตอบ โค้ดจึงคืน `LOCATION_PERMISSION_DENIED` แล้วจบ ไม่มีอะไรมาเริ่ม
ranging ให้หลังผู้ใช้กด Allow — CoreLocation คืนผลของ prompt ผ่าน delegate
เท่านั้น ไม่มีทางอ่านได้แบบ synchronous

**แก้แล้ว (27 ส.ค. 2026):** ย้ายการเริ่ม `startRangingBeacons` ไปรอ
`locationManagerDidChangeAuthorization(_:)` — เคส `.notDetermined` จะพักคำขอไว้ใน
`pendingStart` (ไม่เรียก `FlutterResult` ทันที) แล้วให้ delegate callback เป็นคน
สรุปผลครั้งเดียวหลังผู้ใช้ตอบ prompt พร้อมเปลี่ยนไปใช้ instance property
`locationManager.authorizationStatus` แทน class method ที่ deprecated ตั้งแต่ iOS 14

**สถานะการแก้:** `code-complete, unverified` — คอมไพล์ผ่าน แต่ **ยังไม่ได้ทดสอบซ้ำ
บนเครื่องจริง** ต้องรันข้อ 1 นี้ใหม่ทั้งข้อบนเครื่องที่ลบแอปออกแล้ว จึงจะปิดได้

- [ ] **(ทดสอบซ้ำหลังแก้)** ลบแอป → รันใหม่ → กด Start scan **ครั้งเดียว** → กด
      Allow → ranging ต้องเริ่มเองทันทีโดยไม่ต้องกด Start scan ซ้ำ
- [ ] **(ทดสอบซ้ำหลังแก้)** ลบแอป → รันใหม่ → กด Start scan → กด Don't Allow →
      ต้องได้ `LOCATION_PERMISSION_DENIED` ครั้งเดียว ไม่ค้าง ไม่ crash
- [ ] **(ทดสอบซ้ำหลังแก้)** กด Start scan รัว ๆ หลายครั้งขณะ prompt ยังค้างบนจอ →
      ทุกคำขอต้องได้คำตอบครบ ไม่มี Future ฝั่ง Dart ค้างไม่ complete

### 🐞 บั๊กที่เจอจากการทดสอบบน iPhone จริง — รอบที่ 2 (27 ส.ค. 2026)

**รายงานโดย:** ผู้ใช้ (เจ้าของโปรเจกต์) จากการรันบนเครื่องจริง พร้อมลำดับการกดและ
ผลลัพธ์ครบทุกขั้น — หลักฐานระดับ "ทดสอบจริง" ตาม `SPRINT.md`

**ลำดับที่เจอ:**

| ขั้น | การกระทำ | ผลที่ได้ | ถูกต้องไหม |
|---|---|---|---|
| 1 | Start → Don't Allow | `LOCATION_PERMISSION_DENIED` | ✅ ถูก |
| 2 | Start ครั้งที่ 2 (status = `.denied`) | **ไม่มีอะไรเกิดขึ้นเลย ไม่มี error** | ❌ ควรได้ `LOCATION_PERMISSION_DENIED` ทันที |
| 3 | เปิดสิทธิ์ใน Settings → กลับแอป (ไม่ force quit) → Start ครั้งที่ 3 | ไม่มีผลใด ๆ scan ไม่เริ่ม ปุ่มยังกดได้ ไม่ crash ไม่ freeze | ❌ ควรเริ่มสแกนได้ |
| 4 | force quit → เปิดใหม่ (สิทธิ์ผ่านแล้ว) → Start | ทำงานปกติทันที | ✅ |

**ตัดออกจากการวินิจฉัยได้เลย:** ไม่ใช่ main-thread deadlock (UI ตอบสนองปกติ) และ
ไม่ใช่ปัญหา permission ระดับ OS (ขั้น 4 พิสูจน์ว่าสิทธิ์ผ่านแล้วจริง) — เป็น
**state ค้างในหน่วยความจำภายใน session เดียว**

**สาเหตุจริง (ยืนยันด้วยการรันเทสต์ให้แดงบนโค้ดเดิม ไม่ใช่การเดา):** อยู่ฝั่ง
**Dart** ไม่ใช่ Swift — `GenericIBeaconEddystoneAdapter.scan()` ใช้ broadcast
`StreamController` ตัวเดียว re-use ข้ามการเรียก (`_controller ??= ...`) เมื่อ native
start ล้มเหลว โค้ดเดิมแค่ `addError` แล้วจบ ซึ่ง**ไม่ปิด stream และไม่ยกเลิก
subscription** controller ตัวเดิมจึงยังอยู่พร้อม listener ค้าง 1 ตัว พอกด Start
รอบถัดไป `scan()` คืน controller ตัวเดิม แล้วจำนวนผู้ฟังขยับ 1 → 2 ซึ่ง
**`onListen` ยิงเฉพาะตอน 0 → 1 เท่านั้น** → `_startScanning()` ไม่ถูกเรียก →
ไม่มีการเรียก native แม้แต่ครั้งเดียว → เงียบสนิทตลอดไปจนกว่าจะ force quit

**หมายเหตุเทียบกับสมมติฐานตอนตั้งโจทย์:** สมมติฐานข้อ 1 (path `.denied` ไหลไปฝาก
`pendingStart` รอ callback ที่ไม่มีวันมา) **ไม่ใช่สาเหตุของอาการนี้** — ฝั่ง Swift
มี branch `.denied/.restricted` คืน error ทันทีอยู่แล้วตั้งแต่รอบแก้ก่อนหน้า และที่
ขั้น 2 โค้ด Swift ไม่ถูกเรียกด้วยซ้ำ ส่วนสมมติฐานข้อ 2 **ถูกในหลักการ** (มี guard
ที่บล็อกเงียบ ๆ ข้ามการเรียกจนกว่าจะ restart) แต่อยู่คนละที่กับที่คาด — ไม่ใช่
guard ที่เขียนไว้เอง แต่เป็น semantic ของ broadcast `StreamController.onListen`

**แก้แล้ว (27 ส.ค. 2026):**
- **Dart (สาเหตุหลัก):** เพิ่ม `_failAndTearDown()` — เมื่อ native start ล้มเหลว
  ให้หยุด native scan, เคลียร์ `_controller`, และ **ปิด controller** เพื่อให้
  listener ที่ค้างได้ `done` การ `scan()` รอบถัดไปจึงสร้าง controller ใหม่และ
  `onListen` ยิงตามปกติ
- **Dart (example app):** เพิ่ม `onDone` เคลียร์ `_subscription` ไม่ถือ handle ที่ตายแล้ว
- **Swift (ก):** ยืนยัน/คงไว้ว่า `.denied/.restricted` มี branch แยกคืน error ทันที
  เสมอ ไม่ไหลไปฝาก `pendingStart` — ย้ายมาใช้ตารางตัดสินใจตัวเดียว
  (`authorizationDecision(for:)`) ทั้งใน `startMonitoring` และ delegate callback
  เพื่อไม่ให้ logic แตกเป็นสองชุด
- **Swift (ข):** เพิ่ม `failPendingStart()` — ทุกครั้งที่คืน error เพราะสิทธิ์ถูก
  ปฏิเสธ ต้องปลดคำขอที่ค้างอยู่ทั้งหมดทิ้งด้วย ไม่ปล่อยข้ามไปบล็อกการเรียกครั้งถัดไป
  (ไม่ปลดในเคส argument ผิด/เกินเพดาน region เพราะคำขอเก่ายังรอ prompt อยู่อย่างถูกต้อง)

**เทสต์ที่กันไม่ให้กลับมาอีก:**
- Dart regression 2 ตัวใน
  `packages/beacon_kit/test/generic_ibeacon_eddystone_adapter_test.dart`
  จำลองลำดับ Start #1 (ล้มเหลว) → Start #2 → Start #3 (สิทธิ์ผ่านแล้ว)
  **พิสูจน์แล้วว่าแดงบนโค้ดเดิม** (`startIBeaconMonitoring` ถูกเรียกแค่ 1 ครั้งแทนที่จะเป็น 2)
  และเขียวบนโค้ดที่แก้แล้ว
- XCTest ใน `packages/beacon_kit/example/ios/RunnerTests/RunnerTests.swift`
  ตรวจตารางตัดสินใจ authorization บน simulator (ไม่ต้องมีอุปกรณ์)

**สถานะการแก้:** `code-complete, unverified บนเครื่องจริง` — Dart regression test
เขียวและพิสูจน์สาเหตุได้จริง แต่ **ยังไม่ได้รันลำดับนี้ซ้ำบน iPhone จริง**

- [ ] **(ทดสอบซ้ำหลังแก้ รอบ 2)** ลบแอป → Start → Don't Allow → Start ครั้งที่ 2
      ต้องได้ `LOCATION_PERMISSION_DENIED` **ทันที** ไม่เงียบ
- [ ] **(ทดสอบซ้ำหลังแก้ รอบ 2)** ต่อจากข้อบน: ไป Settings เปิดสิทธิ์ → กลับแอป
      (ห้าม force quit) → Start → ต้องเริ่มสแกนได้จริงโดยไม่ต้อง restart แอป

### ✅ ผลการทดสอบจริง — ส่วนที่ผ่านแล้ว (29 ส.ค. 2026)

**อุปกรณ์ที่ใช้:** iPhone _(ผู้ทดสอบกรอกรุ่น/เวอร์ชัน iOS)_ + K9P จริง 2 ตัว

- [x] **Allow ครั้งเดียวแล้ว scan ทำงาน** — กด Start → prompt ขึ้น → กด Allow →
      ranging เริ่มเองทันที **ไม่ต้องกด Start ซ้ำ** ยืนยันว่าการแก้บั๊กรอบ 1
      (ย้ายไปรอ `locationManagerDidChangeAuthorization`) ทำงานถูกบนอุปกรณ์จริง
- [x] **กด Start ซ้ำหลายครั้งขณะ prompt ยังค้างบนจอ** — ไม่ crash ไม่ค้าง และ
      ทำงานต่อได้ปกติหลังกด Allow ยืนยันว่า `pendingStart.results` ที่เก็บเป็น
      array (ทุก `FlutterResult` ถูกเรียกครบพอดีครั้งเดียว) ทำงานถูกจริง —
      ไม่มี Future ฝั่ง Dart ค้างไม่ complete

### ✅ ผลการทดสอบซ้ำ — ผ่านแล้ว (31 ส.ค. 2026)

ลำดับนี้คือลำดับที่เคยทำให้เจอบั๊กรอบ 2 (state ค้างใน broadcast controller ทำให้กด
Start แล้วไม่มีอะไรเกิดขึ้นเลย ไม่มี error ไม่ crash — ดูหัวข้อ 🐞 รอบ 2 ข้างบน)

- [x] Don't Allow → เปิดสิทธิ์ใน Settings → กลับแอป **โดยไม่ force quit** → Start
      → **สแกนได้ปกติ**

| รายการ | ค่า |
|---|---|
| วันที่ทดสอบ | 31 ส.ค. 2026 |
| iPhone รุ่น / iOS | _(ผู้ทดสอบกรอก)_ |
| K9P รุ่น/firmware | _(ผู้ทดสอบกรอก)_ |

**นี่ปิดบั๊กรอบ 2 อย่างสมบูรณ์** — การแก้ (`_failAndTearDown` รื้อ controller ที่
start ไม่สำเร็จทิ้งเสมอ) ได้รับการยืนยันบนอุปกรณ์จริงแล้ว ไม่ใช่แค่ Dart
regression test เขียว

### 🔍 ข้อสังเกต: เส้นทาง "ปฏิเสธสิทธิ์" ถูกออกแบบให้ตรงกันทั้งสองแพลตฟอร์มแล้ว

พฤติกรรมที่ตั้งใจให้เหมือนกันคือ **"ทุกเส้นทางต้องได้คำตอบเสมอ ห้ามค้างรอ callback
ที่ไม่มีวันมา และห้ามเงียบโดยไม่มี error"**

| สถานการณ์ | iOS | Android |
|---|---|---|
| ผู้ใช้ปฏิเสธ | `LOCATION_PERMISSION_DENIED` ทันที | `ScanPermissionStatus.denied` |
| ปฏิเสธแล้วขอซ้ำ (ระบบไม่ถามอีก) | คืน error ทันที ไม่ค้าง | `permanentlyDenied` → พาไป Settings |
| ไม่มีทางได้ callback (ไม่มี Activity / engine detach) | ไม่มีเคสนี้ | ปลด pending result ทันทีด้วย error |
| เปิดสิทธิ์ใน Settings แล้วกลับมา | ✅ **ยืนยันบนอุปกรณ์จริงแล้ว** | ⚠️ **ยังไม่ทดสอบ** |

⚠️ **ข้อควรระวังในการตีความ — ยังสรุปว่า "ตรงกันแล้ว" ไม่ได้**

สิ่งที่ยืนยันแล้วคือ **ฝั่ง iOS ผ่านบนอุปกรณ์จริง** และ **ฝั่ง Android เขียนโค้ดตาม
หลักการเดียวกันโดยตั้งใจ** (ใช้บทเรียนจากบั๊ก iOS รอบ 2 ตรง ๆ — ดูคอมเมนต์ใน
`BeaconKitAndroidPlugin.kt` ที่ `pendingPermissionResult`)

**แต่ฝั่ง Android ยังไม่เคยรันบนเครื่องจริงเลยแม้แต่ครั้งเดียว** (เช็คลิสต์ข้อ 17)
— จึงเป็น **ความตั้งใจในการออกแบบที่ตรงกัน ยังไม่ใช่พฤติกรรมที่วัดแล้วว่าตรงกัน**

และมีจุดที่**รู้อยู่แล้วว่าไม่ตรงกัน**สองข้อ ซึ่งเป็นข้อจำกัดของแพลตฟอร์ม ไม่ใช่บั๊ก:

1. Android มีสถานะ `permanentlyDenied` ("ไม่ถามอีกแล้ว") ซึ่ง **iOS ไม่มีสถานะ
   เทียบเท่า** — iOS ให้ prompt ครั้งเดียวตลอดอายุการติดตั้ง
2. Android อาจ**รีสตาร์ต process เองเมื่อสิทธิ์ถูกเปลี่ยนจากหน้า Settings** ซึ่งจะ
   ทำให้เส้นทาง "กลับมาโดยไม่ปิดแอป" มีความหมายต่างจาก iOS โดยสิ้นเชิง —
   **ยังไม่ยืนยัน** ต้องทดสอบเป็นเคสของตัวเองในข้อ 17

**ทำไมข้อสังเกตนี้ถึงมีค่ามากกว่าการที่ UUID ตรงกัน:** ค่าที่อ่านได้ตรงกันพิสูจน์แค่
ว่า parser ถูก ส่วนพฤติกรรมในสถานการณ์ผิดปกติที่ตรงกันพิสูจน์ว่า**การตัดสินใจเชิง
ออกแบบถูกถ่ายทอดข้ามแพลตฟอร์มจริง** ซึ่งเป็นสิ่งที่ทำให้คำว่า "SDK กลาง" มีความหมาย
— **แต่ด้วยเหตุผลเดียวกันนี้เอง มันจึงเป็นข้ออ้างที่ต้องมีหลักฐานสองฝั่งก่อนเขียนว่า
ยืนยันแล้ว** ตอนนี้มีฝั่งเดียว

## 2. iBeacon ranging ผ่าน CoreLocation (path หลัก)

- [ ] ตั้งค่า K9P ให้ broadcast iBeacon ด้วย UUID ค่าโรงงาน
      `7777772E-6B6B-6D63-6E2E-636F6D000001`
- [ ] เปิด K9P ให้อยู่ในระยะที่มองเห็นได้ (ไม่กี่เมตร) กด "Start scan" ในแอป
- [ ] ต้องเห็น K9P ขึ้นในรายการภายในไม่กี่วินาที พร้อม icon `location_on`
      (source = `coreLocation` ตาม `_BeaconTile` ใน `main.dart`)
- [ ] ตรวจ subtitle ต้องมี `uuid`/`major`/`minor` ตรงกับที่ตั้งค่าไว้ และ
      `proximity` ต้องเป็นค่าที่สมเหตุสมผล (ไม่ใช่ `unknown` ค้างตลอดตอนอยู่ใกล้)
- [x] RSSI (dBm) ที่แสดงต้องเป็นค่าลบที่สมเหตุสมผล (เช่น -40 ถึง -90) ไม่ใช่ 0
      หรือค่ามั่ว

### ✅ ผลการทดสอบจริง — ผ่าน (29 ส.ค. 2026)

**อุปกรณ์ที่ใช้:** iPhone _(ผู้ทดสอบกรอกรุ่น/เวอร์ชัน iOS)_ + K9P จริง **2 ตัว**

**หลักฐานที่บันทึกได้:**

| อุปกรณ์ | UUID | Major | Minor |
|---|---|---|---|
| K9P #1 | `7777772e-6b6b-6d63-6e2e-636f6d000001` | 229 | 24333 |
| K9P #2 | `7777772e-6b6b-6d63-6e2e-636f6d000001` | 228 | 24332 |

**สิ่งที่ยืนยันได้จากผลนี้:**
- CoreLocation ranging เห็น K9P จริงทั้งสองตัว และ **แอปแยกเป็นคนละอุปกรณ์ได้ถูกต้อง**
  ทั้งที่ UUID เดียวกัน — ยืนยันว่า dedup key ที่ใช้ `(deviceId.kind, deviceId.value)`
  ตาม ADR-1 ทำงานถูก ไม่ยุบสองตัวเป็นตัวเดียว และไม่แตกตัวเดียวเป็นหลายแถว
- **นี่คือหลักฐานตรงว่า BigC ID Scheme (ADR-5) ใช้ได้จริงบนอุปกรณ์** — UUID เดียว
  แยกอุปกรณ์ด้วย major/minor คือสิ่งที่เพิ่งเห็นทำงานจริง ไม่ใช่แค่ทฤษฎีจากเอกสาร Apple
- `proximity` และ RSSI **resolve จริง เปลี่ยนตามระยะ** (near/far/unknown สลับไปมา
  ตามที่ขยับอุปกรณ์) **ไม่ค้างที่ `unknown` และไม่ค้างที่ 0 dBm** — ตัดข้อสงสัยว่า
  ค่าที่เห็นเป็นค่า default ที่ไม่เคยถูกเขียนทับ

### ✅ ผลการทดสอบจริง — background (ไม่ kill แอป) ผ่าน (30 ส.ค. 2026)

**อุปกรณ์:** iPhone จริง _(ผู้ทดสอบกรอกรุ่น/เวอร์ชัน iOS)_ + K9P จริง
**วิธีทำให้ beacon หาย/กลับมา:** ถอดแบตออก / ใส่แบตกลับ

**เวลาที่วัดได้ (วัดครั้งแรก ยังไม่ได้ทำซ้ำหลายรอบเพื่อหาค่าเฉลี่ย):**

| event | เวลาตั้งแต่เปลี่ยนสถานะจนได้ notification |
|---|---|
| `didEnterRegion` | **5-8 วินาที** |
| `didExitRegion` | **30-50 วินาที** |

⚠️ **ตัวเลขนี้เป็นการวัดครั้งเดียว ยังไม่ได้ทำซ้ำหลายรอบ** จึงยังบอกไม่ได้ว่าเป็นค่า
ปกติหรือเป็นค่าที่บังเอิญได้ในรอบนั้น ก่อนเอาไปใช้ตั้ง timeout หรือสัญญากับฝ่ายธุรกิจ
ต้องวัดซ้ำอย่างน้อย 5 รอบแล้วดูค่ากลาง/ช่วงกระจาย — โดยเฉพาะ exit ที่ช่วงกว้างถึง
20 วินาที

**exit ช้ากว่า enter มากเป็นพฤติกรรมที่คาดได้:** CoreLocation ไม่ประกาศ exit ทันที
ที่ไม่เห็นสัญญาณ แต่รอยืนยันช่วงหนึ่งก่อนเพื่อกันการกระพริบ (beacon ที่สัญญาณขาด ๆ
หาย ๆ จะทำให้เกิด enter/exit รัวถ้าไม่มีการหน่วง) — **อย่าตีความว่าเป็นบั๊ก**
แต่ต้องเผื่อไว้ในการออกแบบ use case ที่ต้องรู้ว่าผู้ใช้ออกจากสาขาแล้ว

### สิ่งที่ผลข้อนี้พิสูจน์ และ**ไม่ได้**พิสูจน์

**พิสูจน์แล้ว:** proximity UUID ที่ตั้งไว้ถูกต้อง, region ถูกลงทะเบียนกับ CoreLocation
สำเร็จ, สิทธิ์ location เพียงพอ, delegate `didEnterRegion`/`didExitRegion` ถูกเรียกจริง
และ event ไหลจาก native → Dart → เขียน log → ยิง notification ได้ครบสาย
**แปลว่าฝั่ง CoreLocation/region ทำงานถูกทั้งหมด**

**ยังไม่ได้พิสูจน์ — อย่าสับสนกับ B5:** นี่คือเคส **"แอปอยู่เบื้องหลังแต่ process ยังมีชีวิต"**
ซึ่ง**ไม่ใช่**สิ่งที่ B5 ต้องการพิสูจน์ B5 คือ **process ถูกฆ่าไปแล้วแล้ว iOS ปลุกขึ้นมาใหม่**
ซึ่งยังไม่ได้ทดสอบ (ดูหัวข้อ 12 — เกณฑ์ผ่านคือต้องเห็นบรรทัด `relaunchedFromTerminated`
ในไฟล์ log)

### 🐞 ปัญหาที่เจอควบคู่กัน — foreground ไม่เห็นอะไรเลย (แก้แล้ว 30 ส.ค. 2026)

**อาการ:** ทดสอบข้อ 1 (แอปเปิดอยู่หน้าจอ) ถอด/ใส่แบต K9P แล้ว **ไม่เห็นอะไรเลย**
ทั้งที่ข้อ 2 (background) ได้ notification ปกติ

**สาเหตุ — ไม่ใช่ปัญหาของ CoreLocation:** แอปไม่ได้ implement
`userNotificationCenter(_:willPresent:withCompletionHandler:)` และไม่ได้ตั้ง
`UNUserNotificationCenter.current().delegate` เลย คอมเมนต์ใน SDK header ระบุตรงตัว
(`UserNotifications.framework/Headers/UNUserNotificationCenter.h:96`, iPhoneOS26.5.sdk):

> "The method will be called on the delegate only if the application is in the
> foreground. **If the method is not implemented or the handler is not called in a
> timely manner then the notification will not be presented.**"

แปลว่า event **เกิดขึ้นจริงและถูกเขียนลง log แล้ว** แต่ iOS เลือกไม่แสดง notification
ให้แอปที่กำลังเปิดอยู่ — เป็นปัญหาการ**มองเห็นผล** ไม่ใช่ปัญหาที่ตัว event

**การแก้ (ทั้งหมดอยู่ใน example app ไม่แตะ CoreLocation/region เลย):**
1. ตั้ง `UNUserNotificationCenter.current().delegate = self` ใน
   `didFinishLaunchingWithOptions` + implement `willPresent` คืนค่า
   `[.banner, .list, .sound]` (ไม่ใช่ `.alert` ที่ deprecated ตั้งแต่ iOS 14)
2. หน้าดู log **อัปเดตอัตโนมัติ**เมื่อมี event ใหม่ ระหว่างเปิดหน้านั้นค้างไว้
   (เดิมอ่านไฟล์เฉพาะตอนเปิดหน้าและตอนกดปุ่ม refresh — ปุ่มอ่านไฟล์ใหม่จริงอยู่แล้ว
   ไม่ได้แสดงจาก cache แต่ไม่มีใครสั่งให้อ่านซ้ำเอง)
3. หน้าจอหลักมี **ตัวนับ enter/exit + เวลาล่าสุดแบบ realtime** เพื่อให้เห็นผลทันที
   **โดยไม่ต้องพึ่ง notification เลย** — ถ้ารอบก่อนมีตัวนับนี้ จะรู้ตั้งแต่แรกว่า event
   มาถึงแล้วและปัญหาอยู่ที่การแสดงผลเท่านั้น

**สถานะการแก้:** `code-complete, unverified` — ยังไม่ได้ทดสอบซ้ำบนเครื่องจริง

- [ ] **(ทดสอบซ้ำหลังแก้)** เปิดแอปค้างไว้หน้าจอหลัก → ถอด/ใส่แบต K9P →
      ตัวนับ enter/exit ต้องขยับทันที **และ** ต้องเห็น notification banner เด้งขึ้นมา
      ด้วยทั้งที่แอปเปิดอยู่
- [ ] **(ทดสอบซ้ำหลังแก้)** เปิดหน้า "ดู log" ค้างไว้ → ถอด/ใส่แบต → บรรทัดใหม่ต้อง
      โผล่เองโดยไม่ต้องกด refresh

## 3. K9P หายจากระยะ / ปิดเครื่อง

- [ ] ปิด K9P (หรือเดินออกนอกระยะสัญญาณ ~10+ เมตร หรือกำบังด้วยวัสดุ) ขณะแอปกำลัง
      scan อยู่
- [ ] รอสังเกต — CoreLocation ไม่ได้แจ้ง "หายไปทันที" เหมือน BLE scan ปกติ (มี
      `didExitRegion`/timeout ของตัวเอง) บันทึกเวลาที่ RSSI เริ่มอ่อนลงหรือ
      รายการหยุดอัปเดต
- [ ] ต้อง**ไม่ค้าง**ที่ค่า RSSI เดิมตลอดไปโดยไม่ขยับเลยหลังจากปิดเครื่องไปนาน
      พอสมควร (หลายนาที) — ถ้าค้างถือว่าผิดปกติ ต้องรายงานกลับ `flutter-dev`

## 4. Background mode (`location`)

- [ ] เริ่ม scan แล้วกด Home (suspend แอป ไม่ swipe ปิด/kill)
- [ ] เปิด K9P ใหม่ (หรือให้ยังคงอยู่ในระยะ) แล้วดู Xcode console/log ว่ามี
      `didRange`/`didDetermineState` callback ยิงต่อเนื่องในพื้นหลังหรือไม่ (ยาก
      ตรวจสอบตรง ๆ จาก UI เพราะแอป suspended — ต้องพึ่ง log ฝั่ง native)
- [ ] เปิดแอปกลับมา foreground แล้วตรวจว่ารายการ beacon อัปเดตต่อเนื่องจากตอน
      background โดยไม่ต้องกด "Start scan" ใหม่ (บ่งชี้ว่า monitoring ไม่ได้
      หลุดตอน suspend)

## 5. เพดาน 20 regions (`TOO_MANY_REGIONS`)

- [ ] เขียนโค้ดทดสอบชั่วคราว (หรือแก้ example ชั่วคราวแบบไม่ commit) เรียก
      `BeaconKitIos().startIBeaconMonitoring(...)` ด้วย region มากกว่า 20 region
      (uuid สุ่มได้ ไม่จำเป็นต้องมีจริง)
- [ ] ต้องได้ `PlatformException(code: 'TOO_MANY_REGIONS')` กลับมา **ก่อน**ที่จะ
      สร้าง `CLBeaconRegion` แม้แต่ตัวเดียว (ตาม ADR-4 — all-or-nothing) ไม่ crash
      แอป
- [ ] ตรวจว่า monitoring เดิม (ถ้ามีอยู่ก่อนเรียก) ยังอยู่ครบ ไม่ถูกแก้ไข
      บางส่วน (เช็คผ่าน `CLLocationManager.monitoredRegions` ใน log ฝั่ง native)

## 6. Eddystone ผ่าน CoreBluetooth (ถ้า K9P รองรับ)

**ขั้นตอนทดสอบส่วน UID/TLM ที่ยังเหลือ:** `ios_device_test_runbook.md` §6

- [ ] ถ้า firmware/การตั้งค่า K9P รองรับการ broadcast Eddystone (service
      `0xFEAA`) ให้เปิดโหมดนี้แล้วสแกนอีกครั้ง
- [ ] ต้องเห็นอุปกรณ์ขึ้นในรายการด้วย icon `bluetooth` (source =
      `coreBluetooth`) และ subtitle แสดงค่า `raw['eddystone']` เป็น
      `EddystoneUidFrame`/`EddystoneUrlFrame`/`EddystoneTlmFrame` ที่ parse
      สำเร็จ (ไม่ใช่ `null`/ว่างเปล่า)
- [ ] เทียบค่าที่ parse ได้ (namespaceId/instanceId หรือ url ฯลฯ) กับค่าที่ตั้งไว้
      บน K9P จริงว่าตรงกัน — ถ้าไม่ตรง หรือ parse ไม่สำเร็จ ให้บันทึก raw hex
      ที่จับได้จริง (เช่นผ่าน nRF Connect) ไว้เป็น fixture ใหม่ที่
      `docs/fixtures/` (`source: captured`) แล้วรายงานกลับ `flutter-dev`

### ✅ ผลการทดสอบจริง — ผ่าน (29 ส.ค. 2026)

**อุปกรณ์ที่ใช้:** iPhone _(ผู้ทดสอบกรอกรุ่น/เวอร์ชัน iOS)_ + **อุปกรณ์บุคคลที่สาม
ที่ไม่รู้จักมาก่อน** (ไม่ใช่ K9P และไม่ได้ตั้งค่าเอง)

**สิ่งที่ decode ได้จริง:**

```
EddystoneUrlFrame(txPower: -38, url: https://www.google.com/)   @ -88 dBm
```

**ทำไมผลนี้มีน้ำหนักกว่าที่หัวข้อนี้ตั้งเป้าไว้ตอนแรก:** หัวข้อนี้เขียนไว้เดิมว่า
"ถ้า K9P รองรับ" คือคาดว่าจะทดสอบกับอุปกรณ์ที่เราตั้งค่าเอง แต่ผลจริงมาจาก
**อุปกรณ์ของคนอื่นที่บังเอิญอยู่ในระยะ ซึ่งเราไม่เคยตั้งค่าและไม่รู้ว่าเป็นยี่ห้ออะไร**
— แปลว่า path นี้ทำงานได้จริงแบบ vendor-agnostic ตามที่ ARCHITECTURE.md ตั้งใจไว้
ไม่ใช่ทำงานได้เพราะเรารู้คำตอบล่วงหน้า

ยืนยันครบทั้งสาย: CoreBluetooth ส่ง raw service data ของ `0xFEAA` กลับมา →
`EddystoneParser` ฝั่ง Dart ถอด URL scheme + suffix expansion ถูกต้อง
(`https://www.` + `google` + `.com/`) → แสดงผลถูกใน example app

**หมายเหตุ:** ยังไม่ได้เก็บ raw hex ของ advertisement นี้เป็น fixture
`source: captured` เพราะไม่ได้จับ byte ดิบไว้ตอนทดสอบ ถ้าเจออุปกรณ์นี้อีกและอยาก
เพิ่ม fixture ให้ใช้ nRF Connect จับ raw hex ตาม `docs/fixtures/README.md`

**สิ่งที่ยังไม่ได้ทดสอบในหัวข้อนี้:** `EddystoneUidFrame` และ `EddystoneTlmFrame`
(เจอแต่ frame แบบ URL) — parser ทั้งสองแบบผ่าน unit test แต่ยังไม่เคยเจอของจริง

## 7. Bluetooth ปิดกลางคัน (`BLUETOOTH_UNAVAILABLE`)

- [ ] เริ่ม scan ให้เห็นอุปกรณ์ในรายการก่อน แล้วปิด Bluetooth จาก Settings (หรือ
      Control Center) ของ iPhone ระหว่างที่แอปกำลัง scan อยู่
- [ ] ต้องเห็น error banner ขึ้นในแอป (คาดว่า
      `PlatformException(code: 'BLUETOOTH_UNAVAILABLE')` ตาม ADR-4) **ไม่ crash
      แอป**
- [ ] เปิด Bluetooth กลับมา แล้วกด "Start scan" ใหม่ ต้องกลับมาทำงานได้ปกติ
      (ไม่ค้างอยู่ใน state พังจากรอบก่อนหน้า)

## 8. Password/negative-path อื่น ๆ ที่เกี่ยวข้องกับ broadcast path

หมายเหตุ: broadcast-only path (`GenericIBeaconEddystoneAdapter`,
`supportsConnect == false`) **ไม่มี** password/GATT auth เกี่ยวข้องเลย —
password/MD5 auth/connect timeout เป็นของ connect-path (`KkmK9pAdapter`) ซึ่ง
ยังไม่เริ่ม implement ในสปรินต์นี้ (ดู `ARCHITECTURE.md` ADR-1 "ผลกระทบต่อเนื่อง"
และ `SPRINT.md` ลำดับความสำคัญข้อ 6) — เมื่อเริ่มงาน connect-path ต้องเพิ่ม
เช็คลิสต์แยกต่างหาก (`docs/test-checklists/ios_gatt_connect.md` เป็นต้น)
ครอบคลุม password ผิด/สั้นกว่า 8/ยาวกว่า 16 ตัวอักษร, connect timeout, BLE ปิด
กลางคันตอน GATT session ค้างอยู่ — **ไม่ใช่ขอบเขตของเช็คลิสต์นี้**

---

## 9. region ซ้อนทับกัน — `didEnterRegion` มาซ้ำหรือไม่ (ADR-8 open question)

**ขั้นตอนทดสอบ:** `ios_device_test_runbook.md` §4

**สถานะ: ยังไม่ทดสอบ** — เป็น open question ที่ ADR-8 ระบุไว้ว่า **ไม่พบเอกสาร Apple
ที่ตอบได้ชัด ห้ามสมมติเอาเอง**

ตาม ADR-8 เราลงทะเบียน region 2 ชั้นที่ซ้อนทับกันโดยตั้งใจ: ชั้นที่ 1 (UUID อย่างเดียว)
ครอบคลุม beacon ทุกตัว และชั้นที่ 2 (UUID + major) ครอบคลุมเฉพาะสาขานั้น — beacon
ตัวหนึ่งในสาขาที่ลงทะเบียนไว้จึงตรงกับ **ทั้งสอง region พร้อมกัน**

- [ ] ลงทะเบียนทั้งชั้นที่ 1 และชั้นที่ 2 ของสาขาที่ K9P ตัวทดสอบอยู่ พร้อมกัน
- [ ] เดินออกนอกระยะจนได้ exit แล้วเดินกลับเข้ามา
- [ ] นับว่า `didEnterRegion` ถูกเรียก **กี่ครั้ง** ต่อการเข้าหนึ่งครั้ง
- [ ] ถ้าถูกเรียกมากกว่าหนึ่งครั้ง ให้บันทึก `region.identifier` ของแต่ละครั้งว่าเป็น
      `bigc-fleet-wide` หรือรหัสสาขา และเรียงลำดับมาอย่างไร
- [ ] ทำซ้ำอย่างน้อย 3 รอบ เพื่อดูว่าพฤติกรรมคงที่หรือสุ่ม

**ทำไมต้องรู้:** ถ้ายิงสองครั้งจริงแต่เราเขียนโค้ดโดยคิดว่าครั้งเดียว business logic จะนับ
การเข้าสาขาซ้ำสองเท่า ถ้ายิงครั้งเดียวจริงแต่เราใส่ dedupe ไว้ อาจกลืน event ที่ถูกต้องทิ้ง
**ห้ามเขียน dedupe logic จนกว่าจะรู้ผลข้อนี้**

## 10. region monitoring ตอนไม่มีอินเทอร์เน็ต

**ขั้นตอนทดสอบ:** `ios_device_test_runbook.md` §5

**สถานะ: ยังไม่ทดสอบ**

Apple ระบุไว้ตรงตัวในหน้า `startMonitoring(for:)`:

> "In order to report region changes in a timely manner, the region monitoring service
> requires network connectivity."

**ทำไมข้อนี้สำคัญมากกับ use case จริงของ BigC:** สาขาจริงมีจุดอับสัญญาณเยอะ —
ชั้นใต้ดิน, ลานจอดรถใต้อาคาร, ห้องเย็น, คลังสินค้าหลังร้าน ซึ่งเป็นที่ที่ beacon มักถูก
ติดตั้งพอดี ถ้า region monitoring ต้องพึ่ง network จริง พฤติกรรมในจุดเหล่านั้นอาจต่างจาก
ที่ทดสอบในออฟฟิศโดยสิ้นเชิง

- [ ] เปิด Airplane Mode (ปิดทั้ง Wi-Fi และ cellular) แต่**เปิด Bluetooth ไว้**
- [ ] เดินเข้า/ออกระยะ beacon แล้วดูว่า enter/exit ยังยิงไหม และช้าลงแค่ไหน
      เทียบกับตอนมีเน็ต (จับเวลาคร่าว ๆ)
- [ ] ทดสอบซ้ำแบบมี Wi-Fi แต่ไม่มี internet จริง (เชื่อมต่อ AP ที่ไม่มีทางออกเน็ต)
      — เพื่อแยกว่า "มี network interface" กับ "ต่อเน็ตได้จริง" ให้ผลต่างกันไหม
- [ ] บันทึกผลว่าใช้งานได้/ช้าลง/ไม่ทำงานเลย พร้อมเวลาที่วัดได้

ถ้าผลออกมาว่าไม่ทำงานเลยตอนออฟไลน์ ต้องกลับไปทบทวน ADR-6/ADR-8 ว่า use case
ในจุดอับสัญญาณยังทำได้จริงหรือไม่ — อาจกระทบถึงการเลือกตำแหน่งติดตั้ง beacon

## 11. เทียบความเร็วการตรวจจับ: iBeacon อย่างเดียว vs หลายโหมดพร้อมกัน

**สถานะ: ยังทำไม่ได้ — ติด dependency ที่ยังไม่ implement**

**⛔ เคสนี้ต้องเขียน config ลง K9P ผ่าน GATT ซึ่ง `beacon_kit` ยังไม่ implement เลย**
(ดู README ตารางสถานะ: GATT connect/auth/OTA = "ยังไม่ implement" ไม่ใช่แค่ยังไม่
ทดสอบ) ทางเลือกชั่วคราวคือใช้แอปของผู้ผลิตตั้งค่าเอง แล้วค่อยทดสอบส่วนที่เหลือ —
บันทึกไว้ตรงนี้เพื่อไม่ให้ตกหล่นเมื่อ GATT path พร้อม

สมมติฐานที่จะทดสอบ: วิศวกร Apple DTS ชี้ว่า **mixed advertising modes เป็นสาเหตุที่พบ
บ่อยของการตรวจจับ beacon ช้า** — ถ้า K9P broadcast iBeacon + Eddystone + Ksensor
สลับกันในช่องเวลาเดียวกัน แต่ละฟอร์แมตจะออกอากาศถี่น้อยลง ทำให้ iOS ใช้เวลานานขึ้น
กว่าจะยืนยันว่าเข้า region

*(ที่มา: การปรึกษา Apple DTS ตามที่ผู้ใช้รายงาน — ไม่ใช่เอกสารสาธารณะที่ตรวจสอบ
ย้อนกลับได้ ถือเป็นสมมติฐานที่ต้องพิสูจน์ ไม่ใช่ข้อเท็จจริงที่ยืนยันแล้ว)*

- [ ] ตั้ง K9P ตัวที่ 1 ให้ broadcast **iBeacon อย่างเดียว**
- [ ] ตั้ง K9P ตัวที่ 2 ให้ broadcast **iBeacon + Eddystone + Ksensor ที่ 1000ms**
- [ ] วัดเวลาจาก "เดินเข้าระยะ" ถึง "ได้ `didEnterRegion`" ของแต่ละตัว อย่างน้อย
      ตัวละ 5 รอบ แล้วเทียบค่ากลาง
- [ ] ทดสอบทั้งตอน foreground และตอนแอปถูก terminate

**ทำไมคุ้มที่จะวัด:** ถ้าต่างกันจริงอย่างมีนัยสำคัญ นี่คือ **knob ที่ปรับได้ที่ฝั่ง
provisioning โดยไม่ต้องแก้โค้ดแอปเลย** — เปลี่ยนการตั้งค่า beacon ตอนติดตั้ง
ก็ได้ความเร็วกลับมา ซึ่งถูกกว่าและเร็วกว่าการไล่ optimize โค้ด

## 12. เครื่องมือบันทึกหลักฐานใน example app — วิธีแยก "ถูกปลุกจากสถานะถูกฆ่า"

**สถานะ: ✅ ผ่านแล้วบนอุปกรณ์จริง (30 ส.ค. 2026) — ทดสอบ 2 รอบ**

> **⚠️ อัปเดต 3 ก.ย. 2026 — ต้องอ่านคู่กับ ARCHITECTURE.md ADR-16:**
> พบว่า `hasEverBecomeActive` (คอลัมน์ `everActive` ในสัญญาณดิบ) ค้าง `false`
> **ตลอดชีพ process ทุกกรณี** ที่แอปประกาศ `UIApplicationSceneManifest` — เป็น
> บั๊กคนละตัวกับเรื่อง `launchKey` ที่บันทึกไว้ในหัวข้อนี้อยู่แล้ว (ดูหัวข้อ 🔍
> ด้านล่าง) แก้แล้วด้วยการเพิ่ม `NotificationCenter` observer ของ
> `UIApplication.didBecomeActiveNotification`
>
> **ผลสรุป B5 "ผ่าน" ของหัวข้อนี้ยังยืนอยู่ ไม่ถูกเพิกถอน** — แต่**เหตุผลรองรับ
> เดิมที่อ้าง `everActive=false` เชื่อไม่ได้อีกต่อไป** เพราะค่านั้นจะเป็น `false`
> เสมอไม่ว่าความจริงจะเป็นอะไรก็ตาม (รายละเอียดในกล่อง "หลักฐานที่ทำให้ถือว่าผ่าน"
> ด้านล่าง) และ**ทุกบรรทัดในไฟล์นี้ที่มีข้อสรุปเป็น `relaunchedFromTerminated`
> ซึ่งบันทึกไว้ก่อน commit ที่แก้บั๊กนี้ (`c24d36b`) ต้องตีความใหม่ตามตาราง 6
> ระดับใน ADR-16 หัวข้อ 3** ห้ามยึดคอลัมน์ข้อสรุปตามตัวอักษรเพียงอย่างเดียวอีก
> ต่อไป — ไม่มีการเขียนกฎใหม่ซ้อนในไฟล์นี้ ให้ใช้ตารางของ ADR-16 หัวข้อ 3 เป็นวิธี
> ตีความเดียว
>
> **ขอบเขตยังไม่ยืนยัน (Track B):** ยังไม่มีการทดสอบบนอุปกรณ์จริงหลังแก้บั๊กนี้
> เลยสักครั้ง — ดูขั้นตอนที่ต้องทำที่ `ios_device_test_runbook.md` §11 (3 ข้อ:
> observer ยิงจริง / process ที่ไม่เคย active ยังให้ `false` ถูกต้อง / process
> อายุยืนที่ active กลางทางแยก `background` ออกจาก `relaunchedFromTerminated`
> ได้จริง)
>
> **ขอบเขตครอบคลุมหน้าจอแอปด้วย ไม่ใช่แค่ไฟล์ log:**
> `example/lib/diagnostics/launch_context.dart:70-78`
> (`LaunchDiagnostics.context`) ใช้ตรรกะชุดเดียวกันเป๊ะกับ `currentRunContext()`
> ฝั่ง native (เช็ค `applicationState == active` ก่อน แล้วดู `hasEverBecomeActive`)
> และรับค่า `hasEverBecomeActive` มาจาก native ตัวเดียวกันผ่าน
> `getLaunchDiagnostics` — แปลว่า**ข้อความสรุปที่แสดงบนหน้าจอหลัก** (เช่น
> `_lastRegionEvent` ที่ต่อท้ายด้วย `(diagnostics.context.name)`) **รายงานผิดมา
> ตลอดด้วยเหตุผลเดียวกัน** ก่อน commit ที่แก้บั๊กนี้ — การ re-verify ต้องดูทั้ง
> ไฟล์ log และสิ่งที่แสดงบนหน้าจอ ไม่ใช่แค่ไฟล์เดียว

### ✅ ผลการทดสอบจริง — B5 ผ่าน (30 ส.ค. 2026)

**เงื่อนไขการทดสอบ**

| รายการ | ค่า |
|---|---|
| build mode | **release / profile** (ไม่ใช่ debug — debug มี debugger ต่ออยู่ พฤติกรรม terminate ไม่ตรงของจริง) |
| การติดตั้ง | **ลบแอปแล้วติดตั้งใหม่** ก่อนเริ่ม (สิทธิ์/region เริ่มจากศูนย์) |
| วิธี terminate | **ผู้ใช้ปัดแอปทิ้งจาก app switcher (force-quit)** |
| วิธีกระตุ้น event | ถอด/ใส่แบต K9P |
| iPhone รุ่น | _(ผู้ทดสอบกรอก)_ |
| iOS เวอร์ชัน | _(ผู้ทดสอบกรอก)_ |
| K9P | _(ผู้ทดสอบกรอก รุ่น/firmware)_ |

**ผลที่วัดได้**

| รอบ | exit | enter |
|---|---|---|
| 1 | 55 วินาที | 5 วินาที |
| 2 | 30 วินาที | 3 วินาที |

ทิศทางเดียวกับที่วัดตอน background (ข้อ 2): **exit ช้ากว่า enter อย่างมีนัยสำคัญ**
ซึ่งเป็นพฤติกรรมที่คาดได้ของ CoreLocation (รอยืนยันก่อนประกาศ exit เพื่อกันการ
กระพริบจาก beacon ที่สัญญาณขาด ๆ หาย ๆ) **ยังเป็นการวัดแค่ 2 รอบ** ช่วง exit
30-55 วินาทีกว้างเกินกว่าจะเอาไปตั้ง timeout ได้โดยตรง

**หลักฐานที่ทำให้ถือว่าผ่าน**

ทั้งสองรอบ ทั้งบรรทัด exit และ enter มี:

```
everActive=false   state=background
```

ซึ่งตอนบันทึกผลนี้ (30 ส.ค. 2026) ถือว่าตรงตามเกณฑ์ที่ตั้งไว้: คอลัมน์ข้อสรุปเป็น
`relaunchedFromTerminated` (process อยู่เบื้องหลัง **และ** ไม่เคยขึ้น foreground
เลยตั้งแต่เริ่ม = ไม่ใช่ผู้ใช้เปิดแอปเอง)

> ⚠️ **แก้ไข 3 ก.ย. 2026 (ADR-16) — เหตุผลข้างบนใช้ `everActive=false` เป็น
> หลักฐานไม่ได้อีกต่อไป ต้องอ่านใหม่:**
>
> `everActive=false` ที่ยกมาข้างบน**ไม่มีน้ำหนักพิสูจน์อะไรเลย** เพราะ
> `hasEverBecomeActive` ค้าง `false` ตลอดชีพ process ทุกกรณีที่แอปประกาศ
> `UIApplicationSceneManifest` (บั๊กที่ ADR-16 อธิบายไว้ — สาเหตุคือ
> `applicationDidBecomeActive` ไม่ถูก UIKit เรียกเลยภายใต้ UIScene lifecycle)
> ไม่ว่าแอปจะถูกปลุกจากสถานะ terminated จริงหรือรันอยู่เบื้องหลังอยู่แล้วก็ตาม
> จะได้ `everActive=false` เหมือนกันเป๊ะ — ค่านี้จึงแยกสองเคสนี้ออกจากกันไม่ได้
> เลยในตอนที่วัดผลนี้
>
> **ข้อสรุป "ผ่าน" ของการทดสอบนี้ยังยืนอยู่** แต่เหตุผลตัวจริงคือ **เวลา
> ไม่ใช่ `everActive`**: ทั้งสองรอบมีบรรทัด `launch` (`uptime=0.0s`) ตามด้วย
> บรรทัด `enter` ทันที (`uptime≈0.8s` และ `uptime≈3-5s`) — ระยะเวลาสั้นขนาดนี้
> ทำให้ทางเลือก "จริง ๆ คือ `background`" เป็นไปไม่ได้ทางกายภาพ (ไม่มีเวลาให้
> ผู้ใช้เปิด-ใช้-พับแอปได้จริงในช่วง 1 วินาทีก่อน `enter` จะเกิด) — นี่คือแถวที่
> 2-3 ของตาราง 6 ระดับใน ADR-16 หัวข้อ 3 ซึ่งเป็นวิธีตีความบรรทัด log เก่าที่
> `relaunchedFromTerminated` ทั้งหมดในไฟล์นี้ (บันทึกไว้ก่อน commit ที่แก้บั๊กนี้
> คือ `c24d36b`) — ห้ามยึดคอลัมน์ข้อสรุปตามตัวอักษรอย่างเดียวอีกต่อไปโดยไม่เทียบ
> `uptime` กับบรรทัด `launch` ของ `procUuid` เดียวกันก่อน

**สิ่งที่ผลนี้พิสูจน์ และ *ไม่ได้* พิสูจน์**

| พิสูจน์แล้ว | ยังไม่ได้พิสูจน์ |
|---|---|
| iOS ปลุก process ที่**ผู้ใช้ปัดทิ้งเอง** ขึ้นมาส่ง region event ได้จริง | **ระบบฆ่าแอปเองเพราะหน่วยความจำ** — เกิดบ่อยกว่า force-quit มากในการใช้งานจริง และเป็นคนละเส้นทางของ OS |
| `CLLocationManager` ที่สร้างใน `didFinishLaunchingWithOptions` รับ event ได้ทันในรอบ launch | พฤติกรรมตอน**เครื่องล็อก** (ข้อ 13 — Data Protection) |
| region รอดข้าม process จริง (ไม่ต้องลงทะเบียนใหม่) | ตอน**ไม่มีอินเทอร์เน็ต** (ข้อ 10) |
| log ฝั่ง native เขียนได้ตอนถูกปลุกเบื้องหลัง | region **ซ้อนทับกัน** จะได้ enter ซ้ำหรือไม่ (ข้อ 9) |
| สิทธิ์ Always + `UIBackgroundModes: location` ที่ตั้งไว้เพียงพอจริง | หลังเครื่อง**รีบูตแล้วยังไม่ปลดล็อก** — Apple ระบุว่า monitoring เริ่มไม่ได้จนกว่าจะปลดล็อกครั้งแรก |

⚠️ **ห้ามสรุปเหมารวมว่า "background scan ใช้งานได้"** — สิ่งที่ผ่านคือเส้นทางเดียวที่
ทดสอบ (force-quit → region enter/exit → iBeacon) ในเงื่อนไขเดียวที่ทดสอบ

### 🔍 ข้อค้นพบสำคัญ: `launchKey=false` ทั้งที่แอปถูกปลุกจากสถานะ terminated จริง

**ข้อเท็จจริงที่วัดได้:** ทั้ง 2 รอบ log บันทึก `launchKey=false` —
`UIApplication.LaunchOptionsKey.location` **ไม่ถูกเซ็ต** แม้แอปจะถูกปลุกจากสถานะ
terminated จริง (ยืนยันด้วย `everActive=false` + `state=background` + การที่ event
มาถึงหลังผู้ใช้ปัดแอปทิ้งไปแล้ว)

**ทำไมเรื่องนี้สำคัญ:** แนวทางคลาสสิกที่พบทั่วไปคือใช้ launch key ตัวนี้เป็นสัญญาณ
เดียวว่า "แอปถูกปลุกด้วย location event หรือไม่" ใครทำแบบนั้นในสภาพแวดล้อมนี้จะได้
**false negative** — สรุปผิดว่าฟีเจอร์ไม่ทำงานทั้งที่มันทำงานอยู่ ซึ่งเป็นความ
ล้มเหลวชนิดที่อันตรายที่สุดเพราะดูเหมือนข้อสรุปที่มีหลักฐานรองรับ

**สัญญาณที่เชื่อได้ในสภาพแวดล้อมนี้คือ `everActive`** (process เคยผ่าน
`applicationDidBecomeActive` หรือยัง) — ไม่พึ่ง API ที่ deprecated เลย และตั้งอยู่บน
ข้อเท็จจริงของ lifecycle ล้วน ๆ

**สาเหตุที่เป็นไปได้ — ยังเป็น open question ห้ามสรุป:**

| สมมติฐาน | หลักฐานที่มี | ยังขาดอะไร |
|---|---|---|
| (ก) key นี้ deprecated ใน iOS 26 แล้วระบบเลิกเซ็ตให้ | `UIApplication.h:586` ระบุ `API_DEPRECATED(..., ios(4.0, 26.0))` จริง (เลขเวอร์ชันจริง ไม่ใช่ `API_TO_BE_DEPRECATED`) | ยังไม่พบเอกสาร Apple ที่ระบุว่า deprecated แล้ว **หยุดเซ็ตค่า** — deprecated ปกติแปลว่า "ยังทำงานอยู่แต่เลิกแนะนำ" ไม่ใช่ "หยุดทำงาน" · ยังไม่ได้ทดสอบบน iOS ที่เก่ากว่า 26 เพื่อเทียบ |
| (ข) แอปใช้ scene lifecycle ซึ่ง launch options เดินคนละเส้นทาง | ข้อความ deprecation เองพูดถึง "...to handle expected location events **after scene connection**" ซึ่งบอกเป็นนัยว่าเส้นทางย้ายไปฝั่ง scene · `Runner/Info.plist` ประกาศ `UIApplicationSceneManifest` จริง | ยังไม่ได้ทดสอบแอปที่**ไม่ใช้** scene lifecycle เพื่อเทียบ · ยังไม่ได้ตรวจว่า `UISceneDelegate.scene(_:willConnectTo:options:)` ได้รับ location signal แทนหรือไม่ |

**ยังไม่ได้พิสูจน์ว่าเป็นข้อไหน** — และไม่จำเป็นต้องพิสูจน์เพื่อให้ B5 ผ่าน เพราะ
เราออกแบบให้ใช้สองสัญญาณอิสระตั้งแต่แรกโดยไม่ให้ตัวที่ deprecated เป็นตัวตัดสินหลัก
(ดูเหตุผลในหัวข้อถัดไป) แต่ **ต้องบันทึกไว้** เพราะใครก็ตามที่เขียนโค้ดใหม่บนสมมติฐาน
คลาสสิกจะเจอปัญหานี้

> **อัปเดต 3 ก.ย. 2026 (ADR-16 หัวข้อ 2) — สมมติฐาน (ข) ยืนยันแล้วจากเอกสาร Apple
> โดยตรง สมมติฐาน (ก) ไม่จำเป็นต้องพิสูจน์อีกต่อไป:**
>
> เอกสาร Apple ของ `application(_:didFinishLaunchingWithOptions:)`
> (<https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:didfinishlaunchingwithoptions:)>)
> ระบุตรง ๆ ในคำอธิบายพารามิเตอร์ `launchOptions` ว่า **"If the app supports
> scenes, this is `nil`"** — ทั้ง `launchOptions` dictionary เป็น `nil` เสมอ
> ไม่ใช่แค่ key `.location` หายไปเฉย ๆ ยืนยันซ้ำจาก Apple Developer Forums
> (กระทู้ "Scene-based Launch Detection",
> <https://developer.apple.com/forums/thread/814444>, คำตอบระบุว่ามาจาก Apple
> engineer แต่ยืนยัน badge ไม่ได้โดยตรงเพราะข้อจำกัดของเครื่องมือดึงหน้าเว็บ):
> "For apps that support UIScene, the UIApplication launch options will be
> nil."
>
> แอปนี้ประกาศ `UIApplicationSceneManifest` (`Info.plist:40-60`) จึง "supports
> scenes" ตามนิยามข้างบน — **`launchKey` จึงเป็นสัญญาณตายทางโครงสร้าง ไม่มี
> ข้อมูลอยู่ในค่านี้เลยไม่ว่าความจริงจะเป็นอะไร** ไม่ใช่แค่ "เชื่อเดี่ยว ๆ ไม่ได้"
> ตามที่บันทึกไว้เดิมในหัวข้อนี้ สมมติฐาน (ก) เรื่อง deprecation จึง**ไม่จำเป็น
> ต้องพิสูจน์อีกต่อไป** เพราะ (ข) อธิบายผลที่วัดได้ 2/2 รอบครบอยู่แล้วโดยไม่ต้อง
> อาศัย (ก) เลย
>
> **สิ่งที่ยังปิดไม่ได้จริง ๆ และยังไม่จำเป็นต้องทำ:** การทดสอบเทียบกับบิลด์ที่
> ไม่ใช้ scene lifecycle เพื่อยืนยันเชิงประจักษ์ — ยังไม่ได้ทำ และ**ตามการ
> ตัดสินใจใน ADR-16 หัวข้อ 2 ไม่จำเป็นต้องทำ** เพราะไม่กระทบการใช้งานจริง (การปิด
> สถานะ open question นี้เป็นงานของ `beacon-qa` ในขั้นที่ 3 ตามที่ ADR-16 ระบุไว้
> — ปิดในบรรทัดนี้แล้ว ไม่ใช่การเขียนกฎใหม่ซ้อน)
>
> รายละเอียดเต็ม: `ARCHITECTURE.md` ADR-16 หัวข้อ 2

**ผลกระทบต่อการออกแบบ:** การตัดสินใจไม่พึ่ง launch key เป็นตัวตัดสินหลัก —
ซึ่งตอนตัดสินใจเป็นเพียงการป้องกันความเสี่ยงตามทฤษฎี — **พิสูจน์คุณค่าตัวเองใน
การใช้งานจริงครั้งแรก** ถ้าเลือกอีกทาง B5 จะถูกรายงานว่า "ไม่ผ่าน" ทั้งที่ผ่าน

### 🐞 ผลทดสอบ B5 ครั้งที่ 1 — ไม่ผ่าน (30 ส.ค. 2026, ก่อนแก้)

| ขั้นตอน | ผลที่ได้ |
|---|---|
| ปัดแอปทิ้งจาก app switcher | process ตาย |
| ถอด/ใส่แบต K9P แล้วรอ 5 นาที | **ไม่มี notification** |
| เปิดแอปดู log | **ไม่มีบรรทัดใด ๆ เลย** |
| (เทียบ) ข้อ 2 background ไม่ kill | ผ่านปกติ |

**สาเหตุที่พบ (ตรวจจากโค้ดจริง + header ไม่ใช่การเดา — เหตุผลเต็มใน ARCHITECTURE.md
ADR-10):** `CLLocationManager` ถูกสร้างที่ `IBeaconRangingManager.init()` ที่เดียว
ซึ่งวิ่งตอน `BeaconKitIosPlugin.register(with:)` เท่านั้น และ register วิ่งจาก
`didInitializeImplicitFlutterEngine` ที่ header ของ Flutter ระบุว่าเกิด "such as
when created by a FlutterViewController from a storyboard"
(`FlutterEngine.h:476-490`) — คือผูกกับการที่ **UI ถูกสร้าง**

ตอน iOS ปลุก process ที่ถูกฆ่าขึ้นมาเบื้องหลัง ไม่มี scene ถูก connect จึงไม่มี
`FlutterViewController` ไม่มี engine ไม่มีการ register plugin → **ไม่มี location
manager และไม่มี delegate ให้ CoreLocation เรียก**

ซ้ำร้าย เส้นทางเขียน log เดิมวิ่งผ่าน Dart ทั้งหมด ซึ่งก็ต้องมี engine เหมือนกัน —
**เครื่องมือวัดตายพร้อมกับสิ่งที่มันควรวัด** ทำให้ผลออกมาเป็น "ไม่มีอะไรเลย" ที่
แยกไม่ออกว่าแอปไม่ถูกปลุก หรือถูกปลุกแล้วแต่ event ไปไม่ถึง

**สิ่งที่แก้ (30 ส.ค. 2026):** สร้าง `CLLocationManager` + ตั้ง delegate ตั้งแต่
`didFinishLaunchingWithOptions` ผ่าน
`BeaconKitIosPlugin.startBackgroundRegionMonitoring()`, อ่าน region ที่ระบบเก็บไว้
ข้าม launch กลับมา (**อ่านอย่างเดียว ห้ามหยุด monitor ในเส้นทาง init**), buffer
event ที่มาก่อน Dart subscribe, และย้ายการเขียน log + ยิง notification ไปเป็น
**โค้ด native ล้วน** ที่ไม่พึ่ง Flutter engine

**ไม่ได้แตะ logic ของ CoreLocation/region เดิมเลย** — ข้อ 2 พิสูจน์แล้วว่ามันถูก
ปัญหาอยู่ที่ "ไม่มีใครสร้าง manager ในรอบ launch นั้น" ไม่ใช่ที่ตัว region monitoring

เพื่อพิสูจน์ B5 ต้องแยกให้ออกว่า event ที่ได้มาเกิดตอน **แอปรันอยู่เบื้องหลังอยู่แล้ว**
(ไม่ได้พิสูจน์อะไรมาก) หรือตอน **process ถูกฆ่าไปแล้วแล้ว iOS ปลุกขึ้นมาใหม่**
(นี่คือสิ่งที่ต้องการ) — ปัญหาคือ **iOS ไม่มี API เดียวที่ตอบเรื่องนี้ตรง ๆ**

### วิธีที่เลือกใช้ และเหตุผล (ค้นคว้าแล้ว ไม่ได้เดา)

ใช้ **2 สัญญาณอิสระ** แล้วบันทึก**ทั้งสัญญาณดิบและข้อสรุป**ลง log ทุกบรรทัด

| สัญญาณ | ที่มา | ใช้ยังไง |
|---|---|---|
| `UIApplication.LaunchOptionsKey.location` | Apple: "A key indicating that the app was launched to handle an incoming location event" / UIKit header: "The app was launched in response to a CoreLocation event" | **หลักฐานสนับสนุน** ไม่ใช่ตัวตัดสินหลัก — **ทดสอบจริงแล้วได้ `false` ทั้งที่ถูกปลุกจริง** ดูหัวข้อ 🔍 ข้างบน |
| แอปเคย `applicationDidBecomeActive` ใน process นี้หรือยัง | `UIApplication.State` + lifecycle callback | **ตัวตัดสินหลัก** |

**สูตรที่ใช้สรุป:**
- `applicationState == active` → `foreground`
- ไม่เคย active เลยใน process นี้ + อยู่ background → **`relaunchedFromTerminated`**
- เคย active แล้ว + อยู่ background → `background`

**เหตุผลที่ไม่ใช้ launch key เป็นตัวตัดสินหลัก ทั้งที่ความหมายตรงที่สุด:**
`UIApplicationLaunchOptionsLocationKey` **ถูก deprecate แล้วใน iOS 26.0** —
ยืนยันจาก SDK header จริง (`UIApplication.h:586`):

```
API_DEPRECATED("Adopt CLLocationUpdate or CLMonitor, or use
CLLocationManagerDelegate from CoreLocation to handle expected location events
after scene connection.", ios(4.0, 26.0), ...)
```

สังเกตว่านี่เป็น **เลขเวอร์ชันจริง (26.0)** ไม่ใช่ `API_TO_BE_DEPRECATED` แบบที่
`CLBeaconRegion` เป็น — และทางเลือกที่ Apple แนะนำคือ `CLMonitor` ซึ่ง **ADR-6
หัวข้อ 4 ตัดสินแล้วว่ายังไม่ย้ายในรอบนี้** ถ้าพึ่ง key นี้ตัวเดียวแล้ววันหนึ่ง Apple
ถอดออกจริง การทดสอบจะพัง**เงียบ ๆ** (ได้ `false` เสมอ = สรุปว่าไม่เคยถูกปลุกเลย
ทั้งที่จริงถูกปลุก) ซึ่งเป็นความล้มเหลวชนิดที่แย่ที่สุดคือดูเหมือนทำงานปกติ

ส่วนสัญญาณ "เคย active หรือยัง" **ไม่พึ่ง API ที่ deprecated เลย** และตั้งอยู่บน
ข้อเท็จจริงของ lifecycle: process ที่ผู้ใช้เปิดเองต้องผ่าน active เสมอ ส่วน process
ที่ระบบสร้างขึ้นมาเองเพื่อส่ง location event จะไม่เคยผ่าน

**อัปเดตหลังทดสอบจริง (30 ส.ค. 2026):** ความเสี่ยงที่กลัวไว้ข้างบนไม่ใช่แค่ทฤษฎี —
เกิดขึ้นจริงทันทีในการใช้งานครั้งแรก `launchKey` ได้ `false` ทั้งสองรอบทั้งที่แอปถูก
ปลุกจากสถานะ terminated จริง ถ้าเลือกใช้ key นี้เป็นตัวตัดสินหลัก B5 จะถูกรายงานว่า
"ไม่ผ่าน" ทั้งที่ผ่าน — ดูหัวข้อ 🔍 ข้างบนสำหรับสาเหตุที่เป็นไปได้ (ยังเป็น open
question)

**ทำไมถึงบันทึกสัญญาณดิบไว้ด้วย ไม่ใช่แค่ข้อสรุป:** ถ้าภายหลังพบว่าสูตรข้างบนผิด
ข้อมูลดิบใน log ยังตรวจย้อนกลับได้โดยไม่ต้องทดสอบใหม่ทั้งรอบ (การทดสอบ B5 หนึ่ง
รอบต้องรอให้ iOS terminate แอปจริง ซึ่งควบคุมเวลาไม่ได้ ทำซ้ำแพง)

### รูปแบบแต่ละบรรทัดใน log

```
2026-08-30T14:23:06.980+07:00	launch	-	relaunchedFromTerminated	launchKey=true everActive=false state=background uptime=0.0s monitoredRegions=[bigc-fleet-wide]
2026-08-30T14:23:07.123+07:00	enter	bigc-fleet-wide	relaunchedFromTerminated	launchKey=true everActive=false state=background uptime=0.8s
```
`timestamp(ISO8601+tz)` TAB `event` TAB `regionIdentifier` TAB `ข้อสรุป` TAB `สัญญาณดิบ`

**บรรทัด `launch` (เพิ่ม 30 ส.ค. 2026)** เขียนทุกครั้งที่ process เริ่มทำงาน ไม่ว่า
รอบนั้นจะมี region event หรือไม่ — มีไว้เพื่อแยกสองอย่างที่รอบทดสอบก่อนหน้าแยกไม่ออก:

| สิ่งที่เห็นใน log | แปลว่า |
|---|---|
| ไม่มีบรรทัด `launch` ใหม่เลย | **iOS ไม่ได้ปลุกแอป** — ปัญหาอยู่ที่ region/สิทธิ์/ระยะ beacon |
| มี `launch` แต่ `monitoredRegions=[]` | ถูกปลุกแล้ว แต่ไม่มี region ค้างในระบบ — ไม่น่าถูกปลุกตั้งแต่แรก ให้สงสัยว่ามีโค้ดไปล้าง region ทิ้ง |
| มี `launch` + `monitoredRegions=[…]` แต่ไม่มี `enter`/`exit` ตามมา | ถูกปลุกจริงและ region ยังอยู่ แต่ **event ไปไม่ถึง handler** — คนละสาเหตุคนละวิธีแก้ |
| มี `launch` แล้วตามด้วย `enter`/`exit` ที่เป็น `relaunchedFromTerminated` | **B5 ผ่าน** |

**ผู้เขียนไฟล์นี้คือโค้ด native** (`example/ios/Runner/BackgroundEvidenceLog.swift`)
ไม่ใช่ Dart — จงใจให้มีผู้เขียนรายเดียว ถ้าปล่อยให้ Dart เขียนด้วยจะได้บรรทัดซ้ำ
สองชุดต่อหนึ่ง event ตอน foreground แล้วนับผลผิด

ไฟล์อยู่ใน **Application Support** ของแอป (ไม่ใช่ Documents — ไม่ต้องการให้โผล่ใน
Files app และไม่ใช่ Caches ที่ระบบล้างเองได้) เขียนแบบ append + flush ทันทีทุกบรรทัด
เพราะ iOS อาจ suspend process ทันทีหลังจบงาน ถ้าค้างใน buffer จะเสียหลักฐานทั้งบรรทัด

### วิธีใช้ทดสอบ B5

> **หมายเหตุ:** ขั้นตอนชุดนี้ **ทำครบและผ่านแล้ว 2 รอบเมื่อ 30 ส.ค. 2026**
> (ผลอยู่ในหัวข้อ ✅ ด้านบน) เก็บไว้เป็นวิธีทำซ้ำสำหรับการ regression test

- [x] เปิดแอป กด **"Start region monitoring"** (ไม่ใช่ "Start scan")
- [x] ตรวจว่าแผงบอกว่าสิทธิ์เป็น **Always** — ถ้าเป็น When In Use จะไม่ถูกปลุกตอนถูก kill
      (ต้องไปตั้งที่ Settings เพราะ iOS ไม่ให้ขอ Always ซ้ำ)
- [x] กด **"ดู log" → ล้าง log** เพื่อเริ่มรอบสะอาด
- [x] **kill แอปจากตัวสลับแอป** (swipe ขึ้น) ให้ process ตายจริง
- [x] เดินออกนอกระยะ beacon แล้วเดินกลับเข้ามา (ใช้วิธีถอด/ใส่แบต K9P)
- [x] ต้องเห็น **notification บนหน้าจอล็อกโดยไม่ต้องเปิดแอป**
- [x] เปิดแอป → ดู log → **บรรทัดนั้นต้องเป็น `relaunchedFromTerminated`**
      ถ้าเป็น `background` แปลว่า process ไม่ได้ตายจริง ให้ทำซ้ำ
- [x] **ถ้ายังไม่ผ่าน ให้อ่านบรรทัด `launch` ก่อนสรุป** — ตารางในหัวข้อ "รูปแบบแต่ละ
      บรรทัดใน log" ข้างบนบอกว่าแต่ละแบบแปลว่าอะไร อย่าสรุปว่า "ไม่รองรับ" จากการที่
      log ว่าง เพราะ log ว่างเป็นได้ทั้งสามสาเหตุที่ต่างกันสิ้นเชิง
- [x] **ต้องรันโหมด release หรือ profile เท่านั้น** — debug mode มี debugger ต่ออยู่
      พฤติกรรมการ terminate/relaunch ไม่ตรงกับของจริง (ดู CONTRIBUTING ข้อ 6)
- [x] บันทึกบรรทัดที่ได้ลงตารางสรุปด้านล่างเป็นหลักฐาน

**เกณฑ์ผ่านของ B5: ต้องเห็นบรรทัด `relaunchedFromTerminated` จริงในไฟล์ log**
notification อย่างเดียวไม่พอ เพราะไม่ได้บอกว่า process ตายจริงหรือแค่อยู่เบื้องหลัง

## 13. เครื่องล็อกอยู่ตอนถูกปลุก — log ถูกเขียนครบหรือไม่ (Data Protection)

**ขั้นตอนทดสอบ:** `ios_device_test_runbook.md` §3

### 🔶 หลักฐานสนับสนุน (ไม่ใช่การทดสอบเคสนี้ — สถานะยังเป็น "ยังไม่ทดสอบ")

จากการทดสอบ flapping ข้ามคืน 30-31 ส.ค. 2026 (ข้อ 16): เครื่อง**ล็อกและจอดับตลอด
14 ชั่วโมง** และ log ยังถูกเขียนครบ **176 บรรทัด**ตลอดช่วงนั้น รวมถึงบรรทัดที่เกิด
ตอนตี 1 ถึง 7 โมงเช้าซึ่งไม่มีใครแตะเครื่องเลย

**แปลว่า `completeUntilFirstUserAuthentication` ทำงานตามที่ตั้งใจจริง** — ความกังวล
ว่า Data Protection จะบล็อกการเขียนไฟล์ตอนเครื่องล็อกจนทำให้ "แอปตื่นแต่ไม่มีหลักฐาน"
**ไม่เกิดขึ้นในสภาพนี้**

⚠️ **ทำไมยังไม่เปลี่ยนสถานะเป็น "ผ่าน":**

- เป็นการสังเกตจากการทดสอบที่**ตั้งใจวัดเรื่องอื่น** ไม่ได้ควบคุมตัวแปรของเคสนี้
- **ไม่ได้ทดสอบเคสย่อย 13b** (รีบูตแล้วไม่ปลดล็อกเลย) ซึ่งเป็นขอบเขตจริงของ
  protection class นี้ และเป็นเคสที่คาดว่าจะเขียนไม่ได้
- ไม่ได้ตรวจว่ามี notification โผล่บนหน้าจอล็อกหรือไม่ (คนทดสอบหลับอยู่)
- เครื่องผ่านการปลดล็อกครั้งแรกมาแล้วก่อนเริ่ม ซึ่งเป็นเงื่อนไขที่ทำให้ไฟล์เข้าถึงได้
  อยู่แล้ว — ยังไม่ได้ทดสอบเงื่อนไขที่ไม่เป็นจริง

**ยังต้องทดสอบแบบควบคุมตามขั้นตอนเดิมใน runbook §3 ให้ครบ**

**สถานะ: ยังไม่ทดสอบ — Track B (ทดสอบบน simulator ไม่ได้)**

**ความเสี่ยงที่เคสนี้ป้องกัน:** สถานการณ์จริงของ B5 คือมือถืออยู่ในกระเป๋า **จอล็อก**
แล้วแอปถูกปลุก ถ้าไฟล์ log ได้ Data Protection class ที่เข้มเกินไป การเขียนจะล้มเหลว
เงียบ ๆ ตอนเครื่องล็อก = **แอปตื่นจริงแต่ไม่มีหลักฐาน** แล้วเราจะสรุปผิดว่า B5 ไม่ผ่าน
ทั้งที่มันผ่าน — เป็นความล้มเหลวชนิดที่หลอกให้ตัดสินใจผิดทั้งสปรินต์

### ค่าที่ตั้งไว้ในโค้ดตอนนี้ และเหตุผล

ตั้งเป็น **`NSFileProtectionCompleteUntilFirstUserAuthentication`** อย่างชัดเจน
(ทั้งที่ตัว directory และตัวไฟล์) ใน `AppDelegate.prepareLogFile`

ค่าที่เป็นไปได้ ยืนยันจาก SDK header `Foundation/NSFileManager.h:602-606`
(`iPhoneOS26.5.sdk`): `None`, `Complete`, `CompleteUnlessOpen`,
`CompleteUntilFirstUserAuthentication`, `CompleteWhenUserInactive` (iOS 17+)

**ค่า default ของ iOS คืออะไร — ตรวจจากเอกสาร Apple แล้ว ไม่ได้เดา:**

> "If you do not specify a protection level when creating a file, iOS applies the
> default protection level automatically."
>
> "**(Default)** The file is inaccessible until the first time the user unlocks the
> device. After the first unlocking of the device, the file remains accessible until
> the device shuts down or reboots."
>
> — [Encrypting your app's files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)

**แปลว่า default ตรงกับที่เราต้องการอยู่แล้ว** — แต่ยังตั้งเองเพราะการพึ่ง default
คือการพึ่งสิ่งที่เราไม่ได้ควบคุมและอาจเปลี่ยนตาม entitlement/เวอร์ชัน iOS ถ้าวันหนึ่ง
กลายเป็น `.complete` การทดสอบ B5 ทั้งหมดจะให้ผลลบลวงโดยไม่มีอะไรสะกิด การตั้งค่าชัด
คือการล็อกสมมติฐานที่การทดสอบทั้งชุดตั้งอยู่บนมัน

**ข้อจำกัดที่ยอมรับ:** ถ้าเครื่อง**รีบูตแล้วยังไม่เคยปลดล็อกเลยสักครั้ง** ไฟล์ระดับนี้
ยังเข้าถึงไม่ได้ → log จะหาย ระดับที่ต่ำกว่านี้คือ `.none` (ไม่เข้ารหัสเลย) ซึ่งไม่เหมาะ
กับไฟล์ที่บันทึกว่าผู้ใช้อยู่สาขาไหนเวลาใด — จึงยอมรับข้อจำกัดนี้ **เคสนี้ต้องทดสอบ
แยกด้วย** (ดู checklist ด้านล่าง)

**state store อื่นในเส้นทางเดียวกัน:** ตรวจแล้ว — เส้นทางนี้**ไม่ใช้ `UserDefaults`,
Keychain หรือที่เก็บ state อื่นเลย** ใช้แค่ไฟล์ log อย่างเดียว จึงไม่มีข้อจำกัดอื่น
ต้องตรวจเพิ่ม (ถ้าอนาคตเพิ่ม `UserDefaults` ต้องกลับมาตรวจ เพราะมันมีข้อจำกัด
protection class ของตัวเองเช่นกัน)

### สิ่งที่ทดสอบอัตโนมัติได้แล้ว vs ต้องใช้เครื่องจริง

| ส่วน | ทดสอบที่ไหน | สถานะ |
|---|---|---|
| `prepareLogFile` สร้างไฟล์ได้จริง | XCTest simulator | ✅ ผ่าน |
| เรียก `prepareLogFile` ซ้ำไม่ล้างไฟล์เดิม | XCTest simulator | ✅ ผ่าน |
| เขียนต่อท้ายได้จริง | XCTest simulator | ✅ ผ่าน |
| protection class เป็นค่าที่ตั้งไว้จริง | **เครื่องจริงเท่านั้น** | ⏭️ skip บน simulator |
| เขียนได้จริงตอนเครื่องล็อก | **เครื่องจริงเท่านั้น** | ❌ ยังไม่ทดสอบ |

**ทำไม simulator ตรวจ protection class ไม่ได้ — ยืนยันด้วยการรันจริงแล้ว:**
`attributesOfItem` คืน `.protectionKey` เป็น `nil` เสมอบน simulator แม้
`setAttributes` จะสำเร็จ เพราะ simulator ไม่ได้ implement Data Protection
(ไม่มี Secure Enclave ไม่มีสถานะล็อกแบบเครื่องจริง) XCTest 2 ตัวจึงใช้ `XCTSkip`
พร้อมเหตุผล **ไม่ใช่ assert แบบหลอกให้ผ่าน** — จะ assert จริงเมื่อรันบนอุปกรณ์จริง

### เช็คลิสต์

- [ ] รัน XCTest **บนอุปกรณ์จริง** (ไม่ใช่ simulator) → 2 เทสต์ที่ skip ต้องเปลี่ยนเป็น
      ผ่าน และยืนยันว่า protection class เป็น `CompleteUntilFirstUserAuthentication`
- [ ] ตั้ง region monitoring แล้ว **ล็อกจอ** ทิ้งไว้ (อย่าแค่กดปิดหน้าจอชั่วคราว —
      ต้องเป็นสถานะล็อกจริง มี passcode)
- [ ] เดินออก/เข้าระยะ beacon ขณะจอยังล็อกอยู่
- [ ] ปลดล็อกเปิดแอป → **log ต้องมีบรรทัดของช่วงที่จอล็อก ครบทุก event**
      ถ้าขาดหายแปลว่า protection class ยังบล็อกการเขียนอยู่
- [ ] เทียบจำนวนบรรทัดใน log กับจำนวน notification ที่เห็นบนหน้าจอล็อก —
      **ถ้า notification มาแต่ log ไม่มีบรรทัด นั่นคืออาการของปัญหานี้พอดี**
- [ ] **เคสสุดขั้ว:** รีบูตเครื่อง แล้ว**ไม่ปลดล็อกเลย** (ข้ามการใส่ passcode) →
      เดินเข้าระยะ beacon → คาดว่า log จะเขียนไม่ได้ตามข้อจำกัดที่ยอมรับไว้
      บันทึกผลที่ได้จริงว่าตรงกับที่คาดหรือไม่

## 14. ระบบฆ่าแอปเองเพราะหน่วยความจำ (ไม่ใช่ผู้ใช้ปัดทิ้ง)

**สถานะ: ยังไม่ทดสอบ** — เป็นเคสที่สำคัญที่สุดที่เหลืออยู่

**ต่างจากข้อ 12 ตรงไหน:** ข้อ 12 คือ **ผู้ใช้ปัดแอปทิ้งเอง** ข้อนี้คือ **iOS ฆ่าแอป
เองเพราะหน่วยความจำไม่พอ** — เป็นคนละเส้นทางของ OS และเป็นเส้นทางที่เกิดกับผู้ใช้จริง
บ่อยกว่ามาก (ลูกค้า BigC แทบไม่มีใครปัดแอปทิ้งเอง) **ห้ามเหมารวมว่าข้อ 12 ผ่านแล้ว
ข้อนี้จะผ่านด้วย**

**ขั้นตอนทดสอบ:** ดู `ios_device_test_runbook.md` §2

### 🔶 หลักฐานสนับสนุนที่แข็งแรง (ยังไม่เปลี่ยนสถานะ — ต้องยืนยันแบบควบคุมตัวแปร)

log ของการทดสอบ flapping ข้ามคืน (ข้อ 16) มีบรรทัด `launch` **4 ครั้ง** ในไฟล์เดียว
ทั้งที่ **ไม่มีใครแตะเครื่องเลยทั้งคืน และไม่มีใครปัดแอปทิ้ง**

| launch | เวลา | อายุ process ที่บันทึกได้ | monitoredRegions |
|---|---|---|---|
| #1 | 30 ส.ค. 18:34:30 | 17 วินาที | `[k9p-default]` |
| #2 | 30 ส.ค. 19:35:30 | 0 วินาที | `[k9p-default]` |
| #3 | 30 ส.ค. 22:45:56 | **8 ชั่วโมง 29 นาที** | `[k9p-default]` |
| #4 | 31 ส.ค. 08:41:07 | 0 วินาที | `[k9p-default]` |

ทุกบรรทัดเป็น `relaunchedFromTerminated` (`everActive=false`, `state=background`)

> **หมายเหตุ 3 ก.ย. 2026 (ADR-16):** ทั้ง 4 แถวข้างบนเป็นบรรทัด `launch`
> (`uptimeMs≈0` เสมอโดยนิยาม) — ตามตาราง 6 ระดับใน ADR-16 หัวข้อ 3 (แถวที่ 2)
> บรรทัด `launch` ที่เป็น `relaunchedFromTerminated` **ยังเชื่อได้เต็มที่แม้บั๊ก
> `everActive` ค้าง `false` จะมีอยู่ก็ตาม** เพราะก่อนบรรทัดนี้ process ยังไม่มี
> ตัวตนเลย ไม่มีเวลาให้ทางเลือก "จริง ๆ คือ `background`" เป็นไปได้ — ข้อสังเกต
> เรื่อง "iOS terminate แอปเองแล้วปลุกกลับมา" ในย่อหน้าถัดไปจึงยังใช้ได้ตามเดิม
> ไม่ต้องตีความใหม่ (ต่างจากบรรทัด `enter`/`exit` ที่ห่างจาก `launch` ในหัวข้อ 12
> ซึ่งต้องอ่านตามตารางเดียวกันแถวอื่น)

**บรรทัด `launch` ใหม่ = process ใหม่** (`didFinishLaunchingWithOptions` วิ่งครั้งเดียว
ต่อ process) — เมื่อไม่มีใคร force-quit แปลว่า **iOS terminate แอปเองแล้วปลุกกลับมา
ด้วย region event** ซึ่งตรงกับสิ่งที่เคสนี้ต้องการพิสูจน์พอดี และ region ยังอยู่ครบ
ทุกครั้งที่ถูกปลุก

⚠️ **ทำไมยังไม่เปลี่ยนสถานะเป็น "ผ่าน":**

- เป็นการสังเกตจากการทดสอบที่**ตั้งใจวัดเรื่องอื่น** ไม่ได้ควบคุมตัวแปร
- **ไม่ได้พิสูจน์ว่าสาเหตุการ terminate คือแรงกดดันหน่วยความจำ** — iOS terminate แอป
  เบื้องหลังได้ด้วยเหตุผลอื่น ซึ่งอาจเป็นคนละเส้นทางของ OS
- **prerequisite เรื่อง process UUID ยังไม่ได้ทำ** — การสรุปว่า "process ใหม่" รอบนี้
  อาศัยบรรทัด `launch` กับ `uptime` ซึ่งในเคสนี้ชัดพอ แต่ยังไม่ใช่หลักฐานระดับที่
  ตั้งใจจะเก็บ
- ไม่ได้ตรวจว่า notification ถูกส่งถึงจริงในรอบที่ถูกปลุก (คนทดสอบหลับอยู่)

**ยังต้องทดสอบแบบควบคุมตามขั้นตอนใน runbook §2 ให้ครบ** — แต่หลักฐานนี้ทำให้
**คาดได้ว่าจะผ่าน** และควรทำเคสนี้ก่อนเคสอื่น

### ⚠️ Prerequisite ที่ยังไม่ได้ทำ — เพิ่ม process UUID ลงทุกบรรทัด log

ตอนนี้เราแยก "process ใหม่" ออกจาก "process เดิม" ด้วย `uptime` ซึ่งตีความได้ไม่ชัด
(process เดิมที่เพิ่งกลับจาก suspend ก็มี uptime สั้นได้เหมือนกัน) ควรเพิ่ม **UUID
สุ่มหนึ่งค่าตอน process เริ่ม** ลงทุกบรรทัด — ถ้า UUID เปลี่ยน แปลว่าเป็น process ใหม่
แน่นอน ไม่ต้องเดาจากตัวเลขเวลา

**เป็นงานแก้โค้ด ยังไม่ได้ทำ จะทำเป็น PR แยก** — ถ้าทดสอบเคสนี้ก่อนมีสิ่งนี้
ให้ระบุในหมายเหตุว่าการอ่านผลอาศัยการตีความ `uptime` ซึ่งเถียงได้

- [ ] เตรียมมาตรฐานครบตาม runbook §0
- [ ] กด home (ไม่ปัดทิ้ง) → สร้างแรงกดดันหน่วยความจำ → ถอด/ใส่แบต
- [ ] ตรวจว่า `uptime` สั้น + `everActive=false` (= process ใหม่) ไม่ใช่ process เดิม
- [ ] บันทึกผลลงตารางสรุปด้านล่าง

## 15. เก็บสถิติ enter/exit ให้พอใช้กำหนด timeout

**สถานะ: ยังไม่ทำ**

**ทำไมต้องมีข้อนี้แยก:** ตัวเลขที่บันทึกไว้ในข้อ 2 และข้อ 12 มาจากการวัดไม่กี่รอบ
ซึ่ง**ไม่พอ**ให้ทีม backend ใช้กำหนด timeout จริง — โดยเฉพาะ exit ที่ช่วงกว้างมาก
ตัวเลขที่มีอยู่ใช้เป็น**ค่าอ้างอิงหยาบ ๆ** ได้เท่านั้น

**ขั้นตอนทดสอบ:** ดู `ios_device_test_runbook.md` §7

- [ ] ทำซ้ำ 5 รอบต่อเงื่อนไข (foreground/background × enter/exit)
- [ ] บันทึกค่าต่ำสุด / สูงสุด / ค่ากลาง
- [ ] **บันทึกจำนวนรอบที่ไม่ยิง event เลยด้วย** — ห้ามตัดทิ้ง ไม่งั้นตัวเลขจะดูดีเกินจริง
- [ ] ทดลองแยก: ปิด ranging เหลือแต่ region monitoring แล้วดูว่า exit เสถียรขึ้นไหม

## 16. Region flapping ระยะยาว (วางนิ่งข้ามคืน)

**สถานะ: ทดสอบแล้ว 1 รอบ — พบ flapping รุนแรง (ไม่ใช่บั๊ก แต่ต้องมี debounce)**

**ขั้นตอนทดสอบ:** `ios_device_test_runbook.md` §9

**ทำไมต้องมีเคสนี้:** เคสอื่นทั้งหมดวัด "ตอบสนองเร็วแค่ไหน" เคสนี้วัด **"เงียบพอ
หรือเปล่าตอนไม่มีอะไรเกิดขึ้น"** ซึ่งเป็นคนละคำถามและสำคัญกว่าสำหรับการใช้งานจริง —
ระบบที่ตอบสนองเร็วแต่ยิง event มั่วตอนไม่มีอะไรเกิดขึ้น ใช้งานจริงไม่ได้

### ✅ ผลรอบที่ 1 (30-31 ส.ค. 2026)

**เงื่อนไข**

| รายการ | ค่า |
|---|---|
| ระยะเวลา | 14 ชั่วโมง 6 นาที (18:34 → 08:41) |
| สภาพมือถือ | วางนิ่งกับที่ · จอดับ · ล็อกเครื่อง · แอปอยู่เบื้องหลัง |
| สภาพ K9P | วางนิ่ง ไม่ถอดแบต |
| การรบกวน | ไม่มีใครขยับอะไรเลยทั้งคืน |
| ระยะทาง/สิ่งกีดขวางระหว่างมือถือกับ beacon | _(ผู้ทดสอบกรอก — ไม่ได้บันทึกไว้รอบนี้)_ |
| iPhone รุ่น / iOS | _(ผู้ทดสอบกรอก)_ |
| K9P รุ่น/firmware | _(ผู้ทดสอบกรอก)_ |

**ผล**

| ตัวชี้วัด | ค่า |
|---|---|
| enter (นับดิบทุกบรรทัด) | **86 ครั้ง** |
| exit (นับดิบทุกบรรทัด) | **86 ครั้ง** |
| enter หลังตัด artifact ของการส่ง event ค้าง | 71 ครั้ง |
| ลำดับ enter/exit สลับกันครบคู่ | ✅ ไม่มี event ซ้อนหรือหาย |
| ช่วงที่อยู่ในโซน — มัธยฐาน / p90 / สูงสุด | 30.1 วินาที / 1 นาที 56 วินาที / 3 ชั่วโมง 10 นาที |
| ช่วงที่หลุดออก — มัธยฐาน / p90 / **สูงสุด** | 25.2 วินาที / 1 นาที 30 วินาที / **3 นาที 29 วินาที** |
| ช่วงเวลาที่ flap ถี่ที่สุด | 05:00-07:00 (75 จาก 86 ครั้ง) |
| ช่วงเวลาที่นิ่งที่สุด | 18:00-05:00 (6 ครั้งใน 10.5 ชั่วโมง) |

ไฟล์ดิบ: `docs/test-data/2026-08-30_overnight_region_flapping.log`
วิเคราะห์ซ้ำ: `dart run tool/analyze_region_log.dart <ไฟล์>`

⚠️ **ตัวเลข enter รายงานได้หลายค่า ต้องระบุทุกครั้งว่าใช้แบบไหน** — 86 (ดิบ) /
71 (ตัด artifact) / 85 (ช่วงที่มี exit ปิดครบคู่) การเทียบผลข้ามรอบจะมีความหมาย
ก็ต่อเมื่อใช้นิยามเดียวกัน

### เกณฑ์ว่าเท่าไหร่ถือว่ายอมรับได้

**ยังไม่มีเกณฑ์ที่ตกลงกับฝ่ายธุรกิจแล้ว** — ข้างล่างเป็นข้อเสนอเริ่มต้นจากทีมพัฒนา

| ระดับ | จำนวน enter ดิบต่อ 8 ชั่วโมงที่วางนิ่ง | ความหมาย |
|---|---|---|
| ดี | ≤ 5 | ไม่ต้องทำอะไรเพิ่ม |
| ยอมรับได้ | 6-20 | ชั้น debounce ตาม ADR-11 เอาอยู่สบาย |
| ต้องระวัง | 21-60 | ต้องยืนยันว่าค่า debounce ที่ตั้งไว้ยังกรองได้จริง |
| **รอบนี้อยู่ตรงนี้** | **> 60** | ต้องมี debounce แน่นอน ห้าม deploy โดยไม่มี |

**สำคัญ: flapping ไม่ใช่บั๊กของ SDK** — เป็นพฤติกรรมของ CoreLocation + สภาพสัญญาณ
สิ่งที่วัดคือ "สภาพแวดล้อมนี้แย่แค่ไหน" ไม่ใช่ "โค้ดเราผิดหรือเปล่า" การแก้อยู่ที่
ชั้น debounce (ADR-11) ไม่ใช่ที่ region monitoring

### ต้องทำต่อ

- [ ] ทำซ้ำโดยบันทึกระยะทาง + สิ่งกีดขวางด้วย (รอบนี้ไม่ได้บันทึก จึงไม่รู้ว่า
      "ก้ำกึ่ง" คือกี่เมตร)
- [ ] ทำซ้ำในสภาพ **ใกล้ชัดเจน** และ **ไกลชัดเจน** เพื่อยืนยันว่า flap เกิดเฉพาะ
      ระยะก้ำกึ่งจริงหรือไม่
- [ ] เก็บอย่างน้อย 3 จุดในสาขาจริงที่มีสภาพต่างกัน ก่อนล็อกค่า debounce ลง production
- [ ] หาสาเหตุว่าทำไม flap กระจุกที่ 05:00-07:00 (ยังไม่รู้ — ดู ADR-11 หัวข้อ 3)

## 17. Android — สแกนตอนแอปเปิดอยู่ (ก้อนที่ 1)

**สถานะ: ยังไม่ทดสอบบนเครื่องจริง** — code-complete เท่านั้น

**เครื่องเป้าหมาย:** Redmi Note 9 · Android 12 (MIUI) — _(ผู้ทดสอบกรอกรุ่น MIUI)_

**เป้าหมายของเคสนี้:** พิสูจน์ว่า **beacon ตัวเดียวกันขึ้นบนทั้ง iPhone และ
Android ด้วยโค้ดถอดรหัสชุดเดียวกัน** (`IBeaconParser` / `EddystoneParser` ใน
`beacon_kit_platform_interface`)

⚠️ **สิ่งที่ยังไม่ถูกพิสูจน์เลยแม้แต่น้อยจนกว่าจะรันเครื่องจริง:** บน iOS
`IBeaconParser` **ไม่เคยถูกเรียกใช้จริงสักครั้ง** เพราะ CoreLocation ถอด
uuid/major/minor ให้ก่อนเสมอ — Android จะเป็นการใช้งานจริงครั้งแรกของ parser ตัวนี้
unit test ที่มีอยู่ใช้ byte ที่**เราประกอบขึ้นเอง**จากค่าที่ iOS ถอดมา ไม่ใช่ byte
ที่ดักจับจากอากาศจริง จึงพิสูจน์ได้แค่ว่า "ต่อสายถูก" เท่านั้น

### เตรียมก่อนทดสอบ

- [ ] ติดตั้งด้วย `flutter run -d <device>` หรือ `flutter build apk --debug`
- [ ] เปิด Bluetooth และ **เปิดสวิตช์ Location ของระบบ** (ยังไม่ยืนยันว่าจำเป็น —
      ดู ADR-12 หัวข้อ 1 · ให้ทดสอบทั้งเปิดและปิดแล้วบันทึกผล)
- [ ] วาง K9P ตัวเดียวกับที่ใช้ทดสอบ iPhone ไว้ใกล้ ๆ

### เช็คลิสต์

- [ ] กด **Start scan** ครั้งแรก → ต้องเห็น **prompt ขอสิทธิ์ของ Android จริง**
      (Bluetooth สแกน + Location)
- [ ] กด **Allow** → ต้องเห็นรายการ beacon ขึ้นภายในไม่กี่วินาที
- [ ] **เทียบกับ iPhone:** `uuid` / `major` / `minor` ต้องตรงกันทุกตัว
      (ถ้าไม่ตรง = `IBeaconParser` ถอด byte จริงไม่ถูก → **หยุดแล้วรายงานทันที**
      เพราะแปลว่า fixture ที่ใช้ทดสอบมาตลอดอาจไม่ตรงกับของจริง)
- [ ] `deviceId` ต้องเป็น **MAC address** (Android ให้ MAC จริง ต่างจาก iOS ที่ให้
      UUID สุ่มต่อแอป — ADR-1)
- [ ] RSSI ต้องเปลี่ยนตามระยะจริง
- [ ] กด **Don't Allow** → ต้องเห็นข้อความบอกเหตุผล **ห้ามเงียบ**
- [ ] กด Don't Allow แล้วเลือก "ไม่ถามอีก" → กด Start ซ้ำ → ต้องได้ข้อความว่าถูก
      ปฏิเสธถาวรและถูกพาไปหน้า Settings **ห้ามค้างรอ prompt ที่ไม่มีวันมา**
- [ ] ปิด Bluetooth แล้วกด Start → ต้องได้ `BLUETOOTH_UNAVAILABLE` ไม่ใช่เงียบ
- [ ] กด Start/Stop สลับกันเร็ว ๆ หลายครั้ง → ถ้าเจอ
      `SCAN_FAILED_SCANNING_TOO_FREQUENTLY` ให้บันทึกว่ากดกี่ครั้งในกี่วินาที
      (ADR-12: ตัวเลข throttle จริงยืนยันจากเอกสารไม่ได้ ต้องวัดเอง)
- [ ] Eddystone: ถ้ามีอุปกรณ์ที่ broadcast `0xFEAA` ต้องขึ้นเหมือนฝั่ง iOS

### สิ่งที่ต้องบันทึก

รุ่น MIUI · เวอร์ชัน Android · ผลการเทียบ uuid/major/minor กับ iPhone ·
พฤติกรรมเมื่อปิดสวิตช์ Location ของระบบ

## ค่าอ้างอิงสำหรับ regression (ตัวเลขที่วัดได้แล้วทั้งหมด)

รวมตัวเลขที่กระจายอยู่ตามหัวข้อข้างบนไว้ที่เดียว เพื่อให้เทียบตอนทดสอบซ้ำได้เร็ว
**นี่คือที่เดียวที่คัดลอกตัวเลขได้** — runbook จงใจไม่เก็บตัวเลขไว้เลย

| เงื่อนไข | enter | exit | จำนวนรอบที่วัด | ข้อ |
|---|---|---|---|---|
| background (กด home ไม่ปัดทิ้ง) | 5-8 วินาที | 30-50 วินาที | 1 | 2 |
| terminated รอบ 1 (force-quit) | 5 วินาที | 55 วินาที | — | 12 |
| terminated รอบ 2 (force-quit) | 3 วินาที | 30 วินาที | — | 12 |
| foreground | _(ยังไม่มีตัวเลข)_ | _(ยังไม่มีตัวเลข)_ | 0 | 1 |

⚠️ **ห้ามเอาตัวเลขเหล่านี้ไปตั้ง timeout โดยตรง** — จำนวนรอบน้อยเกินไป และยังไม่มีการ
บันทึกรอบที่ไม่ยิง event เลย (ดูข้อ 15) ค่าเหล่านี้ใช้เทียบว่า "เปลี่ยนไปมากผิดปกติ
หรือไม่" หลังแก้โค้ดเท่านั้น

## สรุปผล (กรอกหลังทดสอบจริง)

| ข้อ | ผ่าน/ไม่ผ่าน | วันที่ | อุปกรณ์ (iPhone รุ่น/iOS) | K9P (รุ่น/firmware) | หมายเหตุ/หลักฐาน |
|---|---|---|---|---|---|
| 1. Foreground (แอปเปิดอยู่) | **ไม่ผ่าน** → แก้แล้ว **รอทดสอบซ้ำ** | 30 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P _(ผู้ทดสอบกรอก)_ | ไม่เห็นอะไรเลยเพราะไม่ได้ implement `willPresent` — event มาจริงแต่ iOS ไม่แสดงให้ ดูหัวข้อ 2 🐞 |
| 1b. Permission prompt | **ผ่าน** (ครบทุกลำดับแล้ว) | 29 ส.ค. 2026 + **31 ส.ค. 2026** | iPhone _(ผู้ทดสอบกรอก)_ | K9P 2 ตัว _(รุ่น/fw: ผู้ทดสอบกรอก)_ | บั๊กรอบ 1+2 แก้แล้วและ retest ผ่านครบ · ลำดับ Don't Allow → Settings → กลับแอปโดยไม่ force quit → สแกนได้ปกติ (31 ส.ค.) = **ปิดบั๊กรอบ 2 สมบูรณ์** — ดูหัวข้อ 1 |
| 2. iBeacon ranging + region enter/exit (background ไม่ kill) | **ผ่าน** | 29-30 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P 2 ตัว _(รุ่น/fw: ผู้ทดสอบกรอก)_ | เจอทั้ง 2 ตัว uuid `7777772e-…000001` major/minor 229/24333 และ 228/24332 แยกอุปกรณ์ถูก, proximity/RSSI resolve จริง · **enter 5-8 วิ / exit 30-50 วิ (วัดครั้งแรก ยังไม่ทำซ้ำ)** · ไม่ใช่ B5 — process ยังมีชีวิตอยู่ |
| 3. หาย/ปิดเครื่อง | ยังไม่ทดสอบ | — | — | — | — |
| 4. Background mode | ยังไม่ทดสอบ | — | — | — | — |
| 5. เพดาน 20 regions | ยังไม่ทดสอบ | — | — | — | — |
| 6. Eddystone/CoreBluetooth | **ผ่าน** | 29 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | อุปกรณ์บุคคลที่สาม (ไม่ใช่ K9P, ไม่รู้ยี่ห้อ) | decode `EddystoneUrlFrame(txPower: -38, url: https://www.google.com/)` ที่ -88 dBm — ยืนยัน vendor-agnostic จริง / ยังไม่เจอ UID/TLM frame |
| 7. Bluetooth ปิดกลางคัน | ยังไม่ทดสอบ | — | — | — | — |
| 9. region ซ้อนทับ (enter ซ้ำ?) | ยังไม่ทดสอบ | — | — | — | ADR-8 open question — ห้ามเขียน dedupe จนกว่าจะรู้ผล |
| 10. ไม่มีอินเทอร์เน็ต | ยังไม่ทดสอบ | — | — | — | Apple ระบุว่า region monitoring ต้องการ network connectivity |
| 11. เทียบ advertising mode | **ยังทำไม่ได้** | — | — | — | ติด GATT config ที่ยังไม่ implement |
| 12. B5 wake-from-terminate | **ผ่าน** (ทดสอบ 2 รอบ) | 30 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P _(ผู้ทดสอบกรอก)_ | release/profile build · ลบแอปติดตั้งใหม่ · **force-quit โดยผู้ใช้** · exit 55/30 วิ enter 5/3 วิ · log มี `everActive=false state=background` ทั้งสองรอบ **แต่เหตุผลรองรับแก้เป็นเวลา (`uptime` ใกล้ศูนย์หลัง `launch`) แล้วตาม ADR-16 — ห้ามอ้าง `everActive=false` เป็นหลักฐานอีกต่อไป** (ดูหัวข้อ 12) · **`launchKey=false` ทั้งสองรอบ** สาเหตุยืนยันแล้วว่าเป็นสัญญาณตายทางโครงสร้างภายใต้ scene lifecycle (ดูหัวข้อ 12 — ADR-16 §2) · ครั้งที่ 1 ไม่ผ่านเพราะไม่มีใครสร้าง `CLLocationManager` ในรอบ cold launch (ADR-10) · **ยังไม่ re-verify บนอุปกรณ์จริงหลังแก้ ADR-16** (runbook §11) |
| 13. เครื่องล็อกตอนถูกปลุก (Data Protection) | ยังไม่ทดสอบ — **มีหลักฐานสนับสนุน** | — | — | — | log ถูกเขียนครบ 176 บรรทัดขณะเครื่องล็อก/จอดับ 14 ชม. (ข้อ 16) = Data Protection ไม่ได้บล็อกอย่างที่กังวล · ยังไม่ได้ทดสอบเคสย่อย 13b (รีบูตแล้วไม่ปลดล็อก) · Track B — simulator ตรวจไม่ได้ (XCTest skip) ถ้าพลาดข้อนี้จะสรุปผิดว่า B5 ไม่ผ่านทั้งที่ผ่าน |
| 14. ระบบฆ่าแอปเองจากหน่วยความจำ | ยังไม่ทดสอบ — **มีหลักฐานสนับสนุนแข็งแรงแล้ว** | — | — | — | log ข้ามคืน (ข้อ 16) มีบรรทัด `launch` 4 ครั้งโดยไม่มีใครแตะเครื่อง = iOS ฆ่าเองแล้วปลุกกลับมาด้วย region event · ยังต้องยืนยันแบบควบคุมตัวแปร · **เคสสำคัญที่สุดที่เหลือ** — คนละเส้นทางกับข้อ 12 และเกิดกับผู้ใช้จริงบ่อยกว่า · มี prerequisite เป็นงานโค้ด (process UUID ใน log) ที่ยังไม่ได้ทำ |
| 15. สถิติ enter/exit ให้พอกำหนด timeout | ยังไม่ทำ | — | — | — | ตัวเลขที่มีตอนนี้มาจากการวัดไม่กี่รอบ ใช้กำหนด timeout จริงไม่ได้ |
| 17. Android สแกนตอนแอปเปิดอยู่ | ยังไม่ทดสอบ | — | — | — | code-complete · เป้าหมาย: เทียบ uuid/major/minor กับ iPhone ให้ตรง · **ถ้าไม่ตรง = parser ถอด byte จริงไม่ถูก ให้หยุดแล้วรายงาน** |
| 16. Region flapping ระยะยาว | **ทดสอบแล้ว 1 รอบ — พบ flapping รุนแรง** | 30-31 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P _(ผู้ทดสอบกรอก)_ | วางนิ่ง 14 ชม. ได้ enter 86 / exit 86 ครั้งทั้งที่ไม่มีอะไรขยับ · ไม่ใช่บั๊กของ SDK แต่**ต้องมีชั้น debounce ตาม ADR-11 ก่อน deploy** · ไฟล์ดิบใน `docs/test-data/` |

**อัปเดต 29 ส.ค. 2026 — สรุปสถานะล่าสุด**

ทดสอบบนอุปกรณ์จริงไปแล้ว 3 รอบ (iPhone + K9P จริง 2 ตัว + อุปกรณ์ Eddystone
บุคคลที่สามที่บังเอิญอยู่ในระยะ)

## 18. ปิด Bluetooth ระหว่างเฝ้า `CLBeaconRegion` — `didExitRegion` ยิงหรือไม่

**สถานะ: ยังไม่ทดสอบบนเครื่องจริง**

**ขั้นตอนลงมือ:** `ios_device_test_runbook.md` §10 (และเคสย่อย 18b)

**เครื่องที่ใช้ทดสอบ:** _(ผู้ทดสอบกรอก — รุ่น iPhone / เวอร์ชัน iOS)_

⚠️ **ห้ามกรอกผลถ้าช่องเครื่องยังว่าง** — ผลที่ไม่รู้ว่ามาจากเครื่องรุ่นไหน iOS
เวอร์ชันไหน เอาไปเทียบกับรอบอื่นไม่ได้ และนี่คือข้อบกพร่องที่ทำให้ผลของสองรอบก่อน
หน้าสืบกลับไม่ได้ (ดูหมายเหตุท้ายไฟล์)

**ทำไมต้องมีเคสนี้:** ค้นเอกสารของ Apple แล้ว **ไม่พบประโยคที่ระบุพฤติกรรมนี้**
บันทึกไว้ที่ `docs/sources/ios_sensing_availability.md` หัวข้อ "หาแหล่งอ้างอิงไม่ได้"
· คำตอบเปลี่ยนการออกแบบชั้นกรอง visit โดยตรง (`prototype/visit_filter/SENSING.md`
หัวข้อ 2): ถ้า CoreLocation ยิง `exit` ตอน Bluetooth ปิด ฝั่ง iOS จะเจอบั๊ก visit
ปลอมแบบเดียวกับ Android **และ `SensingLost` ช่วยไม่ได้ถ้า `exit` มาถึงก่อนที่เราจะ
รู้ตัวว่าตาบอด**

**เคสนี้ต่างจากข้อ 7 อย่างไร:** ข้อ 7 วัดว่า *ตอนกด Start scan* แล้ว Bluetooth ปิด
อยู่ จะได้ `BLUETOOTH_UNAVAILABLE` หรือไม่ — เป็นเส้นทาง CoreBluetooth ตอนแอปเปิดอยู่
· ข้อ 18 วัด **เส้นทาง CoreLocation region monitoring ตอนแอปอยู่เบื้องหลัง** ซึ่ง
คนละ API และคนละสถานการณ์กันคนละเรื่อง

- [ ] 18 — ปิดจาก **Settings**
- [ ] 18b — ปิดจาก **Control Center** _(ไม่พบเอกสารที่ระบุว่า iOS แยกสองสถานะนี้
      หรือไม่ — ถ้าผลต่างกันคือข้อค้นพบที่ต้องบันทึกทันที)_

**สิ่งที่ต้องกรอกเมื่อทำเสร็จ**

| ช่อง | ค่า |
|---|---|
| รุ่น iPhone / เวอร์ชัน iOS | |
| รุ่น / firmware K9P | |
| เวลาปิด Bluetooth (ถึงวินาที) | |
| เวลาของ `exit` แรกหลังจากนั้น | |
| มี `enter` ตามมาระหว่าง Bluetooth ปิดหรือไม่ | |
| `enter`/`exit` ในช่วง baseline 60 นาที | |
| `enter`/`exit` ในช่วง 60 นาทีหลังปิด Bluetooth | |
| เวลาเปิด Bluetooth กลับ / เวลา `enter` ถัดไป | |

⚠️ **บรรทัด `exit` เดียวยังไม่ใช่คำตอบ** — ข้อ 16 วัดได้ว่า region flapping เกิดเอง
ตลอดคืนโดยไม่มีใครแตะอะไร ตัวแยกคือ **รูปแบบ**: flap ปกติ `enter`/`exit` สลับกัน ·
ตาบอดจริง `exit` แล้วเงียบสนิทไม่มี `enter` ตามมาเลย · จึงต้องเทียบกับ baseline
ของคืนเดียวกันเท่านั้น ห้ามเทียบข้ามคืนหรือข้ามเครื่อง

---

**ผ่านแล้ว:** ข้อ 2 (iBeacon ranging — แยก 2 อุปกรณ์ที่ UUID เดียวกันด้วย
major/minor ได้ถูก, proximity/RSSI resolve จริง), ข้อ 6 (Eddystone ผ่าน
CoreBluetooth — decode URL frame จากอุปกรณ์ที่ไม่รู้จักมาก่อนได้ถูก) และข้อ 1
เฉพาะส่วน Allow ครั้งเดียว + กด Start ซ้ำระหว่าง prompt

**ยังไม่ผ่าน / ยังไม่ทดสอบ:**
- ข้อ 1 ส่วนลำดับ Don't Allow → เปิดสิทธิ์ใน Settings → กลับแอปโดยไม่ force quit
  — **แก้แล้ว รอ retest** (เคยเป็นบั๊กรอบ 2) ยังไม่ใช่ "ผ่าน"
- ข้อ 3 (beacon หายจากระยะ), ข้อ 4 (background mode), ข้อ 5 (เพดาน 20 regions),
  ข้อ 7 (Bluetooth ปิดกลางคัน) — **ยังไม่ทดสอบเลย**
- background wake-on-terminate (B5) และ Always permission edge case (B6)
  — ยังไม่ทดสอบเลย ยังเป็น `code-complete, unverified`

**ช่องรุ่น iPhone / เวอร์ชัน iOS / รุ่น-firmware ของ K9P ยังว่างอยู่ทุกแถว**
เพราะผู้บันทึกไม่ได้รับข้อมูลนี้มา — ผู้ทดสอบต้องกรอกเองเพื่อให้ผลตรวจสอบย้อนกลับได้
ห้ามเดาแทน

⚠️ **ผลของสองรอบที่เก็บมาแล้วจึงสืบกลับไปหาเครื่องไม่ได้เลย** — แก้ที่ต้นเหตุแล้วโดย
ย้าย "รุ่น iPhone" กับ "เวอร์ชัน iOS" ขึ้นเป็น **คอลัมน์** ในตารางบันทึกผลของ
`ios_device_test_runbook.md` แทนที่จะเป็นหัวข้อย่อยใต้ตารางที่ถูกข้ามได้
· **แถวที่สองช่องนี้ว่าง = แถวที่ใช้อ้างอิงข้ามรอบไม่ได้**

**ห้าม subagent หรือคนใดอ้างว่า iOS broadcast scanning "ใช้งานได้จริง/verified"
แบบเหมารวมทั้งฟีเจอร์ — ตอนนี้ยืนยันได้เฉพาะข้อที่กรอกว่าผ่านข้างบนเท่านั้น
การที่ ranging กับ Eddystone ผ่าน ไม่ได้แปลว่า background หรือ edge case ผ่านด้วย**

**บทเรียนที่ยังใช้ได้:** บั๊กสองตัวจากรอบ 1-2 คอมไพล์ผ่านและเทสต์เดิมเขียวหมด
แต่พังทันทีที่มีคนกดปุ่มจริง — เป็นเหตุผลที่ `SPRINT.md` ห้ามนับ
"คอมไพล์ผ่าน + mock test เขียว" เป็น verified
