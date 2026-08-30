# beacon_kit — สถาปัตยกรรม Flutter Cross-Platform Beacon Library

สรุปสถาปัตยกรรมเริ่มต้นสำหรับ `beacon-architect` subagent ใช้เป็นจุดตั้งต้น — ปรับ/ขยายได้ตาม ADR ที่ subagent ตัดสินใจเพิ่มเติม เอกสารนี้ไม่ใช่ข้อกำหนดตายตัว แต่เป็น baseline ที่มีเหตุผลรองรับชัดเจน

## หลักการออกแบบ

1. **แยก "รับ broadcast" กับ "connect" ออกจากกันเด็ดขาด** เพราะข้อจำกัดและความเสี่ยงต่างกันมาก (ยืนยันจาก K9P Playbook ก่อนหน้า)
2. **Broadcast/passive path ต้อง vendor-agnostic ตั้งแต่ต้น** — ตามที่ยืนยันแล้วว่าจะยังไม่ผูกกับยี่ห้อใดยี่ห้อหนึ่ง ใช้มาตรฐานเปิด (iBeacon/Eddystone) เป็นหลัก ทำให้ใช้ได้กับ beacon แทบทุกยี่ห้อในตลาดโดยไม่ต้องรอ SDK เฉพาะ
3. **Connect/active path ผูกกับ native SDK ของแต่ละยี่ห้อผ่าน platform channel** แทนการ reimplement protocol (เช่น MD5 auth ของ KKM) ใหม่ใน Dart/FFI — ลดความเสี่ยงและใช้เวลาพัฒนาน้อยกว่า เพราะ SDK ต้นทางผ่านการทดสอบจริงจากผู้ผลิตมาแล้ว
4. **ทุก adapter ใหม่ต้องผ่าน skill `beacon-sdk-verify` ก่อนเขียนโค้ด** และมีไฟล์ `docs/sources/<vendor>.md` กำกับ (บังคับโดย hook — ดู PIPELINE.md)

## โครงสร้าง Package (Flutter Federated Plugin Pattern)

```
beacon_kit/                        # ← app-facing Dart API (สิ่งที่ทีมแอปเรียกใช้)
beacon_kit_platform_interface/     # ← สัญญา method channel กลาง (federated plugin contract)
beacon_kit_android/                # ← implementation ฝั่ง Android (Kotlin)
beacon_kit_ios/                    # ← implementation ฝั่ง iOS (Swift)
```

เหตุผลที่แยกเป็น federated plugin (ไม่ยัดรวมไฟล์เดียว): เป็น pattern ที่ Flutter เองแนะนำสำหรับ plugin ที่มี native code สองแพลตฟอร์ม ทำให้ทดสอบ/อัปเดตแต่ละฝั่งแยกกันได้ และเปิดทางให้ภายหลังมี `beacon_kit_windows`/`beacon_kit_linux` (สำหรับ gateway บน Linux) โดยไม่กระทบ API หลัก

## Dart API หลัก (`beacon_kit`)

```dart
abstract class BeaconAdapter {
  String get vendorId;                    // เช่น "generic_ibeacon_eddystone", "kkm_k9p"
  bool get supportsConnect;               // false = broadcast-only

  Stream<BeaconAdvertisement> scan();     // path A: ใช้ได้ทุก adapter
  Future<BeaconConnection> connect({      // path B: throw UnsupportedError ถ้า supportsConnect=false
    required String macAddress,           // TODO (ดู ADR-1 ท้ายเอกสาร): มีปัญหา identity เดียวกับ BeaconAdvertisement.macAddress เดิม — ยังไม่แก้วันนี้เพราะ connect-path เป็น Track B (ต้องรอฮาร์ดแวร์ตาม SPRINT.md) จะเปลี่ยนเป็น BeaconDeviceId ในรอบถัดไป
    required String password,
    Duration timeout = const Duration(seconds: 15),
  });
}

// ⚠️ ฉบับตั้งต้นนี้ล้าสมัยแล้ว — macAddress ไม่มีจริงบน iOS (CoreBluetooth ให้แค่
// per-app peripheral identifier ที่สุ่มใหม่ทุกครั้งที่ลงแอปใหม่, CLBeacon ไม่มี device
// identifier เลย) และไม่มีทางบอกว่าข้อมูลมาจาก CoreLocation (typed) หรือ
// CoreBluetooth/Android (raw bytes ผ่าน parser) ดูหัวข้อ "ADR: iOS-first Sprint —
// Domain Layer & Platform Channel Contract" ท้ายเอกสารสำหรับ shape จริงที่
// flutter-dev ต้อง implement ตาม (ADR-1, ADR-2) — เก็บโค้ดเดิมไว้ตรงนี้เป็นร่องรอย
// การตัดสินใจเท่านั้น ห้าม copy ไปใช้ตรง ๆ
class BeaconAdvertisement {
  final String macAddress;
  final int rssi;
  final Map<String, dynamic> raw;         // ค่าที่ decode แล้ว (battery, temperature, ...)
}

abstract class BeaconConnection {
  Future<Map<String, dynamic>> readConfig();
  Future<void> writeConfig(Map<String, dynamic> config);
  Future<SensorHistoryPage> readSensorHistory(String sensorType, {int offset = 0});
  Future<void> startFirmwareUpdate(String firmwarePath, {required void Function(int percent) onProgress});
  Future<void> disconnect();
}

class BeaconManager {
  static final _adapters = <BeaconAdapter>[];
  static void register(BeaconAdapter adapter) => _adapters.add(adapter);
  static Stream<BeaconAdvertisement> scanAll() { /* merge stream จากทุก adapter ที่ลงทะเบียน */ }
}
```

แอปเรียกแค่ `BeaconManager` และ `BeaconAdapter` เท่านั้น — ไม่เห็นคลาสของ KKM หรือยี่ห้อใดโดยตรง (ตรงตามหลัก facade ที่เคยแนะนำใน K9P Playbook ข้อ 6.3)

## ข้อค้นพบสำคัญ: "รองรับหลายยี่ห้อ" ไม่ต้องแยก adapter ต่อยี่ห้อ (แก้ไข 27 ส.ค. 2026)

**iBeacon เป็นฟอร์แมตมาตรฐานตัวเดียว ไม่มีความต่างรายยี่ห้อ** payload คือ Apple company ID `0x004C` + `0x02 0x15` + UUID 16 ไบต์ + major 2 ไบต์ + minor 2 ไบต์ + txPower 1 ไบต์ เหมือนกันหมดทุกผู้ผลิต

ยืนยันด้วยการเทียบ 2 codebase ที่ไม่เกี่ยวข้องกันเลย (คนละบริษัท คนละภาษา): SDK ทางการของ KKM (`KBUtility.java`) และ Flutter plugin สาธารณะตัวหนึ่ง (`BeaconParser.kt`) — ใช้ constant `0x004C` และ prefix `{0x02, 0x15}` ตรงกันเป๊ะ

**ผลต่อสถาปัตยกรรม:** การ "รองรับ iBeacon หลายยี่ห้อ" แทบไม่ต้องเขียนโค้ดต่อยี่ห้อเลย — parser ตัวเดียว ~30 บรรทัดครอบคลุมทุกยี่ห้อในตลาด การมี `BeaconAdapter` แยกต่อยี่ห้อสำหรับงาน broadcast จึงเป็นการ over-engineer

### โครงที่ถูกต้อง: แบ่งตาม "มาตรฐานเปิด vs เฉพาะเจ้า" ไม่ใช่แบ่งตามยี่ห้อ

**ชั้นที่ 1 — vendor-neutral (implement ครั้งเดียว ใช้ได้ทุกยี่ห้อ)**
- iBeacon parser (มาตรฐาน Apple)
- Eddystone parser UID/URL/TLM (มาตรฐานเปิด, service `0xFEAA`)
- **กลไก background scanning ต่อ OS** ← งานยากจริงและมีค่าที่สุดอยู่ตรงนี้

**ชั้นที่ 2 — vendor-specific (เพิ่มเฉพาะเมื่อต้องใช้ฟีเจอร์เฉพาะเจ้านั้นจริง)**
- ตัวถอดรหัส sensor payload เฉพาะเจ้า (เช่น "Ksensor" ของ KKM ที่ใส่ temperature/battery/acceleration มาใน manufacturer data `0x0A53` — ไม่ใช่ iBeacon)
- GATT connect / config / OTA (ต่างกันสิ้นเชิงทุกยี่ห้อ)

**บทเรียนสำคัญ:** ความยากของโปรเจกต์นี้อยู่ที่ **per-platform (iOS/Android/Huawei) ไม่ใช่ per-vendor** — background execution บนแต่ละ OS คือส่วนที่กินเวลาและสร้างความแตกต่างจริง ส่วนการรองรับหลายยี่ห้อในระดับ broadcast ได้มาเกือบฟรีจากการทำตามมาตรฐาน

## ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android (แก้ไข 27 ส.ค. 2026)

iOS แยก API ของ iBeacon ออกจาก BLE ทั่วไปอย่างเด็ดขาด และ **ใช้ปนกันไม่ได้**:

| ฟอร์แมต | API บน iOS | ได้อะไร | Background |
|---|---|---|---|
| **iBeacon** | CoreLocation (`CLBeaconRegion`) | UUID/major/minor/RSSI/proximity แบบ**ถอดมาให้แล้ว** ไม่ใช่ raw bytes | ได้ดี — OS ปลุกแอปแม้โดน kill |
| Eddystone / Ksensor / custom | CoreBluetooth (`CBCentralManager`) | raw advertisement bytes | จำกัดหนัก — ต้อง filter ด้วย service UUID ที่ประกาศไว้ล่วงหน้า |

**iOS ปิดกั้น iBeacon ไม่ให้เห็นผ่าน CoreBluetooth** — manufacturer data ของ iBeacon ถูก OS mask ทิ้ง เห็นได้แค่ peripheral identifier กับ RSSI ไม่มี major/minor

ผลที่ตามมา 3 ข้อ:

1. **Dart parser ของเราจะไม่ถูกเรียกใช้สำหรับ iBeacon บน iOS เลย** — บน iOS ได้ข้อมูลที่ CoreLocation ถอดมาให้แล้ว ส่วน parser ใช้กับ Android (ทุกฟอร์แมต) และ iOS (เฉพาะฟอร์แมตที่ไม่ใช่ iBeacon) → **จุดที่ทั้งสองทางมาบรรจบกันคือ domain entity `BeaconAdvertisement`** ไม่ใช่ที่ตัว parser
2. **บน iOS ต้องรู้ UUID ล่วงหน้า** `CLBeaconRegion` บังคับ ไม่มีโหมด wildcard สแกนหา iBeacon ทุกตัวแบบ Android → SDK กลางที่รองรับหลายยี่ห้อ ต้องออกแบบให้แอปดึงรายการ UUID จาก backend/config มาสร้าง region (เพดาน 20 regions)
3. **อ่านค่า sensor ของ K9P (Ksensor, manufacturer `0x0A53`) บน iOS ตอน background ทำได้ยากมาก** เพราะไม่ใช่ iBeacon จึงต้องผ่าน CoreBluetooth ซึ่งใน background รายงานเฉพาะอุปกรณ์ที่ตรง service UUID ที่ประกาศไว้ และไม่รายงาน advertisement แบบ non-connectable

*ที่มา: Apple Developer Forums (thread 69112 — "No, you can't receive iBeacon advertisement data with CoreBluetooth") และคู่มือ iOS BLE scanning ของ Punch Through — เป็นแหล่งระดับ community/third-party ที่สอดคล้องกัน ไม่ใช่ถ้อยแถลงในเอกสารทางการของ Apple โดยตรง ควรยืนยันซ้ำด้วยการทดสอบจริงบนเครื่อง*

## Adapter ที่ implement รอบแรก

### 1. `GenericIBeaconEddystoneAdapter` — broadcast-only, vendor-agnostic
- `supportsConnect = false`
- ทำงานผ่าน BLE scan มาตรฐาน (native Android `BluetoothLeScanner` / iOS `CoreBluetooth CBCentralManager`) — **ไม่ต้องพึ่ง SDK ของยี่ห้อไหนเลย** เพราะ iBeacon/Eddystone เป็นฟอร์แมตเปิด
- ใช้ได้กับ K9P และ beacon ยี่ห้ออื่นที่ broadcast ตามมาตรฐานนี้ทันที โดยไม่ต้องรอ vendor SDK ใหม่
- Decode "Ksensor" (รูปแบบเฉพาะของ KKM สำหรับ temperature/acceleration ใน ADV) เป็น optional decoder เสริมในนี้ได้ เพราะ logic การถอดรหัสมาจากซอร์ส MIT ที่ตรวจสอบแล้ว — พอร์ตตรงจาก `KBAdvPacketSensor` (Java/Swift) เป็น Dart ได้เลยตามสิทธิ์ MIT

### 2. `KkmK9pAdapter` — GATT connect, ยี่ห้อ KKM เท่านั้น
- `supportsConnect = true`
- Platform channel เรียกเข้า native SDK ที่ verified แล้วโดยตรง: ฝั่ง Android wrap `com.kkmcn.kbeaconlib2:kbeaconlib2` (AAR), ฝั่ง iOS wrap CocoaPod `kbeaconlib2`
- ทุก UUID/method ที่ native เรียกอ้างอิงจาก K9P Playbook ที่ verified แล้วทั้งหมด (service `0000FEA0`, write/notify/indicate char ตามที่ระบุ, auth MD5 2 รอบ, default password ต้องบังคับเปลี่ยนตอน provision)
- ห้าม native code ฝั่งนี้ hardcode default password `"0000000000000000"` ไว้ที่ไหนนอกจาก unit test — เป็นเงื่อนไข review บังคับ (ดู `beacon-reviewer.md`)

## App Layer — แอปที่ใช้ `beacon_kit` (feature-first + Clean Architecture + BLoC)

`beacon_kit` เป็น library ระดับต่ำเท่านั้น ไม่มี state ของ UI — แอปจริงที่ทีมงานใช้ต้องมีชั้นของตัวเองครอบอีกที ตามที่กำหนด:

```
lib/
  core/                     # DI (get_it), error handling, shared widgets/utils
  features/
    beacon_scanning/        # feature: สแกนหา/แสดงรายการ beacon (path A)
      data/                 #   datasources เรียก beacon_kit ตรงที่นี่ที่เดียว
      domain/               #   pure Dart: entities, repository interface, usecases
      presentation/         #   bloc/ + pages/ + widgets/
    beacon_provisioning/    # feature: connect/config/OTA (path B)
      data/ domain/ presentation/
    beacon_history/         # feature: อ่านประวัติ sensor ย้อนหลัง
      data/ domain/ presentation/
  app.dart
  main.dart
```

กฎทิศทาง dependency: `presentation → domain → data` เท่านั้น (`domain/` เป็น pure Dart ห้าม import beacon_kit/Flutter SDK) — รายละเอียดกฎ BLoC และ dependency ที่แนะนำอยู่ใน `.claude/agents/flutter-dev.md`

ทำไมแยกจาก `beacon_kit`: `beacon_kit` ต้องใช้ซ้ำได้ในแอปอื่นในอนาคตโดยไม่ผูกกับ BLoC หรือโครงสร้างแอปใดแอปหนึ่ง — ถ้ายัด BLoC เข้าไปใน plugin เอง จะทำให้ plugin ผูกกับ state management framework หนึ่งตัวโดยไม่จำเป็น

## CI/CD และ Lint/Format มาตรฐาน

- Lint: `flutter_lints` (แพ็กเกจมาตรฐานของทีม Flutter เอง, เวอร์ชันล่าสุด ^6.0.0 ณ วันที่ตรวจสอบ) ผ่าน `analysis_options.yaml`
- Format: `dart format` (มาพร้อม Dart SDK อยู่แล้ว เป็นตัวมาตรฐานเดียว ไม่ใช้ formatter อื่น)
- CI: GitHub Actions (`.github/workflows/ci.yml`) รัน format check → analyze → test ทุก push/PR — รายละเอียดใน README และไฟล์ workflow เอง

## ส่วนที่ยังไม่ implement รอบนี้ (ตามคำตอบผู้ใช้)

- Adapter เฉพาะของยี่ห้ออื่น (Minew, Kontakt.io, Estimote ฯลฯ) — รอจนกว่าจะระบุยี่ห้อจริง แล้วต้องรัน skill `beacon-sdk-verify` วิจัยก่อนเริ่ม
- Peripheral mode (มือถือ broadcast ตัวเองเป็น beacon) — ผู้ใช้ยืนยันแล้วว่าไม่ต้องการส่วนนี้

## ADR: iOS-first Sprint — Domain Layer & Platform Channel Contract (เพิ่ม 27 ส.ค. 2026)

**บริบท:** สปรินต์วันนี้สลับลำดับให้ **iOS มาก่อน Android** (override จาก `SPRINT.md` เดิมโดยผู้ใช้) และจะเริ่มเขียน Dart domain layer กับ Swift platform channel **พร้อมกัน** — ADR นี้ปิดช่องโหว่ 4 จุดที่ยังไม่เคยตัดสินใจใน ARCHITECTURE.md เพื่อไม่ให้สองทีม implement คนละแบบ ทุก field/signature ในหัวข้อนี้ให้ `flutter-dev` copy ไปใช้ implement ได้ตรงตัว ไม่ต้องตีความเพิ่ม

ห้ามอ้างอิง SDK/library ของยี่ห้อใดที่ไม่มีใน `docs/sources/` — ทั้งหมดในหัวข้อนี้เป็น broadcast-path มาตรฐานเปิดล้วน ๆ (CoreLocation/CoreBluetooth เป็น OS framework ของ Apple เอง ไม่ใช่ vendor beacon SDK, Eddystone เป็น open protocol ของ Google) **ไม่เกี่ยวกับ kbeaconlib2/KKM**

### ADR-1: `BeaconAdvertisement.macAddress` → `BeaconDeviceId` (deviceId + kind)

**ปัญหา:** ฟิลด์ `macAddress: String` เดิม (ดูโค้ดต้นฉบับด้านบนที่เก็บไว้เป็นร่องรอย) สมมติว่าทุก platform ให้ MAC address จริงได้ ซึ่งไม่จริงบน iOS:

