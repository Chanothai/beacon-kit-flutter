# Sources: iOS — รู้ได้อย่างไรว่าตอนนี้ "ตาบอด"

วันที่ค้นคว้า: 2 กันยายน 2026 — ดึงจากเอกสารทางการของ Apple โดยตรง
(developer.apple.com) **ไม่ใช่จากบล็อก, StackOverflow หรือความจำ**

หน้าเอกสารของ Apple เรนเดอร์ด้วย JavaScript ดึงเป็น HTML ธรรมดาแล้วได้แต่หัวข้อ —
ข้อความข้างล่างดึงจาก **endpoint JSON ที่หน้าเดียวกันใช้** ซึ่งเป็นแหล่งเดียวกับที่
เรนเดอร์ขึ้นหน้าจอ:
`https://developer.apple.com/tutorials/data/documentation/<path>.json`

ไฟล์นี้ตอบคำถามที่ `prototype/visit_filter/SENSING.md` ค้างไว้ก่อนเริ่ม port
**ข้อความในเครื่องหมายคำพูดคือคำต่อคำ** ไม่ได้ถอดความ

---

## 1. ปิด alert ตอนสร้าง `CBCentralManager` ได้ด้วย `CBCentralManagerOptionShowPowerAlertKey` — ✅ ยืนยันแล้ว

**คำถาม:** การสร้าง `CBCentralManager` ขึ้นมาเพื่อ *ถาม* สถานะ Bluetooth อย่างเดียว
ทำให้ระบบขึ้น alert เตือนผู้ใช้ · มี option ปิดได้จริงไหม และชื่อคีย์คืออะไร

**คำตอบ: มีจริง และนี่คือชื่อคำต่อคำ**

```swift
let CBCentralManagerOptionShowPowerAlertKey: String
```

> "A Boolean value that specifies whether the system warns the user if the app
> instantiates the central manager when Bluetooth service isn't available."

> "The value for this key is an NSNumber object. **If the key isn't specified, the
> default value is true.**"

— https://developer.apple.com/documentation/corebluetooth/cbcentralmanageroptionshowpoweralertkey

**สิ่งที่เอกสารบอกและต้องอ่านให้ตรง:**

- ค่าปริยายคือ **`true`** → ถ้าไม่ส่ง option นี้ **ระบบจะเตือนผู้ใช้** ตอนสร้าง
  central manager ขณะที่ Bluetooth ใช้ไม่ได้ · การสร้างเพื่อถามสถานะเฉย ๆ จึงมี
  ผลข้างเคียงที่ผู้ใช้เห็น **ตามที่ `RawAdvertisementScanner.swift:17-18` เขียนกังวลไว้**
- ค่าที่ใส่ต้องเป็น `NSNumber` ไม่ใช่ `Bool` ดิบ (เอกสารระบุชนิดไว้ตรง ๆ)

⚠️ **สิ่งที่เอกสารหน้านี้ *ไม่ได้* บอก** — ห้ามเติมเอง:
- ไม่ได้ระบุว่า alert หน้าตาเป็นอย่างไร หรือขึ้นกี่ครั้ง
- ไม่ได้ระบุว่าการตั้ง `false` มีผลกับการทำงานอื่นของ central manager หรือไม่
- **ไม่ได้ระบุว่าปิด alert แล้วยังได้ `centralManagerDidUpdateState` ครบเหมือนเดิม
  หรือไม่** — สมเหตุสมผลว่าได้ แต่ไม่มีประโยคไหนรับรอง

---

## 2. ถามสถานะ **สิทธิ์** ได้โดยไม่ต้องสร้าง instance เลย — ✅ ยืนยันแล้ว

`CBManager.authorization` เป็น **class property** ไม่ใช่ instance property:

```swift
class var authorization: CBManagerAuthorization { get }
```

> "The current authorization status for using Bluetooth."

> "Check this property in your implementation of the delegate methods
> `centralManagerDidUpdateState(_:)` and `peripheralManagerDidUpdateState(_:)` to
> determine whether your app can use Core Bluetooth. **You can also use it to check the
> app's authorization status before creating a `CBManager` instance.**"

