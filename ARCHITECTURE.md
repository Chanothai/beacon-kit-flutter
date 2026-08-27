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
