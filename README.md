# beacon_kit

Flutter SDK กลางของ BigC สำหรับรับข้อมูล BLE beacon แบบ broadcast (iBeacon / Eddystone)
ออกแบบให้ **ไม่ผูกกับยี่ห้อ** — ใช้ได้กับ beacon ทุกยี่ห้อที่ broadcast ตามมาตรฐานเปิด
โดยไม่ต้องรอ SDK เฉพาะของผู้ผลิต

> **สถานะ: 0.x — API ยังไม่ stable** อาจมี breaking change ระหว่าง minor version
> อ่านตารางสถานะฟีเจอร์ด้านล่างให้ครบก่อนตัดสินใจใช้ในงานจริง

---

## ตารางสถานะฟีเจอร์ (ณ 30 ส.ค. 2026)

| ฟีเจอร์ | สถานะ | อ่านว่ายังไง |
|---|---|---|
| **Broadcast scan: iBeacon ranging** บน **iOS** | ✅ ทดสอบบนอุปกรณ์จริงแล้ว | เจอ K9P จริง 2 ตัวพร้อมกัน แยกอุปกรณ์ด้วย major/minor ได้ถูก proximity/RSSI เปลี่ยนตามระยะจริง |
| **Broadcast scan: Eddystone (URL frame)** บน **iOS** | ✅ ทดสอบบนอุปกรณ์จริงแล้ว | decode จากอุปกรณ์บุคคลที่สามที่ไม่รู้จักมาก่อนได้ถูก — ยืนยัน vendor-agnostic จริง (UID/TLM frame ยังไม่เจอของจริง) |
| **Region enter/exit ตอนแอปอยู่เบื้องหลัง (process ยังไม่ถูก kill)** | ✅ ทดสอบบนอุปกรณ์จริงแล้ว | enter มาใน 5-8 วินาที exit มาใน 30-50 วินาที — **วัดครั้งเดียว ยังไม่ทำซ้ำหาค่าเฉลี่ย** อย่าเอาไปตั้ง timeout โดยตรง |
| **ปลุกแอปหลังผู้ใช้ปัดแอปทิ้งเอง (B5)** | ✅ ทดสอบบนอุปกรณ์จริงแล้ว — **เฉพาะเคส force-quit** | ทดสอบ 2 รอบด้วย release/profile build หลังลบแอปติดตั้งใหม่: iOS ปลุก process ที่ตายแล้วขึ้นมาส่ง event จริง (exit 55/30 วิ · enter 5/3 วิ) **ยังไม่ได้ทดสอบกรณีระบบฆ่าแอปเองจากหน่วยความจำ ซึ่งเกิดบ่อยกว่ามากในการใช้งานจริง** |
| **GATT connect / auth / config / OTA** | ❌ **ยังไม่ implement** | ไม่มีโค้ดส่วนนี้อยู่เลย `connect()` throw `UnsupportedError` ทันที |
| **อ่านประวัติ sensor ย้อนหลัง** | ❌ **ยังไม่ implement** | มีแต่ interface ว่าง ๆ ไม่มี implementation |
| **Android** (ทุกฟีเจอร์) | ❌ **ยังไม่มี** | เรียกจาก Android จะได้ `MissingPluginException` — ยังไม่มีแพ็กเกจ `beacon_kit_android` |

**คำที่ใช้ในตารางนี้แปลว่า:**

- **ทดสอบบนอุปกรณ์จริงแล้ว** — มีคนรันบน iPhone จริงและเห็นผลจริง
- **code-complete, ยังไม่ verified** — โค้ดครบ คอมไพล์ผ่าน unit test เขียว แต่**ไม่มีใครเคยเห็นมันทำงานบนอุปกรณ์จริง** unit test ที่เขียวเป็น mock ซึ่งพิสูจน์ได้แค่ว่าโค้ดเราเรียกตามสัญญาที่เรา*คิดว่า*ถูก ไม่ได้พิสูจน์ว่า OS ตอบแบบนั้นจริง
- **ยังไม่ implement** — ไม่มีโค้ดอยู่เลย

เอกสารนี้ **เลี่ยงคำว่า "รองรับ"** โดยตั้งใจ เพราะคำนั้นถูกอ่านว่า "ใช้งานได้จริงแล้ว"
ซึ่งจริงเฉพาะแถวที่ติด ✅ เท่านั้น และจริงเฉพาะในขอบเขตที่ระบุไว้ในแต่ละแถว

### ⚠️ ขอบเขตของ background region monitoring — อ่านก่อนพึ่งพา

แถว B5 ผ่านแล้วจริง แต่ **ห้ามอ่านว่า "background scan ใช้งานได้"** แบบเหมารวม
สิ่งที่ทดสอบคือเส้นทางเดียวในเงื่อนไขเดียว รายการข้างล่างนี้ **ยังไม่มีใครพิสูจน์**:

