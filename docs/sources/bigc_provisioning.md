# BigC Provisioning Values (bigc_provisioning)

**ประเภทเอกสาร: BigC internal provisioning record — ไม่ใช่ผลวิจัย vendor SDK**

ต่างจากไฟล์อื่นใน `docs/sources/` (เช่น `docs/sources/kkm_k9p.md` ซึ่งเป็นผลค้นคว้า SDK/GATT ของยี่ห้อภายนอก ผ่าน skill `beacon-sdk-verify`) ไฟล์นี้คือ**ค่าที่ BigC เอง generate ขึ้นมาใช้เป็นสคีมกลาง** ตาม ADR-5 ("BigC ID Scheme สำหรับ multi-vendor provisioning") ใน `ARCHITECTURE.md` — ไม่มี vendor ภายนอกให้ verify ในไฟล์นี้ ค่าทุกตัวในนี้คือของบริษัทเองที่ต้อง provision ลงอุปกรณ์ทุกยี่ห้อในฟลีต

**เหตุผลที่เก็บค่าไว้ที่นี่ (single source of truth) แทนที่จะห้ามเขียนค่าลงเอกสารเด็ดขาด:** ดู ARCHITECTURE.md หัวข้อ ADR-5 → "1. Proximity UUID — เดียวทั้งบริษัท (ข้อบังคับ)" — proximity UUID ของ iBeacon **ไม่ใช่ความลับ** (payload เป็น plaintext broadcast ที่ทุกอุปกรณ์ในระยะรับสัญญาณอ่านได้อยู่แล้วโดยไม่ต้องแฮ็ค) ความเสี่ยงตัวจริงคือเรื่อง**operational** — ถ้าค่าเดียวกันไปฝังกระจัดกระจายหลายที่ (โค้ด, เอกสารเก่า, README) การ rotate ค่าในอนาคตจะตามหา/แก้ให้ครบทุกที่ได้ยาก จึงกำหนดให้ไฟล์นี้เป็นที่เก็บค่าเดียวแทน **ห้ามเขียนค่า UUID นี้ซ้ำในเอกสารอื่นของโปรเจกต์ หรือ hardcode ซ้ำในซอร์สโค้ดที่ใดนอกเหนือจาก config ที่ backend/config service ควบคุม** (ตามที่ ADR-5 กำหนด)

## Proximity UUID ของ BigC

| ฟิลด์ | ค่า |
|---|---|
| Proximity UUID (uppercase, ตามที่ `uuidgen` คืนมาโดยตรง) | `14818526-C5A9-41C7-98F1-4ECA6C6FBD15` |
| Proximity UUID (lowercase, hyphenated — รูปแบบที่ `IBeaconFrame.uuid` และ `BeaconAdvertisement.ibeaconUuid` ใช้ตาม ADR-2/ADR-3) | `14818526-c5a9-41c7-98f1-4eca6c6fbd15` |

**คำสั่งที่ใช้ generate (รันจริงบนเครื่องนี้ผ่าน Bash tool, macOS):**

```
$ uuidgen
14818526-C5A9-41C7-98F1-4ECA6C6FBD15
```

**วันที่/เวลาที่ generate:**
- UTC: `2026-08-28 11:34:50 UTC` (จาก `date -u "+%Y-%m-%d %H:%M:%S UTC"` รันคู่กันทันทีหลัง `uuidgen`)
- Local: `2026-08-28 18:34:50 +07` (จาก `date "+%Y-%m-%d %H:%M:%S %Z"`)

### การตรวจสอบว่าเป็น UUID v4 จริง (ตรวจจากบิตของค่านี้เอง)

ค่า: `14818526-C5A9-41C7-98F1-4ECA6C6FBD15` แบ่งเป็น 5 กลุ่มตามมาตรฐาน UUID (`8-4-4-4-12` hex digits):

| กลุ่มที่ | ค่า |
|---|---|
| 1 | `14818526` |
| 2 | `C5A9` |
| 3 | `41C7` |
| 4 | `98F1` |
| 5 | `4ECA6C6FBD15` |

- **Version nibble** ต้องเป็นตัวอักษรตัวแรกของกลุ่มที่ 3 (nibble ตำแหน่งที่ 13 ของ UUID ทั้งหมดเมื่อนับต่อเนื่องไม่รวมขีด) — กลุ่มที่ 3 คือ `41C7` → ตัวแรกคือ **`4`** ตรงกับ version 4 (UUID v4 / random) ✅ ผ่าน
- **Variant nibble (RFC 4122)** ต้องเป็นตัวอักษรตัวแรกของกลุ่มที่ 4 และต้องอยู่ในเซ็ต `{8, 9, a, b}` — กลุ่มที่ 4 คือ `98F1` → ตัวแรกคือ **`9`** ซึ่งอยู่ใน `{8,9,a,b}` ✅ ผ่าน