> "The initial value of this property is `notDetermined`."

มีตั้งแต่ iOS 13.1+ / iPadOS 13.1+ / macOS 10.15+ / watchOS 6.0+ / visionOS 1.0+

— https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization

🛑 **ข้อจำกัดที่ต้องระบุทุกครั้งที่อ้างถึง:** ตัวนี้ตอบเรื่อง **สิทธิ์** เท่านั้น
(`allowedAlways` / `denied` / `restricted` / `notDetermined`) — **ไม่ได้บอกว่า
Bluetooth เปิดอยู่หรือไม่** สองเรื่องนี้ทำให้เราตาบอดได้เหมือนกันแต่คนละสาเหตุ
ผู้ใช้ที่ให้สิทธิ์ครบแล้วปิด Bluetooth จะยังได้ `allowedAlways` จาก property นี้

---

## 3. CoreLocation แจ้งเมื่อการเฝ้า region ล้มเหลว — ✅ ยืนยันแล้ว (แต่ตอบไม่ตรงคำถาม)

```swift
optional func locationManager(
    _ manager: CLLocationManager,
    monitoringDidFailFor region: CLRegion?,
    withError error: any Error
)
```

> "Tells the delegate that a region monitoring error occurred."

> "If an error occurs while trying to monitor a given region, the location manager
> sends this message to its delegate. Region monitoring might fail because the region
> itself cannot be monitored or because there was a more general failure in configuring
> the region monitoring service."

> "Although implementation of this method is optional, it is recommended that you
> implement it if you use region monitoring in your application."

— https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:monitoringdidfailfor:witherror:)

⚠️ **เอกสารบอกแค่ว่า "มี error" ไม่ได้แจกแจงว่าอะไรบ้างที่ทำให้เกิด** — วลี
"a more general failure in configuring the region monitoring service" กว้างเกินกว่าจะ
สรุปว่าครอบคลุมกรณี Bluetooth ปิด · **ห้ามอ้างว่าเมธอดนี้จะถูกเรียกเมื่อผู้ใช้ปิด
Bluetooth** จนกว่าจะวัดบนเครื่องจริง

---

## หาแหล่งอ้างอิงไม่ได้ / ยังไม่ยืนยัน

รายการนี้ **ไม่ใช่** ข้ออ้างที่เราใช้อยู่ — บันทึกไว้เพื่อไม่ให้มีใครเติมเข้ามาโดย
คิดว่าเคยตรวจแล้ว

- 🛑 **สิ่งที่สำคัญที่สุดและยังตอบไม่ได้: เมื่อผู้ใช้ปิด Bluetooth ระหว่างที่เฝ้า
  `CLBeaconRegion` อยู่ CoreLocation ยิง `didExitRegion` ให้หรือไม่** — ถ้ายิง แปลว่า
  ฝั่ง iOS จะเจอบั๊ก visit ปลอมแบบเดียวกับที่เจอมาแล้ว **โดยที่ `SensingLost` ช่วย
  ไม่ได้เลยถ้าเราไม่รู้ตัวว่าตาบอดก่อนที่ `didExitRegion` จะมาถึง** · ค้นในหน้า
  region monitoring และหน้า `didExitRegion` แล้วไม่พบประโยคที่ระบุพฤติกรรมนี้
  **ต้องวัดบนเครื่องจริงเป็นเคสแรกของรอบทดสอบ iOS รอบหน้า**
- **ชื่อ selector ที่แจ้งการเปลี่ยน authorization ของ `CLLocationManager`** —
  `SENSING.md` เดิมเขียนไว้แบบไม่ระบุชื่อเพราะยังไม่ยืนยัน · **ยังไม่ได้ดึงมา**
- **`CBCentralManagerOptionShowPowerAlertKey` เมื่อตั้ง `false` แล้ว
  `centralManagerDidUpdateState` ยังถูกเรียกครบหรือไม่** — ดูข้อ 1
- **iOS แยกสถานะ "ผู้ใช้ปิด Bluetooth จาก Settings" ออกจาก "ปิดจาก Control Center"
  หรือไม่** — ไม่พบเอกสารที่ระบุ
