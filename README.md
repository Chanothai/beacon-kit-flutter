# beacon_kit

Flutter SDK กลางของ BigC สำหรับรับข้อมูล BLE beacon แบบ broadcast (iBeacon / Eddystone)
ออกแบบให้ **ไม่ผูกกับยี่ห้อ** — ใช้ได้กับ beacon ทุกยี่ห้อที่ broadcast ตามมาตรฐานเปิด
โดยไม่ต้องรอ SDK เฉพาะของผู้ผลิต

> **สถานะ: 0.x — API ยังไม่ stable** อาจมี breaking change ระหว่าง minor version
> อ่านตารางสถานะฟีเจอร์ด้านล่างให้ครบก่อนตัดสินใจใช้ในงานจริง

---

## ตารางสถานะฟีเจอร์ (ณ 29 ส.ค. 2026)

| ฟีเจอร์ | สถานะ | อ่านว่ายังไง |
|---|---|---|
| **Broadcast scan: iBeacon ranging** บน **iOS** | ✅ ทดสอบบนอุปกรณ์จริงแล้ว | เจอ K9P จริง 2 ตัวพร้อมกัน แยกอุปกรณ์ด้วย major/minor ได้ถูก proximity/RSSI เปลี่ยนตามระยะจริง |
| **Broadcast scan: Eddystone (URL frame)** บน **iOS** | ✅ ทดสอบบนอุปกรณ์จริงแล้ว | decode จากอุปกรณ์บุคคลที่สามที่ไม่รู้จักมาก่อนได้ถูก — ยืนยัน vendor-agnostic จริง (UID/TLM frame ยังไม่เจอของจริง) |
| **Background region monitoring** (enter/exit, ปลุกแอปตอนถูก kill) | ⚠️ code-complete — **ยังไม่ verified** | โค้ดเขียนครบและคอมไพล์ผ่าน แต่**ยังไม่เคยรันบนอุปกรณ์จริงสักครั้ง** ห้ามพึ่งพาในงานจริงจนกว่าจะทดสอบ |
| **GATT connect / auth / config / OTA** | ❌ **ยังไม่ implement** | ไม่มีโค้ดส่วนนี้อยู่เลย `connect()` throw `UnsupportedError` ทันที |
| **อ่านประวัติ sensor ย้อนหลัง** | ❌ **ยังไม่ implement** | มีแต่ interface ว่าง ๆ ไม่มี implementation |
| **Android** (ทุกฟีเจอร์) | ❌ **ยังไม่มี** | เรียกจาก Android จะได้ `MissingPluginException` — ยังไม่มีแพ็กเกจ `beacon_kit_android` |

**คำที่ใช้ในตารางนี้แปลว่า:**

- **ทดสอบบนอุปกรณ์จริงแล้ว** — มีคนรันบน iPhone จริงและเห็นผลจริง
- **code-complete, ยังไม่ verified** — โค้ดครบ คอมไพล์ผ่าน unit test เขียว แต่**ไม่มีใครเคยเห็นมันทำงานบนอุปกรณ์จริง** unit test ที่เขียวเป็น mock ซึ่งพิสูจน์ได้แค่ว่าโค้ดเราเรียกตามสัญญาที่เรา*คิดว่า*ถูก ไม่ได้พิสูจน์ว่า OS ตอบแบบนั้นจริง
- **ยังไม่ implement** — ไม่มีโค้ดอยู่เลย

เอกสารนี้ **เลี่ยงคำว่า "รองรับ"** โดยตั้งใจ เพราะคำนั้นถูกอ่านว่า "ใช้งานได้จริงแล้ว"
ซึ่งจริงเฉพาะแถวแรกแถวเดียวเท่านั้น

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
- **`docs/test-checklists/`** — สิ่งที่ยังต้องยืนยันกับอุปกรณ์จริง
- **`CONTRIBUTING.md`** — กติกาก่อนส่ง PR

## License

Proprietary / internal use only — ดู `LICENSE` และ `NOTICE`