- **CoreBluetooth** (`CBPeripheral.identifier`) — UUID สุ่ม **ต่อแอป** (per-app) OS สร้างใหม่ทุกครั้งที่ถอน-ลงแอปใหม่ ไม่ใช่ MAC จริงของวิทยุ ไม่คงที่ข้าม install
- **CoreLocation** (`CLBeacon`) — **ไม่มี device identifier เลย** identity ที่มีคือ `uuid`+`major`+`minor` ซึ่งเป็น identity เชิงตรรกะของ "สัญญาณ beacon ที่ตั้งค่าไว้" ไม่ใช่ identity ของตัววิทยุกายภาพ (สองเครื่องตั้งค่า uuid/major/minor ซ้ำกันได้)
- **Android** (`BluetoothDevice.address`, สปรินต์หน้า) — MAC จริงจาก radio คงที่ข้าม install

เก็บทั้งสามอย่างไว้ในฟิลด์ `macAddress: String` เดียวกัน จะทำให้โค้ด Dart (BLoC/repository/dedup logic) เข้าใจผิดว่าเทียบ/persist ข้ามค่ากันได้ ทั้งที่เป็นคนละชนิดของ identity กันเลย — เป็นบั๊กเงียบที่ compile ผ่านตลอดแต่พังตอน runtime

**คำตัดสิน:**

```dart
enum DeviceIdKind {
  /// Android BluetoothDevice.address — MAC address จริงจากวิทยุ คงที่ข้าม install
  macAddress,

  /// iOS CBPeripheral.identifier (CoreBluetooth) — UUID สุ่มต่อแอป ไม่ใช่ MAC จริง
  /// เปลี่ยนได้เมื่อถอน-ลงแอปใหม่ ใช้เทียบ "อุปกรณ์เดียวกันภายในการติดตั้งนี้" เท่านั้น
  coreBluetoothPeripheralId,

  /// iOS CLBeacon (CoreLocation) — ไม่มี physical device identifier ให้เลย
  /// ใช้ identity เชิงตรรกะแทน รูปแบบ "<uuid>:<major>:<minor>" (uuid เป็น lowercase)
  /// หมายเหตุ: สอง beacon ที่ตั้งค่า uuid/major/minor ซ้ำกันจะได้ deviceId เดียวกัน
  /// — เป็นข้อจำกัดของ platform เอง ไม่ใช่บั๊กของ SDK นี้
  iBeaconLogicalId,
}

class BeaconDeviceId {
  final String value;
  final DeviceIdKind kind;
  const BeaconDeviceId({required this.value, required this.kind});

  @override
  bool operator ==(Object other) =>
      other is BeaconDeviceId && other.value == value && other.kind == kind;
  @override
  int get hashCode => Object.hash(value, kind);
}
```

**กฎการใช้งานที่ต้อง enforce (ใน doc comment + code review ไม่ใช่แค่ตั้งชื่อ):** ห้ามเทียบ/dedup `BeaconDeviceId` สอง instance ที่ `kind` ต่างกันราวกับเป็นอุปกรณ์เดียวกัน (`value` ตรงกันข้าม kind โดยบังเอิญไม่มีความหมายอะไร) — `BeaconManager.scanAll()` ที่ merge stream จากหลาย adapter/source ต้อง dedup ตามคู่ `(kind, value)` เสมอ

**ผลกระทบต่อเนื่อง (ตั้งใจไม่แก้วันนี้):** `BeaconAdapter.connect({required String macAddress, ...})` มีปัญหา identity เดียวกัน แต่เป็น connect-path ของ K9P ซึ่งเป็น Track B (ต้องรอฮาร์ดแวร์จริงตาม `SPRINT.md`) — บันทึกเป็น TODO ในโค้ดต้นฉบับด้านบนแล้ว ต้องเปลี่ยนเป็น `BeaconDeviceId` ในรอบถัดไปเช่นกัน

### ADR-2: แหล่งที่มาของข้อมูล + shape เต็มของ `BeaconAdvertisement`

**ปัญหา:** CoreLocation ถอด iBeacon ให้เป็น typed fields แล้ว (ไม่ผ่าน parser ของเรา) ส่วน CoreBluetooth (iOS, ทุกฟอร์แมตยกเว้น iBeacon) และ Android (ทุกฟอร์แมตรวม iBeacon) ให้ raw bytes ที่ต้องผ่าน Dart parser — ต้องมี field บอกชัดว่า advertisement นี้มาทางไหน (สอดคล้องกับที่บันทึกไว้แล้วในหัวข้อ "ข้อจำกัดของ iOS ...": "จุดที่ทั้งสองทางมาบรรจบกันคือ domain entity `BeaconAdvertisement` ไม่ใช่ที่ตัว parser")

**คำตัดสิน — shape เต็ม (แทนที่ shape เดิมทั้งหมด) ไฟล์: `packages/beacon_kit_platform_interface/lib/src/entities/beacon_advertisement.dart`:**

```dart
/// แหล่งข้อมูลดิบที่ BeaconAdvertisement นี้เดินทางมา — บอกว่า field กลุ่มไหน
/// การันตีว่ามีค่า และกลุ่มไหนการันตีว่าไม่มี (null / ว่าง)
enum AdvertisementSource {
  /// iOS, ผ่าน CLLocationManager ranging (CLBeaconRegion) — เฉพาะ iBeacon เท่านั้น
  /// ibeaconUuid/Major/Minor/proximity การันตีว่ามีค่าเสมอ, ibeaconTxPower เป็น null
  /// เสมอ (CLBeacon ไม่มี field นี้ตรง ๆ), raw และ rawBytes ว่างเสมอ
  coreLocation,

  /// iOS, ผ่าน CBCentralManager scan — ทุกฟอร์แมต "ยกเว้น" iBeacon (OS mask
  /// iBeacon manufacturer data ทิ้งที่ระดับ CoreBluetooth ทั้งหมด — ดูหัวข้อ
  /// "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android")
  /// ibeacon* ทุกฟิลด์เป็น null เสมอ, raw/rawBytes มีค่าจาก Dart parser (Eddystone ฯลฯ)
  coreBluetooth,

  /// Android, ผ่าน BluetoothLeScanner — ทุกฟอร์แมตรวม iBeacon (Android ไม่ mask)
  /// ibeacon* มีค่าได้ก็ต่อเมื่อ IBeaconParser.parse() บน manufacturerData สำเร็จ
  /// (ไม่การันตีเหมือน coreLocation เพราะเป็นผล parse ไม่ใช่ native ถอดให้)
  /// raw/rawBytes มีค่าเสมอ (raw ADV bytes จาก OS)
  android,
}

/// ค่า proximity ที่ CoreLocation คำนวณให้ (ระยะห่างโดยประมาณจาก RSSI/txPower ภายใน
/// ของ OS เอง) ไม่มีทางเทียบเท่าฝั่ง Android/Dart parser เพราะไม่ใช่ field ที่ decode
/// ได้จาก byte ของ ADV — มีค่าเฉพาะ source == coreLocation เท่านั้น
enum BeaconProximity { unknown, immediate, near, far }

class BeaconAdvertisement {
  // ---- ระบุตัวตน (ดู ADR-1) ----
  final BeaconDeviceId deviceId;
  final int rssi; // dBm, ค่าดิบจาก OS ไม่ผ่านการแปลง
  final AdvertisementSource source;
  final DateTime timestamp; // UTC, เวลาที่ Dart layer ได้รับ event (ไม่ใช่เวลา broadcast จริง)

  // ---- iBeacon-typed fields ----
  // มีค่าการันตีเมื่อ source == coreLocation เสมอ
  // มีค่าแบบไม่การันตีเมื่อ source == android และ IBeaconParser.parse() สำเร็จ (ADR-3)
  // เป็น null เสมอเมื่อ source == coreBluetooth (iOS มองไม่เห็น iBeacon ทาง CoreBluetooth)
  final String? ibeaconUuid; // lowercase, hyphenated (8-4-4-4-12)
  final int? ibeaconMajor; // 0-65535
  final int? ibeaconMinor; // 0-65535
  final int? ibeaconTxPower; // measured power @ 1m, signed 8-bit dBm — null เสมอเมื่อ source == coreLocation
  final BeaconProximity? proximity; // มีค่าเฉพาะ source == coreLocation

  // ---- raw decoded payload: มาจาก Dart parser (EddystoneParser ฯลฯ) ----
  final Map<String, dynamic> raw; // เช่น {'eddystone': EddystoneUidFrame(...)} — ว่างเสมอเมื่อ source == coreLocation
  final Uint8List? rawBytes; // raw service/manufacturer bytes ก่อน parse, null เมื่อ source == coreLocation — เก็บไว้ debug/forward-compat

  const BeaconAdvertisement({
    required this.deviceId,
    required this.rssi,
    required this.source,
    required this.timestamp,
    this.ibeaconUuid,
    this.ibeaconMajor,
    this.ibeaconMinor,
    this.ibeaconTxPower,
    this.proximity,
    this.raw = const {},
    this.rawBytes,
  });
}
```

**เหตุผลที่ไม่แยก subclass ตาม source (เช่น `CoreLocationAdvertisement extends BeaconAdvertisement`):** พิจารณาแล้วตัดออก เพราะ `BeaconManager.scanAll()` merge stream จากทุก adapter/source เป็น `Stream<BeaconAdvertisement>` เดียว — ถ้าแยก subclass ผู้ใช้ปลายทาง (BLoC) ต้อง type-check/cast ทุกครั้งที่ใช้ ขัดกับหลัก facade ที่ต้องใช้ง่ายเป็นชนิดเดียว การใช้ nullable field + `source` enum แลก null-safety บางจุดเพื่อ API ที่แบนราบใช้ง่ายกว่า — ต้องมี doc comment กำกับทุก field แบบข้างบนเพื่อชดเชยจุดอ่อนนี้ (ไม่มีมันคือทำให้ dev เดา ซึ่งขัดนโยบายห้ามเดา)

### ADR-3: Parser contract — `EddystoneParser` / `IBeaconParser`

ตำแหน่งไฟล์ (ใหม่ทั้งหมด — ปัจจุบัน `packages/beacon_kit_platform_interface/lib/beacon_kit_platform_interface.dart` มีแค่ boilerplate template `Calculator` ต้องถูกแทนที่เป็น barrel export):

```
packages/beacon_kit_platform_interface/lib/
  beacon_kit_platform_interface.dart      # barrel export — export ทุกไฟล์ข้างล่างนี้
  src/
    entities/
      beacon_advertisement.dart           # BeaconAdvertisement, BeaconDeviceId, DeviceIdKind, AdvertisementSource, BeaconProximity (ADR-1, ADR-2)
      ibeacon_frame.dart                  # IBeaconFrame
      eddystone_frame.dart                # EddystoneFrame + EddystoneUidFrame / EddystoneUrlFrame / EddystoneTlmFrame
    parsers/
      parse_result.dart                   # ParseResult<T>, ParseSuccess<T>, ParseFailure<T>, ParseFailureReason
      ibeacon_parser.dart                 # IBeaconParser
      eddystone_parser.dart               # EddystoneParser
```

**Return type ร่วม — `ParseResult<T>` (sealed class, Dart 3 pattern matching, ไม่ throw ทั่วไป):**

```dart
sealed class ParseResult<T> {
  const ParseResult();
}

final class ParseSuccess<T> extends ParseResult<T> {
  final T value;
  const ParseSuccess(this.value);
}

final class ParseFailure<T> extends ParseResult<T> {
  final ParseFailureReason reason;
  final String? detail; // เช่น "expected total length 20 bytes, got 14"
  const ParseFailure(this.reason, {this.detail});
}

enum ParseFailureReason {
  tooShort,               // ความยาวรวมน้อยกว่าค่าต่ำสุดของ frame type นั้น
  tooLong,                // ความยาวรวมเกินขนาดสูงสุดที่ ADV payload รองรับ (31 bytes)
  invalidPrefix,          // byte แรก ๆ ไม่ตรง prefix ที่ frame type นั้นกำหนด (เช่น iBeacon ต้องเป็น 0x02 0x15)
  invalidFrameType,       // byte ที่ควรเป็น frame type ไม่ตรงกับค่าใด ๆ ที่ spec นิยามไว้เลย
  truncatedField,         // byte พอสำหรับ frame type แต่ field ใด field หนึ่งถูกตัดสั้นกลางคัน
  unsupportedFrameType,   // frame type ที่ spec นิยามไว้จริง แต่ parser เวอร์ชันนี้ยังไม่ implement decode logic (เช่น Eddystone-EID 0x30)
}
```

**`IBeaconParser` — ใช้บน Android เท่านั้น:**

```dart
/// Parse Apple manufacturer-specific data (company ID 0x004C, frame prefix 0x02 0x15)
/// เป็น [IBeaconFrame] — byte layout ยืนยันแล้วจากการเทียบ KBUtility.java (KKM SDK)
/// กับ BeaconParser.kt (Flutter plugin สาธารณะ) ดูหัวข้อ "ข้อค้นพบสำคัญ: iBeacon
/// เป็นฟอร์แมตมาตรฐานตัวเดียว" ด้านบน
///
/// **เรียกใช้บน Android เท่านั้น** — ห้ามเรียกจากโค้ด iOS เพราะ:
/// - CoreBluetooth บน iOS mask manufacturer data ของ iBeacon ทิ้งตั้งแต่ระดับ OS
///   (เห็นแค่ peripheral identifier + RSSI ไม่มี byte ให้ parse เลย)
/// - iBeacon บน iOS มาทาง CoreLocation ซึ่งถอด uuid/major/minor ให้เป็น typed field
///   อยู่แล้วโดย OS โดยตรง ไม่ผ่านการ parse byte ใด ๆ ในฝั่ง Dart (ดู ADR-2,
///   AdvertisementSource.coreLocation)
/// เรียก parser ตัวนี้บน iOS จะไม่มี manufacturerData ที่ valid ให้ป้อนเข้ามาตั้งแต่ต้น
final class IBeaconParser {
  const IBeaconParser._();

  static ParseResult<IBeaconFrame> parse(Uint8List manufacturerData);
}

final class IBeaconFrame {
  final String uuid;      // lowercase, hyphenated
  final int major;
  final int minor;
  final int txPower;      // measured power @ 1m, signed 8-bit dBm
  const IBeaconFrame({
    required this.uuid,
    required this.major,
    required this.minor,
    required this.txPower,
  });
}
```

**`EddystoneParser` — parse service data ของ service `0000FEAA-...`** (service UUID ยืนยันแล้วใน `docs/sources/kkm_k9p.md`; Eddystone เป็น open protocol ของ Google — byte layout ต่อไปนี้ยืนยันจาก spec ทางการที่เปิดดูจริงวันนี้ ไม่ใช่ความจำ):