**สรุป:** ค่า `14818526-C5A9-41C7-98F1-4ECA6C6FBD15` ตรวจแล้วเป็น UUID v4 (RFC 4122 variant) จริงจากบิตของมันเอง ไม่ใช่การอ้างลอย ๆ

## สถานะและขอบเขตการใช้งาน

- นี่คือ **proximity UUID เดียวทั้งบริษัท** ตามสคีมที่ ADR-5 กำหนด (`ARCHITECTURE.md` → "ADR-5: BigC ID Scheme สำหรับ multi-vendor provisioning" → "โครง ID 3 ชั้น" → "1. Proximity UUID — เดียวทั้งบริษัท (ข้อบังคับ)") — ใช้ค่านี้ค่าเดียวสำหรับทุกอุปกรณ์/ทุกยี่ห้อในฟลีต BigC เพื่อให้ `CLBeaconIdentityConstraint(uuid:)` แบบไม่ระบุ major/minor (wildcard) ครอบคลุมทั้งฟลีตด้วย 1 region เดียวได้ตามที่ ADR-5 พิสูจน์ไว้
- Major และ Minor เป็นเลขรันล้วนตามที่ ADR-5 ตัดสินใจแล้ว (ตัวเลือก B) — การกำหนดค่า major/minor จริงต่ออุปกรณ์เป็นงาน provisioning แยกต่างหาก (ยังไม่ scope ของไฟล์นี้ ค่า mapping major/minor → ยี่ห้อ/ล็อต/กลุ่ม/ตำแหน่ง เก็บใน backend/database ตามที่ ADR-5 กำหนด ไม่ใช่ในเอกสารนี้)
- ค่านี้ยังไม่ถูกนำไปตั้งค่าใน production build ใด ๆ ณ วันที่บันทึกนี้ — เป็นเพียงการ generate ค่าไว้ล่วงหน้าตามข้อบังคับของ ADR-5 ก่อน provision อุปกรณ์จริงล็อตแรก ทีมที่จะนำไปตั้งค่า config ของ production build ต้องอ้างอิงจากไฟล์นี้เท่านั้น ห้าม generate ค่าใหม่ซ้ำเอง

## คำเตือนสำคัญ — ห้ามใช้ปนกับค่า K9P demo UUID

`packages/beacon_kit/example/lib/main.dart:9` ตั้งค่า `_k9pDefaultUuid = '7777772E-6B6B-6D63-6E2E-636F6D000001'` เป็นค่าเริ่มต้นของ **example app เท่านั้น** — เป็นค่าโรงงาน demo ของ K9P ที่ผู้ซื้อ K9P รุ่นเดียวกันทุกคนมีเหมือนกันหมด **ไม่ใช่ค่าเดียวกับ proximity UUID ของ BigC ในไฟล์นี้ และห้ามใช้ปนกันเด็ดขาด**:

| | ค่า | ใช้ที่ไหน |
|---|---|---|
| K9P demo UUID (ห้ามใช้ใน production) | `7777772E-6B6B-6D63-6E2E-636F6D000001` | เฉพาะ `example/` เพื่อสาธิตการเชื่อมต่อเท่านั้น |
| **BigC proximity UUID (ค่าจริงของบริษัท)** | `14818526-C5A9-41C7-98F1-4ECA6C6FBD15` | production build เท่านั้น ตามที่ ADR-5 กำหนด |

รายละเอียดเหตุผลเต็มว่าทำไมสองค่านี้ห้ามปนกัน ดู `ARCHITECTURE.md` → ADR-5 → "คำเตือนสำคัญ — ห้าม K9P demo UUID กลายเป็น production UUID ของ BigC"

## อ้างอิง

- `ARCHITECTURE.md` → "ADR-5: BigC ID Scheme สำหรับ multi-vendor provisioning (เพิ่ม 28 ส.ค. 2026)" — ที่มาของข้อบังคับเรื่อง UUID เดียวทั้งบริษัท และเหตุผลเรื่อง single source of truth
- `docs/sources/kkm_k9p.md` — ไฟล์แนวเดียวกันในโครงสร้าง `docs/sources/` (แต่เป็นผลวิจัย vendor SDK ต่างจากไฟล์นี้ที่เป็น BigC internal value)
- คำสั่ง `uuidgen` (macOS built-in) — รันจริงตามที่บันทึกไว้ข้างต้น