| ยังไม่ทดสอบ | ทำไมถึงสำคัญ |
|---|---|
| **ระบบฆ่าแอปเองเพราะหน่วยความจำ** | เกิดบ่อยกว่า force-quit มากในการใช้งานจริง และเป็นคนละเส้นทางของ OS — นี่คือช่องว่างที่ใหญ่ที่สุดที่เหลืออยู่ |
| **เครื่องล็อกอยู่ตอนถูกปลุก** | Data Protection อาจทำให้เขียนไฟล์ไม่ได้ · หลังรีบูตแล้วยังไม่ปลดล็อกครั้งแรก Apple ระบุว่า monitoring เริ่มไม่ได้เลย |
| **ไม่มีอินเทอร์เน็ต** | Apple ระบุว่า region monitoring ต้องการ network connectivity เพื่อรายงานได้ทันเวลา |
| **region ซ้อนทับกัน** | ยังไม่รู้ว่าได้ `didEnterRegion` ซ้ำหรือไม่ — ห้ามเขียน dedupe logic จนกว่าจะรู้ผล (ADR-8 open question) |
| **Eddystone: UID/TLM frame** | ที่ผ่านคือ **URL frame เท่านั้น** ยังไม่เคยเจอ UID/TLM ของจริง |
| **Android ทั้งหมด** | ยังไม่มีแพ็กเกจ — ไม่มีอะไรให้ทดสอบ |

ทั้งหมดนี้อยู่ใน `docs/test-checklists/ios_broadcast_scanning.md` พร้อมวิธีทดสอบ

### 🔴 ต้องมีชั้น debounce เสมอ — ห้าม deploy โดยไม่มี

การทดสอบข้ามคืน 30-31 ส.ค. 2026 (**มือถือวางนิ่ง จอดับ ล็อกเครื่อง K9P ไม่ถอดแบต
ไม่มีใครขยับอะไรเลย**) ได้ **enter 86 ครั้ง / exit 86 ครั้งใน 14 ชั่วโมง**

แปลว่าถ้ายิง event ตรงไป backend ทุกครั้ง **ลูกค้าหนึ่งคนที่นอนใกล้ beacon จะสร้าง
"เข้าสาขา" 86 ครั้งในคืนเดียวโดยไม่ได้ขยับเลย** — และถ้ามี push notification ผูกอยู่
ลูกค้าจะได้ 86 ครั้ง

**นี่ไม่ใช่บั๊กของ SDK** เป็นพฤติกรรมของ CoreLocation กับสภาพสัญญาณจริง SDK จึงรายงาน
สิ่งที่แพลตฟอร์มบอกอย่างซื่อสัตย์และ**ไม่กรองให้เอง** — ผู้ใช้ SDK ต้องใส่ชั้น
debounce เอง ค่าเริ่มต้นที่คำนวณจากข้อมูลจริงและวิธีคิดอยู่ใน ARCHITECTURE.md ADR-11
(ย่อ: รวม session ถ้าห่างน้อยกว่า 5 นาที + ต้องอยู่ต่อเนื่องอย่างน้อย 2 นาที →
ลด 85 ครั้งเหลือ 1)

**ข้อควรระวังสำหรับคนที่จะเขียนโค้ดตรวจว่าแอปถูกปลุกด้วย location event:**
จากการทดสอบจริง `UIApplication.LaunchOptionsKey.location` ได้ `false` ทั้งที่แอปถูก
ปลุกจากสถานะ terminated จริง — ถ้าใช้ key นี้เป็นสัญญาณเดียวจะได้ **false negative**
สาเหตุยังเป็น open question (ดูเช็คลิสต์ข้อ 12)

### ขอบเขตของการทดสอบบนอุปกรณ์จริง (อ่านก่อนพึ่งพา 2 แถวแรก)

ทดสอบไปแล้ว 3 รอบบน iPhone จริง ร่วมกับ K9P จริง 2 ตัว และอุปกรณ์ Eddystone ของ
บุคคลที่สามที่บังเอิญอยู่ในระยะ — รายละเอียดครบพร้อมหลักฐานอยู่ที่
`docs/test-checklists/ios_broadcast_scanning.md`

**ยืนยันแล้วบนอุปกรณ์จริง:**

- **iBeacon ranging** — เห็น K9P 2 ตัวพร้อมกันที่ใช้ UUID เดียวกัน
  (`7777772e-…000001`) และแยกเป็นคนละอุปกรณ์ได้ถูกด้วย major/minor
  (`229/24333` กับ `228/24332`) — เป็นหลักฐานตรงว่า BigC ID Scheme (UUID เดียว
  ทั้งบริษัท แยกอุปกรณ์ด้วย major/minor) ใช้ได้จริง ไม่ใช่แค่ทฤษฎีจากเอกสาร Apple