| Frame | Byte 0 | Byte 1 | Field ถัดไป | แหล่งอ้างอิง |
|---|---|---|---|---|
| UID (`0x00`) | `0x00` | TX power (calibrated @ 0m) | Namespace 10 bytes, Instance 6 bytes, Reserved 2 bytes (รวม 20 bytes) | [eddystone-uid/README.md](https://github.com/google/eddystone/blob/master/eddystone-uid/README.md) |
| URL (`0x10`) | `0x10` | TX power (calibrated @ 0m) | URL scheme prefix 1 byte (`0x00`-`0x03`) + encoded URL 1-17 bytes | [eddystone-url/README.md](https://github.com/google/eddystone/blob/master/eddystone-url/README.md) |
| TLM (`0x20`) | `0x20` | Version (`0x00` = unencrypted) | Battery voltage 2 bytes (1 mV/bit), Temperature 2 bytes (signed 8.8 fixed-point, `0x8000` = ไม่รองรับ sensor), Adv PDU count 4 bytes, Time since power-on 4 bytes (0.1s resolution) — รวม 14 bytes, **ทุกฟิลด์หลาย byte เป็น big-endian** | [eddystone-tlm/tlm-plain.md](https://github.com/google/eddystone/blob/master/eddystone-tlm/tlm-plain.md) |
| EID (`0x30`) | `0x30` | TX power | EID 8 bytes — **ต้องมี key exchange กับ trusted resolver ก่อนถอดค่าได้จริง ไม่ใช่แค่ byte parsing** | [eddystone-eid/README.md](https://github.com/google/eddystone/blob/master/eddystone-eid/README.md) |

EID เกินสโคปสปรินต์นี้ (ต้องมี resolver/registration flow ที่ยังไม่ได้ออกแบบ) → `EddystoneParser.parse()` คืน `ParseFailure(unsupportedFrameType)` เสมอเมื่อ byte 0 เป็น `0x30` ไม่ implement decode logic ในรอบนี้

```dart
sealed class EddystoneFrame {
  const EddystoneFrame();
}

final class EddystoneUidFrame extends EddystoneFrame {
  final String namespaceId; // 10 bytes → 20 hex chars
  final String instanceId;  // 6 bytes → 12 hex chars
  final int txPower;        // calibrated @ 0m, signed 8-bit dBm
  const EddystoneUidFrame({
    required this.namespaceId,
    required this.instanceId,
    required this.txPower,
  });
}

final class EddystoneUrlFrame extends EddystoneFrame {
  final int txPower;
  final String url; // ขยาย scheme prefix + encoded suffix ตาม spec แล้ว
  const EddystoneUrlFrame({required this.txPower, required this.url});
}

final class EddystoneTlmFrame extends EddystoneFrame {
  final int version;               // ปกติ 0x00
  final double batteryVoltageMv;   // มิลลิโวลต์, 0 = ไม่รองรับ
  final double? temperatureC;      // null เมื่อ raw == 0x8000 (sensor ไม่รองรับ)
  final int advertisingPduCount;
  final Duration timeSincePowerOn; // resolution 0.1s ตาม spec
  const EddystoneTlmFrame({
    required this.version,
    required this.batteryVoltageMv,
    required this.temperatureC,
    required this.advertisingPduCount,
    required this.timeSincePowerOn,
  });
}

/// Parse Eddystone service data (จาก service UUID 0000FEAA-...) — pure function
/// ไม่ผูก platform ใด ๆ เรียกได้ทั้ง Android (raw ADV) และ iOS (CoreBluetooth raw
/// service data — Eddystone ไม่ถูก OS mask เหมือน iBeacon เพราะไม่ใช่ Apple format)
final class EddystoneParser {
  const EddystoneParser._();

  static ParseResult<EddystoneFrame> parse(Uint8List serviceData);
}
```

### ADR-4: iOS platform channel contract

**Federated plugin endorsement (แผน — ยังไม่สร้างไฟล์ pubspec เอง ผู้ใช้จะ scaffold เอง):** `beacon_kit` (app-facing) ประกาศ endorse `beacon_kit_ios` ผ่าน `pubspec.yaml`:

```yaml
flutter:
  plugin:
    platforms:
      ios:
        default_package: beacon_kit_ios
```

และ `beacon_kit_ios/pubspec.yaml` เองประกาศ:

```yaml
flutter:
  plugin:
    platforms:
      ios:
        pluginClass: BeaconKitIosPlugin
```

เหตุผล: มาตรฐาน federated plugin ของ Flutter เอง — แอปที่ใช้ `beacon_kit` ไม่ต้องเพิ่ม `beacon_kit_ios` เป็น dependency แยกเอง ลดโอกาส "ลืม add platform package" ซึ่งเป็นปัญหาที่พบบ่อยของ federated plugin pattern

**Method channel:** `beacon_kit_ios/methods`

| Method | Args | Return | Error code |
|---|---|---|---|
| `startIBeaconMonitoring` | `regions: List<Map>` — แต่ละ region `{identifier: String, uuid: String, major: int?, minor: int?}` | `void` | `TOO_MANY_REGIONS` (regions.length + จำนวนที่ monitor อยู่แล้ว > 20), `INVALID_ARGUMENT` (`regions` ไม่ใช่ `List<Map>` หรือ region ขาด key `identifier`/`uuid` — บั๊กฝั่งผู้เรียก), `INVALID_REGION_UUID` (**เฉพาะ**กรณี uuid string parse เป็น `NSUUID` ไม่ได้), `LOCATION_PERMISSION_DENIED` |
| `stopIBeaconMonitoring` | `identifiers: List<String>?` (null = stop ทั้งหมด) | `void` | — |
| `startBluetoothScan` | `serviceUuids: List<String>` (บังคับระบุเสมอ ไม่มี wildcard — ดูเหตุผลด้านล่าง) | `void` | `INVALID_ARGUMENT` (`serviceUuids` ไม่ใช่ `List<String>` — บั๊กฝั่งผู้เรียก), `BLUETOOTH_UNAVAILABLE` (CBManagerState != poweredOn — สภาวะเครื่อง ไม่ใช่บั๊กโค้ด), `BLUETOOTH_PERMISSION_DENIED` |
| `stopBluetoothScan` | — | `void` | — |

**`startIBeaconMonitoring` ตอบกลับแบบ async เมื่อสิทธิ์ยังเป็น `.notDetermined` (แก้ 27 ส.ค. 2026 หลังทดสอบบน iPhone จริง):** ถ้า authorization ยังไม่ถูกกำหนด native จะ **ไม่** ตอบ `FlutterResult` ทันที แต่พักคำขอไว้แล้วขอสิทธิ์ จากนั้นรอ `locationManagerDidChangeAuthorization(_:)` เป็นคนตอบครั้งเดียว — Allow → `null` (ranging เริ่มให้เอง ผู้เรียกไม่ต้อง retry), Don't Allow → `LOCATION_PERMISSION_DENIED` แปลว่า Future ฝั่ง Dart จะค้างอยู่นานเท่าที่ผู้ใช้ยังไม่กดตอบ prompt ซึ่งถูกต้องตามความเป็นจริงของ OS

เหตุผลที่ต้องเป็นแบบนี้: อ่าน authorization status แบบ synchronous ทันทีหลังเรียก `requestAlwaysAuthorization()` จะได้ `.notDetermined` เสมอ (prompt เพิ่งขึ้น ผู้ใช้ยังไม่ทันตอบ) CoreLocation คืนผลผ่าน delegate ทางเดียวเท่านั้น — บั๊กเวอร์ชันแรกที่เจอจากการทดสอบเครื่องจริงคือแอปคืน error แล้วไม่เริ่ม ranging เลยแม้ผู้ใช้กด Allow ต้องกด start ซ้ำเอง (รายละเอียด: `docs/test-checklists/ios_broadcast_scanning.md` หัวข้อ 1)

**ลำดับการตรวจใน `startIBeaconMonitoring` เปลี่ยนเป็น:** เพดาน region → parse/validate argument → authorization (เดิม authorization มาก่อน) เพื่อให้ `INVALID_ARGUMENT`/`INVALID_REGION_UUID` ซึ่งเป็นบั๊กของผู้เรียกโผล่ทันทีไม่ว่าสถานะสิทธิ์จะเป็นอะไร และเพราะการพักคำขอไว้รอ prompt ต้อง parse ให้เสร็จก่อนอยู่แล้ว

เหตุผลที่ `startBluetoothScan` บังคับ `serviceUuids` ไม่มี wildcard scan: เพื่อให้ contract เดียวกันทำงานถูกทั้ง foreground และ background ตั้งแต่ต้น (background CoreBluetooth ที่ไม่ระบุ service UUID จะไม่รายงานอะไรเลย — ยืนยันแล้วในหัวข้อ "ข้อจำกัดของ iOS" ข้อ 3 ด้านบน) ถ้าปล่อยเป็น optional จะมีโค้ดที่ใช้ได้แค่ foreground หลุดเข้ามาได้ง่าย

**สัญญาของ `BeaconAdapter.scan()` เมื่อ native start ล้มเหลว (เพิ่ม 27 ส.ค. 2026 หลังทดสอบเครื่องจริงรอบ 2):** adapter ที่ใช้ broadcast `StreamController` ตัวเดียว re-use ข้ามการเรียก **ต้องรื้อ controller ทิ้งและปิด stream ทุกครั้งที่ native start ล้มเหลว** ห้ามแค่ `addError` แล้วปล่อยค้าง เพราะ `onListen` ของ broadcast controller ยิงเฉพาะตอนผู้ฟังขยับ 0 → 1 เท่านั้น — ถ้า controller เดิมยังมี listener ค้าง การเรียก `scan()` รอบถัดไปจะไม่ trigger การเริ่ม native อีกเลยและเงียบสนิทจนกว่าจะ restart แอป (บั๊กจริงที่เจอบนเครื่อง: `docs/test-checklists/ios_broadcast_scanning.md` หัวข้อ 1 🐞 รอบ 2)

**Event channel #1 — iBeacon ranging:** `beacon_kit_ios/ibeacon_ranging_events`
- ยิง 1 event ต่อการเรียก `locationManager(_:didRange:satisfying:)` ของ CoreLocation 1 ครั้ง (เป็น batch ตามที่ OS ให้มา — **ไม่ flatten ฝั่ง native**)
- Payload: `List<Map>` แต่ละ map = `{regionIdentifier, uuid, major, minor, rssi, proximity: String (immediate|near|far|unknown), timestamp: int (epoch ms)}`
- `beacon_kit_ios` (Dart) เป็นคน flatten `List` → `BeaconAdvertisement` ทีละตัว (`AdvertisementSource.coreLocation`) ก่อนส่งต่อ — ไม่ flatten ที่ Swift เพื่อให้ native code เรียบง่าย ตรงกับ native callback 1:1 (ลด surface ของบั๊กฝั่ง Swift ซึ่งแก้ยากกว่าฝั่ง Dart)

**Event channel #2 — raw CoreBluetooth advertisement:** `beacon_kit_ios/raw_advertisement_events`
- ยิง 1 event ต่อการเรียก `centralManager(_:didDiscover:advertisementData:rssi:)` 1 ครั้ง
- Payload: `Map` = `{peripheralId: String (CBPeripheral.identifier.uuidString), rssi: int, serviceData: Map<String, Uint8List>? (keyed ด้วย service UUID string ตัวพิมพ์เล็ก), timestamp: int}`
- **ไม่ส่ง manufacturerData ของ iBeacon มาในช่องนี้** เพราะ OS mask ทิ้งอยู่แล้ว (ส่งมาก็ว่างเปล่า/ไม่สมบูรณ์) — ถ้า native เห็น manufacturerData ใน advertisementData ให้ถือว่าเป็นของฟอร์แมตอื่นที่ไม่ใช่ iBeacon (เช่น Ksensor `0x0A53`) ซึ่งเกินสโคป broadcast-path มาตรฐานเปิดของสปรินต์นี้ — ไม่ decode ในรอบนี้

**การ enforce เพดาน 20 regions / ไม่มี wildcard ของ `CLBeaconRegion`:** ทำที่ฝั่ง Swift (`BeaconKitIosPlugin.swift`) **ก่อน**สร้าง `CLBeaconRegion` แม้แต่ตัวเดียว — เช็ค `regions.count + currentlyMonitoredRegions.count > 20` แล้ว throw `FlutterError(code: "TOO_MANY_REGIONS", ...)` กลับทันที ไม่สร้าง region บางส่วนแล้วพังครึ่งทาง (all-or-nothing ต่อการเรียกแต่ละครั้ง) เหตุผล: ถ้าสร้างสำเร็จบางส่วนแล้วพัง จะเหลือ state ที่ Dart layer กับ native layer ไม่ตรงกัน (Dart คิดว่า monitoring ล้มเหลวทั้งหมด แต่ native จริง ๆ monitor ไปแล้วบางส่วน) ซึ่ง debug ยากกว่าการปฏิเสธทั้งก้อนตั้งแต่ต้นมาก

### ไม่พบ / ต้องวิจัยเพิ่มก่อน (ห้ามสมมติ)

- ค่าที่แน่นอนของ `CLProximity`/accuracy ที่ CoreLocation คืนตอน background vs foreground (ความแม่นยำต่างกันหรือไม่) — ยังไม่ได้ทดสอบบนเครื่องจริง ต้องยืนยันกับฮาร์ดแวร์ตาม Track B
- พฤติกรรม `CBCentralManager` background scan เมื่อแอปโดน iOS kill (ไม่ใช่แค่ suspend) กับ `startBluetoothScan` ที่ไม่มี iBeacon fallback — ยังไม่ยืนยัน ต้องทดสอบเครื่องจริง
- Eddystone-EID resolver/registration flow (ต้องมีถ้าจะ implement จริงในอนาคต) — นอกสโคปสปรินต์นี้ทั้งหมด ยังไม่ได้ค้นคว้า

### Android — deferred (สปรินต์หน้า)

สปรินต์วันนี้ผู้ใช้สั่งให้โฟกัส iOS ก่อน (override ลำดับความสำคัญเดิมใน `SPRINT.md` ที่ให้ Android มาก่อน) จึง**ยังไม่สร้าง `beacon_kit_android` เลย** ไม่มีแม้แต่ Kotlin stub — ตัดสินใจแล้วว่าไม่สร้าง stub ลวก ๆ เพราะจะทำให้ `pub get`/`flutter analyze` ของ monorepo พังหรือสร้างภาพลวงว่ามีของจริงอยู่

**ผลที่ตามมาที่ต้องรู้ก่อนใช้งาน:**

- `packages/beacon_kit/pubspec.yaml` **ไม่มี** `flutter.plugin.platforms.android` เลย (มีแค่ `ios.default_package: beacon_kit_ios`) — ตั้งใจเว้นไว้ ไม่ใช่ลืม
- ถ้าเอา `packages/beacon_kit/example` ไปรันบน Android (`flutter run -d <android-device>`) แอปจะ build ผ่าน แต่พอเรียก `BeaconManager.scanAll()`/`GenericIBeaconEddystoneAdapter.scan()` จะได้ `MissingPluginException` ทันที เพราะไม่มี native Android plugin ลงทะเบียนรับ method channel `beacon_kit_ios/methods` เลย (ชื่อ channel นี้ก็ยังผูกกับ iOS โดยเฉพาะด้วย ยังไม่ได้ออกแบบเป็นชื่อกลางข้าม-platform)
- งาน sprint หน้า: ต้องเริ่มด้วย `beacon-architect` ตัดสินใจ platform-channel contract ของ Android แยก (คนละ method/event channel name จาก iOS เพราะ Android ได้ raw ADV bytes ของ iBeacon ด้วย ไม่ผ่าน CoreLocation) แล้วค่อย implement `beacon_kit_android` (Kotlin) + เพิ่ม `android.default_package` ใน `beacon_kit/pubspec.yaml` + ทำให้ `IBeaconParser` (ที่ implement ไว้แล้วใน `beacon_kit_platform_interface` รอบนี้) ถูกเรียกใช้จริงฝั่ง Android เป็นครั้งแรก
- `.github/workflows/ci.yml` มี job `build-android` เตรียมไว้แล้วแต่ comment ปิดอยู่ — เปิดพร้อมกับตอนที่ `beacon_kit_android` เริ่มมีโค้ดจริง

## ADR-5: BigC ID Scheme สำหรับ multi-vendor provisioning (เพิ่ม 28 ส.ค. 2026)

**บริบท:** เมื่อ BigC เริ่มมี beacon มากกว่าหนึ่งยี่ห้อในฟลีตเดียวกัน (K9P วันนี้ + ยี่ห้ออื่นในอนาคตตามที่ระบุใน "ส่วนที่ยังไม่ implement รอบนี้") ต้องมีสคีมกำหนด iBeacon UUID/Major/Minor ที่ใช้ร่วมกันทั้งบริษัท ก่อนจะ provision อุปกรณ์จริงล็อตแรก — ADR นี้ตัดสินใจโครง ID และบันทึกเหตุผลเชิงเทคนิคที่บังคับให้ต้องออกแบบแบบนี้ ไม่ใช่แค่เรื่องความเป็นระเบียบ

### เหตุผลเชิงเทคนิค: ทำไม "UUID เดียวทั้งบริษัท" ไม่ใช่ทางเลือก แต่เป็นข้อบังคับบน iOS

หัวข้อ "ข้อจำกัดของ iOS ที่บังคับให้สถาปัตยกรรมต่างจาก Android" ข้อ 2 ระบุไว้แล้วว่า `CLBeaconRegion` ไม่มีโหมด wildcard ข้าม UUID และมีเพดานจำนวน region — ADR นี้ยืนยันตัวเลขเพดานและกลไก wildcard ด้วยเอกสารทางการของ Apple โดยตรง (ไม่ใช่แหล่ง community เหมือนที่บันทึกไว้ก่อนหน้า):

| ข้อเท็จจริง | คำพูดต้นฉบับ | แหล่งอ้างอิง (Apple official) |
|---|---|---|
| เพดาน 20 region ต่อแอป — ยืนยันตรงกับ method ที่โค้ดปัจจุบันเรียกจริง (`locationManager.startMonitoring(for:)` ใน `IBeaconRangingManager.swift`) | "An app can register up to 20 regions at a time." | [`startMonitoring(for:)`](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:)) — Apple Developer Documentation (reference page ของ method ที่โค้ดเรียกใช้ตรงตัว) |
| เพดานเดิมมาจากการที่ region เป็นทรัพยากรระบบที่ใช้ร่วมกัน (ไม่ใช่แค่ข้อจำกัดทาง performance เฉย ๆ) | "Regions are a shared system resource, and the total number of regions available systemwide is limited. For this reason, Core Location limits to 20 the number of regions that may be simultaneously monitored by a single app." | [Region Monitoring and iBeacon — Location Awareness Programming Guide (archived)](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html) — ข้อความนี้อยู่ในหัวข้อย่อย "Defining a Geographical Region to Be Monitored" (บริบทเดิมพูดถึง `CLCircularRegion`) แต่บรรยายเป็นข้อจำกัดของ region โดยรวมของแอป ไม่ใช่เฉพาะ geographic region |
| เพดานเดียวกันถูกคงไว้ใน API รุ่นใหม่ (`CLMonitor`, iOS 17+) ในชื่อ "condition" แทน "region" | "Core Location prevents any single app from monitoring more than 20 conditions of any type simultaneously." | [Monitoring the user's proximity to geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions) — Apple Developer Documentation |
| Wildcard ทำงานเฉพาะ **ภายใน UUID เดียวกัน** เท่านั้น (major/minor เว้นว่างได้ = ครอบคลุมทุกค่าของ major/minor **แต่ UUID ต้องระบุเสมอ ไม่มี wildcard ข้าม UUID**) — นี่คือกลไกที่ทำให้ "1 UUID เดียวทั้งบริษัท" ครอบคลุมทั้งฟลีตด้วย 1 region ได้จริง | "Constraints always specify a UUID value, but the major and minor values are optional. ... Major and minor characteristics are wildcards if they have no value. A major or minor wildcard value matches any value in the beacon's corresponding characteristic." | [`CLBeaconIdentityConstraint`](https://developer.apple.com/documentation/corelocation/clbeaconidentityconstraint) — Apple Developer Documentation (คือ type เดียวกับที่ `IBeaconRangingManager.swift` ใช้สร้าง `CLBeaconRegion` จริง) |

**สรุปห่วงโซ่เหตุผล (ผูกทุกจุดเข้าด้วยกัน):** iOS จำกัดจำนวน region ที่ monitor พร้อมกันได้ที่ 20 ต่อแอป (ยืนยันจาก 2 หน้าเอกสารอิสระต่อกัน — หน้า method ที่โค้ดเรียกจริง และคู่มือ region monitoring) และ `CLBeaconIdentityConstraint`/`CLBeaconRegion` ไม่มี wildcard ข้าม UUID (ต้องระบุ UUID เสมอ) ดังนั้นถ้าแต่ละยี่ห้อมี UUID default ของตัวเอง การจะ monitor ให้ครบทุกยี่ห้อต้องใช้ 1 region ต่อ 1 UUID — พอมี beacon เกิน 20 ยี่ห้อ (หรือแม้แต่ไม่กี่ยี่ห้อแต่แบ่งเป็นหลาย region ตามโซน/สาขา) ก็ชนเพดานทันที ในทางกลับกัน ถ้าทุกอุปกรณ์ broadcast ด้วย **UUID เดียวกัน** (ของ BigC เอง) แล้วสร้าง `CLBeaconIdentityConstraint(uuid:)` แบบไม่ระบุ major/minor เพียง 1 ตัว — 1 region นั้นจะ wildcard ครอบคลุม major/minor ทุกค่าโดยอัตโนมัติ = ครอบคลุมทั้งฟลีตทุกยี่ห้อด้วย region เดียว เหลือพื้นที่อีก 19 region ไว้ใช้งานอื่น (เช่น geofence สาขา) นี่คือเหตุผลที่ "UUID เดียวทั้งบริษัท" เป็น**ข้อบังคับเชิงสถาปัตยกรรมบน iOS** ไม่ใช่แค่ความสะดวกในการดูแลระบบ

**หมายเหตุที่ต้อง flag (ไม่ใช่ขัดแย้ง แต่ควรรู้ไว้):** `startMonitoring(for:)` ที่โค้ดปัจจุบันเรียกอยู่มี `deprecationSummary` ในเอกสาร Apple ระบุให้ใช้ `CLMonitor`/`addCondition(for:)` แทน (API ใหม่ตั้งแต่ iOS 17) — ตัวเลข 20 ไม่ขัดแย้งกัน (ยืนยันตรงกันทั้ง API เก่าและใหม่) จึงไม่ต้องแก้โค้ดตอนนี้ แต่บันทึกไว้เป็นข้อสังเกตสำหรับสปรินต์ Android/ปรับปรุง iOS รอบหน้า — **ไม่ใช่สโคปงานนี้ ห้ามแก้ `IBeaconRangingManager.swift` จาก ADR นี้**

### โครง ID 3 ชั้น

**1. Proximity UUID — เดียวทั้งบริษัท (ข้อบังคับ)**

- ต้อง **generate ขึ้นใหม่เอง** ด้วยเครื่องมือมาตรฐาน (เช่น `uuidgen` บน macOS/Linux, `New-Guid` บน PowerShell, หรือ UUID v4 library) — **ห้ามใช้ค่า default จากโรงงานของยี่ห้อใดยี่ห้อหนึ่งเด็ดขาด** เพราะเป็นค่าที่ทุกลูกค้าที่ซื้อรุ่นเดียวกันมีเหมือนกันหมด (ดูคำเตือนเรื่อง K9P demo UUID ด้านล่าง — เป็นตัวอย่างของปัญหานี้โดยตรง)
- ค่าจริงต้องเก็บที่ **backend/config service** ที่ควบคุมการเข้าถึงได้ (เช่น remote config หรือ secret store ของบริษัท) **ห้าม hardcode ในซอร์สโค้ด** ของ `beacon_kit`, แอปที่เรียกใช้, หรือ config ที่ provision ลงตัวอุปกรณ์แบบไม่ผ่านระบบควบคุม — เหตุผล: ค่านี้รั่วเท่ากับทั้งฟลีตถูกปลอมได้ (ดูหัวข้อ "ความเสี่ยง iBeacon spoofing" ด้านล่าง) การเก็บใน config ที่หมุนเวียน/ควบคุมสิทธิ์ได้ ลดพื้นผิวการรั่วเทียบกับฝังในซอร์สที่กระจายไปทุกที่ที่ build
- **เหตุผลที่แก้ไข (28 ส.ค. 2026) — เก็บค่าไว้ที่เดียวคือ `docs/sources/bigc_provisioning.md` ห้ามกระจาย/hardcode ซ้ำที่อื่น:** เดิมกฎข้อนี้เขียนว่า "ห้ามเขียนค่า UUID ตัวอย่างลงในเอกสารใด ๆ ของโปรเจกต์เด็ดขาด" โดยอ้างเหตุผลเรื่องความลับ (confidentiality) — เหตุผลนั้น**ไม่ตรงกับข้อเท็จจริงที่บันทึกไว้เองในหัวข้อ "ความเสี่ยง iBeacon spoofing" ด้านล่าง**: payload ของ iBeacon เป็น plaintext broadcast ที่ทุกอุปกรณ์ในระยะรับสัญญาณอ่านค่า UUID ได้อยู่แล้วตลอดเวลาโดยไม่ต้องแฮ็คอะไรเลย ดังนั้น proximity UUID จึง **ไม่ใช่ความลับ (not confidential)** ตั้งแต่ต้น — การห้ามเขียนค่าลงเอกสารจึงป้องกัน "การรั่ว" ไม่ได้จริง (รั่วอยู่แล้วทุกครั้งที่ beacon broadcast) ความเสี่ยงตัวจริงที่ต้องระวังคือ**เรื่อง operational**: ถ้าค่าเดียวกันไปฝังกระจัดกระจายอยู่หลายที่ (โค้ด, เอกสารเก่าหลายฉบับ, README ต่าง ๆ ที่ต่างคน generate/จำเอง) การจะ rotate ค่าในอนาคต (เช่น ถ้าต้องเปลี่ยน UUID จริง ๆ ด้วยเหตุผลอื่น) จะต้องตามหา/แก้ให้ครบทุกที่ ซึ่งพลาดง่ายและตรวจสอบยาก — ทางแก้คือกำหนดที่เก็บค่าเดียว (**single source of truth**) แทนการห้ามเขียนเสียเลย: ค่าจริงของ BigC เก็บไว้ที่ **`docs/sources/bigc_provisioning.md` เท่านั้น** (แพทเทิร์นเดียวกับที่ `docs/sources/kkm_k9p.md` ใช้เก็บ citation ของยี่ห้อ K9P อยู่แล้ว) **ห้ามเขียนค่าซ้ำในเอกสารอื่นของโปรเจกต์หรือ hardcode ซ้ำในซอร์สโค้ดที่ใดนอกเหนือจากไฟล์นั้น** — ถ้าต้องอ้างอิงตำแหน่งของ field ในเอกสารอื่น ให้ใช้ placeholder แบบไม่ใช่ hex เช่น `<BIGC_PROXIMITY_UUID>` แล้วชี้ไปที่ `docs/sources/bigc_provisioning.md` แทนการ copy ค่าจริงมาซ้ำ

**2. Major — เลขรันล้วน (ตัดสินใจแล้ว)**

`major` เป็น `uint16` (ขอบเขต 0-65535) — **ทีมตัดสินใจแล้ว (28 ส.ค. 2026): เลือกตัวเลือก B — Major เป็นเลขรันเปล่า ไม่มีความหมายทางธุรกิจใด ๆ ฝังอยู่ในตัวเลข** ความหมายทางธุรกิจทั้งหมด (ยี่ห้อ / ล็อต / กลุ่ม / **ตำแหน่ง** — หมายถึงตำแหน่งติดตั้ง/สาขา/โซน) เก็บไว้ที่ **backend/database เท่านั้น** ไม่ encode ลงในบิตของ major เลย ตารางด้านล่างเก็บไว้เป็น**บันทึกเหตุผลของการตัดสินใจ** (trade-off ระหว่าง A กับ B ที่เคยพิจารณา) ไม่ใช่ทางเลือกที่ยังเปิดให้เลือกอีกต่อไป:

| | **ตัวเลือก A — Major มีความหมาย (encode กลุ่ม/ล็อต/ยี่ห้อ/ตำแหน่งลงในบิต)** | **ตัวเลือก B — Major เป็นเลขรันเปล่า + เก็บความหมายในฐานข้อมูล (ตัวเลือกที่เลือกแล้ว)** |
|---|---|---|
| ข้อดี | อ่าน major เพียงค่าเดียวก็รู้ทันทีว่าเป็นกลุ่ม/ยี่ห้อ/ล็อต/ตำแหน่งไหน โดยไม่ต้อง query อะไรเลย — มีประโยชน์มากเวลาช่างหน้างาน/เครื่องมือ diagnostic แบบ offline (ไม่มีเน็ต/ไม่ต่อ backend) ต้องเดาว่าเจออุปกรณ์ยี่ห้อ/กลุ่มไหน | ยืดหยุ่นเมื่อโครงองค์กรเปลี่ยน (ยี่ห้อใหม่, จัดกลุ่มสาขาใหม่, ล็อตแตกเป็นหลายรุ่นย่อย, ย้ายตำแหน่งติดตั้ง) — แก้แค่ record ใน backend ไม่ต้อง provision hardware ใหม่ (เขียน major/minor ผ่าน GATT ใหม่ต้องมีคนไปเชื่อมต่ออุปกรณ์ทีละตัว ซึ่งแพงมากเมื่อฟลีตใหญ่); ค่า major ที่ "ไม่มีความหมายเดา ๆ ได้" ยังลดความเสี่ยงเล็กน้อยที่คนนอกจะ reverse-engineer โครงสร้างองค์กรจาก broadcast ที่ดักฟังได้ (ดูหัวข้อ spoofing ด้านล่าง — broadcast เป็น plaintext อยู่แล้ว) |
| ข้อเสีย | encode หลายมิติ (ยี่ห้อ + กลุ่ม + ล็อต + ตำแหน่ง) ลงใน 16 บิตเดียวต้องออกแบบบิต-แพ็กกิ้งตายตัวตั้งแต่ต้น พอพื้นที่ที่จัดสรรให้มิติใดมิติหนึ่งเต็ม (เช่นจำนวนยี่ห้อ/ตำแหน่งเกินที่กันบิตไว้) ต้อง re-provision hardware ทั้งกลุ่มเพื่อขยับ scheme — แพงและช้า เพราะต้องเชื่อมต่ออุปกรณ์ทีละตัว | ต้อง query backend เพื่อรู้ความหมายของ major เสมอ — เครื่องมือ diagnostic หน้างานที่ไม่มีเน็ต/ไม่ sync ข้อมูลอ่านค่าตรง ๆ ไม่รู้เรื่องอะไรเลยนอกจากตัวเลข |
| **ผลตัดสินใจ** | ไม่เลือก | **เลือกแล้ว (28 ส.ค. 2026) — ใช้จริงตั้งแต่นี้ไป** |

**เหตุผลที่ทีมเลือกตัวเลือก B (ตัดสินใจแล้ว — ไม่ใช่ข้อเสนอแนะที่รอ approve อีกต่อไป):** BigC เป็นองค์กรค้าปลีกขนาดใหญ่ที่โครงสร้าง (สาขา/ตำแหน่งติดตั้ง/กลุ่มสินค้า/ยี่ห้อ vendor ที่ใช้) มีแนวโน้มเปลี่ยนบ่อยกว่าที่ hardware fleet จะเปลี่ยนได้ทัน — การ re-provision beacon ที่ติดตั้งอยู่หน้างานแล้ว (ต้องส่งช่างไปต่อ GATT ทีละตัวเพื่อเขียน major ใหม่ตาม auth flow ของแต่ละยี่ห้อ) แพงกว่าการแก้ record ในฐานข้อมูล backend มาก โดยเฉพาะเมื่อระบบนี้ตั้งใจรองรับหลายยี่ห้อ (vendor mix จะเปลี่ยนได้เรื่อย ๆ ตามการจัดซื้อ) การ encode ความหมายลงในบิตของ major จะกลายเป็นภาระทันทีที่ scheme ต้องขยาย ส่วนข้อเสียเรื่อง "ต้อง query backend ถึงจะรู้ความหมาย" แก้ได้ด้วยเครื่องมือ diagnostic ที่ cache mapping major→ความหมายไว้ล่วงหน้า (sync ตอน online) ซึ่งเป็นปัญหาที่แก้ในซอฟต์แวร์ได้ง่ายกว่าการแก้ที่ hardware ที่ติดตั้งไปแล้ว — `flutter-dev`/`beacon-qa` implement ตาม scheme นี้ได้ทันทีโดยไม่ต้องรอการยืนยันเพิ่ม

**3. Minor — รหัสอุปกรณ์เฉพาะตัว (ข้อบังคับ) — เป็นเลขรันเปล่าเช่นเดียวกับ Major**

`minor` เป็น `uint16` (ขอบเขต 0-65535) เก็บรหัสอุปกรณ์เฉพาะตัว — **เช่นเดียวกับ major ที่เพิ่งตัดสินใจข้างบน `minor` เป็นเลขรันล้วน ไม่มีความหมายทางธุรกิจใด ๆ ฝังอยู่ในตัวเลขเช่นกัน** (ไม่ encode ยี่ห้อ/ล็อต/กลุ่ม/ตำแหน่งหรือมิติอื่นใดลงในบิตของ minor) ความหมายทางธุรกิจของอุปกรณ์แต่ละตัว (เช่น serial number จริง, วันที่ provision, ตำแหน่งติดตั้งเฉพาะเจาะจง) เก็บที่ backend/database ทั้งหมดเหมือนกับ major — `minor` ทำหน้าที่แค่เป็น "กุญแจ" ที่ unique เฉพาะ**ภายใน major เดียวกัน** ไม่ใช่ unique ข้าม major ทั้งฟลีต (ตามกลไก `CLBeaconIdentityConstraint` ที่ยืนยันด้านบน คือ beacon จะ match constraint ก็ต่อเมื่อ uuid+major+minor ตรงกันทั้งสามค่า — สอง major ที่ต่างกันใช้ minor ซ้ำกันได้โดยไม่ชนกัน)

**ผลต่อจำนวนอุปกรณ์ที่รองรับได้:** ต่อค่า major หนึ่งค่า รองรับได้สูงสุด 65,536 อุปกรณ์ (ค่า minor 0-65535) ถ้าใช้หลายค่า major (ทั้งสองตัวเลือกข้างบนทำได้) จำนวนอุปกรณ์รวมทั้งฟลีต = (จำนวน major ที่ใช้งานจริง) × สูงสุด 65,536 ต่อ major — เพดานทางทฤษฎีทั้งหมดของ (major, minor) คือ 65,536 × 65,536 = 4,294,967,296 คู่ ภายใต้ UUID เดียว ซึ่งเกินความจำเป็นของ BigC มากในทางปฏิบัติ (ตัวเลขนี้มาจาก field width 16 บิตของ major/minor ในฟอร์แมต iBeacon ที่ยืนยันแล้วในหัวข้อ "ข้อค้นพบสำคัญ" ด้านบนของเอกสารนี้ ไม่ใช่ข้อมูลใหม่ที่ต้องยืนยันเพิ่ม)

### คำเตือนสำคัญ — ห้าม K9P demo UUID กลายเป็น production UUID ของ BigC

`packages/beacon_kit/example/lib/main.dart:9` ตั้งค่า `_k9pDefaultUuid = '7777772E-6B6B-6D63-6E2E-636F6D000001'` เป็นค่าเริ่มต้นของ example app ตอนนี้ — **ค่านี้เป็นค่าโรงงานของ K9P สำหรับ demo เท่านั้น** เป็นค่าที่ผู้ซื้อ K9P รุ่นเดียวกัน**ทุกคน**มีเหมือนกันหมด (ไม่ใช่ค่าที่ generate เฉพาะให้ BigC) **ห้ามนำค่านี้ไปใช้เป็น proximity UUID ของ BigC ใน production เด็ดขาด** ถ้านำไปใช้จริง จะเท่ากับ BigC "ใช้ UUID ร่วมกับทุกคนในโลกที่ซื้อ K9P รุ่นนี้" — beacon ของบริษัทอื่นที่ใช้ค่าเดียวกันจะถูกแอป BigC มองว่าเป็น beacon ของ BigC ด้วย (false positive) และในทางกลับกันแอปของคนอื่นก็จะมองเห็น beacon ของ BigC เป็นของเขาเช่นกัน

**ข้อบังคับ:** ก่อน provision อุปกรณ์จริงล็อตแรก ต้อง generate UUID ใหม่ตามหัวข้อ "โครง ID 3 ชั้น" ด้านบน แล้วนำไปตั้งค่าใน config ของ production build แยกจาก `example/` โดยเด็ดขาด — `example/` คงค่า demo เดิมไว้ได้ต่อไปเพราะมีจุดประสงค์แค่สาธิตการเชื่อมต่อ ไม่ใช่แอปจริงที่ deploy

### ความเสี่ยง iBeacon spoofing — known accepted risk (ไม่ใช่บั๊ก ไม่ใช่ข้อบกพร่องของ implementation)

**ข้อเท็จจริง:** payload ของ iBeacon (Apple company ID `0x004C` + prefix `0x02 0x15` + UUID + major + minor + txPower — ยืนยันแล้วในหัวข้อ "ข้อค้นพบสำคัญ" ด้านบนของเอกสารนี้) **ไม่มี field ใดสำหรับ signature, nonce, หรือกลไก authentication ใด ๆ เลย** เป็น broadcast แบบ plaintext ที่ทุกอุปกรณ์ในระยะรับสัญญาณอ่านได้ ทุกอุปกรณ์ BLE ที่ broadcast ได้ (รวมมือถือทั่วไป) สามารถปลอม (spoof) ให้ broadcast payload ที่มี UUID/major/minor เดียวกับ beacon จริงได้ทันที — นี่คือคุณสมบัติของมาตรฐาน iBeacon เอง ไม่ใช่ช่องโหว่ที่เกิดจากการ implement ของ `beacon_kit` หรือของยี่ห้อใด **ต้องบันทึกเป็นความเสี่ยงที่รู้แล้วและยอมรับ (accepted risk) ไม่ใช่รายการที่ต้อง "แก้"**

**ผลกระทบจริงที่เป็นไปได้:**
- ปลอม beacon ให้แอปของ BigC เข้าใจว่าอุปกรณ์อยู่ในโซน/สาขาที่ไม่ได้อยู่จริง (location spoofing)
- Clone อุปกรณ์จริงได้ง่าย (แค่ดักอ่าน UUID/major/minor แล้ว broadcast ซ้ำจากอุปกรณ์อื่น ไม่ต้องแฮ็คอะไรเลย)
- ถ้า UUID ของ BigC รั่วออกไป (เช่น หลุดจาก config, หรือดักฟัง broadcast แล้ว reverse ได้ตรง ๆ อยู่แล้วเพราะเป็น plaintext) ใครก็ตั้ง beacon ปลอมอ้างเป็น BigC ได้

**การใช้ UUID เดียวทั้งบริษัทเปลี่ยนลักษณะความเสี่ยงนี้อย่างไร (trade-off ที่ต้องยอมรับคู่กับข้อดีเรื่องเพดาน region):** เดิมถ้าแต่ละยี่ห้อ/แต่ละกลุ่มมี UUID แยกกัน การรั่วของ UUID หนึ่งตัวกระทบแค่ยี่ห้อ/กลุ่มนั้น — แต่พอรวมเป็น UUID เดียวทั้งบริษัทตาม ADR นี้ (ซึ่งจำเป็นเพราะเพดาน 20 region ตามที่พิสูจน์ด้านบน) **การรั่วของ UUID เดียวนี้กระทบทั้งฟลีตพร้อมกัน** — เป็น single point of failure ในมิติของ spoofing แลกกับการที่สถาปัตยกรรมทำงานได้จริงบน iOS เลย เป็น trade-off ที่ต้องรู้ตัวและยอมรับตั้งแต่ต้น ไม่ใช่ผลข้างเคียงที่ค้นพบทีหลัง

**ถ้าอนาคต requirement ต้องการความปลอดภัยเพิ่ม (ทางเลือกให้พิจารณา ไม่ใช่สั่งให้ทำตอนนี้):**
- **Eddystone-EID** — frame type ที่ broadcast "encrypted ephemeral identifier that changes periodically" และดูเหมือนสุ่มสำหรับผู้สังเกตการณ์ภายนอก ("appears to be changing randomly" ตามคำอธิบายของ spec) ต้องมี key exchange กับ trusted resolver ก่อนถอดค่าได้จริง — [eddystone-eid/README.md](https://github.com/google/eddystone/blob/master/eddystone-eid/README.md) (อ้างอิงเดียวกับที่ใช้ใน ADR-3) **ข้อควรระวัง:** เอกสารนี้ไม่ได้ระบุตรง ๆ ว่า "ป้องกัน spoofing/replay" เป็นคำมั่นสัญญาความปลอดภัยที่รับประกัน เป็นเพียงกลไกที่ทำให้ identifier หมุนเวียนและต้อง resolve ผ่านเซิร์ฟเวอร์ที่เชื่อถือได้ ซึ่งลดคุณค่าของการดักฟังแล้ว replay ระยะยาวลง — ถ้าจะใช้จริงต้องออกแบบ resolver/registration flow เพิ่ม (นอกสโคปที่ยังไม่ได้ค้นคว้า ตามที่บันทึกไว้แล้วใน ADR-3)
- **ยืนยันซ้ำฝั่ง server** — ไม่เชื่อ presence ของ beacon จากฝั่ง client อย่างเดียวสำหรับการตัดสินใจที่มีมูลค่า (เช่น ผูกกับธุรกรรม/สิทธิประโยชน์) ให้ backend ตรวจสอบ context อื่นประกอบ (เวลา, ตำแหน่ง GPS คร่าว ๆ, pattern การเคลื่อนไหว) แทนการเชื่อ UUID/major/minor เดี่ยว ๆ
- **ไม่ใช้ตำแหน่ง beacon เป็นหลักฐานเดียวสำหรับการตัดสินใจที่มีมูลค่าสูง** — ใช้เป็นสัญญาณเสริม (signal) ไม่ใช่ source of truth เดี่ยว โดยเฉพาะ use case ที่เกี่ยวกับเงิน/สิทธิประโยชน์/ความปลอดภัย

### ไม่พบ / ต้องวิจัยเพิ่มก่อน (ห้ามสมมติ)

- **ยังไม่ยืนยันว่า K9P เขียน UUID/Major/Minor ผ่าน GATT ได้จริงหรือไม่** — `docs/sources/kkm_k9p.md` ปัจจุบันมีแค่ GATT UUID ของ service/characteristic และ auth flow (MD5 2 รอบ) เท่านั้น **ไม่มีการยืนยันเรื่อง write UUID/Major/Minor ตรง ๆ** ห้ามสรุปเองว่า K9P ทำได้เพราะมี auth/write characteristic อยู่แล้ว — ต้องรัน skill `beacon-sdk-verify` เพิ่มเพื่อยืนยันก่อนที่จะพึ่งพา K9P เป็นอุปกรณ์อ้างอิงของ BigC ID Scheme นี้จริงจัง (ดู checklist ใหม่ใน `.claude/skills/beacon-sdk-verify/SKILL.md`)
- **หน้าเอกสาร Apple เฉพาะของ beacon region เอง (`CLBeaconRegion`, `CLBeaconIdentityCondition`) ไม่ได้ระบุตัวเลข 20 ซ้ำตรง ๆ ในหน้าของมันเอง** — ตัวเลข 20 ยืนยันได้จากหน้า `startMonitoring(for:)` (method ที่ใช้จริง, รับ `CLRegion` ซึ่งเป็น superclass ของทั้ง `CLCircularRegion`/`CLBeaconRegion`), คู่มือ archived ที่พูดถึงบริบท geographic region เป็นหลัก, และหน้า `CLMonitor` รุ่นใหม่ที่พูดถึง "conditions ทุกชนิด" แบบรวม — ไม่มีหน้าไหนพูดคำว่า "beacon region" คู่กับเลข "20" ในประโยคเดียวกันตรง ๆ จึงสรุปได้ว่าเพดานนี้"น่าจะครอบคลุมทุกชนิด region รวม beacon region ด้วย" จากบริบท "shared system resource"/"any type" ไม่ใช่จากถ้อยแถลงที่เจาะจงคำว่า beacon region ตรง ๆ — สอดคล้องกับตัวเลขที่โค้ดปัจจุบันใช้ (`maxMonitoredRegions = 20`) จึงไม่มีข้อขัดแย้งให้ flag เพิ่มเติม แต่บันทึกไว้ตรงนี้ว่าคือระดับความมั่นใจของแหล่งอ้างอิง
- **ยังไม่ได้ค้นคว้า resolver/registration flow ของ Eddystone-EID** — เหมือนที่บันทึกไว้แล้วใน ADR-3 นอกสโคปทั้งหมด ถ้าจะพิจารณาใช้จริงต้องรันการค้นคว้าเพิ่มก่อน ไม่ใช่แค่ส่วนของ ADR-5 นี้

## ADR-6: จาก ranging-only เป็น region monitoring (enter/exit) — เพิ่ม 28 ส.ค. 2026

**นี่เป็นเอกสาร ADR เท่านั้น ยังไม่ implement** — ห้ามแก้ `IBeaconRangingManager.swift` จาก ADR นี้ การ implement จริงเป็นงาน B5/B6 ที่ `flutter-dev` ทำต่อจากนี้ โดยอ้างอิงทุกจุดที่ตัดสินใจไว้ในหัวข้อนี้ตรงตัว ไม่ต้องตีความเพิ่ม

**บริบท:** สปรินต์นี้ต้องเปลี่ยนจาก "ranging อย่างเดียว" (รู้ว่าเห็น beacon ตอนอยู่ใกล้ ๆ ระหว่างแอปทำงาน) ไปเป็น **background region monitoring แบบเต็มรูป** (รู้ว่า "เข้า"/"ออก" โซนของ beacon แม้แอปโดน suspend หรือถูก terminate) ซึ่งเป็นจุดประสงค์หลักของสปรินต์ตาม `SPRINT.md`

**สถานะโค้ดจริงตอนนี้ (ยืนยันจากการอ่าน `packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift` วันนี้):** `applyParsedRegions(_:)` เรียกทั้ง `locationManager.startMonitoring(for:)` และ `locationManager.startRangingBeacons(satisfying:)` คู่กันอยู่แล้ว (บรรทัด `startMonitoring`/`startRangingBeacons` ในเมธอดนี้) แต่ไฟล์ implement เฉพาะ `CLLocationManagerDelegate` method `locationManager(_:didRange:satisfying:)` เท่านั้น **ไม่มี** `locationManager(_:didEnterRegion:)`, `locationManager(_:didExitRegion:)`, หรือ `locationManager(_:didDetermineState:for:)` เลยแม้แต่ตัวเดียว — สรุปคือ**สั่ง monitor ไปแล้วแต่ไม่มีใครฟังผล enter/exit** ทุกวันนี้แอปได้แค่ ranging (เห็น beacon เฉพาะตอน CoreLocation รายงาน batch ผ่าน `didRange`) ไม่มี event ใดถูกยิงเมื่อเข้า/ออกโซนจริง ๆ

### 1. Delegate method ที่ต้องเพิ่ม

ต้องเพิ่มทั้ง 3 เมธอดนี้ใน `IBeaconRangingManager` (extends `CLLocationManagerDelegate` ที่มีอยู่แล้ว):

- **`locationManager(_:didEnterRegion:)`** — ยิงเมื่อเข้าโซน ยืนยัน signature/semantic จาก [Apple Developer Documentation](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:didenterregion:)): "Because regions are a shared application resource, every active location manager object delivers this message to its associated delegate... you should never perform pointer-level comparisons to determine equality [of the region object]. Instead, use the region's identifier string" — สอดคล้องกับโค้ดปัจจุบันที่ dictionary `constraintsByIdentifier` ใช้ identifier string เป็น key อยู่แล้ว ไม่ต้องเปลี่ยนแพทเทิร์นนี้
- **`locationManager(_:didExitRegion:)`** — ยิงเมื่อออกโซน semantic เดียวกัน ยืนยันจาก [Apple Developer Documentation](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:didexitregion:))
- **`locationManager(_:didDetermineState:for:)`** + เรียก **`locationManager.requestState(for:)`** ทันทีหลัง `startMonitoring(for:)` สำเร็จในแต่ละ region — **ตัดสินใจ: ต้องมี** เหตุผล (ยืนยันจากเอกสาร ไม่ใช่การเดา): [`startMonitoring(for:)`](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:)) ระบุว่า region events (didEnterRegion/didExitRegion) ยิงเฉพาะตอนมี "boundary crossing" ในอนาคตเท่านั้น — ถ้าอุปกรณ์**อยู่ในโซนอยู่แล้ว**ตั้งแต่ก่อนเรียก `startMonitoring`, จะไม่มี event enter ยิงออกมาเลยจนกว่าจะมีการออก-แล้วเข้าใหม่จริง ๆ ทำให้แอปไม่รู้ initial state ทันทีตอนเริ่ม monitor ส่วน [`locationManager(_:didDetermineState:for:)`](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:diddeterminestate:for:)) ระบุตรง ๆ ว่า "The location manager calls this method whenever there is a boundary transition for a region. It calls this method in addition to calling the didEnterRegion and didExitRegion methods. The location manager also calls this method in response to a call to its [`requestState(for:)`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requeststate(for:)) method, which runs asynchronously" — นี่คือกลไกทางการเดียวที่ Apple ให้มาเพื่อ query initial state โดยไม่ต้องรอ boundary crossing จริง จึงต้อง implement คู่กันเพื่อให้แอปรู้สถานะเริ่มต้นถูกต้องตั้งแต่เปิด monitoring ครั้งแรก (ไม่ใช่แค่รอ future transition)

### 2. Event/method channel contract ที่เปลี่ยน

**Method channel (`beacon_kit_ios/methods`) — ไม่เปลี่ยนชื่อ/signature ของ `startIBeaconMonitoring`/`stopIBeaconMonitoring` ที่มีอยู่แล้วใน ADR-4** เพราะ argument shape (`regions: List<Map>` พร้อม `identifier`/`uuid`/`major`/`minor`) และ error code (`TOO_MANY_REGIONS`, `INVALID_ARGUMENT`, `INVALID_REGION_UUID`, `LOCATION_PERMISSION_DENIED`) ยังใช้ตรงกันได้พอดี — สิ่งที่เปลี่ยนคือ native จะเริ่มฟัง delegate เพิ่มและยิง event ใหม่ ไม่ใช่ contract ของ method call

**Event channel ใหม่ — ตัดสินใจ: แยกช่องใหม่ ไม่ reuse ranging channel เดิม**

ชื่อ: `beacon_kit_ios/region_state_events`

**เหตุผลที่แยก (ไม่ reuse `beacon_kit_ios/ibeacon_ranging_events`):** semantic ของสอง event ต่างกันโดยพื้นฐาน — ranging event (`didRange`) ยิง**ถี่มาก** (ทุกครั้งที่ CoreLocation ได้ batch ใหม่ตอนอยู่ใกล้ beacon อาจเป็นวินาทีละครั้ง) ขณะที่ region-state event (enter/exit/determine-state) ยิง**เฉพาะตอน state เปลี่ยนจริง ๆ** เท่านั้น (นาน ๆ ครั้ง) ถ้ารวมช่องเดียวกัน ผู้ฟังที่สนใจแค่ enter/exit จะต้อง filter ทิ้ง event ranging จำนวนมากตลอดเวลาที่แอปทำงาน — สิ้นเปลืองทั้งฝั่ง Dart (ต้อง deserialize ทุก event) และเพิ่มโอกาสพลาด/บั๊กจากการ filter ผิด แยกเป็นคนละ stream ทำให้ผู้ฟังแต่ละแบบ subscribe เฉพาะสิ่งที่ต้องการได้ตรง ๆ สอดคล้องกับแพทเทิร์นที่ ADR-4 วางไว้แล้วสำหรับ ranging vs raw-advertisement (คนละ channel เพราะ semantic ต่างกัน) — ตอนนี้ `beacon_kit_ios` จะมีรวม 3 channel: 1 method channel + 3 event channel (ranging, raw advertisement, region state)

**Payload shape ของ `beacon_kit_ios/region_state_events` (ตามสไตล์ตารางที่ ADR-4 ใช้):**

| Field | Type | คำอธิบาย |
|---|---|---|
| `regionIdentifier` | `String` | identifier ที่แอปกำหนดตอนเรียก `startIBeaconMonitoring` — หา region กลับด้วย `constraintsByIdentifier` เหมือนที่ `didRange` ทำอยู่แล้ว |
| `uuid` | `String` | lowercase, hyphenated — จาก `CLBeaconIdentityConstraint.uuid` ของ region นั้น |
| `major` | `int?` | จาก constraint — `null` ถ้า region นั้นเป็น wildcard ไม่ระบุ major (ตาม ADR-5 กลไก `CLBeaconIdentityConstraint`) |
| `minor` | `int?` | เช่นเดียวกับ major |
| `state` | `String` | หนึ่งใน `"enter" \| "exit" \| "unknown"` — `enter`/`exit` มาจาก `didEnterRegion`/`didExitRegion`, ส่วน `unknown` มาจาก `didDetermineState` เมื่อผลเป็น `CLRegionState.unknown` (ยืนยันว่า `CLRegionState` มี 3 ค่านี้จริงจากหน้า [`didDetermineState`](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:diddeterminestate:for:)) ที่ระบุถึง type `CLRegionState`) — `didDetermineState` ที่ให้ผลเป็น `.inside`/`.outside` ให้ map เป็น `"enter"`/`"exit"` เหมือนกัน (**ต้อง dedupe ฝั่ง native หรือ Dart ไม่ให้ยิงซ้ำสองรอบเมื่อ boundary transition เกิดพร้อมกับ requestState** — จุดนี้ยังไม่ตัดสินใจรายละเอียด dedupe logic ในสปรินต์นี้ ให้ `flutter-dev` ออกแบบตอน implement B6 โดยอ้างอิง constraint นี้) |
| `timestamp` | `int` | epoch ms — เวลาที่ native สร้าง event เดียวกับแพทเทิร์นที่ ranging event ใช้ |

**ทำไมไม่ flatten/รวม field เพิ่มจาก raw `CLRegion`/`CLBeaconRegion`:** ให้ shape เท่าที่จำเป็นต่อการระบุตัวตน region (`regionIdentifier`/`uuid`/`major`/`minor`) และผล state เท่านั้น สอดคล้องกับแพทเทิร์น ranging event เดิมที่ flatten เฉพาะฟิลด์ที่ domain layer (`BeaconAdvertisement`/ADR-2) ต้องใช้จริง ไม่ส่ง raw native object ข้าม platform channel

### 3. สิทธิ์ `requestAlwaysAuthorization()` พอสำหรับ background region monitoring จริงหรือไม่ — **พอ ยืนยันจากเอกสาร Apple**

โค้ดปัจจุบันเรียก `locationManager.requestAlwaysAuthorization()` ตอนสถานะเป็น `.notDetermined` อยู่แล้ว (ดู `startMonitoring(regions:result:)`) — ตรวจสอบแล้วว่า **Always authorization จำเป็นจริงสำหรับ background region monitoring ที่ต้องปลุกแอปที่ถูก terminate** ตามเอกสารทางการ [Requesting Authorization to Use Location Services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) ตารางเปรียบเทียบ capability ระบุตรง ๆ ว่า:

> "Launches a terminated app automatically — When in Use: No. The user must launch the app. / Always: Yes for significant location change, visits, and **region monitoring services**; no for others."

นี่คือการยืนยันตรงจุดที่สุด: **region monitoring service ถูกระบุชื่อตรง ๆ ว่าเป็นหนึ่งในบริการที่ต้องมี Always authorization ถึงจะปลุกแอปที่โดน terminate ได้** — ถ้ามีแค่ When In Use, region events ยัง**ทำงานได้ระหว่างที่แอปยังไม่ถูก terminate จริง** (foreground/suspended) แต่จะไม่ปลุกแอปกลับมาถ้า iOS terminate แอปไปแล้ว ซึ่งขัดกับจุดประสงค์ของสปรินต์นี้ (background region monitoring ที่ทำงานได้แม้แอปโดน kill) จึงสรุปว่า **`requestAlwaysAuthorization()` ที่โค้ดเรียกอยู่ถูกต้องแล้ว ไม่ต้องเปลี่ยน**

**หมายเหตุประกอบจากหน้าเอกสาร `requestAlwaysAuthorization()` (คนละหน้ากับที่อ้างด้านบน ไม่กระทบข้อสรุปแต่ควรรู้):** "To obtain Always authorization, your app must first request When In Use permission followed by requesting Always authorization" ([`requestAlwaysAuthorization()`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization())) — โค้ดปัจจุบันเรียก `requestAlwaysAuthorization()` ตรง ๆ ครั้งเดียวตอน `.notDetermined` ซึ่งตาม flow ที่เอกสารอธิบาย (2-prompt flow: prompt แรกถามด้วยข้อความจาก `NSLocationWhenInUseUsageDescription`, prompt สองถามด้วยข้อความจาก `NSLocationAlwaysAndWhenInUseUsageDescription` ตอนระบบเตรียมส่ง event ที่ต้อง Always) เป็นพฤติกรรมที่ CoreLocation จัดการ 2-prompt นี้ให้เองโดยอัตโนมัติเมื่อแอปเรียก `requestAlwaysAuthorization()` — ไม่ใช่สิ่งที่โค้ดต้องเขียนแยกสองขั้นตอนเอง จึงไม่ขัดกับโค้ดปัจจุบัน

### 4. Info.plist ของ example พอสำหรับ background region monitoring หรือยัง — **พอแล้ว ไม่ต้องเพิ่ม**

ตรวจ `packages/beacon_kit/example/ios/Runner/Info.plist` เทียบกับ [Requesting Authorization to Use Location Services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) ซึ่งระบุตารางคีย์ที่ต้องมีตามระดับสิทธิ์:

- `NSLocationWhenInUseUsageDescription` — required เมื่อขอ When In Use หรือ Always — **มีอยู่แล้วในไฟล์**
- `NSLocationAlwaysAndWhenInUseUsageDescription` — required เมื่อขอ Always — **มีอยู่แล้วในไฟล์**
- `NSLocationAlwaysUsageDescription` (คีย์เก่า) — ตรวจแยกจากหน้า [`NSLocationAlwaysUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationalwaysusagedescription) ยืนยันชัดเจนว่า "For apps deployed to targets in iOS 11 and later, use [`NSLocationAlwaysAndWhenInUseUsageDescription`] instead" และ "This key is required if your iOS app uses APIs that access the user's location at all times **and deploys to targets earlier than iOS 11**" — โปรเจกต์นี้ deploy target สูงกว่า iOS 11 มาก (Flutter ปัจจุบันไม่รองรับ iOS ต่ำกว่า 12 อยู่แล้ว) จึง**ไม่จำเป็นต้องเพิ่มคีย์เก่านี้** ไฟล์ปัจจุบันที่ไม่มีคีย์นี้ถูกต้องแล้ว ไม่ใช่ของขาด
- `NSBluetoothAlwaysUsageDescription` — ไม่เกี่ยวกับ region monitoring โดยตรง (เกี่ยวกับ path CoreBluetooth ตาม ADR-4) แต่มีอยู่แล้วและไม่ขัดแย้งอะไร
- `UIBackgroundModes` = `[location, bluetooth-central]` — ค่า `location` เป็นหนึ่งใน possible values ที่ถูกต้องจริงตาม [`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes) (ยืนยันจาก possibleValues list ในเอกสาร)

**สรุป: ไม่ต้องเพิ่ม key ใด ๆ ใน Info.plist สำหรับงาน B5/B6** ชุด key ปัจจุบันครบตามที่เอกสาร Apple ระบุสำหรับ Always authorization + background modes แล้ว

**ข้อสังเกตที่ยังไม่ยืนยันชัดเจน (บันทึกไว้เพื่อความโปร่งใส ไม่ใช่บั๊ก):** เอกสารหน้า [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates()) ระบุว่าคีย์ `UIBackgroundModes` ค่า `location` "must" มีคู่กับการเรียก `startUpdatingLocation()` แบบ continuous — ซึ่งเป็นคนละ API กับที่โค้ดปัจจุบันใช้ (`startMonitoring(for:)` + `startRangingBeacons(satisfying:)` ไม่ใช่ `startUpdatingLocation()`/`allowsBackgroundLocationUpdates`) ไม่พบเอกสารหน้าใดที่ระบุตรง ๆ ว่า region monitoring (`didEnterRegion`/`didExitRegion`) เองบังคับต้องมี `UIBackgroundModes: location` ด้วยหรือไม่ (เอกสาร [`startMonitoring(for:)`](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:)) ไม่พูดถึง background mode เลย) — **ไม่พบ/ไม่ยืนยัน** จุดนี้ตรง ๆ แต่ไม่กระทบคำแนะนำเรื่อง Info.plist เพราะค่านี้มีอยู่แล้วในไฟล์ปัจจุบันและไม่ขัดแย้งกับอะไร (ไม่ต้องเอาออก)

