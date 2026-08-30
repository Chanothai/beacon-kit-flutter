# iOS Broadcast Scanning — Hardware-in-the-loop Checklist

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

### ⏳ ส่วนที่ยังไม่ได้ retest — สถานะ "แก้แล้ว รอ retest" (ไม่ใช่ "ผ่าน")

ลำดับนี้คือลำดับที่เคยทำให้เจอบั๊กรอบ 2 (state ค้างใน broadcast controller)
**แก้แล้วและมี Dart regression test คุมอยู่ แต่ยังไม่เคยรันลำดับนี้ซ้ำบนอุปกรณ์จริง**

- [ ] Don't Allow → เปิดสิทธิ์ใน Settings → กลับแอป **โดยไม่ force quit** → Start
      → ต้องเริ่มสแกนได้จริง

จนกว่าจะรันข้อนี้บนเครื่องจริง **ห้ามเขียนว่าข้อ 1 "ผ่าน" ทั้งข้อ**

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

**สถานะ: ทดสอบแล้วครั้งที่ 1 → ไม่ผ่าน → เจอสาเหตุและแก้แล้ว → รอทดสอบซ้ำ**

### 🐞 ผลทดสอบ B5 ครั้งที่ 1 — ไม่ผ่าน (30 ส.ค. 2026)

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
| `UIApplication.LaunchOptionsKey.location` | Apple: "A key indicating that the app was launched to handle an incoming location event" / UIKit header: "The app was launched in response to a CoreLocation event" | **หลักฐานสนับสนุน** ไม่ใช่ตัวตัดสินหลัก |
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

- [ ] เปิดแอป กด **"Start region monitoring"** (ไม่ใช่ "Start scan")
- [ ] ตรวจว่าแผงบอกว่าสิทธิ์เป็น **Always** — ถ้าเป็น When In Use จะไม่ถูกปลุกตอนถูก kill
      (ต้องไปตั้งที่ Settings เพราะ iOS ไม่ให้ขอ Always ซ้ำ)
- [ ] กด **"ดู log" → ล้าง log** เพื่อเริ่มรอบสะอาด
- [ ] **kill แอปจากตัวสลับแอป** (swipe ขึ้น) ให้ process ตายจริง
- [ ] เดินออกนอกระยะ beacon แล้วเดินกลับเข้ามา
- [ ] ต้องเห็น **notification บนหน้าจอล็อกโดยไม่ต้องเปิดแอป**
- [ ] เปิดแอป → ดู log → **บรรทัดนั้นต้องเป็น `relaunchedFromTerminated`**
      ถ้าเป็น `background` แปลว่า process ไม่ได้ตายจริง ให้ทำซ้ำ
- [ ] **ถ้ายังไม่ผ่าน ให้อ่านบรรทัด `launch` ก่อนสรุป** — ตารางในหัวข้อ "รูปแบบแต่ละ
      บรรทัดใน log" ข้างบนบอกว่าแต่ละแบบแปลว่าอะไร อย่าสรุปว่า "ไม่รองรับ" จากการที่
      log ว่าง เพราะ log ว่างเป็นได้ทั้งสามสาเหตุที่ต่างกันสิ้นเชิง
- [ ] **ต้องรันโหมด release หรือ profile เท่านั้น** — debug mode มี debugger ต่ออยู่
      พฤติกรรมการ terminate/relaunch ไม่ตรงกับของจริง (ดู CONTRIBUTING ข้อ 6)
- [ ] บันทึกบรรทัดที่ได้ลงตารางสรุปด้านล่างเป็นหลักฐาน

**เกณฑ์ผ่านของ B5: ต้องเห็นบรรทัด `relaunchedFromTerminated` จริงในไฟล์ log**
notification อย่างเดียวไม่พอ เพราะไม่ได้บอกว่า process ตายจริงหรือแค่อยู่เบื้องหลัง

## 13. เครื่องล็อกอยู่ตอนถูกปลุก — log ถูกเขียนครบหรือไม่ (Data Protection)

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

## สรุปผล (กรอกหลังทดสอบจริง)

