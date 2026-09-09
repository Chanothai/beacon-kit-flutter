# Sources: Apple CoreLocation beacon ranging — `CLProximity` / `CLBeacon`

วันที่ค้นคว้า: 8 กันยายน 2026 — ดึงจาก Apple Developer Documentation โดยตรง
(`developer.apple.com`) ผ่าน tutorials-data JSON API ของหน้าเอกสารเอง (ไม่ใช่จากบล็อก,
StackOverflow หรือความจำ) **ข้อความในเครื่องหมายคำพูดคือคำต่อคำจากหน้าเอกสาร** ไม่ได้
ถอดความ

ไฟล์นี้มีไว้รองรับ ARCHITECTURE.md ADR-19 (`ProximityGate`) — โดยเฉพาะเหตุผลที่ชั้น
ProximityGate ใช้ bucket (`immediate`/`near`/`far`/`unknown`) แทนตัวเลขเมตรตรง ๆ

---

## 1. `CLProximity` — enum คือ "ระยะห่างสัมพัทธ์" ไม่ใช่ตัวเลข — ✅ ยืนยันแล้ว

> **Abstract:** "Constants that reflect the relative distance to a beacon."

**Cases (คำต่อคำ):**

| Case | คำอธิบาย (คำต่อคำจากเอกสาร) |
|---|---|
| `unknown` | "The proximity of the beacon could not be determined." |
| `immediate` | "The beacon is in the user's immediate vicinity." |
| `near` | "The beacon is relatively close to the user." |
| `far` | "The beacon is far away." |

- แหล่ง: `CLProximity` — https://developer.apple.com/documentation/corelocation/clproximity
  (ดึงเนื้อหาจริงผ่าน `https://developer.apple.com/tutorials/data/documentation/corelocation/clproximity.json`
  เพราะหน้า HTML ปกติ render ด้วย JavaScript ฝั่ง client อ่านไม่ได้ตรง ๆ)

**ตรงกับ enum ของเราอย่างไร:** `BeaconProximity` ใน
`packages/beacon_kit_platform_interface/lib/src/entities/beacon_advertisement.dart:96`
ใช้ชื่อ case ตรงกับ `CLProximity` ทุกตัว (`unknown`, `immediate`, `near`, `far`) โดยตั้งใจ
— ไม่ใช่การเดา แต่เป็นการ mirror สัญญาที่ Apple ให้มา

---

## 2. `CLBeacon.proximity` — ✅ ยืนยันแล้ว

> **Abstract:** "The relative distance to the beacon."
> Type: `var proximity: CLProximity`

> **Discussion:** "The value in this property gives a general sense of the relative
> distance to the beacon. Use it to quickly identify beacons that are nearer to the
> user rather than farther away."

- แหล่ง: `CLBeacon.proximity` — https://developer.apple.com/documentation/corelocation/clbeacon/proximity

---

## 3. `CLBeacon.accuracy` — คำเตือนตรง ๆ ห้ามใช้ระบุตำแหน่งแม่นยำ — ✅ ยืนยันแล้ว (คำต่อคำ)

> **Abstract:** "The accuracy of the proximity value, measured in meters from the beacon."
> Type: `var accuracy: CLLocationAccuracy`

> **Discussion (คำต่อคำ):**
> "A beacon with a smaller value for accuracy is typically nearer than a beacon with
> a larger accuracy value.
>
> Use this property to differentiate between beacons with the same proximity value.
> **Do not use it to identify a precise location for the beacon.** Accuracy values may
> fluctuate due to RF interference.
>
> A negative value in this property signifies that the actual accuracy could not be
> determined."

- แหล่ง: `CLBeacon.accuracy` — https://developer.apple.com/documentation/corelocation/clbeacon/accuracy

**นี่คือประโยคที่ ADR-19 อ้างเป็นเหตุผลหลักของการเลือก bucket แทนตัวเลขเมตร** — Apple
เตือนตรง ๆ ว่าห้ามใช้แม้แต่ค่า `accuracy` ที่เป็นตัวเลขเมตรจริง ๆ (ซึ่งละเอียดกว่า
`proximity` เสียอีก) ไปใช้ระบุตำแหน่งที่แม่นยำ — สะท้อนว่าปัญหาไม่ได้อยู่ที่ "เรายังไม่
แปลงเป็นเมตร" แต่อยู่ที่ตัวสัญญาณ RF เองผันผวนเกินกว่าจะแม่นยำระดับนั้นได้ ไม่ว่าจะแปลง
หน่วยอย่างไร

