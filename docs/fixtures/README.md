# ADV Packet Fixtures — กุญแจที่ทำให้ทดสอบได้โดยไม่ต้องมี beacon

## ทำไมถึงสำคัญ

การถอดรหัส advertisement packet เป็น **pure function**: byte array เข้าไป → object ออกมา ไม่มี I/O ไม่มี Bluetooth ไม่มี state — แปลว่าถ้าเรามี byte array ตัวอย่างที่รู้คำตอบที่ถูกต้องอยู่แล้ว เราทดสอบ **ฟีเจอร์ broadcast ทั้งฟีเจอร์ได้ 100% โดยไม่ต้องมี beacon สักตัวเดียว**

นี่คือเหตุผลที่ Track A ใน `SPRINT.md` จบได้จริงภายในวันเดียว ทั้งที่โปรเจกต์นี้เป็นงาน BLE

## รูปแบบไฟล์

หนึ่งไฟล์ JSON ต่อหนึ่งเคส วางใน `docs/fixtures/`

```json
{
  "name": "kkm_k9p_ksensor_temp_and_acc",
  "source": "captured | derived_from_sdk_source | vendor_doc",
  "source_detail": "จับจากอุปกรณ์ K9P MAC AA:BB:CC:DD:EE:FF ด้วย nRF Connect เมื่อ 2026-08-27",
  "raw_hex": "0201060303aafe1216aafe20000b1234...",
  "expect": {
    "vendor": "kkm",
    "temperature_c": 26.5,
    "battery_percent": 98,
    "acc": { "x": 12, "y": -4, "z": 1020 }
  }
}
```

ช่อง `source` สำคัญมาก — บอกว่าค่านี้เชื่อถือได้แค่ไหน:

| ค่า | ความหมาย | น่าเชื่อถือ |
|---|---|---|
| `captured` | จับจากอุปกรณ์จริง | สูงสุด — เป็นความจริงจากของจริง |
| `derived_from_sdk_source` | สร้างขึ้นจาก logic ใน SDK ต้นทางที่อ่านโค้ดแล้ว | กลาง — พิสูจน์ว่าเรา implement ตรงกับ SDK แต่ถ้า SDK ตีความผิดเราก็ผิดตาม |
| `vendor_doc` | มาจากเอกสารผู้ผลิต | กลาง |

**ห้ามใส่ `source: captured` ถ้าไม่ได้จับมาจากอุปกรณ์จริง** — เป็นการโกหกข้อมูลต้นทาง ผิดนโยบายหลักของโปรเจกต์

## วิธีเก็บ fixture จากของจริง (ทำได้เร็ว ไม่ต้องเขียนโค้ด)

ใช้แอป **nRF Connect** (Nordic, ฟรี ทั้ง iOS/Android) — สแกนเจอ K9P แล้วก๊อป raw advertisement bytes ออกมาเป็น hex ได้เลย ใช้เวลาไม่กี่นาทีต่ออุปกรณ์ แล้วเอามาใส่ `raw_hex`

ถ้ายังไม่มีอุปกรณ์อยู่ตรงหน้า: เริ่มด้วย `derived_from_sdk_source` จาก logic ใน `KBAdvPacketSensor` (Java/Swift ที่ verified แล้ว) ไปก่อนได้ แล้วค่อยเพิ่ม `captured` ทีหลังเพื่อยืนยันซ้ำ — งานไม่ต้องหยุดรอ

## เคสที่ควรมีเป็นอย่างน้อย

- iBeacon มาตรฐาน (UUID/Major/Minor/TxPower)
- Eddystone UID, URL, TLM อย่างละ 1
- Ksensor ของ KKM: มีค่า temperature, มีค่า acceleration, มีทั้งคู่, และเคสที่ไม่มี sensor เลย
- **เคสพัง** — packet สั้นเกินไป, ยาวเกินไป, byte เพี้ยน, mask บอกว่ามี field แต่ข้อมูลขาด (ตัวถอดรหัสต้องไม่ crash และต้องคืน error ที่ชัดเจน ไม่ใช่ค่ามั่ว)

เคสพังสำคัญพอ ๆ กับเคสปกติ เพราะ beacon ในสนามจริงส่งข้อมูลเพี้ยนได้เสมอ (สัญญาณอ่อน, แบตใกล้หมด, firmware คนละเวอร์ชัน)

