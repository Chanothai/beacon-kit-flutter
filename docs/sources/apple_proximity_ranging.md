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
- ~~**ไม่ได้ตรวจ `CLBeaconRegion` / `CLLocationManager.startRangingBeacons` โดยละเอียด
  ในรอบนี้**~~ — ADR-19 ไม่แตะ region monitoring/ranging lifecycle (อยู่นอกขอบเขตที่
  โจทย์กำหนด) จึงยังไม่ค้นคว้าเพิ่มในรอบนี้ ถ้าต้องแก้โค้ดที่เรียก ranging จริงต้องกลับมา
  ยืนยันเพิ่ม → **ทำแล้วในรอบค้นคว้าที่ 2 (10 ก.ย. 2026) ดูหัวข้อ 5-10 ท้ายไฟล์นี้** —
  แต่ **ไม่ได้ปิดทุกช่อง** ดูหัวข้อ "ไม่พบ / ไม่ยืนยัน (รอบที่ 2)" ประกอบเสมอ
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

---

# รอบค้นคว้าที่ 2 — ranging lifecycle, background, และอัตราการยิง (10 กันยายน 2026)

รอบนี้ปิดช่องที่หัวข้อ "ไม่พบ / ไม่ยืนยัน" ของรอบแรกเขียนกำกับตัวเองไว้ว่า *"ไม่ได้ตรวจ
`CLBeaconRegion` / `CLLocationManager.startRangingBeacons` โดยละเอียดในรอบนี้ … ถ้าต้อง
แก้โค้ดที่เรียก ranging จริงต้องกลับมายืนยันเพิ่ม"* — ทำเพื่อรองรับ **ADR-21** (ยก
ProximityGate ขึ้นฝั่ง native ของ iOS)

**วิธีการ:** ดึงเนื้อหาจาก `developer.apple.com` โดยตรง — หน้าเอกสารปัจจุบันผ่าน
tutorials-data JSON API และคู่มือที่ Apple archive ไว้ผ่าน HTML ดิบ (ดาวน์โหลดด้วย `curl`
แล้วถอด tag เอง เพื่อให้ได้ข้อความคำต่อคำจริง ไม่ผ่านตัวสรุปใด ๆ) **ข้อความในเครื่องหมาย
คำพูดคือคำต่อคำ** ข้อที่ยืนยันไม่ได้อยู่ในหัวข้อ "ไม่พบ / ไม่ยืนยัน (รอบที่ 2)" แยกไว้ต่างหาก

## 5. ranging ตอน background ทำได้ไหม และนานแค่ไหน — ⚠️ ยืนยันได้บางส่วน

**(ก) ระบบปลุก/relaunch แอปจาก region event ได้จริง — ✅ ยืนยันแล้ว 2 แหล่ง**

> "If your app is not running when a beacon is detected, the system tries to launch your app."
> — "Determining the Proximity to an iBeacon Device" (หน้าเอกสารปัจจุบัน)

> "In iOS, regions associated with your app are tracked at all times, including when the
> app isn't running. If a region boundary is crossed while an app isn't running, that app
> is relaunched into the background to handle the event."
> — "Region Monitoring and iBeacon", Location Awareness Programming Guide (Apple archive)

**(ข) เวลาที่ได้หลังถูกปลุกมีเพดาน ~10 วินาที — ✅ ยืนยันแล้ว (คำต่อคำ, แหล่งเดียว)**

> "Similarly, if the app is suspended when the event occurs, it's woken up and given a
> short amount of time (around 10 seconds) to handle the event. When necessary, an app can
> request more background execution time using the `beginBackgroundTaskWithExpirationHandler:`
> method of the `UIApplication` class."
> — "Region Monitoring and iBeacon" (Apple archive)

⚠️ ตัวเลขนี้พบใน**คู่มือที่ Apple archive แล้ว**เท่านั้น — ไม่พบประโยคเทียบเท่าในหน้าเอกสาร
ปัจจุบัน จึงถือว่า **ยืนยันทางเดียว** และเป็นตัวเลขของ "หน้าต่างเวลาหลังถูกปลุกด้วย region
event" ไม่ใช่ "เพดานของ ranging" โดยตรง