- **proximity / RSSI** — resolve จริงและเปลี่ยนตามระยะ ไม่ค้างที่ `unknown` หรือ 0 dBm
- **Eddystone ผ่าน CoreBluetooth** — decode
  `EddystoneUrlFrame(txPower: -38, url: https://www.google.com/)` ที่ -88 dBm จาก
  **อุปกรณ์ที่ไม่ได้ตั้งค่าเองและไม่รู้ยี่ห้อ** ซึ่งมีน้ำหนักกว่าการทดสอบกับอุปกรณ์
  ที่รู้คำตอบล่วงหน้า
- **permission flow ปกติ** — Allow ครั้งเดียวแล้วสแกนเริ่มเอง ไม่ต้องกด Start ซ้ำ
  และการกด Start รัว ๆ ระหว่าง prompt ค้างไม่ทำให้ crash หรือค้าง

**ยังไม่ได้ทดสอบ — อย่าเพิ่งพึ่งพา:**

| ยังไม่ทดสอบ | สถานะ |
|---|---|
| Don't Allow → เปิดสิทธิ์ใน Settings → กลับแอปโดยไม่ force quit | เคยเป็นบั๊ก **แก้แล้ว รอ retest** — ยังไม่ใช่ "ผ่าน" |
| beacon หายจากระยะ / ปิดเครื่อง | ยังไม่ทดสอบเลย |
| Bluetooth ปิดกลางคัน | ยังไม่ทดสอบเลย |
| เพดาน 20 regions | ยังไม่ทดสอบเลย |
| background mode / wake-on-terminate | ยังไม่ทดสอบเลย |
| Eddystone UID frame และ TLM frame | ยังไม่เจอของจริง (ผ่านแต่ unit test) |

**การที่ ranging กับ Eddystone URL ผ่าน ไม่ได้แปลว่าฟีเจอร์ broadcast ทั้งก้อนผ่าน**
ให้ถือเช็คลิสต์เป็นแหล่งความจริงที่ละเอียดกว่าตารางนี้เสมอ

---

## วิธีติดตั้ง

`beacon_kit` **ไม่ได้เผยแพร่บน pub.dev** (เป็น internal SDK — ดู LICENSE)
ให้ใช้ผ่าน git dependency และ **pin ที่ tag เสมอ อย่า pin ที่ branch**

```yaml
dependencies:
  beacon_kit:
    git:
      url: <URL ของ private remote>
      ref: v0.1.0            # <-- pin ที่ tag เสมอ
      path: packages/beacon_kit
```

**ทำไมต้อง pin ที่ tag ไม่ใช่ branch:** `ref: main` จะดึงคอมมิตล่าสุดของ branch นั้นมา
ทุกครั้งที่ resolve ใหม่ แปลว่าบิลด์ของคุณเปลี่ยนพฤติกรรมได้เองโดยไม่มีใครแก้อะไรในแอป
และ reproduce บิลด์เก่าไม่ได้ — อันตรายมากกับ SDK ที่ API ยังไม่ stable อย่าง 0.x

### สิ่งที่ต้องตั้งค่าเพิ่มฝั่ง iOS

ใส่ key เหล่านี้ใน `Info.plist` ของแอปที่เรียกใช้ (ดูตัวอย่างครบใน
`packages/beacon_kit/example/ios/Runner/Info.plist`):

| Key | จำเป็นเมื่อ |
|---|---|
| `NSLocationWhenInUseUsageDescription` | สแกน iBeacon ขณะใช้งานแอป |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | ต้องการ background region monitoring |
| `NSBluetoothAlwaysUsageDescription` | สแกน non-iBeacon (Eddystone) ผ่าน CoreBluetooth |
| `UIBackgroundModes` = `location`, `bluetooth-central` | ทำงานต่อเนื่องตอน background |

**ถ้าต้องการให้แอปถูกปลุกตอนถูก kill (B5)** ต้องเรียกเพิ่มหนึ่งบรรทัดใน
`AppDelegate` ด้วย:

```swift
import beacon_kit_ios

override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
  BeaconKitIosPlugin.startBackgroundRegionMonitoring { event in
    // ทำอะไรกับ event ก็ได้ — SDK ไม่บังคับ (เขียน log / ยิง notification / ส่งขึ้น server)
  }
  return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

**ทำไม SDK ทำให้เองไม่ได้:** ตอน iOS ปลุก process ที่ถูกฆ่าขึ้นมาเบื้องหลัง จะไม่มี
UI ถูกสร้าง จึงไม่มีการ register plugin ของ Flutter เลย — SDK ยังไม่มีตัวตนในรอบนั้น
จึงแทรกตัวเข้าไปเองไม่ได้ ต้องเป็น host app เรียก แอปที่ไม่ต้องการพฤติกรรมนี้ข้ามได้
เหตุผลเต็มอยู่ใน ARCHITECTURE.md ADR-10

---

## ตัวอย่างการใช้งาน

```dart
import 'package:beacon_kit/beacon_kit.dart';