| ข้อ | ผ่าน/ไม่ผ่าน | วันที่ | อุปกรณ์ (iPhone รุ่น/iOS) | K9P (รุ่น/firmware) | หมายเหตุ/หลักฐาน |
|---|---|---|---|---|---|
| 1. Foreground (แอปเปิดอยู่) | **ไม่ผ่าน** → แก้แล้ว **รอทดสอบซ้ำ** | 30 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P _(ผู้ทดสอบกรอก)_ | ไม่เห็นอะไรเลยเพราะไม่ได้ implement `willPresent` — event มาจริงแต่ iOS ไม่แสดงให้ ดูหัวข้อ 2 🐞 |
| 1b. Permission prompt | **ผ่านบางส่วน** — Allow ครั้งเดียว + กด Start ซ้ำระหว่าง prompt: ผ่าน / ลำดับ Don't Allow → Settings → กลับแอป: **แก้แล้ว รอ retest** | 29 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P 2 ตัว _(รุ่น/fw: ผู้ทดสอบกรอก)_ | บั๊กรอบ 1+2 แก้แล้ว ส่วนที่ retest แล้วผ่าน ส่วนลำดับ Settings ยังไม่ได้ retest — ดูหัวข้อ 1 |
| 2. iBeacon ranging + region enter/exit (background ไม่ kill) | **ผ่าน** | 29-30 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P 2 ตัว _(รุ่น/fw: ผู้ทดสอบกรอก)_ | เจอทั้ง 2 ตัว uuid `7777772e-…000001` major/minor 229/24333 และ 228/24332 แยกอุปกรณ์ถูก, proximity/RSSI resolve จริง · **enter 5-8 วิ / exit 30-50 วิ (วัดครั้งแรก ยังไม่ทำซ้ำ)** · ไม่ใช่ B5 — process ยังมีชีวิตอยู่ |
| 3. หาย/ปิดเครื่อง | ยังไม่ทดสอบ | — | — | — | — |
| 4. Background mode | ยังไม่ทดสอบ | — | — | — | — |
| 5. เพดาน 20 regions | ยังไม่ทดสอบ | — | — | — | — |
| 6. Eddystone/CoreBluetooth | **ผ่าน** | 29 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | อุปกรณ์บุคคลที่สาม (ไม่ใช่ K9P, ไม่รู้ยี่ห้อ) | decode `EddystoneUrlFrame(txPower: -38, url: https://www.google.com/)` ที่ -88 dBm — ยืนยัน vendor-agnostic จริง / ยังไม่เจอ UID/TLM frame |
| 7. Bluetooth ปิดกลางคัน | ยังไม่ทดสอบ | — | — | — | — |
| 9. region ซ้อนทับ (enter ซ้ำ?) | ยังไม่ทดสอบ | — | — | — | ADR-8 open question — ห้ามเขียน dedupe จนกว่าจะรู้ผล |
| 10. ไม่มีอินเทอร์เน็ต | ยังไม่ทดสอบ | — | — | — | Apple ระบุว่า region monitoring ต้องการ network connectivity |
| 11. เทียบ advertising mode | **ยังทำไม่ได้** | — | — | — | ติด GATT config ที่ยังไม่ implement |
| 12. B5 wake-from-terminate | **ไม่ผ่าน** (ครั้งที่ 1) → เจอสาเหตุและแก้แล้ว **รอทดสอบซ้ำ** | 30 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P _(ผู้ทดสอบกรอก)_ | ปัดแอปทิ้ง → ถอด/ใส่แบต → รอ 5 นาที: ไม่มี notification ไม่มีบรรทัดใน log เลย · สาเหตุ: ไม่มีใครสร้าง `CLLocationManager` ในรอบ cold launch (ADR-10) · แก้แล้วรอ retest — เกณฑ์ผ่านยังเหมือนเดิม: เห็นบรรทัด `relaunchedFromTerminated` ใน log |
| 13. เครื่องล็อกตอนถูกปลุก (Data Protection) | ยังไม่ทดสอบ | — | — | — | Track B — simulator ตรวจไม่ได้ (XCTest skip) ถ้าพลาดข้อนี้จะสรุปผิดว่า B5 ไม่ผ่านทั้งที่ผ่าน |

**อัปเดต 29 ส.ค. 2026 — สรุปสถานะล่าสุด**

ทดสอบบนอุปกรณ์จริงไปแล้ว 3 รอบ (iPhone + K9P จริง 2 ตัว + อุปกรณ์ Eddystone
บุคคลที่สามที่บังเอิญอยู่ในระยะ)

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

**ห้าม subagent หรือคนใดอ้างว่า iOS broadcast scanning "ใช้งานได้จริง/verified"
แบบเหมารวมทั้งฟีเจอร์ — ตอนนี้ยืนยันได้เฉพาะข้อที่กรอกว่าผ่านข้างบนเท่านั้น
การที่ ranging กับ Eddystone ผ่าน ไม่ได้แปลว่า background หรือ edge case ผ่านด้วย**

**บทเรียนที่ยังใช้ได้:** บั๊กสองตัวจากรอบ 1-2 คอมไพล์ผ่านและเทสต์เดิมเขียวหมด
แต่พังทันทีที่มีคนกดปุ่มจริง — เป็นเหตุผลที่ `SPRINT.md` ห้ามนับ
"คอมไพล์ผ่าน + mock test เขียว" เป็น verified
