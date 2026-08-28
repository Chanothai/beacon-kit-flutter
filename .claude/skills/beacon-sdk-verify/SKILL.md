---
name: beacon-sdk-verify
description: Research a beacon vendor's official SDK/GATT protocol with a strict no-guessing, cross-verified methodology, and write the result to docs/sources/<vendor>.md. Use before writing any new BeaconAdapter for a vendor that isn't already covered by an existing docs/sources/ file.
when_to_use: Use whenever beacon_kit needs to support a new beacon vendor/brand, or whenever an existing vendor's adapter needs a fact that isn't already in its docs/sources/ file.
context: fork
agent: general-purpose
effort: high
disable-model-invocation: false
---

ค้นคว้า SDK/โปรโตคอลอย่างเป็นทางการของยี่ห้อ beacon ที่ระบุใน `$ARGUMENTS` แล้วบันทึกผลเป็นไฟล์ `docs/sources/$0.md` — วิธีนี้เป็นวิธีเดียวกับที่ใช้ยืนยันข้อมูลของ KKM K9P มาก่อน (ดู K9P Playbook) ห้ามเบี่ยงเบนจากขั้นตอนนี้แม้จะรู้สึกว่ารู้คำตอบอยู่แล้ว

## กติกาเหล็ก

- **ห้ามเดา ห้ามตอบจากความจำ/ความรู้ทั่วไปเกี่ยวกับ BLE beacon ยี่ห้ออื่น** ทุกข้อเท็จจริงต้องมี URL ต้นทางกำกับ ถ้าหาไม่เจอให้เขียนว่า "ไม่พบ/ไม่ยืนยัน" ตรง ๆ
- **ห้ามเดา path ของไฟล์ใน repo** ให้เปิดดู file tree จริงก่อน (ผ่านหน้า repo, `git ls-files` ถ้า clone ได้, หรือ API ของแพลตฟอร์ม) แล้วค่อยไปเปิดไฟล์ที่มีจริง
- **ทุกข้อเท็จจริงที่สำคัญต่อการ implement ต้องยืนยันอย่างน้อย 2 ทางที่เป็นอิสระต่อกัน** เช่น เจอใน README ด้วย และเจอในซอร์สโค้ดจริงด้วย หรือเจอในทั้ง Android และ iOS repo ที่ควรมีค่าตรงกัน — ถ้าเจอแค่ทางเดียวให้ระบุไว้ว่ายืนยันแค่ทางเดียว
- **ต้องยืนยันว่ายี่ห้อนั้นเขียน UUID/Major/Minor ผ่าน GATT ได้จริง ก่อนอนุมัติซื้อ** — BigC ใช้ iBeacon UUID เดียวทั้งบริษัท + major/minor ตามสคีมกลาง (ดู ARCHITECTURE.md ADR-5 "BigC ID Scheme สำหรับ multi-vendor provisioning") ทุกอุปกรณ์ที่จะเข้าฟลีตต้อง provision ค่าทั้งสามนี้ใหม่ให้ตรงสคีม ถ้ายี่ห้อไหน lock UUID ไว้แก้ไม่ได้ (หรือแก้ได้เฉพาะผ่านแอปของผู้ผลิตเอง/ต้องใช้ tool เฉพาะที่ไม่ใช่ SDK ที่ integrate ได้) อุปกรณ์ล็อตนั้นจะเข้าสคีมไม่ได้เลย — ต้องเช็ค**ก่อนซื้อ** ไม่ใช่หลังซื้อ เพราะถ้าพลาดคือของเสียทั้งล็อต

  **เช็คให้ผ่านทุกข้อก่อนสรุปว่า "ซื้อได้" (ถ้าข้อใดยืนยันไม่ได้ ให้ mark "ยังไม่ยืนยัน" ในไฟล์ผลลัพธ์ และห้ามอนุมัติซื้อจนกว่าจะยืนยันครบ — ไม่ต่างจากกฎอื่นในไฟล์นี้ที่ห้ามเดาแทนการค้นคว้า):**
  1. มี characteristic/command ใน SDK ทางการที่ **เขียน** ค่า UUID, Major, และ Minor ได้ทั้งสามค่า (ไม่ใช่แค่**อ่าน**) — บันทึกชื่อ characteristic UUID/method/command code ที่แน่นอนของแต่ละค่า (อาจเป็น characteristic เดียวกันหรือคนละตัวก็ได้ ระบุให้ชัด)
  2. การเขียนต้องผ่าน **SDK ที่ integrate เข้า `beacon_kit` ได้จริง** (native library/AAR/CocoaPod) — ถ้าเขียนได้เฉพาะผ่านแอปสำเร็จรูปของผู้ผลิตเอง (consumer app) หรือ tool เฉพาะที่ไม่มี API ให้เรียกจากโค้ดเรา ให้ถือว่า **ยังไม่ผ่าน** เพราะ `beacon_kit` ต้องเป็น facade เดียวที่แอปเรียก จะพึ่งขั้นตอน manual นอกระบบไม่ได้ตามสเกลฟลีตของ BigC
  3. ต้องมี auth ก่อนเขียนหรือไม่ (password/challenge-response ฯลฯ) — ถ้ามี บันทึกกลไกให้ครบเหมือนหัวข้อ "Auth flow" ปกติ และเช็คว่า auth flow นั้นใช้ตอน provisioning จำนวนมาก (bulk) ได้จริงหรือมีข้อจำกัดที่ทำให้ทำทีละเครื่องช้าเกินไป
  4. มี rate limit หรือข้อจำกัดจำนวนครั้งที่เขียนค่านี้ได้หรือไม่ (เช่น เขียนซ้ำถี่ ๆ ไม่ได้, ต้องรอ cooldown) — ถ้าไม่พบข้อมูลนี้ในเอกสาร ให้ระบุว่า "ไม่พบ/ไม่ยืนยัน" ไม่ใช่สันนิษฐานว่าไม่มีข้อจำกัด
  5. ต้อง reboot/power-cycle อุปกรณ์หลังเขียนค่าถึงจะมีผลหรือไม่ — กระทบขั้นตอน provisioning หน้างานโดยตรง (ถ้าต้อง reboot ทุกเครื่อง ต้องวางแผนขั้นตอนซื้อ/รับของให้รองรับ)
  6. ขอบเขตค่า major/minor ที่ SDK ยอมรับตรงกับ `uint16` (0-65535) มาตรฐาน iBeacon หรือไม่ — บางยี่ห้ออาจจำกัดช่วงค่าที่แคบกว่ามาตรฐานเอง ต้องเช็คให้ชัดก่อนผูกกับสคีมกลาง

  บันทึกผลทั้ง 6 ข้อนี้ไว้ในไฟล์ `docs/sources/<vendor>.md` เป็นหัวข้อย่อยของตัวเอง (เช่น "Provisioning: เขียน UUID/Major/Minor") แยกจากหัวข้อ "Auth flow" ทั่วไป — ถ้ายี่ห้อใดที่มีไฟล์ `docs/sources/` อยู่แล้วจากก่อนหน้านี้ (เช่น K9P) ยังไม่มีหัวข้อนี้ ให้ถือว่ายังไม่ยืนยันเรื่องนี้ **ห้ามสรุปเองว่าทำได้เพราะมี write/auth characteristic อยู่แล้วเฉย ๆ** ต้องรัน skill นี้ซ้ำเพื่อยืนยันแยกต่างหาก

