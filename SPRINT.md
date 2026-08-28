# Sprint Scope — สปรินต์ปัจจุบัน: Background Broadcast Scan + BigC ID Scheme

เอกสารนี้คือสัญญาว่า "เสร็จ" แปลว่าอะไรในสปรินต์นี้ ทุก subagent ต้องอ่านก่อนเริ่มงาน และห้ามประกาศว่างานเสร็จโดยไม่ตรงกับนิยามในนี้

> **อัปเดต 28 ส.ค. 2026** — สปรินต์นี้เปลี่ยน focus จากสปรินต์ก่อน (iOS-first broadcast foundation ซึ่งจบไปแล้ว ดู "สิ่งที่ทำเสร็จไปแล้ว" ท้ายเอกสาร) มาเป็น **background broadcast scan + BigC ID scheme** เท่านั้น

## Focus ของสปรินต์นี้

**ทำ:** background broadcast scan (region monitoring) + BigC ID scheme สำหรับ multi-vendor provisioning

**พักไว้ก่อน ไม่ต้องทำในสปรินต์นี้:**
- `connect()` / GATT provisioning path ทั้งหมด
- OTA firmware update
- sensor history (อ่านประวัติย้อนหลัง)
- `beacon_kit_android` (ยัง deferred ต่อจากสปรินต์ก่อน)

**ไม่เร่ง (ทำได้ถ้ามีเวลาเหลือ ไม่นับเป็นเงื่อนไขปิดสปรินต์):** retest บั๊ก `LOCATION_PERMISSION_DENIED` บนเครื่องจริง (เช็คลิสต์ข้อ 1 รอบ 1 + รอบ 2 ที่ยังค้างอยู่ใน `docs/test-checklists/ios_broadcast_scanning.md`) — บั๊กแก้ไปแล้วและมี Dart regression test คุมอยู่ การ retest เป็นการยืนยันซ้ำ ไม่ใช่ตัวบล็อกงานใหม่

---

## หลักการที่ทำให้จบได้จริง: แบ่งงานตาม "ต้องใช้ฮาร์ดแวร์หรือไม่" ไม่ใช่ตามขั้นตอน pipeline

แบ่งเป็น 2 track ที่ **ทำขนานกันได้ ไม่บล็อกกัน** — Track A จบได้ 100% วันนี้ Track B ได้แค่ code-complete

---

## Track A — ไม่ต้องใช้ฮาร์ดแวร์ (ทำให้ "เสร็จจริง 100%" ได้ภายในวันนี้)

**นิยามคำว่าเสร็จ:** โค้ดเขียนครบ + unit test ผ่านจริง + `flutter analyze --fatal-infos` สะอาด + `dart format` ไม่ค้าง

### A1. ADR: BigC ID Scheme (ARCHITECTURE.md)

โครง ID 3 ชั้นสำหรับ multi-vendor provisioning:

- **Proximity UUID เดียวทั้งบริษัท** — generate ขึ้นใหม่เอง **ห้ามใช้ค่า default ของยี่ห้อใดยี่ห้อหนึ่งเด็ดขาด**
- **Major = เลขรันล้วน** ไม่มีความหมายเชิงธุรกิจฝังในตัวเลข
- **Minor = เลขรันล้วน** รหัสอุปกรณ์เฉพาะตัว
- **ความหมายทางธุรกิจ (ยี่ห้อ / ล็อต / กลุ่ม / ตำแหน่ง) เก็บในฐานข้อมูลแยกต่างหาก** ห้าม encode ลงในตัวเลข major/minor

**เหตุผลที่ต้องอ้างอิง:** Apple official docs เรื่องเพดาน 20 region — ต้องมี URL + คำพูดต้นฉบับกำกับ ไม่ใช่เขียนจากความจำ

> **สถานะ:** ADR-5 เขียนไปแล้วในสปรินต์ก่อน (ยังไม่ commit) แต่ยังปล่อย Major เป็น "ทางเลือก A/B ที่รอทีมตัดสิน" — สปรินต์นี้ **ทีมตัดสินแล้วว่าเลือกเลขรันล้วน (ตัวเลือก B)** งานคือแก้ ADR-5 ให้บันทึกว่าเป็นข้อตัดสินแล้ว ไม่ใช่ทางเลือกที่ยังเปิดอยู่ ไม่ใช่เขียน ADR ใหม่ทับ

### A2. Generate BigC production UUID จริง

- generate เป็น **UUID v4 random** ด้วยเครื่องมือมาตรฐาน
- บันทึกลง `docs/sources/bigc_provisioning.md`
- ต้องระบุให้ชัดว่า generate ด้วยอะไร เมื่อไหร่ และ**ยืนยันได้อย่างไรว่าเป็น v4 random จริง** ไม่ใช่ค่าที่ก๊อปมาจากที่ไหน

### A3. Domain entity + usecase: map (UUID, Major, Minor) → ข้อมูลธุรกิจ

- entity/usecase ใหม่ที่แปลง identity triple เป็นข้อมูลธุรกิจ
- pure Dart ทดสอบได้โดยไม่ต้องมีอุปกรณ์
- **fixture test ครบ** ทั้งเคสปกติและเคสพัง ตาม `docs/fixtures/README.md`

### A4. ADR: เปลี่ยนจาก ranging-only → region monitoring

