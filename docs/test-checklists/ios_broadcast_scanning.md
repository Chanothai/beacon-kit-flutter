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

## 2. iBeacon ranging ผ่าน CoreLocation (path หลัก)

- [ ] ตั้งค่า K9P ให้ broadcast iBeacon ด้วย UUID ค่าโรงงาน
      `7777772E-6B6B-6D63-6E2E-636F6D000001`
- [ ] เปิด K9P ให้อยู่ในระยะที่มองเห็นได้ (ไม่กี่เมตร) กด "Start scan" ในแอป
- [ ] ต้องเห็น K9P ขึ้นในรายการภายในไม่กี่วินาที พร้อม icon `location_on`
      (source = `coreLocation` ตาม `_BeaconTile` ใน `main.dart`)
- [ ] ตรวจ subtitle ต้องมี `uuid`/`major`/`minor` ตรงกับที่ตั้งค่าไว้ และ
      `proximity` ต้องเป็นค่าที่สมเหตุสมผล (ไม่ใช่ `unknown` ค้างตลอดตอนอยู่ใกล้)
- [ ] RSSI (dBm) ที่แสดงต้องเป็นค่าลบที่สมเหตุสมผล (เช่น -40 ถึง -90) ไม่ใช่ 0
      หรือค่ามั่ว

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
| 1. Permission prompt | **ไม่ผ่าน (รอบ 1)** → แก้แล้ว **รอทดสอบซ้ำ** | 27 ส.ค. 2026 | _(ผู้ทดสอบกรอก)_ | _(ผู้ทดสอบกรอก)_ | เจอบั๊ก sync authorization check — ดูหัวข้อ 1 🐞 ด้านบน แก้แล้วแต่ยังไม่ verified |
| 2. iBeacon ranging | ยังไม่ทดสอบ | — | — | — | — |
| 3. หาย/ปิดเครื่อง | ยังไม่ทดสอบ | — | — | — | — |
| 4. Background mode | ยังไม่ทดสอบ | — | — | — | — |
| 5. เพดาน 20 regions | ยังไม่ทดสอบ | — | — | — | — |
| 6. Eddystone/CoreBluetooth | ยังไม่ทดสอบ | — | — | — | — |
| 7. Bluetooth ปิดกลางคัน | ยังไม่ทดสอบ | — | — | — | — |

**อัปเดต 27 ส.ค. 2026:** มีการทดสอบบนเครื่องจริงรอบแรกแล้วเฉพาะข้อ 1 ซึ่ง
**ไม่ผ่าน** และทำให้เจอบั๊ก authorization (ดูหัวข้อ 1) บั๊กนั้นแก้แล้วแต่**ยังไม่ได้
ทดสอบซ้ำ** ข้อ 2-7 ยังไม่เคยทดสอบเลย ช่องรุ่นเครื่อง/iOS/K9P ยังว่างอยู่ รอผู้ทดสอบ
กรอก

**ห้าม subagent หรือคนใดอ้างว่า iOS broadcast scanning "ใช้งานได้จริง/verified"
จนกว่าจะมีคนกรอกตารางนี้ครบพร้อมหลักฐานจากอุปกรณ์จริง — การที่บั๊กหนึ่งตัวถูกแก้
ไม่ได้แปลว่าข้ออื่นผ่าน และไม่ได้แปลว่าข้อ 1 ผ่านแล้วด้วย**