### 5. วิจัยเพิ่มเติมสำหรับ B6 — `CLAuthorizationStatus` มีเคส "Allow Once" แยกหรือไม่

**สมมติฐานที่ต้องตรวจ:** iOS ไม่มีสถานะ "Allow Once" แยกใน `CLAuthorizationStatus` enum แต่รายงานเป็น `.authorizedWhenInUse` ชั่วคราวแล้วเปลี่ยนกลับเป็น `.notDetermined` เองเมื่อจบ session

**ผลการค้นคว้า — ยืนยันแล้วจากเอกสารทางการ 2 หน้า (ไม่ใช่การเดา):**

1. หน้า [`CLAuthorizationStatus`](https://developer.apple.com/documentation/corelocation/clauthorizationstatus) enum listing มีแค่ 5 ค่า: "The user has not chosen whether the app can use location services" (`notDetermined`), "The app is not authorized to use location services" (`restricted`), "The user denied the use of location services..." (`denied`), "The user authorized the app to start location services at any time" (`authorizedAlways`), "The user authorized the app to start location services while it is in use" (`authorizedWhenInUse`) — **ไม่มีเคสชื่อ "allowOnce" หรือคล้ายกันเลยในรายการนี้** ยืนยันว่า enum ไม่มีสถานะแยกสำหรับ "Allow Once" จริง
2. หน้า [`requestAlwaysAuthorization()`](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()) อธิบายพฤติกรรมของ "Allow Once" ตรง ๆ ในตาราง prompt options: **"Allow Once — Core Location grants your app a Temporary When in Use authorization. The delegate receives [authorization-changed callback]. This authorization expires when your app is no longer in use, reverting to [Not Determined]."** และย่อหน้าอื่นในหน้าเดียวกันยืนยันซ้ำ: "If the user responded to [the When In Use prompt] with Allow Once, then Core Location ignores further calls to [`requestAlwaysAuthorization()`] due to the temporary authorization"

**สรุป (ยืนยันแล้ว ไม่ใช่ "ไม่พบ"):** สมมติฐานถูกต้อง — "Allow Once" **ไม่ใช่ค่าแยกใน `CLAuthorizationStatus` enum** แต่ Core Location รายงานผ่านค่า `.authorizedWhenInUse` ที่มีลักษณะ**ชั่วคราว** (temporary) แล้วระบบจะเปลี่ยนสถานะกลับเป็น `.notDetermined` เองเมื่อ "app is no longer in use" (จบ session) — โค้ดฝั่ง native **แยกความแตกต่างระหว่าง "permanent When In Use" กับ "temporary Allow Once" ไม่ได้จากค่า `CLAuthorizationStatus` เพียงอย่างเดียว** เพราะทั้งคู่รายงานเป็น `.authorizedWhenInUse` เหมือนกัน — `flutter-dev` ที่ทำ B6 (ขยาย `authorizationDecision(for:)`) ต้องออกแบบรองรับกรณีที่แอปเคยได้ `.authorizedWhenInUse` (อาจเป็น Allow Once ชั่วคราว) แล้ว **status ย้อนกลับเป็น `.notDetermined` เองในภายหลังโดยไม่มีการกระทำของผู้ใช้ที่มองเห็นได้ชัดเจน** (ไม่ใช่บั๊ก เป็นพฤติกรรมที่ตั้งใจของ Allow Once ตามเอกสาร) — ต้องคำนึงถึงตอนออกแบบ retry/re-prompt logic ของ B6

### ไม่พบ / ต้องวิจัยเพิ่มก่อน (ห้ามสมมติ)

- **`UIBackgroundModes: location` จำเป็นสำหรับ region monitoring เพียวๆ (ไม่ใช่ continuous location update) หรือไม่** — ไม่พบเอกสารที่ระบุตรง ๆ (ดูหัวข้อ 4 ด้านบน) ปัจจุบันมีอยู่แล้วในไฟล์จึงไม่กระทบการตัดสินใจ แต่ยังไม่ควรใช้เป็นข้ออ้างอิงยืนยันในอนาคตหากมีคำถามซ้ำ
- **กลไก dedupe ระหว่าง `didDetermineState` (ตอน `requestState` เริ่มต้น) กับ `didEnterRegion`/`didExitRegion`** (ตอน boundary transition เกิดขึ้นพร้อมกัน) — ยังไม่ได้ออกแบบละเอียดในสปรินต์นี้ ให้ B6 ตัดสินใจ
- **`locationManager(_:monitoringDidFailFor:withError:)`** — พบว่ามี delegate method นี้แยกจาก `didFailWithError` ทั่วไป (อ้างอิงพบชื่อในรายการ cross-reference ของหน้า `didEnterRegion`/`didExitRegion`) ยังไม่ได้ตัดสินใจว่าต้อง implement ในสปรินต์นี้หรือไม่ เพราะ ADR-4 เดิมบันทึกไว้แล้วว่า "ADR-4 ไม่ได้กำหนด error channel แยกสำหรับ ranging error รายครั้ง" — คงสถานะเดิมไว้ก่อน (ไม่ implement) ยกเว้น B6 พิจารณาแล้วเห็นว่าจำเป็น ให้บันทึกเป็น ADR เพิ่มตอนนั้น ไม่ใช่เดาตอนนี้

### 4. เลือกใช้ API ที่ถูก deprecate โดยรู้ตัว — ยังไม่ย้ายไป `CLMonitor` รอบนี้ (เพิ่ม 29 ส.ค. 2026)

**การตัดสินใจ: ยังใช้ `CLLocationManager` + `CLBeaconRegion` + `startMonitoring(for:)` ต่อไปในรอบนี้ ห้ามเขียนโค้ด `CLMonitor` ใด ๆ**

#### ข้อเท็จจริง — ยืนยันจาก SDK header โดยตรง (ไม่ใช่จากเว็บ ไม่ใช่จากความจำ)

ตรวจจาก `iPhoneOS26.5.sdk` ที่ติดตั้งอยู่ในเครื่องที่ build โปรเจกต์นี้จริง (Xcode 26.6):

| สิ่งที่ deprecate | attribute ตรงตัวจาก header | ไฟล์ |
|---|---|---|
| `CLBeaconRegion` (ทั้งคลาส) | `API_DEPRECATED_WITH_REPLACEMENT("Use CLBeaconIdentityCondition", macos(10.15, API_TO_BE_DEPRECATED), ios(7.0, API_TO_BE_DEPRECATED))` | `CoreLocation.framework/Headers/CLBeaconRegion.h:32` |
| `-startMonitoringForRegion:` (ตัวที่โค้ดเราเรียกจริง) | `API_DEPRECATED_WITH_REPLACEMENT("Use CLMonitor to start or stop monitoring constraint", ios(5.0, API_TO_BE_DEPRECATED), macos(10.8, API_TO_BE_DEPRECATED))` | `CoreLocation.framework/Headers/CLLocationManager.h:722` |
| ตัวแทนที่ต้องการ iOS เท่าไหร่ | `API_AVAILABLE(macos(14.0), ios(17.0)) API_UNAVAILABLE(watchos, tvos, visionos)` บน `@interface CLBeaconIdentityCondition` | `CoreLocation.framework/Headers/CLBeaconIdentityCondition.h:53` |

**ความแม่นยำของถ้อยคำที่ต้องระวัง (อย่าเขียนคลาดจากนี้):** ตัวเลขเวอร์ชันที่ปิดท้าย
deprecation คือ **`API_TO_BE_DEPRECATED` ซึ่งเป็น placeholder ของ Apple ไม่ใช่เลข
เวอร์ชันจริง** — แปลว่า "ถูกทำเครื่องหมายว่าจะเลิกใช้ ณ SDK ปัจจุบัน" การพูดว่า
"deprecated ใน iOS 26" เป็น **การอนุมานจากข้อเท็จจริงว่า attribute นี้ปรากฏใน SDK
26.5** ไม่ใช่ข้อความที่ Apple เขียนระบุเลขเวอร์ชันไว้ตรง ๆ ถ้าจะอ้างเลข 26 ต้องเขียน
กำกับที่มาแบบนี้เสมอ

#### เหตุผลที่ยังไม่ย้าย (3 ข้อ ทุกข้อต้องยังเป็นจริงถึงจะคงการตัดสินใจนี้ไว้ได้)

**a. การขยับ min deployment target เป็น iOS 17+ เป็นการตัดสินใจทางธุรกิจ ไม่ใช่ของทีมพัฒนา**

`CLBeaconIdentityCondition` ต้องการ iOS 17.0 ขึ้นไป (ยืนยันจาก header ด้านบน) การย้าย
ไป `CLMonitor` จึงบังคับให้ยกพื้น min deployment target ของแอปทั้งตัว = **ตัดลูกค้าที่
ใช้ iOS 16 และต่ำกว่าออกจากระบบทั้งหมด** สำหรับแอปค้าปลีกที่ฐานผู้ใช้กว้างและมีเครื่อง
รุ่นเก่าปนอยู่มาก นี่เป็นการตัดสินใจที่มีผลต่อจำนวนลูกค้าที่เข้าถึงได้จริง

**ยังไม่มีใครอนุมัติเรื่องนี้ — เป็น open question ที่ต้องถามฝ่ายธุรกิจ ทีมพัฒนาตัดสินเองไม่ได้**
ต้องรู้สัดส่วนผู้ใช้ที่ยังอยู่บน iOS 16 และต่ำกว่าก่อน แล้วให้ฝ่ายธุรกิจชั่งกับประโยชน์ที่ได้

**b. ฟีเจอร์ที่เราต้องการมากที่สุด คือส่วนที่ `CLMonitor` มีหลักฐานสาธารณะน้อยที่สุด**

จุดประสงค์หลักของสปรินต์นี้คือ **wake-from-terminate** (แอปถูก iOS terminate ไปแล้ว
ต้องถูกปลุกกลับมาเมื่อเข้าโซน) ซึ่งเป็นพฤติกรรมที่ยืนยันได้ยากที่สุดอยู่แล้วแม้บน API เดิม
และเป็นจุดที่มีรายงานปัญหากับ `CLMonitor` โดยที่ยังไม่มีเอกสาร/หลักฐานสาธารณะที่ชัดพอ
จะตัดสินได้ — การย้ายไป API ใหม่เพื่อไปเจอปัญหาที่ยังไม่มีใครเขียนวิธีแก้ไว้ ไม่ใช่การ
ลดความเสี่ยง แต่เป็นการเพิ่ม

**c. ยังไม่เคยเห็น B5/B6 ทำงานจริงบน API เดิมสักครั้ง — ย้ายตอนนี้จะแยกสาเหตุไม่ออก**

นี่เป็นเหตุผลที่หนักที่สุด ตอนนี้สถานะของ B5 (region monitoring) และ B6 (Always
permission edge case) คือ `code-complete, unverified` — **ไม่มีใครเคยเห็นมันทำงานบน
อุปกรณ์จริงเลยแม้แต่ครั้งเดียว** ถ้าย้ายไป `CLMonitor` ตอนนี้แล้วมันไม่ทำงาน เราจะมีตัวแปร
ที่เปลี่ยนพร้อมกันสองตัว (API ใหม่ + โค้ดที่ยังไม่เคยพิสูจน์) และ**แยกไม่ออกว่าพังเพราะ
`CLMonitor` หรือเพราะโค้ดเราเอง** — ทำให้เสียเวลาดีบักในทิศทางที่ผิดได้ง่ายมาก

แนวทาง "เทียบ API เก่ากับใหม่เคียงข้างกันบนอุปกรณ์เดียวกัน" เป็นสิ่งที่วิศวกร Apple DTS
แนะนำเช่นกัน *(ที่มา: การปรึกษา Apple DTS ตามที่ผู้ใช้รายงาน — **ไม่ใช่เอกสารสาธารณะ
ที่ตรวจสอบย้อนกลับได้** บันทึกไว้ในฐานะข้อมูลประกอบ ไม่ใช่หลักฐานระดับเดียวกับ SDK
header/เอกสาร Apple ที่อ้างข้างบน)*

#### แผนการย้าย (ลำดับบังคับ ห้ามสลับขั้น)

1. **ยืนยัน B5/B6 บน API เดิมให้ผ่านจริงบนอุปกรณ์ก่อน** — ต้องเห็นแอปถูกปลุกกลับมา
   จริงตอนถูก kill ไม่ใช่แค่คอมไพล์ผ่าน นี่คือ definition of done ของสปรินต์ปัจจุบัน
2. implement `CLMonitor` **คู่ขนาน** (ไม่ลบของเดิมทิ้ง) หลังจากฝ่ายธุรกิจตัดสินเรื่อง
   min deployment target แล้วเท่านั้น
3. ทดสอบเทียบ **บนอุปกรณ์เครื่องเดียวกัน beacon ตัวเดียวกัน** เงื่อนไขเดียวกัน
4. ตัดสินใจจาก**ผลจริงที่วัดได้** ไม่ใช่จากการที่ API ใหม่กว่า

**เกณฑ์ที่จะทำให้ต้องกลับมาทบทวน ADR นี้ก่อนกำหนด:** Apple เปลี่ยน
`API_TO_BE_DEPRECATED` เป็นเลขเวอร์ชันจริงพร้อมกำหนดวันหยุดรองรับ, หรือฝ่ายธุรกิจ
อนุมัติ iOS 17+ แล้ว, หรือพบว่า API เดิมใช้ไม่ได้จริงบนอุปกรณ์


#### ระดับความแน่นอนของ deprecation ต่างกัน — และมันสนับสนุนการตัดสินใจนี้ (เพิ่ม 29 ส.ค. 2026)

เทียบ 2 อย่างที่ถูก deprecate ในเรื่องเดียวกัน จาก SDK header เดียวกัน (`iPhoneOS26.5.sdk`):

| สิ่งที่ deprecate | เวอร์ชันปิดท้าย | ความหมาย |
|---|---|---|
| `CLBeaconRegion`, `-startMonitoringForRegion:` | `API_TO_BE_DEPRECATED` | **placeholder** ไม่ใช่เลขเวอร์ชัน |
| `UIApplicationLaunchOptionsLocationKey` | `ios(4.0, 26.0)` | **เลขเวอร์ชันจริง** |

**การตีความของทีมเรา (ไม่ใช่ถ้อยแถลงของ Apple — Apple ไม่ได้อธิบายเจตนาไว้ที่ไหน):**
การที่ Apple ประทับ `API_TO_BE_DEPRECATED` ไว้กับ `CLBeaconRegion` แทนที่จะใส่เลข
เวอร์ชันจริงแบบที่ทำกับ launch options key ในเรื่องเดียวกัน อ่านได้ว่า **ยังไม่ได้
ผูกกำหนดการที่แน่นอนกับตัวหลัง** — ต่างจากตัวแรกที่ตัดสินใจแล้วว่าเลิกเมื่อไหร่

ถ้าอ่านแบบนี้ถูก แปลว่าความเสี่ยงเฉพาะหน้าของการใช้ `CLBeaconRegion` ต่อไป
**ต่ำกว่า**ที่คำว่า "deprecated" ทำให้รู้สึกตอนแรก จึงเป็นเหตุผลสนับสนุนเพิ่มเติม
ของการตัดสินใจข้างบน ที่จะยังไม่ย้ายไป `CLMonitor` ในรอบนี้

**ข้อควรระวังในการใช้การตีความนี้:** นี่เป็นการอ่านสัญญาณ ไม่ใช่คำรับประกัน
`API_TO_BE_DEPRECATED` อาจกลายเป็นเลขจริงเมื่อไหร่ก็ได้ใน SDK รุ่นถัดไป —
เกณฑ์ทบทวน ADR ที่ระบุไว้ข้างบน (ข้อ "Apple เปลี่ยน `API_TO_BE_DEPRECATED` เป็น
เลขเวอร์ชันจริง") จึงยังใช้บังคับเหมือนเดิม ห้ามใช้ย่อหน้านี้เป็นเหตุผลที่จะไม่
ตรวจสอบซ้ำในสปรินต์ถัด ๆ ไป

## ADR-7 (สั้น): ตำแหน่งของ domain entity/usecase สำหรับ BigC ID mapping (A3-decision, เพิ่ม 28 ส.ค. 2026)

**คำถาม:** โค้ด pure-Dart ที่แปลง identity triple (UUID, Major, Minor) → ข้อมูลธุรกิจ (ยี่ห้อ/ล็อต/กลุ่ม/ตำแหน่ง ตาม ADR-5) ควรอยู่ที่ไหน — ยังไม่มี `lib/features/` ที่ไหนใน repo เลยตอนนี้ (ตรวจด้วย `find` แล้วไม่มีจริง) มีแต่ `packages/beacon_kit*` (federated plugin)

**ตัดสินใจ: เลือกตัวเลือก (ก) — วางไว้ใน `packages/beacon_kit_platform_interface/lib/src/`**

- Entity ใหม่: `packages/beacon_kit_platform_interface/lib/src/entities/bigc_beacon_identity.dart` (หรือชื่อไฟล์ที่ใกล้เคียง — รายละเอียด naming ให้ `flutter-dev` ตัดสินตอน implement)
- Usecase ใหม่: โฟลเดอร์ `packages/beacon_kit_platform_interface/lib/src/usecases/` (ยังไม่มีในแพ็กเกจนี้ ต้องสร้างใหม่) เช่น `resolve_bigc_beacon_metadata.dart`
- ทั้งสองไฟล์ต้อง export ผ่าน barrel `packages/beacon_kit_platform_interface/lib/beacon_kit_platform_interface.dart` เหมือนไฟล์อื่นในแพ็กเกจนี้ตาม ADR-3

**เหตุผล:**

1. `beacon_kit_platform_interface` เป็น pure Dart อยู่แล้ว (ไม่มี Flutter SDK dependency) — ตรงกับกฎ "domain ห้าม import Flutter" โดยธรรมชาติของแพ็กเกจ ไม่ต้องสร้างโครงสร้างใหม่เพื่อบังคับกฎนี้
2. แพ็กเกจนี้มี pattern `entities/` + `parsers/` อยู่แล้วจาก ADR-3 (`IBeaconFrame`, `EddystoneFrame`, ฯลฯ) — เพิ่ม `usecases/` เป็นโฟลเดอร์พี่น้องที่สอดคล้องกับโครงเดิม ไม่ใช่การเริ่มโครงใหม่จากศูนย์
3. **ตัวเลือก (ข)** (`lib/features/beacon_scanning/domain/` ใหม่ที่ repo root หรือใต้ `example/`) จะเป็นการสร้างโครง "App Layer" ที่ ARCHITECTURE.md ระบุไว้ล่วงหน้าสำหรับ**แอปที่ใช้ beacon_kit ในอนาคต** — แต่ตอนนี้ยังไม่มีแอปจริงนั้นอยู่เลย (`example/` เป็นแค่ตัวอย่างสาธิต ไม่ใช่แอป production) การสร้างโครง `lib/features/.../domain/` ตอนนี้คือสร้างนั่งร้านไว้ล่วงหน้าก่อนมีสิ่งที่ต้องรองรับจริง เป็นการ over-engineer ที่ตัดออก
4. **ตัวเลือก (ค)** (แพ็กเกจใหม่ `packages/bigc_beacon_domain/`) พิจารณาแล้วว่ายังไม่คุ้ม — ยังไม่มีกรณีใช้ซ้ำข้ามหลายแอป/หลายแพ็กเกจที่ต้องแยก การเพิ่มแพ็กเกจใหม่ตอนนี้เพิ่ม maintenance overhead (pubspec, CI job, versioning) โดยไม่มีประโยชน์ที่จับต้องได้ในสปรินต์นี้ — ถ้าอนาคต `beacon_kit` ต้องถูกใช้นอกบริบท BigC จริง (org อื่น, ID scheme อื่น) ค่อยแยกออกมาเป็น (ค) ตอนนั้น

**Trade-off ที่ต้องรู้ตัว (บันทึกไว้ ไม่ใช่ผลข้างเคียงที่ค้นพบทีหลัง):** `beacon_kit_platform_interface` ตามชื่อและโครงสร้างเดิมมีไว้เป็น "สัญญา method channel กลาง" (protocol-level, vendor-agnostic) — การใส่ business domain logic เฉพาะของ BigC (mapping ยี่ห้อ/ล็อต/กลุ่ม/ตำแหน่ง) เข้าไปในแพ็กเกจเดียวกันทำให้แพ็กเกจนี้ผูกกับ business scheme ของ BigC โดยเฉพาะ ไม่ใช่ pure protocol contract อีกต่อไป — ยอมรับ trade-off นี้ในตอนนี้เพราะ ADR-5 ทั้งฉบับเป็นสคีมเฉพาะของ BigC อยู่แล้วและ repo นี้ยังเป็น single-org monorepo ไม่มีผู้ใช้ภายนอก ถ้าถึงจุดที่ต้องแยก (เช่น reuse `beacon_kit` ข้ามองค์กร) ให้ย้าย entity/usecase กลุ่มนี้ออกไปเป็นตัวเลือก (ค) ในตอนนั้น ไม่ใช่ตอนนี้

---

## ADR-8: Two-tier region registration — ตาข่ายกว้าง 1 อัน + เจาะจงสาขาไม่เกิน 19 อัน (เพิ่ม 29 ส.ค. 2026)

**บริบท:** ADR-5 กำหนดให้ BigC ใช้ proximity UUID เดียวทั้งบริษัท แยกอุปกรณ์ด้วย major/minor และ ADR-6 กำหนดให้ย้ายไปใช้ region monitoring (enter/exit) เพื่อทำงานตอน background คำถามที่ยังไม่ถูกตอบคือ **แล้วจะลงทะเบียน region อะไรบ้าง** ในเมื่อ iOS จำกัดที่ 20 region ต่อแอป แต่ BigC มีสาขามากกว่านั้นมาก

### ข้อจำกัดที่บังคับดีไซน์นี้ (ยืนยันจากเอกสาร Apple)

| ข้อเท็จจริง | คำพูดต้นฉบับ | แหล่งอ้างอิง |
|---|---|---|
| เพดาน 20 region ต่อแอป | "An app can register up to 20 regions at a time." | [`startMonitoring(for:)`](https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:)) |
| region เป็นทรัพยากรระบบที่ใช้ร่วมกัน | "Regions are a shared system resource, and the total number of regions available systemwide is limited. For this reason, Core Location limits to 20 the number of regions that may be simultaneously monitored by a single app." | [Region Monitoring and iBeacon (archived)](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html) |
| Apple แนะนำให้สลับ region ตามตำแหน่งผู้ใช้ | "To work around this limit, consider registering only those regions in the user's immediate vicinity." | แหล่งเดียวกับข้างบน |
| identifier string คือทางเดียวที่การันตีว่าระบุ region ได้ | "The identifier string is the only guaranteed way for your app to identify a region later." | แหล่งเดียวกับข้างบน |
| wildcard ได้เฉพาะภายใน UUID เดียวกัน | "Constraints always specify a UUID value, but the major and minor values are optional. ... Major and minor characteristics are wildcards if they have no value." | [`CLBeaconIdentityConstraint`](https://developer.apple.com/documentation/corelocation/clbeaconidentityconstraint) |

### การตัดสินใจ: ลงทะเบียน region เป็น 2 ชั้น

**ชั้นที่ 1 — region กว้าง 1 อัน (ตาข่ายกันพลาด, ลงทะเบียนถาวร)**

- สร้างด้วย `init(uuid:identifier:)` — **ระบุแค่ UUID ของ BigC ไม่ระบุ major/minor**
  จึงครอบคลุม beacon ของ BigC **ทุกตัวในฟลีต** ด้วย region เดียว (ตามกลไก wildcard
  ที่ยืนยันไว้ข้างบน)
- **ลงทะเบียนถาวร ห้ามถอดออกไม่ว่ากรณีใด** — ไม่ว่าจะสลับชั้นที่ 2 กี่รอบ ไม่ว่าผู้ใช้จะ
  ย้ายไปไหน region นี้ต้องอยู่เสมอ
- หน้าที่: **รับประกันว่าแอปตื่นเสมอเมื่อเจอ beacon ของ BigC** แม้เป็นสาขาที่ไม่ได้อยู่
  ในรายการ 19 อันของชั้นที่ 2

**ชั้นที่ 2 — region เจาะจงสาขา ไม่เกิน 19 อัน (สลับได้ตามตำแหน่ง)**

- สร้างด้วย `init(uuid:major:identifier:)` — ระบุ major (= รหัสสาขาตาม ADR-5)
  ไม่ระบุ minor เพื่อให้ครอบคลุม beacon ทุกตัวในสาขานั้น
- **`identifier` string ตั้งเป็นรหัสสาขา** เพื่อให้ `didEnterRegion` บอกได้ทันทีว่า
  เข้าสาขาไหน โดย**ไม่ต้องรอ ranging** — อ่านจาก `region.identifier` ตรง ๆ
  (ตรงตามที่ Apple ระบุว่า identifier string คือทางเดียวที่การันตีว่าระบุ region ได้
  จึง**ห้ามเทียบ pointer ของ object** หรือพึ่งลำดับใน `monitoredRegions`)
- สลับชุดได้ตามตำแหน่งคร่าว ๆ ของผู้ใช้ ตามที่ Apple แนะนำ

**19 + 1 = 20 พอดี** ตรงเพดานที่ Apple ระบุ

### ทำไมต้องมีทั้งสองชั้น (ตัดชั้นใดชั้นหนึ่งออกไม่ได้)

**ถ้ามีแต่ชั้นกว้างอย่างเดียว** — `didEnterRegion` จะบอกได้แค่ "เข้าโซนของ BigC สักที่หนึ่ง"
ไม่รู้ว่าสาขาไหน ต้องรอ ranging ต่อเพื่อดู major/minor ซึ่ง **อาจไม่ทันในเวลา background
ที่ iOS ให้มาอย่างจำกัด** (แอปที่ถูกปลุกจาก terminate ได้เวลาทำงานสั้นมาก) ผลคืออาจรู้ว่า
เข้าโซนแต่ไม่ทันรู้ว่าสาขาไหนก่อนถูก suspend อีกครั้ง

**ถ้ามีแต่ชั้นเจาะจงอย่างเดียว** — จะเกิด **จุดบอดถาวรที่มองไม่เห็น** ผู้ใช้ที่เดินเข้าสาขาที่ 21
(หรือสาขาที่เพิ่งเปิดใหม่ หรือสาขาที่ระบบเลือกไม่ครอบคลุมเพราะตำแหน่งคร่าว ๆ ผิด) จะ
**ไม่ปลุกแอปเลย** และ — นี่คือส่วนที่อันตรายที่สุด — **ความเงียบแบบนั้นมีหน้าตาเหมือนกับ
"ไม่มีใครเดินผ่าน beacon" ทุกประการ แยกจากกันไม่ออกจากฝั่งเรา** ไม่มี error ไม่มี log
ไม่มีสัญญาณใด ๆ ที่บอกว่าเราพลาดไป ระบบจะดูเหมือนทำงานปกติทั้งที่มีรูโหว่อยู่

ชั้นที่ 1 จึงไม่ใช่ของสำรองที่ "มีก็ดี" แต่เป็นสิ่งที่ทำให้ความล้มเหลวของชั้นที่ 2
**สังเกตเห็นได้** — ถ้าชั้นกว้างตื่นแต่ไม่มีสาขาไหนใน 19 อันตรงกัน นั่นคือสัญญาณชัดเจนว่า
การเลือกสาขาของเราพลาด ซึ่งเป็นข้อมูลที่เอาไปแก้ได้

### ส่วนที่เป็น pure function (Track A — ทดสอบได้โดยไม่ต้องมีฮาร์ดแวร์)

การ **"เลือกว่าจะลงทะเบียน region ชุดไหน"** แยกออกมาเป็น pure function ที่ไม่แตะ
CoreLocation เลย: รับรายการสาขา + ตำแหน่งคร่าว ๆ ของผู้ใช้ → คืนรายการ region ที่ควร
ลงทะเบียน

สัญญาที่ฟังก์ชันนี้ต้องรักษาเสมอ (บังคับด้วย unit test):

1. **ชั้นที่ 1 ต้องอยู่ในผลลัพธ์เสมอ** ไม่ว่า input จะเป็นอะไร — สาขา 0 แห่ง, สาขา 10,000 แห่ง,
   หรือไม่รู้ตำแหน่งผู้ใช้เลย
2. **จำนวนรวมต้องไม่เกิน 20 เสมอ**
3. ชั้นที่ 2 เรียงตามระยะจากผู้ใช้ (ใกล้ก่อน) แล้วตัดที่ 19

ส่วนที่เรียก CoreLocation จริง (`startMonitoring(for:)`) ยังเป็น **Track B**
`code-complete, unverified` ตามปกติ

### Open question ที่ยังไม่ยืนยัน — ห้ามสมมติเอาเอง

**เมื่อ beacon หนึ่งตัวตรงกับทั้ง region ชั้นกว้างและ region เจาะจงสาขาพร้อมกัน
`didEnterRegion` จะถูกเรียกกี่ครั้ง — ครั้งเดียวหรือสองครั้ง (ครั้งละ region)?**

**ไม่พบเอกสารของ Apple ที่ระบุพฤติกรรมของ region ที่ซ้อนทับกันในกรณี beacon region ไว้ชัด**
(หน้า `didEnterRegion` อธิบายว่า callback ส่ง `region` ที่เข้ามาให้ แต่ไม่ได้ระบุว่าเมื่อมี
หลาย region ที่ match พร้อมกันจะยิงกี่ครั้ง)

ผลกระทบถ้าเดาผิด: ถ้ายิงสองครั้งจริงแล้วเราคิดว่าครั้งเดียว จะเกิด event ซ้ำที่ไหลไปถึง
business logic (เช่น นับการเข้าสาขาซ้ำสองเท่า) ถ้ายิงครั้งเดียวจริงแล้วเราคิดว่าสองครั้ง
อาจเขียน dedupe ที่กลืน event ที่ถูกต้องทิ้ง

**ต้องทดสอบบนอุปกรณ์จริงก่อน** แล้วค่อยตัดสินใจว่าจะ dedupe ที่ชั้นไหน — เพิ่มเป็นเคส
ทดสอบไว้ใน `docs/test-checklists/ios_broadcast_scanning.md` แล้ว จนกว่าจะรู้ผล
**ห้ามเขียน dedupe logic ที่ตั้งอยู่บนข้อสมมติข้อใดข้อหนึ่ง**

---

## ADR-9: สัญญา cross-platform ของ `startIBeaconMonitoring()` / `stopIBeaconMonitoring()` (เพิ่ม 29 ส.ค. 2026)

**ทำไมเป็น ADR แยก ไม่ใช่หัวข้อย่อยของ ADR-6:** ADR-6 เป็นการตัดสินใจเรื่อง *iOS* (ย้ายจาก ranging ไป region monitoring บน CoreLocation) ส่วน ADR นี้เป็นสัญญาของ **public API ใน `beacon_kit`** ที่มีผลต่อผู้เรียกทุกแพลตฟอร์มและต่อคนที่จะมาทำ Android — คนคนนั้นจะค้นหาคำว่า "Android" แล้วควรเจอ ADR ที่พูดถึงเรื่องนี้ทั้งหัวข้อ ไม่ใช่ย่อหน้าที่ฝังอยู่กลาง ADR ที่ชื่อบอกว่าเป็นเรื่อง iOS

**บริบท:** `GenericIBeaconEddystoneAdapter` เปิดเมธอด `startIBeaconMonitoring()` / `stopIBeaconMonitoring()` เพิ่มจาก `scan()` เพราะ B5 ต้องการให้ region ยังลงทะเบียนอยู่แม้ไม่มีใครฟัง stream และแม้ process ถูก terminate ซึ่ง `scan()` ทำไม่ได้ (อายุของ region ผูกกับ subscription)

### เมธอดคู่นี้ตั้งอยู่บนความสามารถระดับ OS ที่ iOS มี — และยังไม่รู้ว่า Android มีเทียบเท่าหรือไม่

**ฝั่ง iOS (ยืนยันจากเอกสาร Apple):** region ที่ลงทะเบียนแล้วถูกเก็บที่ระดับระบบและคงอยู่ข้าม process

> "The location manager persists region data between launches of your app. If your app is terminated and then relaunched, the contents of this property are repopulated with region objects that contain the previously registered data."
>
> — [`CLLocationManager.monitoredRegions`](https://developer.apple.com/documentation/corelocation/cllocationmanager/monitoredregions)

หน้าเดียวกันยังระบุว่า property นี้คือ "The set of shared regions monitored by all location-manager objects" — region ไม่ได้เป็นของ instance ใด instance หนึ่ง

**นี่คือเหตุผลที่เมธอดคู่นี้มีหน้าตาแบบนี้:** `start` ไม่ใช่ "เริ่มทำงาน" แต่คือ **"ลงทะเบียนไว้กับระบบ"** และ `stop` คือ **"ถอนออกจากระบบ"** — ไม่มีอะไรต้องคงไว้ใน memory ของแอป ไม่มี stream ที่ต้อง subscribe ค้าง ถ้าไม่เรียก `stop` region จะอยู่ต่อไปแม้ผู้ใช้ปิดแอป (แต่หายเมื่อผู้ใช้ลบแอป)

**ฝั่ง Android — ยังไม่ตัดสิน เป็น open question ที่ต้องตอบก่อนเริ่มงาน Android**

สิ่งที่**ยืนยันแล้ว**จากเอกสาร Android: มี API ที่ส่งผลการสแกน BLE ไปยัง process ที่ไม่ได้รันอยู่ได้จริง

> "Start Bluetooth LE scan using a PendingIntent. The scan results will be delivered via the PendingIntent. **Use this method of scanning if your process is not always running and it should be started when scan results are available.**"
>
> — [`BluetoothLeScanner.startScan(List<ScanFilter>, ScanSettings, PendingIntent)`](https://developer.android.com/reference/android/bluetooth/le/BluetoothLeScanner)

สิ่งที่**ยังไม่ยืนยัน และห้ามเดาทั้งสองทาง**:

| คำถาม | สถานะ |
|---|---|
| กลไกนี้ใช้แทน region monitoring ของ iOS ได้จริงในเชิง use case หรือไม่ | **ยังไม่ตัดสิน** — มันเป็น *scan result* ที่ filter ด้วย `ScanFilter` ไม่ใช่ *region enter/exit* ที่ OS คำนวณให้ ความหมายไม่เหมือนกัน |
| Android เก็บ "ชุด region ที่ลงทะเบียนไว้" ข้าม process แบบ `monitoredRegions` หรือไม่ | **ยังไม่ยืนยัน** |
| มี enter/exit semantics (รู้ว่า "ออก" จากโซนแล้ว) หรือต้องคำนวณเองจากการไม่เจอ scan result | **ยังไม่ยืนยัน** |
| พฤติกรรมหลังผู้ใช้ force-stop แอป เป็นอย่างไร | **ยังไม่ยืนยัน** |
| ข้อจำกัด background scan throttling ของ Android มีผลแค่ไหน | **ยังไม่ยืนยัน** |

**สิ่งที่คนทำ Android ต้องรู้ก่อนแตะเมธอดคู่นี้ (จุดประสงค์หลักของ ADR นี้):**

⚠️ **ห้ามสมมติว่า `startIBeaconMonitoring()` จะทำงานเหมือนกันทั้งสองแพลตฟอร์ม** สัญญาปัจจุบันของเมธอดนี้คือสัญญาแบบ iOS: *"ลงทะเบียน region ไว้กับ OS แล้วมันจะอยู่ข้าม process จนกว่าจะถอน"* ถ้า Android ทำแบบนั้นไม่ได้ **ห้าม implement ให้มัน "ดูเหมือนทำได้"** เช่นเลี้ยง foreground service ไว้เงียบ ๆ แล้วเรียกว่าสำเร็จ — เพราะผู้เรียกจะเข้าใจว่าได้พฤติกรรมเดียวกันทั้งสองแพลตฟอร์มทั้งที่ไม่ใช่ และจะไปเจอความจริงตอนอยู่หน้างานกับอุปกรณ์จริง

ทางเลือกที่ต้องตัดสินตอนเริ่มงาน Android (ยังไม่ตัดสินตอนนี้ เพราะยังไม่มีข้อมูลพอ):
1. ให้ Android throw `UnsupportedError` ตรง ๆ ถ้าทำไม่ได้จริง — ตรงไปตรงมาที่สุด
2. เปลี่ยนชื่อ/แยกเมธอดตามความสามารถจริงของแต่ละแพลตฟอร์ม
3. ถ้าค้นคว้าแล้วพบว่า Android ทำได้เทียบเท่าจริง ค่อยคงสัญญาเดียวกันไว้

**ก่อนตัดสิน ต้องรัน skill `beacon-sdk-verify` หรือการค้นคว้าเทียบเท่ากับเอกสาร Android อย่างเป็นระบบก่อน** — ตอบตารางข้างบนให้ครบพร้อม citation แล้วกลับมาเขียน ADR ต่อจากนี้ ไม่ใช่ตัดสินจากความจำ

### `IBeaconRegionStateEvent` ก็ผูกกับ iOS เช่นกัน

`regionStateEvents` และ type ที่เกี่ยวข้อง (`IBeaconRegionState`, `IBeaconAuthorizationLevel`) ถูก export จาก `beacon_kit` โดย**ตั้งชื่อขึ้นต้นด้วย `IBeacon`/ผูกกับ iOS ชัดเจน**อยู่แล้ว (ดูคอมเมนต์ใน `beacon_kit.dart`) — เจตนาคือให้ผู้เรียกเห็นตั้งแต่ชื่อว่านี่ไม่ใช่ contract กลางข้ามแพลตฟอร์ม เมื่อถึงเวลาทำ Android ถ้าพบว่าต้องมี contract กลางจริง ให้ยกขึ้นไปที่ `beacon_kit_platform_interface` พร้อมชื่อที่เป็นกลาง แทนการดัด type ของ iOS ให้ครอบ Android

---

## ADR-10: รับ region event ได้ตั้งแต่รอบ launch — แก้เหตุที่ B5 ไม่ผ่าน (เพิ่ม 30 ส.ค. 2026)

**สถานะ:** ตัดสินใจแล้ว · โค้ดเสร็จแล้ว · **ยังไม่ยืนยันบนอุปกรณ์จริง** (Track B)

### 1. หลักฐานที่ทำให้ต้องมี ADR นี้

การทดสอบ B5 เมื่อ 30 ส.ค. 2026: ปัดแอปทิ้งจาก app switcher → ถอด/ใส่แบต K9P →
รอ 5 นาที → **ไม่มี notification และไม่มีบรรทัดใน log เลยแม้แต่บรรทัดเดียว**
ขณะที่ข้อ 2 (background แต่ process ยังมีชีวิต) ผ่านปกติ

### 2. เส้นทางที่ขาด (ตรวจจากโค้ดจริง ไม่ใช่จากการเดา)

`CLLocationManager` ถูกสร้างที่ `IBeaconRangingManager.init()` ที่เดียวเท่านั้น
และ `IBeaconRangingManager` ถูกสร้างจาก `BeaconKitIosPlugin()` ซึ่งเกิดใน
`register(with:)` เท่านั้น ส่วน `register(with:)` ถูกเรียกจาก
`GeneratedPluginRegistrant.register` ที่ example app วางไว้ใน
`didInitializeImplicitFlutterEngine`

header ของ Flutter ระบุความหมายของ callback นั้นไว้ว่า:

> "Called once the implicit `FlutterEngine` is initialized."
> "Protocol for receiving a callback when an implicit engine is initialized,
> **such as when created by a FlutterViewController from a storyboard.**"
> — `Flutter.framework/Headers/FlutterEngine.h:476-490`

และ `Runner/Info.plist` ของ example app ประกาศ `UIApplicationSceneManifest`
พร้อม `UISceneStoryboardFile = Main` — `FlutterViewController` จึงเกิดตอน
**scene connect** ซึ่งคือตอนที่มี UI

**สรุปเส้นทางที่ขาด:** ตอน iOS ปลุก process ที่ถูกฆ่าขึ้นมาเบื้องหลังเพื่อส่ง
location event ไม่มี scene ถูก connect → ไม่มี `FlutterViewController` →
implicit engine ไม่ถูกสร้าง → ไม่มีการ register plugin → **ไม่มี
`CLLocationManager` และไม่มี delegate ให้ CoreLocation เรียก** event ที่แอปถูก
ปลุกขึ้นมารับจึงตกหายทั้งหมด

### 3. หลักฐานว่า B5 ทำได้จริง (ไม่ใช่ข้อจำกัดของแพลตฟอร์ม)

จาก `CLLocationManager.h:492-496` (iPhoneOS26.5.sdk) ในคำอธิบายของ
`requestAlwaysAuthorization`:

> "monitoring APIs may launch your app into the background when they detect an
> event. **Even if killed by the user, launch events triggered by monitoring
> APIs will cause a relaunch.**"

และ region ที่ลงทะเบียนไว้ไม่หายไปกับ process — `CLLocationManager.h:420-422`:

> "If any location manager has been instructed to monitor a region, **during
> this or previous launches of your application**, it will be present in this
> set." (`monitoredRegions`)

ส่วนหน้าที่ของแอปในรอบ launch นั้น Apple เขียนไว้ที่
*Handling location updates in the background* ว่า:

> "If your app actively receives and processes location updates and terminates,
> it should **restart those APIs upon launch** in order to continue receiving
> updates. **When you start those services, the system resumes the delivery of
> queued location updates.** Don't start these services at launch time if your
> app's authorization status is undetermined."

**ข้อควรระวังในการตีความ:** ประโยคนี้อยู่ในหน้าที่เขียนสำหรับ API ยุคใหม่
(`CLServiceSession`/`CLBackgroundActivitySession`) ส่วนหน้า region monitoring
ยุคใหม่ก็เขียนว่า "When your app relaunches, it's your responsibility to
recreate the monitor with the same identifier" ซึ่งเป็นสัญญาของ `CLMonitor`
**เราไม่ได้ใช้ `CLMonitor`** (ADR-6 หัวข้อ 4 ตัดสินแล้วว่ายังไม่ย้าย) และสำหรับ
API เดิม header ของ `monitoredRegions` ระบุชัดว่า region ยังอยู่ข้าม launch
เอง จึง **ไม่ต้องลงทะเบียน region ใหม่** สิ่งที่ต้องทำคือมี `CLLocationManager`
+ delegate ให้ทันในรอบ launch เท่านั้น — ส่วนนี้เป็น**การตีความของเรา** จาก
header ไม่ใช่ประโยคที่ Apple เขียนตรง ๆ และจะถือว่ายืนยันแล้วก็ต่อเมื่อเห็น
บรรทัด `relaunchedFromTerminated` ในไฟล์ log บนอุปกรณ์จริง

### 4. การตัดสินใจ

**(ก) SDK เปิดทางให้ host app เริ่ม CoreLocation ได้ตั้งแต่รอบ launch**

`BeaconKitIosPlugin.startBackgroundRegionMonitoring(onRegionStateEvent:)` —
static ไม่ต้องมี `FlutterPluginRegistrar` ไม่ต้องมี engine host app เรียกจาก
`application(_:didFinishLaunchingWithOptions:)` ได้ตรง ๆ คืนรายการ identifier
ของ region ที่ระบบยังเก็บไว้ให้ เพื่อใช้เป็นหลักฐาน

**ทำไม SDK ไม่ทำให้เองอัตโนมัติ:** ไม่มีทางที่ plugin จะแทรกตัวเข้าไปใน
`didFinishLaunchingWithOptions` ของ host app ได้ก่อนที่ตัวมันเองจะถูก register
— และการ register นั่นแหละคือสิ่งที่ไม่เกิดในเคสนี้ จึงต้องเป็น host app เรียก
หนึ่งบรรทัด แอปที่ไม่ต้องการพฤติกรรมนี้ไม่ต้องจ่ายอะไรเลย

**(ข) `IBeaconRangingManager` เป็น singleton**

เพราะตอนนี้มีผู้สร้างสองทาง (จาก `didFinishLaunchingWithOptions` และจาก
`register(with:)` ที่เกิดทีหลัง) ถ้าเป็นคนละ instance จะมี `CLLocationManager`
สองตัว และตาม Apple docs ของ `didEnterRegion` ("every active location manager
object delivers this message to its associated delegate") ทั้งคู่จะได้ callback
เดียวกัน → event ซ้ำสองชุด

**(ค) อ่าน region ที่ระบบเก็บไว้กลับมาตอน init — และ *ห้าม* หยุด monitor**

`init()` เรียก `adoptSystemMonitoredRegions()` ซึ่ง **อ่านอย่างเดียว** —
เติม `constraintsByIdentifier` จาก `locationManager.monitoredRegions`

ข้อห้ามที่เขียนไว้เป็นคอมเมนต์ทั้งใน `IBeaconRangingManager.init()` และใน
`AppDelegate`: **ห้ามเรียก `stopMonitoring(for:)` ใด ๆ ในเส้นทาง initialize**
region ที่ระบบเก็บไว้คือสิ่งเดียวที่ทำให้ iOS ปลุกแอปขึ้นมา ถ้าโค้ด init ไป
ล้างทิ้ง แอปจะไม่มีวันถูกปลุกอีกและอาการจะออกมาเหมือน "ไม่รองรับ background"
ทั้งที่เราลบมันเอง

**ตรวจแล้วว่าโค้ดเดิมไม่มีพฤติกรรมนี้:** `stopMonitoring(identifiers: nil)` ตัว
เดียวที่มีอยู่ถูกเรียกจาก `applyParsedRegions` (เส้นทาง `startIBeaconMonitoring`
ที่ผู้ใช้สั่ง) ไม่ใช่เส้นทาง init และมันวนจาก `constraintsByIdentifier` ซึ่ง
เดิม**ว่างเปล่าเสมอใน process ใหม่** จึงไม่เคยลบ region ของระบบได้อยู่แล้ว
— หลังการเปลี่ยนแปลงข้อนี้ dictionary ไม่ว่างแล้ว การ "แทนที่ ไม่ merge" ของ
`startIBeaconMonitoring` จึงทำงานถูกต้องเป็นครั้งแรก (เดิมมันสะสม region ทิ้งไว้
ในระบบ และการนับเพดาน 20 ที่อ่านจาก `locationManager.monitoredRegions` ก็นับ
ของค้างเหล่านั้นด้วย)

**(ง) ไม่พึ่ง `constraintsByIdentifier` อย่างเดียวตอนยิง event**

`emitRegionStateIfChanged` ถอด constraint จาก `CLBeaconRegion` ที่ CoreLocation
ส่งมาเองได้เลยถ้าไม่รู้จัก identifier นั้น — กันเคสที่ callback มาถึงก่อน
`monitoredRegions` จะสะท้อนค่าครบ (header เตือนเองว่าการลงทะเบียน region เป็น
asynchronous "and may not be immediately reflected in `monitoredRegions`",
`CLLocationManager.h:720`)

**(จ) buffer event ที่เกิดก่อน Dart subscribe**

`RegionStateEventStreamHandler` เก็บ event ไว้ไม่เกิน 50 รายการเมื่อ
`eventSink` ยังเป็น `nil` แล้วส่งให้ทีเดียวตอน `onListen` — ตอนถูกปลุก
เบื้องหลัง CoreLocation เรียก delegate ได้ทันทีที่ manager ถูกสร้าง แต่กว่า
engine จะ start และ Dart จะ subscribe ได้ต้องผ่านอีกหลายขั้น

**(ฉ) เส้นทางบันทึกหลักฐานต้องเป็น native ล้วน (example app)**

เดิม log และ notification วิ่งผ่าน Dart ทั้งคู่ ซึ่งต้องมี Flutter engine
ทำงานอยู่ — เงื่อนไขที่ไม่เป็นจริงในเคสที่ B5 ต้องการพิสูจน์พอดี
**เครื่องมือวัดตายพร้อมกับสิ่งที่มันควรวัด** ย้ายไป
`example/ios/Runner/BackgroundEvidenceLog.swift` (Swift ล้วน ไม่พึ่ง Flutter)
และให้เป็น **ผู้เขียน log เพียงรายเดียว** ฝั่ง Dart เลิกเขียน เพื่อไม่ให้
foreground ได้บรรทัดซ้ำสองชุดต่อหนึ่ง event

ยังคงอยู่ใน example app เท่านั้นตามข้อกำหนดเดิม — SDK ให้แค่ hook เปล่า
(`onRegionStateEvent`) ไม่ยุ่งว่า host จะเขียน log หรือยิง notification

**(ช) เขียนบรรทัด `launch` ทุกครั้งที่ process เริ่ม**

รอบทดสอบที่ผ่านมา "ไม่มีบรรทัดใน log เลย" แยกไม่ออกระหว่าง **"iOS ไม่ได้ปลุก
แอปเลย"** กับ **"ปลุกแล้วแต่ event ไปไม่ถึง handler"** ซึ่งเป็นคนละสาเหตุและ
คนละวิธีแก้โดยสิ้นเชิง บรรทัด `launch` (พร้อม `launchKey=`, `state=`,
`monitoredRegions=[…]`) ทำให้รอบหน้าแยกออกทันที

### 5. เกณฑ์ผ่านของ B5 ไม่เปลี่ยน

ยังต้องเห็นบรรทัดที่คอลัมน์ที่ 4 เป็น `relaunchedFromTerminated` ในไฟล์ log
บนอุปกรณ์จริงหลังปัดแอปทิ้ง — **การมีเครื่องมือวัดที่ทำงานได้ กับการเห็นแอป
ฟื้นเองจริง เป็นคนละเรื่องกัน** จนกว่าจะเห็นบรรทัดนั้น B5 ยังเป็น
`code-complete, unverified`
