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

## สรุปผล (กรอกหลังทดสอบจริง)

| ข้อ | ผ่าน/ไม่ผ่าน | วันที่ | อุปกรณ์ (iPhone รุ่น/iOS) | K9P (รุ่น/firmware) | หมายเหตุ/หลักฐาน |
|---|---|---|---|---|---|
| 1. Permission prompt | **ผ่านบางส่วน** — Allow ครั้งเดียว + กด Start ซ้ำระหว่าง prompt: ผ่าน / ลำดับ Don't Allow → Settings → กลับแอป: **แก้แล้ว รอ retest** | 29 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P 2 ตัว _(รุ่น/fw: ผู้ทดสอบกรอก)_ | บั๊กรอบ 1+2 แก้แล้ว ส่วนที่ retest แล้วผ่าน ส่วนลำดับ Settings ยังไม่ได้ retest — ดูหัวข้อ 1 |
| 2. iBeacon ranging | **ผ่าน** | 29 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | K9P 2 ตัว _(รุ่น/fw: ผู้ทดสอบกรอก)_ | เจอทั้ง 2 ตัว uuid `7777772e-…000001` major/minor 229/24333 และ 228/24332 แยกอุปกรณ์ถูก, proximity/RSSI resolve จริงเปลี่ยนตามระยะ |
| 3. หาย/ปิดเครื่อง | ยังไม่ทดสอบ | — | — | — | — |
| 4. Background mode | ยังไม่ทดสอบ | — | — | — | — |
| 5. เพดาน 20 regions | ยังไม่ทดสอบ | — | — | — | — |
| 6. Eddystone/CoreBluetooth | **ผ่าน** | 29 ส.ค. 2026 | iPhone _(ผู้ทดสอบกรอก)_ | อุปกรณ์บุคคลที่สาม (ไม่ใช่ K9P, ไม่รู้ยี่ห้อ) | decode `EddystoneUrlFrame(txPower: -38, url: https://www.google.com/)` ที่ -88 dBm — ยืนยัน vendor-agnostic จริง / ยังไม่เจอ UID/TLM frame |
| 7. Bluetooth ปิดกลางคัน | ยังไม่ทดสอบ | — | — | — | — |

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
