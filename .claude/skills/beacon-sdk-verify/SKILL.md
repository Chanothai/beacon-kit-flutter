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