---

## โน้ตเพิ่มเติม (QA agent, iOS-first sprint 27 ส.ค. 2026): ธรรมเนียม `raw_hex` ของ fixture `IBeaconParser`/`EddystoneParser`

Fixture ทั้งหมดที่ชื่อขึ้นต้นด้วย `ibeacon_*` และ `eddystone_*` ใน sprint นี้ (ดู
`ARCHITECTURE.md` หัวข้อ "ADR: iOS-first Sprint — Domain Layer & Platform Channel
Contract", ADR-3 และ ADR-4) ใช้ธรรมเนียม `raw_hex` **ต่างจากตัวอย่างในหัวข้อ
"รูปแบบไฟล์" ด้านบน** โดยตั้งใจ:

- `raw_hex` ในตัวอย่างด้านบน (`0201060303aafe1216aafe20000b1234...`) คือ **full ADV
  packet dump** — รวมทุก AD structure (flags, service UUID list, service data
  ฯลฯ) ตามที่สแกนได้ดิบ ๆ จากอากาศ
- `raw_hex` ของ fixture `ibeacon_*`/`eddystone_*` ใน sprint นี้ คือ **byte ที่ป้อน
  เข้าฟังก์ชัน parser ตรง ๆ** เท่านั้น — คือ byte **หลัง AD-structure demux แล้ว**:
  - `IBeaconParser.parse(manufacturerData)` → `raw_hex` = ค่าเต็มของ AD structure
    type `0xFF` (รวม company ID 2 bytes) ไม่รวม length byte ของ AD structure เอง
  - `EddystoneParser.parse(serviceData)` → `raw_hex` = payload ของ service data
    **ไม่รวม** 2-byte service UUID (`0xFEAA`) เริ่มด้วย frame-type byte ทันที

**เหตุผล (ADR-3/ADR-4):** ทั้ง `IBeaconParser`/`EddystoneParser` ถูกออกแบบเป็น
pure function ที่รับ byte array ที่ demux มาแล้วเป็น input โดยตรง (ดู signature
`IBeaconParser.parse(Uint8List manufacturerData)` และ
`EddystoneParser.parse(Uint8List serviceData)` ใน ADR-3) เพราะนี่คือรูปแบบที่ทั้ง
**CoreBluetooth (iOS)** และ **Android `BluetoothLeScanner`** ส่ง data ให้แอปจริง ๆ
— OS แต่ละแพลตฟอร์ม demux AD structure ให้แอปอยู่แล้วก่อนที่ event จะไปถึง Dart
layer (ดู ADR-4 event channel `#2 raw_advertisement_events`:
`serviceData: Map<String, Uint8List>?` คือ per-service-UUID map ที่ demux แล้ว
ไม่ใช่ raw packet dump) การให้ fixture ตรงกับ shape ของ input จริงที่ parser จะ
ได้รับ ทำให้ unit test ทดสอบ parser แบบ pure function ได้ตรงกับการใช้งานจริง
โดยไม่ต้องเขียน AD-structure demux logic ซ้ำอีกชั้นในตัวเทสต์เอง (ซึ่งเป็นโค้ด
คนละส่วนที่ไม่ใช่หน้าที่ของ `IBeaconParser`/`EddystoneParser`)

ทุกไฟล์ `docs/fixtures/ibeacon_*.json` และ `docs/fixtures/eddystone_*.json` มี
field `"parser"` (`"ibeacon"` หรือ `"eddystone"`) ระบุไว้ชัดเจนว่าต้องป้อนเข้า
parser ตัวไหน — ใช้คู่กับ
`packages/beacon_kit_platform_interface/test/parsers/fixture_loader.dart` ซึ่ง
โหลด fixture ตาม field นี้โดยตรง

---

## โน้ตเพิ่มเติม (QA agent, A3 sprint 28 ส.ค. 2026): fixture กลุ่ม `bigc_identity_*.json` ต่างจาก fixture parser ยังไง

Fixture ทั้งหมดที่ชื่อขึ้นต้นด้วย `bigc_identity_*` ใน `docs/fixtures/` **ไม่ใช่**
fixture ของ ADV packet parser (`IBeaconParser`/`EddystoneParser`) — เป็นคนละชั้น
กันโดยสิ้นเชิง อย่าปนกัน:

- fixture `ibeacon_*`/`eddystone_*` ทดสอบ **การถอดรหัส byte ดิบจากอากาศ** (Track
  A1 ของ ADR-3/ADR-4) จึงต้องมี `raw_hex` + `source` (`captured` /
  `derived_from_sdk_source` / `vendor_doc`) เพื่อบอกว่าค่านี้เชื่อถือได้จากของจริง
  แค่ไหน
- fixture `bigc_identity_*` ทดสอบ **usecase `ResolveBigcBeaconMetadata`** (A3 —
  domain entity/usecase ที่แปลง identity triple UUID/Major/Minor เป็นข้อมูล
  ธุรกิจของ BigC) ซึ่งเป็น **business-domain mapping ล้วน ๆ ไม่มี byte จาก wire
  เกี่ยวข้องเลย** จึง **ไม่มี field `raw_hex` และไม่มี field `source: captured`**
  — เพราะไม่มีอุปกรณ์จริงตัวไหนให้ "จับ" ค่าพวกนี้ได้ ข้อมูลทั้งหมดเป็น
  **synthetic test data** ที่ QA agent สร้างขึ้นเองล้วน ๆ เพื่อ exercise logic
  การเทียบ uuid/ตรวจช่วง major-minor/ค้นหาใน repository เท่านั้น

รูปแบบไฟล์ของ `bigc_identity_*.json`:

```json
{
  "name": "bigc_identity_success_known_mapping",
  "kind": "bigc_identity_mapping",
  "note": "SYNTHETIC TEST DATA ONLY — คำเตือนชัดเจนว่า uuid ในไฟล์นี้เป็นค่าจำลอง",
  "test_bigc_proximity_uuid": "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE",
  "repository_mappings": [
    { "identity": { "uuid": "...", "major": 1, "minor": 100 },
      "metadata": { "brand": "...", "lot": "...", "group": "...", "location": "..." } }
  ],
  "query": { "uuid": "...", "major": 1, "minor": 100 },
  "expect": { "result": "success", "metadata": { ... } }
}
```

**สำคัญที่สุด — ห้ามใช้ UUID จริงของ BigC ในไฟล์กลุ่มนี้เด็ดขาด** ค่า UUID จริงที่
generate ไว้ตาม A2 อยู่ที่ `docs/sources/bigc_provisioning.md` เพียงที่เดียวตาม
ADR-5 (ห้าม copy ออกมาที่อื่นแม้แต่ในเทสต์ เพื่อไม่ให้ค่าจริงรั่วไปอยู่ในโค้ด/git
history ที่ไม่ควรมี) ทุกไฟล์ในกลุ่มนี้ใช้ค่าจำลองที่ประกาศชัดใน field `"note"`
เช่น `AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE` แทน

เคสที่ครอบคลุมแล้ว (`packages/beacon_kit_platform_interface/test/usecases/resolve_bigc_beacon_metadata_test.dart`):

- `bigc_identity_success_known_mapping` — uuid ตรง + triple อยู่ใน mapping →
  ได้ metadata ที่ถูกต้อง
- `bigc_identity_success_uuid_case_insensitive` — uuid ตรงแบบไม่สนตัวพิมพ์
  เล็ก/ใหญ่ (query เป็น lowercase ทั้งหมด, configured เป็น mixed/upper case)
- `bigc_identity_uuid_mismatch` — uuid ไม่ตรงกับ `bigcProximityUuid` ที่ inject
  → `uuidMismatch` ทันทีโดยไม่แตะ repository เลย
- `bigc_identity_major_negative` / `bigc_identity_major_too_large` — major
  นอกช่วง uint16 ทั้งด้านติดลบและด้านเกิน 65535 → `majorOutOfRange`
- `bigc_identity_minor_negative` / `bigc_identity_minor_too_large` — minor
  นอกช่วง uint16 ทั้งด้านติดลบและด้านเกิน 65535 → `minorOutOfRange`
- `bigc_identity_not_found` — uuid ตรง, major/minor อยู่ในช่วงถูกต้องทั้งคู่
  แต่ repository ไม่มี mapping ให้ → `notFound`