**ยืนยันอิสระที่สอง (secondary, ไม่ใช่แหล่งทางการ แต่ยืนยันว่าข้อความนี้มีอยู่จริงและ
เป็นที่รู้จักในวงการ):** ผลค้นหาเว็บอ้างถึงประโยคเดียวกันนี้ซ้ำในบทความของบุคคลที่สาม
เช่น Radius Networks (https://developer.radiusnetworks.com/2016/02/15/finding-closest-beacon.html)
ที่อธิบายพฤติกรรมเดียวกัน — ใช้เป็นแค่การยืนยันว่าข้อความนี้ตรงกับที่วงการอ้างถึงทั่วไป
ไม่ใช่แหล่งอ้างอิงหลักที่ใช้ในการตัดสินใจ (แหล่งหลักคือหน้าเอกสาร Apple ข้างบน)

---

## 4. "Determining the Proximity to an iBeacon Device" — สถาปัตยกรรมสองขั้น (region monitoring → ranging) และคำเตือนเรื่องระยะทางแม่นยำ — ✅ ยืนยันแล้ว (คำต่อคำ)

> "Adding iBeacon support to your app involves detecting beacons in two different
> stages:
> 1. Use region monitoring to detect the presence of an iBeacon.
> 2. Use beacon ranging to determine the proximity to a detected iBeacon.
>
> Using a two-step process for detecting beacons significantly reduces power
> consumption. Ranging requires taking frequent measurements of the strength of
> Bluetooth signals and computing the distance to the associated beacons. By contrast,
> region monitoring involves only passive listening for nearby beacons, which consumes
> far less power."

> "After detecting an iBeacon, use ranging to determine the relative distance between
> the beacon and the user's device. **Ranging reports when the two devices are far
> apart, near to each other, or in the immediate vicinity of each other; it does not
> offer a precise distance, nor should you rely on the strength of a beacon's signal
> to compute that information yourself.** Use the relative values to determine an
> appropriate course of action."

- แหล่ง: "Determining the Proximity to an iBeacon Device" —
  https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device

**สิ่งที่หน้านี้ยืนยันเพิ่มเติมนอกจากคำเตือนเรื่องความแม่นยำ:** โครงสร้าง "สองขั้น"
ของ Apple เอง (region monitoring แล้วค่อย ranging) เป็นแนวคิดคนละชั้นกับ `ProximityGate`
ของเรา — ของ Apple คือสองขั้นภายใน "การตรวจจับ beacon" ล้วน ๆ (ยังไม่มีชั้นนโยบายทาง
ธุรกิจ) ส่วน `ProximityGate` ในเอกสารนี้คือชั้นที่อยู่ *เหนือ* ทั้งสองขั้นของ Apple อีกที
— รับ sample ที่มาจากขั้นไหนก็ได้ (ranging ของ iOS หรือ scan ดิบของ Android) แล้วแปลง
เป็นการตัดสินใจเชิงนโยบาย (enter/exit ของ zone แบบละเอียด) **ห้ามสับสนระหว่างสองแนวคิด
นี้เมื่ออ้างอิงเอกสารนี้ใน ADR**

**คำเตือนตรง ๆ ที่มีผลต่อการออกแบบ:** "it does not offer a precise distance, **nor
should you rely on the strength of a beacon's signal to compute that information
yourself**" — ประโยคหลังเตือนตรง ๆ ไม่ให้ทำสิ่งที่ Android-path ของเราทำอยู่ (คำนวณ
ระยะจาก RSSI เอง) ว่าไม่ควรถือว่าแม่นยำ — ไม่ได้ห้ามทำ (ไม่มีทางเลือกอื่นบน Android ที่
ไม่มี `proximity` ให้) แต่เป็นเหตุผลเสริมว่าทำไมผลจากการคำนวณเองต้องถูกปรับให้อยู่ใน
"ความละเอียดเดียวกัน" กับที่ Apple ยอมให้ (bucket 4 ระดับ) แทนที่จะแสดงเป็นตัวเลขเมตร
ที่ดูแม่นยำเกินจริง

---

## ไม่พบ / ไม่ยืนยัน

- **ไม่มีเอกสาร Apple ที่ระบุ threshold ระยะทาง (เมตร) ที่ใช้แบ่ง `immediate`/`near`/
  `far` เป็นตัวเลขตายตัว** — ค้นหน้า `CLProximity`, `CLBeacon.accuracy`,
  `CLBeacon.proximity` และบทความ "Determining the Proximity to an iBeacon Device" แล้ว
  ไม่มีหน้าไหนให้ตัวเลขเมตรที่ใช้แบ่งขอบเขตระหว่าง bucket แต่ละคู่ — เป็นค่าที่ OS
  คำนวณภายในเองและไม่เปิดเผย **ห้าม hard-code สมมติฐานเรื่องขอบเขตเมตรของแต่ละ bucket
  ของ Apple ในโค้ดหรือเอกสารโดยอ้างว่าเป็นสเปกที่ยืนยันแล้ว**
- **ไม่ได้ตรวจ `CLBeaconRegion` / `CLLocationManager.startRangingBeacons` โดยละเอียด
  ในรอบนี้** — ADR-19 ไม่แตะ region monitoring/ranging lifecycle (อยู่นอกขอบเขตที่
  โจทย์กำหนด) จึงยังไม่ค้นคว้าเพิ่มในรอบนี้ ถ้าต้องแก้โค้ดที่เรียก ranging จริงต้องกลับมา
  ยืนยันเพิ่ม
- **ไม่พบว่า Apple เปลี่ยนอัลกอริทึมคำนวณ `proximity`/`accuracy` ข้าม iOS version
  หรือไม่** — ไม่มีเอกสาร changelog ที่ระบุเรื่องนี้ตรง ๆ ในหน้าที่ตรวจ

## แหล่งอ้างอิงทั้งหมดที่เปิดดูจริง

- https://developer.apple.com/documentation/corelocation/clproximity
- https://developer.apple.com/documentation/corelocation/clbeacon
- https://developer.apple.com/documentation/corelocation/clbeacon/proximity
- https://developer.apple.com/documentation/corelocation/clbeacon/accuracy
- https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device
- https://developer.apple.com/documentation/corelocation/clbeaconidentityconstraint (ตรวจ
  เพื่อยืนยันบริบทของ UUID/major/minor matching ที่เกี่ยวข้องอ้อม ๆ — ไม่ได้ใช้เป็น
  แหล่งหลักของ ADR-19)
- (ยืนยันรอง/ไม่ใช่แหล่งหลัก) https://developer.radiusnetworks.com/2016/02/15/finding-closest-beacon.html