## ขั้นตอน

1. หา repo/หน้าเว็บทางการของยี่ห้อนั้น (เว็บบริษัท, GitHub/GitLab org) — บันทึก URL ของทุกแหล่งที่เปิดดู
2. เปิดดู file tree จริงของ SDK repo (Android และ iOS ถ้ามีทั้งคู่) ก่อนเปิดไฟล์ใด ๆ
3. อ่าน README/CHANGELOG หา: dependency coordinate (Gradle/CocoaPods/pub), minimum OS version, license
4. หาคลาส/ไฟล์ที่รับผิดชอบ: scan, connect, authenticate, read config, read sensor, OTA — บันทึกชื่อคลาส/เมธอด/signature ที่แน่นอน พร้อมโค้ดตัวอย่างที่คัดลอกมาตรง ๆ (ไม่ถอดความเป็นภาษาอื่นสำหรับชื่อ identifier)
5. หาไฟล์ที่มี GATT service/characteristic UUID (ค้นด้วยคำว่า UUID, Gatt, Const, Attribute) — quote ค่าตรงตัวอักษร
6. ตรวจสอบ LICENSE ให้ชัดว่าเป็น license อะไร (สำคัญมากเพราะกระทบว่า reuse/rebrand เป็นของบริษัทได้แค่ไหน)
7. ตรวจสอบว่าโมเดล/รุ่นที่ต้องการใช้จริงถูกระบุว่ารองรับหรือไม่ — ถ้าไม่ระบุตรง ๆ ให้บอกว่า "ไม่พบการระบุรุ่นนี้ตรง ๆ" พร้อมอธิบายเหตุผลเชิงสถาปัตยกรรมถ้ามี (เช่น SDK อ่านค่ารุ่นจากอุปกรณ์ตอน runtime แทนการ hardcode)
8. เขียนสรุปเป็นไฟล์ `docs/sources/$0.md` ตามโครงนี้:
   - ยี่ห้อ/รุ่นอุปกรณ์ที่ต้องการ, วันที่ค้นคว้า
   - Dependency coordinate + license
   - GATT UUID/constant ที่ verified (ตารางพร้อม URL อ้างอิง)
   - Auth flow (ถ้ามี password/challenge-response อธิบายกลไกสั้น ๆ)
   - รายการ "ไม่พบ/ไม่ยืนยัน" แยกไว้ชัดเจนเป็นหัวข้อของตัวเอง — ห้ามปนกับส่วนที่ verified แล้ว
   - แหล่งอ้างอิงทั้งหมด (URL ทุกอันที่เปิดดูจริง)

งานนี้ถือว่าเสร็จเมื่อไฟล์ `docs/sources/$0.md` ถูกสร้างและมีทั้งสองส่วน (verified + ไม่พบ) ครบ — ไม่ใช่แค่ตอบในแชท