- ใช้ `didEnterRegion` / `didExitRegion` สำหรับ background scan (ปัจจุบันมีแต่ ranging)
- **ต้องขอสิทธิ์ Always ไม่ใช่ When In Use**
- ระบุ Info.plist keys ที่ต้องเพิ่ม/แก้ให้ครบ

---

## Track B — ต้องมีฮาร์ดแวร์จริงถึงจะ "ยืนยัน" ได้

**นิยามคำว่าเสร็จวันนี้:** โค้ดเขียนครบและคอมไพล์ผ่าน = **"code-complete (ยังไม่ verified)"** เท่านั้น — ห้ามเขียนว่า "เสร็จ" หรือ "ทำงานได้" เด็ดขาด

### B5. Implement region monitoring ตาม ADR ข้อ A4

**เงื่อนไขการยืนยัน:** ห้ามรายงานว่า "ทำงานได้" จนกว่าจะ **เห็นแอปฟื้นขึ้นมาเองจริงตอนถูก kill บนอุปกรณ์จริง** — การคอมไพล์ผ่าน การมี delegate ครบ และ mock test เขียว ไม่นับทั้งหมด

### B6. Implement flow ขอสิทธิ์ Always

ต้องดัก edge case ที่ผู้ใช้เลือกอย่างอื่นแทน Always:
- **"Allow Once"**
- **"When In Use" only**

ทั้งสองกรณีต้องมีพฤติกรรมที่นิยามไว้ชัด ไม่ใช่ปล่อยให้เงียบหรือพังเอง

---

## ข้อห้ามเด็ดขาดของสปรินต์นี้

เมื่อเร่งงาน ความเสี่ยงที่ใหญ่ที่สุดไม่ใช่ "ทำไม่ทัน" แต่คือ **"รายงานว่าเสร็จทั้งที่ยังไม่ได้พิสูจน์"** ซึ่งอันตรายกว่ามาก เพราะทีมจะไปต่อบนสิ่งที่ไม่จริง

1. ห้าม subagent ตัวใดอ้างว่างาน Track B "ทำงานได้/ผ่านการทดสอบแล้ว" โดยไม่มีหลักฐานจากอุปกรณ์จริง (log จากเครื่องจริง หรือคนยืนยัน) — ถ้าไม่มี ให้เขียนว่า `code-complete, unverified — รอทดสอบกับอุปกรณ์จริง`
2. ห้ามนับ mock test ของ Track B เป็นการยืนยันว่าใช้งานได้ — mock พิสูจน์ได้แค่ว่าโค้ดเราเรียกถูกตามสัญญาที่เรา *คิดว่า* ถูก ไม่ได้พิสูจน์ว่าอุปกรณ์/OS ตอบแบบนั้นจริง
3. ห้ามลดคุณภาพของ Track A เพื่อให้ทัน — Track A ไม่มีข้ออ้างเรื่องฮาร์ดแวร์ ถ้าเทสต์ไม่ผ่านคือยังไม่เสร็จ
4. **ห้ามอ้างข้อเท็จจริงเกี่ยวกับ CoreLocation/Apple โดยไม่มี citation จากเอกสารทางการ** — บทเรียนจากสปรินต์ก่อน: บั๊ก 2 ตัวติดกันเกิดจากการสมมติพฤติกรรมของ CoreLocation เอง เอกสาร Apple เป็น JS SPA ที่ WebFetch อ่านไม่ได้ ให้ดึงผ่าน JSON API แทน (`https://developer.apple.com/tutorials/data/documentation/<path>.json`)

## ลำดับความสำคัญเมื่อเวลาไม่พอ

ตัดจากล่างขึ้นบน:

1. A1 + A2 (BigC ID scheme + UUID จริง) — เป็นสิ่งที่บล็อกการจัดซื้อและ provisioning ล็อตแรก ห้ามตัด
2. A4 (ADR region monitoring) — ตัดสินใจก่อน implement
3. A3 (domain mapping + fixture test)
4. B5 (region monitoring, code-complete)
5. B6 (Always permission flow, code-complete)

---

## สิ่งที่ทำเสร็จไปแล้วในสปรินต์ก่อน (ไม่ต้องทำซ้ำ)

- federated plugin 3 package + example app คอมไพล์ผ่าน (`beacon_kit`, `beacon_kit_platform_interface`, `beacon_kit_ios`)
- `BeaconAdvertisement` / `BeaconDeviceId` / `AdvertisementSource` (ADR-1, ADR-2)
- `IBeaconParser` + `EddystoneParser` (UID/URL/TLM) + fixtures 19 ไฟล์ (ADR-3)
- iOS platform channel: CoreLocation ranging + CoreBluetooth raw adv (ADR-4)
- แก้บั๊กจากทดสอบเครื่องจริง 2 รอบ (authorization delegate + broadcast controller ค้าง) พร้อม regression test
- เทสต์ 49/49, analyze สะอาด, `flutter build ios --debug --no-codesign` ผ่าน, XCTest 4/4 บน simulator

**สิ่งที่ยังไม่เคยยืนยันบนเครื่องจริงเลย:** เช็คลิสต์ `docs/test-checklists/ios_broadcast_scanning.md` ข้อ 2-7 ทั้งหมด และข้อ 1 หลังแก้บั๊กทั้งสองรอบ