**(ค) Apple แนะนำตรง ๆ ว่า "ให้ range เฉพาะตอน foreground" — ✅ ยืนยันแล้ว (คำต่อคำ)**

> "To promote consistent results in your app, use beacon ranging only while your app is in
> the foreground. If your app is in the foreground, it is likely that the device is in the
> user's hand and that the device's view to the target beacon has fewer obstructions.
> Running in the foreground also promotes better battery life by processing incoming beacon
> signals only while the user is actively using the device."
> — "Region Monitoring and iBeacon" (Apple archive)

หน้าเอกสารปัจจุบันพูดทำนองเดียวกันแบบอ่อนกว่า (ยืนยันอิสระที่สอง):

> "The method also adds the beacon to an internal array so that the app can stop and restart
> ranging at any time. **For example, you might stop ranging when your app is in the
> background to save power.**"
> — "Determining the Proximity to an iBeacon Device"

**สรุปข้อ 1:** ranging **ไม่ถูกห้าม**ตอน background (ประโยคของ Apple เองที่บอกว่า "คุณ*อาจ*
หยุด ranging ตอน background เพื่อประหยัดพลังงาน" แปลว่ามันเดินต่อได้ถ้าไม่หยุด) แต่ Apple
**แนะนำตรง ๆ ไม่ให้ทำ** และ**ไม่มีเอกสารใดรับประกันว่ามันจะเดินต่อไปเรื่อย ๆ** — สิ่งเดียวที่
เอกสารรับประกันคือหน้าต่าง ~10 วินาทีต่อ region event หนึ่งครั้ง

## 6. ต้องมีอะไรบ้างถึงจะทำงานตอน background — ✅ ยืนยันแล้ว (คำต่อคำ)

**(ก) background mode + `allowsBackgroundLocationUpdates`**

> "Apps that receive location updates when running in the background must include the
> `UIBackgroundModes` key (with the `location` value) in their app's `Info.plist` file.
> After including the `UIBackgroundModes` key, set the value of `allowsBackgroundLocationUpdates`
> to `true`."

> "When the value of this property is `true` and you start location updates while the app is
> in the foreground, Core Location configures the system to keep the app running to receive
> continuous background location updates, and arranges to show the background location
> indicator (blue bar or pill) if needed. Updates continue even if the app subsequently
> enters the background."

> "When the value of this property is `false`, location updates may or may not continue in
> the background depending on other factors, including other background modes."

> "The default value of this property is `false`."

> "**Setting the value to `true` but omitting the `UIBackgroundModes` key and `location`
> value in your app's `Info.plist` file is a fatal error that terminates the app.**"

— `CLLocationManager.allowsBackgroundLocationUpdates`

⚠️ **ข้อความทุกประโยคข้างบนพูดถึง "location updates"** (คือ `startUpdatingLocation()`)
**ไม่ได้พูดถึง beacon ranging เลยแม้แต่ประโยคเดียว** — ดูหัวข้อ "ไม่พบ / ไม่ยืนยัน (รอบที่ 2)"

**(ข) เงื่อนไขของการถูก launch จาก region event**

> "**Important:** Apps must have authorization to use region monitoring, and they must be
> configured with the Location updates background mode to be launched."
> — "Determining the Proximity to an iBeacon Device"

**(ค) ระดับ authorization — `Always` เท่านั้นที่ปลุกแอปที่ถูกฆ่าแล้วได้**

> "On iOS, an app is in use when it's in the foreground and for a short time when it
> transitions from the foreground to the background. If you enable background location
> updates, an app with When in Use authorization continues to run in the background when
> location services are active; if location services aren't running, the normal suspension
> rules apply. **If the system terminates the app or the app isn't running, the system
> doesn't launch an app with When in Use authorization to deliver new updates; it does
> launch an app with Always authorization for some types of location updates.**"

ตารางในหน้าเดียวกัน หัวข้อ "Launches a terminated app automatically" (คำต่อคำ):

| Capability | When in Use | Always |
|---|---|---|
| Launches a terminated app automatically | "No. The user must launch the app." | "Yes for significant location change, visits, and region monitoring services; no for others" |

— "Requesting Authorization to Use Location Services"

**สรุปข้อ 2:** ต้องมีครบสามอย่าง — (1) `UIBackgroundModes` มี `location` (2) authorization
เป็น `Always` ถ้าต้องการให้ระบบ relaunch แอปที่ถูกฆ่าแล้ว (3) `allowsBackgroundLocationUpdates
= true` **ถ้า**ต้องการให้ระบบ "keep the app running" ต่อเนื่อง — โดยข้อ (3) มีผลที่ยืนยันได้
เฉพาะกับ location updates ไม่ใช่ ranging (ดูหัวข้อไม่ยืนยัน)

## 7. อัตราการยิงของ `didRangeBeacons` — ❌ **ไม่มีอัตราคงที่ในเอกสาร** (ยืนยันแล้วว่าไม่มี)

> "The location manager calls the `locationManager:didRangeBeacons:inRegion:` of its delegate
> object **whenever beacons in the specified beacon region come within range, go out of
> range, or their proximity changes.** This delegate method provides an array of `CLBeacon`
> objects that represent the beacons currently in range. The array of beacons is ordered by
> approximate distance from the device, with the closest beacon at the beginning of the array."
> — "Region Monitoring and iBeacon" (Apple archive)

ยืนยันอิสระที่สองจากหน้าเอกสารปัจจุบัน:

> "When ranging is active, the location manager object calls the
> `locationManager(_:didRangeBeacons:in:)` method of its delegate **whenever there is a
> change to report.**"
> — "Determining the Proximity to an iBeacon Device"

**สรุปข้อ 3: สมมติฐาน "~1 sample/วินาที" ที่ ADR-19 หัวข้อ 8 ใช้ตั้งค่า `staleAfter`
ยังคงยืนยันไม่ได้แม้หลังรอบค้นคว้านี้** — ทั้งสองแหล่งของ Apple อธิบาย callback นี้ว่าเป็น
**event-driven** ("whenever there is a change to report") ไม่ใช่ periodic ที่มีคาบแน่นอน
**ห้ามเขียนที่ใดว่า "iOS ยิง ranging ทุก 1 วินาที" โดยอ้างว่าเป็นสเปกของแพลตฟอร์ม** — ถ้า
ต้องการตัวเลขจริงต้องวัดจากอุปกรณ์จริงแล้วอ้างไฟล์ข้อมูล เหมือนที่ ADR-20 หัวข้อ 7 ทำกับ
ฝั่ง Android

## 8. `didRangeBeacons` ยิงตอนไม่เจอ beacon เลยหรือไม่ — ⚠️ ขึ้นกับว่าใช้ API รุ่นไหน

**API รุ่นใหม่ (iOS 13+, constraint-based — รุ่นที่โค้ดเราใช้อยู่จริง):** เอกสารบอกว่า
callback นี้แปลว่า "เจออย่างน้อยหนึ่งตัว" และมี callback **แยกต่างหาก**สำหรับกรณีไม่เจอ

> "Tells the delegate that the location manager **detected at least one beacon** that
> satisfies the provided constraint."
> — abstract ของ `locationManager(_:didRange:satisfying:)`

> "Tells the delegate that the location manager **couldn't detect any beacons** that satisfy
> the provided constraint."
> — abstract ของ `locationManager(_:didFailRangingFor:error:)`

**API รุ่นเก่า (region-based):** ตัวอย่างโค้ดของ Apple เองในคู่มือ archive **ป้องกันเคส
array ว่างไว้** (`if ([beacons count] > 0) {`) และหน้าเอกสารปัจจุบันของ
`locationManager(_:didRangeBeacons:in:)` ก็ใช้ตัวอย่างเดียวกัน (`if beacons.count > 0`)
— ไม่มีประโยคใดอธิบายว่าเมื่อไรถึงจะว่าง

**สรุปข้อ 4 (สำคัญกับการตรวจ stale):** สำหรับเส้นทางที่โค้ดเราใช้ (`satisfying:`) **"ไม่เจอ
beacon" มาทาง `didFailRangingFor` ไม่ใช่ทาง `didRange` ที่มี array ว่าง** — แปลว่า **ห้าม
พึ่ง `didRange` ว่าจะยิงต่อเนื่องเพื่อใช้เป็นสัญญาณนาฬิกาสำหรับตรวจ stale** เพราะเมื่อ
บีคอนหายไปหมด callback ที่เราจะได้อาจเป็นคนละตัว หรือไม่ได้เลย ⚠️ **ยังไม่ได้ยืนยันด้วย
อุปกรณ์จริง** ว่า `didFailRangingFor` ยิงซ้ำ ๆ เป็นจังหวะหรือยิงครั้งเดียว — เอกสารไม่ระบุ

## 9. `stopRangingBeacons` จำเป็นเมื่อไหร่ + ผลต่อแบตเตอรี่ — ✅ ยืนยันแล้ว (แต่ไม่มีตัวเลข)

> "Stops the delivery of notifications for the specified beacon constraints."
> — abstract ของ `stopRangingBeacons(satisfying:)` (**ไม่มี discussion ในหน้านี้เลย**)

จุดที่ควรหยุด (คำต่อคำ):

> "The most logical place to start ranging is in your location manager delegate's
> `locationManager(_:didEnterRegion:)` method when a beacon is first detected. (**The place
> to stop ranging is in your delegate's `locationManager(_:didExitRegion:)` method.**)"
> — "Determining the Proximity to an iBeacon Device"

ผลต่อพลังงานที่ Apple ระบุไว้จริง (คำต่อคำ, สองแหล่งอิสระ):

> "Using a two-step process for detecting beacons significantly reduces power consumption.
> Ranging requires taking frequent measurements of the strength of Bluetooth signals and
> computing the distance to the associated beacons. By contrast, region monitoring involves
> only passive listening for nearby beacons, which consumes far less power."
> — "Determining the Proximity to an iBeacon Device"

> "Running in the foreground also promotes better battery life by processing incoming beacon
> signals only while the user is actively using the device."
> — "Region Monitoring and iBeacon" (Apple archive)

**สรุปข้อ 5:** Apple ไม่ให้ตัวเลข mAh/เปอร์เซ็นต์ใด ๆ — ให้แค่คำเชิงคุณภาพว่า ranging กิน
พลังงาน "อย่างมีนัยสำคัญ" มากกว่า monitoring เพราะต้องวัดสัญญาณถี่ ๆ · ไม่มีเอกสารใดบอกว่า
"ต้องเรียก `stopRangingBeacons` ไม่งั้นจะเกิด X" — เป็นคำแนะนำเชิงพลังงาน ไม่ใช่ข้อบังคับ

## 10. พบระหว่างทาง (นอกคำถาม แต่กระทบงาน iOS โดยตรง) — ✅ ยืนยันแล้วจาก metadata ของเอกสาร

| Symbol | สถานะตาม metadata ของ Apple | ทางแทน |
|---|---|---|
| `CLBeaconRegion` | `deprecatedAt: 27.0` (iOS/iPadOS) · deprecationSummary: "Use `CLBeaconIdentityCondition` instead." | `CLBeaconIdentityCondition` (iOS 17.0+) |
| `CLBeaconIdentityConstraint` | `deprecatedAt: 27.0` · deprecationSummary เดียวกัน | `CLBeaconIdentityCondition` |
| `startRangingBeacons(satisfying:)` | **ไม่มี `deprecatedAt`** (iOS 13.0+) | — |
| `locationManager(_:didRange:satisfying:)` | **ไม่มี `deprecatedAt`** (iOS 13.0+) | — |

โค้ดปัจจุบันใน `IBeaconRangingManager.swift` ใช้ทั้งสี่ตัวนี้ — สองตัวแรกถูก deprecate แล้ว
(ยังไม่ถูกถอด) ส่วนสองตัวหลังยังไม่ถูก deprecate ตาม metadata ที่ตรวจ **ไม่พบเอกสารที่
อธิบายว่าทำไม `startRangingBeacons(satisfying:)` ยังไม่ถูก deprecate ทั้งที่พารามิเตอร์ของ
มันถูก deprecate ไปแล้ว** — บันทึกไว้เป็นข้อสังเกต ไม่ใช่ข้อสรุป

## ไม่พบ / ไม่ยืนยัน (รอบที่ 2)

- **ไม่พบเอกสาร Apple ที่ระบุว่า `allowsBackgroundLocationUpdates = true` ทำให้ beacon
  ranging เดินต่อตอน background ได้** — ทุกประโยคในหน้านั้นพูดถึง "location updates" ล้วน ๆ
  การอนุมานว่า "ใช้กับ ranging ได้เหมือนกัน" เป็น**การเดา** ห้ามเขียนเป็นข้อเท็จจริงใน ADR
  ต้องพิสูจน์ด้วยอุปกรณ์จริงเท่านั้น
- **ไม่พบเพดานเวลาของ ranging ตอน background เป็นตัวเลขที่ระบุตรง ๆ** — ~10 วินาทีที่พบคือ
  เวลาที่ให้ "handle the event" หลังถูกปลุก ไม่ใช่ "ranging จะหยุดใน 10 วินาที"
- **ไม่พบอัตราการยิงของ `didRange` เป็นตัวเลข** (ดูหัวข้อ 7) — สมมติฐาน ~1 sample/วินาที
  ของ ADR-19 หัวข้อ 8 **ยังไม่มี citation หลังรอบนี้เช่นเดิม**
- **ไม่พบว่า `didFailRangingFor` ยิงซ้ำเป็นจังหวะหรือยิงครั้งเดียว** เมื่อบีคอนหายไปหมด
- **ไม่พบว่าระบบยิง `didRange` ให้ตอนแอปอยู่ background โดยไม่มี region boundary crossing
  ใหม่หรือไม่** — เอกสารพูดถึงการปลุกจาก region event เท่านั้น
- **ไม่พบเอกสารที่ระบุว่า ranging ถูก throttle ตอน background** (อัตราลดลงแต่ไม่หยุด) —
  ไม่มีหน้าใดยืนยันหรือปฏิเสธ
- **ไม่พบตัวเลขการใช้พลังงานของ ranging** (mAh / % ต่อชั่วโมง) — มีแต่คำเชิงคุณภาพ

## แหล่งอ้างอิงที่เปิดดูจริงในรอบที่ 2

- https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device (ดึงเนื้อหาเต็มผ่าน tutorials-data JSON)
- https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html (HTML ดิบ ถอด tag เอง)
- https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services
- https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()
- https://developer.apple.com/documentation/corelocation/cllocationmanager/startrangingbeacons(satisfying:)
- https://developer.apple.com/documentation/corelocation/cllocationmanager/startrangingbeacons(in:)
- https://developer.apple.com/documentation/corelocation/cllocationmanager/stoprangingbeacons(satisfying:)
- https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:didrange:satisfying:)
- https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:didfailrangingfor:error:)
- https://developer.apple.com/documentation/corelocation/clbeaconregion
- https://developer.apple.com/documentation/corelocation/clbeaconregion/notifyentrystateondisplay
- https://developer.apple.com/documentation/corelocation/clbeaconidentityconstraint
- https://developer.apple.com/documentation/corelocation/clbeaconidentitycondition
- https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions
- https://developer.apple.com/documentation/corelocation/ranging-for-beacons