// 1. สร้าง adapter พร้อมระบุ region ที่จะเฝ้าฟัง
//    iOS บังคับให้รู้ proximity UUID ล่วงหน้า — ไม่มีโหมด wildcard สแกนหาทุก UUID
//    (ดู ARCHITECTURE.md หัวข้อ "ข้อจำกัดของ iOS")
final adapter = GenericIBeaconEddystoneAdapter(
  iBeaconRegions: const [
    IBeaconRegionConfig(identifier: 'bigc-fleet', uuid: '<BIGC_PROXIMITY_UUID>'),
  ],
);

BeaconManager.register(adapter);

// 2. ฟัง stream — event มาจากทั้ง CoreLocation (iBeacon) และ CoreBluetooth (Eddystone)
final subscription = BeaconManager.scanAll().listen(
  (advertisement) {
    switch (advertisement.source) {
      case AdvertisementSource.coreLocation:
        // iOS ถอด uuid/major/minor/proximity มาให้แล้ว ไม่ต้อง parse เอง
        print('${advertisement.ibeaconMajor}/${advertisement.ibeaconMinor} '
            '${advertisement.rssi} dBm ${advertisement.proximity?.name}');
      case AdvertisementSource.coreBluetooth:
        // ได้ raw bytes มา Dart parser ถอดให้แล้วใส่ไว้ใน raw
        print(advertisement.raw['eddystone']);
      case AdvertisementSource.android:
        break; // ยังไม่มี Android
    }
  },
  onError: (Object error) => print('scan error: $error'),
);

// 3. ยกเลิกเมื่อเลิกใช้ — ไม่ยกเลิกจะปล่อยให้ native scan ค้างกินแบต
await subscription.cancel();
```

`<BIGC_PROXIMITY_UUID>` คือ proximity UUID กลางของบริษัท — ค่าจริงอยู่ที่
`docs/sources/bigc_provisioning.md` ให้ดึงจาก config/backend ตอน runtime
อย่า hardcode ลงในแอป (เหตุผล: ADR-5 ใน `ARCHITECTURE.md`)

---

## โครงสร้าง repo

```
packages/
  beacon_kit/                     # API ที่แอปเรียกใช้ (BeaconManager, BeaconAdapter)
    example/                      # แอปตัวอย่าง หน้าจอเดียว แสดง beacon แบบ realtime
  beacon_kit_platform_interface/  # entity + parser + usecase (pure Dart ทดสอบได้ไม่ต้องมีอุปกรณ์)
  beacon_kit_ios/                 # implementation ฝั่ง iOS (Swift)
docs/
  sources/                        # ผลการค้นคว้าโปรโตคอลรายยี่ห้อ + BigC provisioning
  fixtures/                       # ข้อมูลทดสอบ parser/usecase
  test-checklists/                # เช็คลิสต์ที่ต้องทำกับอุปกรณ์จริง
ARCHITECTURE.md                   # การตัดสินใจเชิงสถาปัตยกรรมทั้งหมด (ADR-1 ถึง ADR-7)
SPRINT.md                         # ขอบเขตสปรินต์ปัจจุบัน + กติกาการรายงานสถานะ
CONTRIBUTING.md                   # กติกาที่ต้องผ่านก่อนเปิด PR
```

## เอกสารที่ควรอ่านต่อ

- **`ARCHITECTURE.md`** — ทำไมถึงออกแบบแบบนี้ โดยเฉพาะหัวข้อ "ข้อจำกัดของ iOS"
  ที่อธิบายว่าทำไม iBeacon กับ Eddystone ต้องเดินคนละทางบน iOS
- **`docs/test-checklists/ios_broadcast_scanning.md`** — **สถานะจริงของทุกเคส**
  (ผ่าน/ไม่ผ่าน/ยังไม่ทดสอบ + ตัวเลขที่วัดได้) — ที่เดียวที่บันทึกสถานะ
- **`docs/test-checklists/ios_device_test_runbook.md`** — **ขั้นตอนลงมือทดสอบ**
  บนอุปกรณ์จริง เขียนสำหรับคนที่ถือเครื่องอยู่หน้างาน (ไม่มีสถานะอยู่ในไฟล์นั้น)
- **`CONTRIBUTING.md`** — กติกาก่อนส่ง PR

## License

Proprietary / internal use only — ดู `LICENSE` และ `NOTICE`
