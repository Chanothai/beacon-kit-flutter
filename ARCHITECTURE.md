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
  /// OS ถอดรหัสมาให้แล้ว (iOS CoreLocation ranging) — ibeacon*/proximity การันตี
  /// ว่ามีค่า, raw/rawBytes ว่างเสมอ
  osDecoded,

  /// ได้ byte ดิบมาแล้ว Dart parser ถอดเอง (iOS CoreBluetooth + Android
  /// BluetoothLeScanner) — rawBytes การันตีว่ามี, ibeacon* มีก็ต่อเมื่อ parse สำเร็จ
  rawParsed,
}
// ⚠️ ชื่อค่าเปลี่ยนแล้วใน ADR-13 (31 ส.ค. 2026) — เดิมคือ coreLocation /
// coreBluetooth / android ซึ่งตั้งชื่อตาม API ของ iOS ปนกับชื่อแพลตฟอร์ม
// ดูเหตุผลการเปลี่ยนและการยุบ 3 ค่าเหลือ 2 ที่ ADR-13 หัวข้อ 5

/// ค่า proximity ที่ CoreLocation คำนวณให้ (ระยะห่างโดยประมาณจาก RSSI/txPower ภายใน
/// ของ OS เอง) ไม่มีทางเทียบเท่าฝั่ง Android/Dart parser เพราะไม่ใช่ field ที่ decode
/// ได้จาก byte ของ ADV — มีค่าเฉพาะ source == osDecoded เท่านั้น
enum BeaconProximity { unknown, immediate, near, far }

class BeaconAdvertisement {
  // ---- ระบุตัวตน (ดู ADR-1) ----
  final BeaconDeviceId deviceId;
  final int rssi; // dBm, ค่าดิบจาก OS ไม่ผ่านการแปลง
  final AdvertisementSource source;
  final DateTime timestamp; // UTC, เวลาที่ Dart layer ได้รับ event (ไม่ใช่เวลา broadcast จริง)

  // ---- iBeacon-typed fields ----
  // มีค่าการันตีเมื่อ source == osDecoded เสมอ
  // มีค่าแบบไม่การันตีเมื่อ source == android และ IBeaconParser.parse() สำเร็จ (ADR-3)
  // เป็น null เสมอเมื่อ source == rawParsed (iOS มองไม่เห็น iBeacon ทาง CoreBluetooth)
  final String? ibeaconUuid; // lowercase, hyphenated (8-4-4-4-12)
  final int? ibeaconMajor; // 0-65535
  final int? ibeaconMinor; // 0-65535
  final int? ibeaconTxPower; // measured power @ 1m, signed 8-bit dBm — null เสมอเมื่อ source == osDecoded
  final BeaconProximity? proximity; // มีค่าเฉพาะ source == osDecoded

  // ---- raw decoded payload: มาจาก Dart parser (EddystoneParser ฯลฯ) ----
  final Map<String, dynamic> raw; // เช่น {'eddystone': EddystoneUidFrame(...)} — ว่างเสมอเมื่อ source == osDecoded
  final Uint8List? rawBytes; // raw service/manufacturer bytes ก่อน parse, null เมื่อ source == osDecoded — เก็บไว้ debug/forward-compat

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
///   AdvertisementSource.osDecoded)
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
- `beacon_kit_ios` (Dart) เป็นคน flatten `List` → `BeaconAdvertisement` ทีละตัว (`AdvertisementSource.osDecoded`) ก่อนส่งต่อ — ไม่ flatten ที่ Swift เพื่อให้ native code เรียบง่าย ตรงกับ native callback 1:1 (ลด surface ของบั๊กฝั่ง Swift ซึ่งแก้ยากกว่าฝั่ง Dart)

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

- ~~`packages/beacon_kit/pubspec.yaml` **ไม่มี** `flutter.plugin.platforms.android` เลย~~ **แก้แล้วใน ADR-13 (31 ส.ค. 2026)** — ตอนนี้ endorse `android.default_package: beacon_kit_android` แล้ว ขอบเขตคือสแกนตอนแอปเปิดอยู่เท่านั้น
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

#### ✅ ปิดจบแล้ว: "ผู้ใช้ปัดแอปทิ้งเองแล้วยังถูกปลุกไหม" (อัปเดต 30 ส.ค. 2026)

ตอนเขียน ADR นี้ยังเหลือข้อสงสัยว่า เอกสารที่อ้างข้างบนพูดถึง "terminated app"
ซึ่ง**อาจหมายถึงเฉพาะกรณีที่ระบบ terminate เอง** ไม่รวมกรณีที่ผู้ใช้ปัดแอปทิ้งจาก
app switcher (บางฟีเจอร์ของ iOS ถือว่า force-quit คือเจตนาของผู้ใช้ที่จะให้แอปหยุด
ทำงานถาวร และจะไม่ปลุกให้อีก) — ตอนนี้ปิดจบแล้วด้วยหลักฐานสองชั้น

**(1) จาก SDK header โดยตรง** — `CLLocationManager.h:492-496` (iPhoneOS26.5.sdk)
ในคำอธิบายของ `requestAlwaysAuthorization`:

> "monitoring APIs may launch your app into the background when they detect an
> event. **Even if killed by the user, launch events triggered by monitoring APIs
> will cause a relaunch.**"

ประโยค "Even if killed by the user" ตอบคำถามนี้ตรงตัว ไม่ต้องตีความ

**(2) จากการทดสอบบนอุปกรณ์จริง 30 ส.ค. 2026** — ทดสอบ 2 รอบด้วย release/profile
build หลังลบแอปติดตั้งใหม่ **ปัดแอปทิ้งจาก app switcher** แล้วกระตุ้น event: iOS
ปลุก process ขึ้นมาส่ง region event จริงทั้งสองรอบ (exit 55/30 วินาที, enter 5/3
วินาที) log ยืนยัน `everActive=false` + `state=background` ทั้งสองรอบ
รายละเอียดเต็มใน `docs/test-checklists/ios_broadcast_scanning.md` ข้อ 12

**ยังไม่ปิด:** กรณี**ระบบฆ่าแอปเองเพราะหน่วยความจำ** — เป็นคนละเส้นทางของ OS และ
เกิดบ่อยกว่า force-quit ในการใช้งานจริง ยังไม่มีใครทดสอบ ห้ามเหมารวมว่าผ่านด้วย

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

**สถานะ:** ตัดสินใจแล้ว · โค้ดเสร็จแล้ว · ✅ **ยืนยันบนอุปกรณ์จริงแล้ว 30 ส.ค. 2026**
(ทดสอบ 2 รอบ release/profile, force-quit โดยผู้ใช้ — ดูเช็คลิสต์ข้อ 12)
**ขอบเขต:** ยังไม่ครอบคลุมกรณีระบบฆ่าแอปเองจากหน่วยความจำ

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
ฟื้นเองจริง เป็นคนละเรื่องกัน**

**อัปเดต 30 ส.ค. 2026: เห็นแล้ว** ทดสอบ 2 รอบ log ยืนยัน `everActive=false` +
`state=background` ทั้ง exit และ enter ทั้งสองรอบ → B5 เปลี่ยนจาก
`code-complete, unverified` เป็น **verified เฉพาะเคส force-quit**

### 6. ผลข้างเคียงที่ไม่ได้คาดไว้: `launchKey` ไม่ทำงานในสภาพแวดล้อมนี้

ทั้งสองรอบที่ผ่าน log บันทึก `launchKey=false` — `UIApplication.LaunchOptionsKey.location`
**ไม่ถูกเซ็ต** แม้แอปจะถูกปลุกจากสถานะ terminated จริง

นี่ทำให้การตัดสินใจใน ADR นี้ที่ให้ `everActive` เป็นตัวตัดสินหลัก (และให้ launch key
เป็นแค่หลักฐานสนับสนุน) กลายเป็นสิ่งที่**จำเป็น ไม่ใช่แค่การป้องกันเผื่อไว้** — ถ้าใช้
launch key เป็นสัญญาณเดียวตามแนวทางคลาสสิก B5 จะถูกรายงานว่าไม่ผ่านทั้งที่ผ่าน

**สาเหตุยังเป็น open question ห้ามสรุป** — สองสมมติฐานที่ยังไม่ได้พิสูจน์ว่าเป็นข้อไหน:

- **(ก)** key ถูก deprecated ใน iOS 26 (`UIApplication.h:586`) แล้วระบบเลิกเซ็ตให้
  — แต่ deprecated ตามปกติแปลว่า "ยังทำงานแต่เลิกแนะนำ" ไม่ใช่ "หยุดทำงาน" ยังไม่พบ
  เอกสารที่ระบุว่าหยุดเซ็ตค่า
- **(ข)** แอปใช้ scene lifecycle ซึ่ง launch options เดินคนละเส้นทาง — ข้อความ
  deprecation เองพูดถึง "...to handle expected location events **after scene
  connection**" ซึ่งบอกเป็นนัยไปทางนี้ แต่ยังไม่ได้ทดสอบแอปที่ไม่ใช้ scene เพื่อเทียบ

จะพิสูจน์ได้ต้องทดสอบเทียบ (แอปที่ไม่ใช้ scene lifecycle / iOS ที่เก่ากว่า 26) ซึ่ง
**ไม่จำเป็นต่อการใช้งาน** เพราะเราไม่ได้พึ่ง key นี้อยู่แล้ว — บันทึกไว้เพราะใครก็ตาม
ที่เขียนโค้ดใหม่บนสมมติฐานคลาสสิกจะเจอปัญหานี้

> **หมายเหตุเพิ่ม 3 ก.ย. 2026 — ดู ADR-16:** พบว่า `hasEverBecomeActive` เองก็ค้าง
> `false` ตลอดชีพ process ด้วยสาเหตุคนละอันแต่เกี่ยวโยงกัน (ไม่ใช่แค่ `launchKey`) —
> ADR-16 มีคำตอบยืนยันจากเอกสาร Apple ทั้งสองเรื่อง (ทำไม `launchKey` เป็น `false`
> เสมอ และทำไม `everActive` ค้าง `false`) พร้อมทางแก้และผลต่อการตีความ log เก่า
> **ผลการทดสอบ B5 ที่บันทึก "ผ่าน" ในหัวข้อนี้ยังไม่ถูกเพิกถอน** แต่เหตุผลที่ใช้รองรับ
> ต้องอ่านใหม่ตาม ADR-16 หัวข้อ 3 — ห้ามอ่านแค่หัวข้อนี้เพียวๆ อีกต่อไป

---

## ADR-11: Region flapping — ข้อกำหนดเรื่อง debounce และการรวม session (เพิ่ม 31 ส.ค. 2026)

**สถานะ:** ตัดสินใจแล้วจากข้อมูลจริง 1 ชุด · **ยังไม่ implement** · ค่าที่เสนอเป็น
ค่าเริ่มต้นที่ต้องทบทวนเมื่อมีข้อมูลจากสาขาจริง

### 1. ปรากฏการณ์ที่เจอ

ทดสอบข้ามคืน 30-31 ส.ค. 2026: **มือถือวางนิ่งอยู่กับที่ จอดับ ล็อกเครื่อง แอปอยู่
เบื้องหลัง K9P วางนิ่งไม่ได้ถอดแบต ไม่มีใครขยับอะไรเลยทั้งคืน**

ผลใน 14 ชั่วโมง 6 นาที: **enter 86 ครั้ง / exit 86 ครั้ง**

ทั้งที่ไม่มีอะไรเคลื่อนไหวเลย — นี่คือ **region flapping** คือการที่ระบบรายงานว่า
เข้า-ออกโซนสลับไปมาทั้งที่ตำแหน่งจริงไม่เปลี่ยน

ไฟล์ดิบอยู่ที่ `docs/test-data/2026-08-30_overnight_region_flapping.log`
วิเคราะห์ซ้ำได้ด้วย `dart run tool/analyze_region_log.dart <ไฟล์>`

### 2. สาเหตุ — แยกสิ่งที่ยืนยันแล้วออกจากสมมติฐาน

**✅ ยืนยันจากข้อมูลของเราเอง**

การกระจายตัวของ "ช่วงที่อยู่ในโซน" (enter → exit ถัดไป) กองแน่นผิดปกติ:

| ช่วง | จำนวน | สัดส่วน |
|---|---|---|
| 29.5-30.5 วินาที | **37 จาก 85** | **43.5%** |
| 30-60 วินาที (รวมช่วงบน) | 45 | 52.9% |

การที่เกือบครึ่งหนึ่งของช่วงตกอยู่ในหน้าต่างกว้าง 1 วินาทีเดียวกันแบบนี้
**ไม่ใช่ความบังเอิญ** — บ่งชี้ว่ามี**ค่าหน่วงคงที่ราว 30 วินาที**ก่อนระบบประกาศ
exit นั่นคือสัญญาณหายไปแทบจะทันทีหลัง enter แล้วระบบรอครบ ~30 วินาทีจึงประกาศ

**นัยสำคัญ:** flap ทั้ง 86 ครั้งนี้จึงไม่ใช่ noise ชั่วขณะระดับมิลลิวินาที แต่คือ
**สัญญาณหายจริงนานพอที่จะผ่านตัวกรองของระบบไปแล้ว** — การไปเขียนตัวกรองระดับ
"กันสัญญาณกระพริบ" ทับอีกชั้นจึงแก้ไม่ตรงจุด ต้องกรองที่ระดับ**นาที** ไม่ใช่วินาที

**⚠️ ตรวจแล้วไม่พบ citation จาก Apple สำหรับตัวเลข 30 วินาที**
ค้นทั้ง `CLRegion.h`, `CLBeaconRegion.h`, `CLLocationManager.h` (iPhoneOS26.5.sdk)
และหน้าเอกสาร `locationManager(_:didExitRegion:)` กับ
"Monitoring the user's proximity to geographic regions" — **ไม่มีหน้าไหนระบุเวลาหน่วง
ก่อนประกาศ exit หรือบอกว่าปรับได้/ไม่ได้** ตัวเลข ~30 วินาทีนี้จึงเป็น
**ค่าที่เราวัดได้เอง ไม่ใช่ค่าที่ Apple ประกาศ** และไม่มีอะไรรับประกันว่าจะเท่าเดิม
ในอุปกรณ์อื่นหรือ iOS เวอร์ชันอื่น — ห้าม hard-code ตัวเลขนี้ในโค้ดโดยอ้างว่าเป็น
สเปกของแพลตฟอร์ม

**🔶 สมมติฐานที่ยังไม่ได้พิสูจน์ — ห้ามเขียนเป็นข้อเท็จจริง**

| สมมติฐาน | สถานะการตรวจสอบ |
|---|---|
| RSSI แกว่งจนข้ามเกณฑ์เข้า-ออกไปมา | สมเหตุสมผลแต่**ยังไม่ได้วัด** — log ปัจจุบันไม่บันทึก RSSI ตอน enter/exit เลย (region monitoring ไม่ให้ RSSI มาด้วย ต้องเปิด ranging คู่กันถึงจะได้) |
| K9P กระจายทุก 1000 ms ซึ่งช้ากว่า beacon ทั่วไป (100-500 ms) จึงพลาดง่ายกว่า | **ยืนยันไม่ได้** — `docs/sources/kkm_k9p.md` ไม่มีข้อมูล advertising interval เลย และเอกสาร protocol สาธารณะของผู้ผลิตเป็น 404 (บันทึกไว้ในหัวข้อ "ไม่พบ / ไม่ยืนยัน" ของไฟล์นั้น) ต้องได้ datasheet หรืออ่านค่าจากอุปกรณ์จริงก่อน |
| iOS ลดความถี่การสแกนตอนเครื่องหลับ | **ไม่พบเอกสาร Apple ที่ระบุตรง ๆ** ค้นแล้วในเอกสาร region monitoring และ header |

ทั้งสามข้ออาจถูกทั้งหมด แต่ **ยังไม่มีข้อไหนที่เรายืนยันเองได้** — บันทึกไว้เป็น
ทิศทางการสืบต่อ ไม่ใช่คำอธิบายที่สรุปแล้ว

### 3. รูปแบบของ flap ที่พบ (ข้อมูลประกอบ)

| สถิติ | ช่วงที่อยู่ในโซน | ช่วงที่หลุดออก |
|---|---|---|
| จำนวน | 85 | 86 |
| ต่ำสุด | 0.3 วินาที | 1 มิลลิวินาที |
| มัธยฐาน | 30.1 วินาที | 25.2 วินาที |
| เปอร์เซ็นไทล์ 90 | 1 นาที 56 วินาที | 1 นาที 30 วินาที |
| **สูงสุด** | 3 ชั่วโมง 10 นาที | **3 นาที 29 วินาที** |

**ตัวเลขที่สำคัญที่สุดคือ "ช่วงที่หลุดออกนานที่สุด = 3 นาที 29 วินาที"** — ทั้งคืน
ไม่มีสักครั้งที่หลุดออกนานเกินนั้น ค่านี้เป็นฐานของข้อเสนอ debounce ในหัวข้อ 5

**การกระจุกตัวตามเวลา:** flap เกือบทั้งหมดเกิดในช่วง 05:00-07:00 (75 จาก 86 ครั้ง)
ส่วนช่วง 18:00-05:00 มีแค่ 6 ครั้ง โดยมีช่วงนิ่งยาว 2-3 ชั่วโมงติดกันหลายช่วง
**ยังไม่รู้ว่าอะไรทำให้เปลี่ยน** — สมมติฐานที่ยังไม่ตรวจ: มีคนหรือสิ่งของขยับในห้อง
ตอนเช้า, อุณหภูมิ/ความชื้นเปลี่ยน, แรงดันแบต K9P ตก, หรือสถานะเครื่องเปลี่ยน
(นาฬิกาปลุก/การ refresh ตอนเช้า) — ต้องบันทึกสภาพแวดล้อมให้ละเอียดกว่านี้ในรอบหน้า

**event ที่เป็นผลของการส่งค้าง ไม่ใช่การเข้า/ออกจริง:** พบคู่ที่ห่างกันไม่ถึง 1
วินาที **15 คู่** (บางคู่ห่างกัน 4 มิลลิวินาที) ซึ่งเป็นไปไม่ได้ทางกายภาพ —
timestamp ในไฟล์คือ**เวลาที่แอปได้รับ event** ไม่ใช่เวลาที่ข้ามขอบเขตจริง ระบบคิว
event ไว้แล้วส่งมาติด ๆ กัน โดยเฉพาะตอน process เพิ่งถูกปลุกขึ้นมา

⚠️ **จำนวนที่รายงานได้หลายค่า ต้องระบุทุกครั้งว่าใช้แบบไหน:** นับ enter ดิบทุกบรรทัด
= **86** · ตัด artifact ข้างบนออก = **71** · ช่วงที่มี exit ปิดครบคู่ = **85**

### 4. ผลกระทบทางธุรกิจ

ถ้ายิง event ตรงไป backend ทุกครั้งที่ได้ `didEnterRegion`:

**ลูกค้าหนึ่งคนที่นอนหลับใกล้ beacon จะสร้างเหตุการณ์ "เข้าสาขา" 86 ครั้งในคืนเดียว
โดยไม่ได้ขยับเลยแม้แต่ก้าวเดียว**

ผลที่ตามมา — ไม่ใช่แค่ตัวเลขเพี้ยน:

- **สถิติผู้เข้าสาขาพองเกินจริงหลายสิบเท่า** และไม่มีใครรู้ตัวจนกว่าจะไปเทียบกับ
  ข้อมูลจากแหล่งอื่น (เครื่องนับคนหน้าประตู, ยอดขาย)
- **ถ้ามี push notification ผูกกับการเข้าสาขา ลูกค้าจะได้ 86 ครั้งในคืนเดียว** →
  ปิด notification ทิ้ง หรือลบแอป
- ค่าใช้จ่าย API/traffic ที่ไม่จำเป็น
- ข้อมูลพฤติกรรมที่ผิดจะไหลไปถึงการตัดสินใจทางธุรกิจ ซึ่งแก้ย้อนหลังยากที่สุด

### 5. ค่าที่เสนอ — คำนวณย้อนกลับจากข้อมูลจริง

**(ก) "exit แล้ว enter ใหม่ภายในกี่นาทีถือเป็น session เดิม" → เสนอ 5 นาที**

ที่มา: **ช่วงที่หลุดออกนานที่สุดตลอดทั้งคืนคือ 3 นาที 29 วินาที** และเปอร์เซ็นไทล์
90 อยู่ที่ 1 นาที 30 วินาที — ค่า 5 นาทีจึงครอบคลุมทุกช่วงที่วัดได้จริงพร้อมส่วนเผื่อ
ประมาณ 43% เหนือค่าที่แย่ที่สุด

**(ข) "ต้องอยู่ต่อเนื่องกี่นาทีถึงนับว่าเข้าสาขาจริง" → เสนอ 2 นาที**

ที่มา: **เปอร์เซ็นไทล์ 90 ของช่วงที่อยู่ในโซนคือ 1 นาที 56 วินาที** — เกณฑ์ 2 นาที
จึงตัด flap ทิ้งได้ประมาณ 90% แม้กลไกรวม session ในข้อ (ก) จะล้มเหลว
เป็น**ชั้นป้องกันที่สอง** ไม่ใช่ตัวหลัก

### 6. ผลถ้าใช้ค่าที่เสนอกับข้อมูลจริง (คำนวณย้อนกลับ)

ลำดับการคำนวณ: **รวม session ก่อน แล้วค่อยกรองด้วยเวลา** — ถ้ากรองก่อน ช่วงสั้น ๆ
ที่ต่อเนื่องกันจะถูกตัดทิ้งทีละอันทั้งที่รวมกันแล้วนานพอ

| รวม session ถ้าห่างน้อยกว่า | ต้องอยู่อย่างน้อย | เหลือกี่ครั้ง |
|---|---|---|
| ไม่ทำอะไรเลย | — | **85** |
| 1 นาที | ไม่กำหนด | 23 |
| 1 นาที | 2 นาที | 10 |
| 2 นาที | 2 นาที | 4 |
| 3 นาที | 2 นาที | 2 |
| 4 นาที | ไม่กำหนด | 1 |
| **5 นาที** | **2 นาที** | **1** ✅ |

**85 ครั้ง → 1 ครั้ง** ซึ่งตรงกับความจริงที่ว่าคืนนั้นมีการ "อยู่ในบริเวณ" ครั้งเดียว
ยาวต่อเนื่อง

ตารางนี้สร้างจาก `dart run tool/analyze_region_log.dart` ทำซ้ำได้ทุกเมื่อ

**ราคาที่ต้องจ่าย ต้องให้ฝ่ายธุรกิจตัดสิน ไม่ใช่ทีมพัฒนา:**

- ค่า (ก) 5 นาที แปลว่า **ลูกค้าที่ออกจากสาขาแล้วกลับเข้ามาใหม่ภายใน 5 นาที จะนับ
  เป็นการเข้าครั้งเดียว** — สำหรับความหมาย "มาเยือนสาขา" ถือว่าถูกต้อง แต่ถ้าธุรกิจ
  ต้องการนับ "จำนวนครั้งที่เดินผ่านประตู" จะนับขาด
- ค่า (ข) 2 นาที แปลว่า **ลูกค้าที่แวะซื้อของเร็วมากแล้วออกภายใน 2 นาที จะไม่ถูก
  นับเลย** — ในทางกลับกันมันก็กันคนที่แค่เดินผ่านหน้าร้านไม่ให้ถูกนับ

ทั้งสองค่าเป็น**การตัดสินใจทางธุรกิจที่ตั้งอยู่บนข้อมูลเทคนิค** ไม่ใช่ค่าที่ถูก/ผิด
ทางเทคนิคล้วน

### 7. ข้อกำหนด: ต้องมีชั้น debounce เสมอ และอยู่ที่ไหน

**ข้อกำหนด:** ห้ามให้ `didEnterRegion` ดิบไหลไปถึง business logic หรือ backend
โดยไม่ผ่านชั้น debounce — ไม่ว่าจะทำที่ชั้นไหนก็ตาม

**ตัดสินใจว่าอยู่ชั้นไหน:**

| ชั้น | ประเมิน |
|---|---|
| **ใน SDK (`beacon_kit`) — บังคับ** | ❌ **ไม่เอา** SDK มีหน้าที่รายงานสิ่งที่แพลตฟอร์มบอกอย่างซื่อสัตย์ ถ้า SDK กลืน event ทิ้งเอง ผู้ใช้ SDK จะดีบักไม่ได้เลยว่า event หายไปไหน และเราเพิ่งเสียเวลาไปทั้งรอบทดสอบกับปัญหา "ระบบเงียบแล้วไม่รู้ว่าเงียบเพราะอะไร" มาแล้ว (ADR-10) · อีกทั้งค่าที่เหมาะสมขึ้นกับ use case ซึ่ง SDK ไม่รู้ |
| **ใน SDK — เป็น utility ที่เลือกใช้ได้** | ✅ **เอา** ให้ `beacon_kit_platform_interface` มี usecase แบบ pure Dart (เช่น `DebounceRegionEvents`) ที่รับ stream ดิบแล้วคืน stream ที่ผ่านการรวม session — **ผู้ใช้เลือกเองว่าจะต่อหรือไม่ต่อ** stream ดิบยังเข้าถึงได้เสมอ · เป็น pure Dart จึงมี unit test คลุมได้จริงตาม ADR-7 |
| **ในแอปที่เรียกใช้** | ✅ **ที่นี่คือที่ที่ตัดสินใจ** แอปเป็นคนรู้ว่า "เข้าสาขา" ในเชิงธุรกิจแปลว่าอะไร และเป็นคนถือค่า config · ให้แอปเรียก utility ข้างบน |
| **ที่ backend** | ⚠️ **จำเป็นแต่ไม่พอ** ต้องมีเป็นชั้นสุดท้ายกันแอปเวอร์ชันเก่าที่ยังไม่มี debounce ยิงเข้ามา แต่ถ้าพึ่งชั้นนี้อย่างเดียว traffic และแบตของเครื่องลูกค้าจะถูกใช้ไปแล้ว และ push notification ที่ยิงจากฝั่งแอปจะเล็ดลอดไปก่อน |

**สรุป: กรองสองชั้น** — ในแอป (ผ่าน utility ของ SDK) เป็นชั้นหลัก + ที่ backend เป็น
ชั้นกันพลาด **และ SDK ต้องไม่กรองให้เองโดยอัตโนมัติ**

### 8. ⚠️ ข้อจำกัดของข้อมูลชุดนี้ — อ่านก่อนเอาตัวเลขไปใช้

- **การทดสอบคืนเดียว สถานที่เดียว เครื่องเดียว beacon ตัวเดียว** ไม่มีการทำซ้ำ
- **เป็นสภาพสัญญาณก้ำกึ่ง** (borderline) — มือถืออยู่ในระยะที่สัญญาณเข้า ๆ ออก ๆ พอดี
  ซึ่งเป็นสภาพที่ทำให้เกิด flap มากที่สุด **ค่าที่ได้จึงเป็นกรณีที่แย่กว่าปกติ
  ไม่ใช่ค่ามาตรฐาน** ถ้ามือถืออยู่ใกล้ beacon ชัดเจนหรือไกลชัดเจน จะไม่เห็น flap
  แบบนี้
- **ไม่ได้บันทึกระยะทาง สิ่งกีดขวาง หรือ RSSI** จึงไม่รู้ว่า "ก้ำกึ่ง" คือกี่เมตร
- ยังไม่รู้ว่าสภาพในสาขาจริง (คนเดินผ่าน ชั้นวางของโลหะ beacon หลายตัว) จะให้ผล
  แย่กว่าหรือดีกว่านี้

**ต้องเก็บข้อมูลในสาขาจริงอย่างน้อย 3 จุดที่มีสภาพต่างกันก่อนล็อกค่าเหล่านี้ลง
production** — ค่าในหัวข้อ 5 ใช้เป็น**ค่าเริ่มต้นสำหรับทดสอบ**เท่านั้น
วิธีเก็บอยู่ในเช็คลิสต์ข้อ 16

---

## ADR-12: Android ก้อนที่ 1 — สแกนตอนแอปเปิดอยู่ (เพิ่ม 31 ส.ค. 2026)

**สถานะ:** ✅ ค้นคว้าเสร็จ (หัวข้อ 1-4) · 🛑 **หยุดก่อนเขียนโค้ด** เพราะพบว่าไม่มี
"สัญญากลาง" ให้ implement (หัวข้อ 5) — ต้องให้ผู้ถือโปรเจกต์ตัดสินก่อน

**ขอบเขต:** เฉพาะการสแกนตอนแอปเปิดอยู่ (foreground) — ส่วนทำงานเบื้องหลังเป็นก้อน
แยกที่จะทำหลังก้อนนี้เสร็จ ADR นี้จึงตอบเฉพาะสิ่งที่ก้อนที่ 1 ต้องรู้ บวกกับ
บันทึกเรื่อง `PendingIntent` ไว้ล่วงหน้า

**เครื่องทดสอบเป้าหมาย:** Redmi Note 9 · Android 12 (MIUI)

### 1. สิทธิ์ที่ต้องประกาศและขอตอนรันบน Android 12

**ยืนยันจากซอร์สจริงในเครื่อง** (`~/Library/Android/sdk/sources/android-37.0/`)
และเอกสารทางการ ตาม CONTRIBUTING ข้อ 5

**(ก) `BLUETOOTH_SCAN` — บังคับ และเป็น runtime permission**

จาก `android/bluetooth/le/BluetoothLeScanner.java:113-115`:

> "This method requires the calling app to have the
> `android.Manifest.permission#BLUETOOTH_SCAN` permission."

annotation จริงบนเมธอด (บรรทัด 122-127):

```java
@RequiresLegacyBluetoothAdminPermission
@RequiresBluetoothScanPermission
@RequiresBluetoothLocationPermission
@RequiresPermission(allOf = {BLUETOOTH_PRIVILEGED, BLUETOOTH_SCAN}, ...)
```

เอกสารทางการยืนยันว่าเป็น runtime permission:

> "The `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, and `BLUETOOTH_SCAN` permissions
> are **runtime permissions**. Therefore, you must explicitly request user approval
> in your app before you can look for Bluetooth devices..."
> — [Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)

**(ข) `ACCESS_FINE_LOCATION` — ยังต้องมี เพราะ use case ของเราคือการอนุมานตำแหน่ง**

จาก `BluetoothLeScanner.java:109-112`:

> "An app must have `ACCESS_COARSE_LOCATION` permission in order to get results.
> An App targeting Android Q or later must have `ACCESS_FINE_LOCATION` permission
> in order to get results."

**⚠️ กับดักที่สำคัญที่สุดของหัวข้อนี้ — `neverForLocation`**

เอกสารทางการเสนอทางลัดว่าถ้าแอปไม่ได้ใช้ผลสแกนอนุมานตำแหน่ง ให้ประกาศ:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
                 android:usesPermissionFlags="neverForLocation" />
```

แล้วจะไม่ต้องขอ `ACCESS_FINE_LOCATION` เลย — **แต่เอกสารหน้าเดียวกันเตือนไว้ว่า:**

> "If you include `neverForLocation` in your `android:usesPermissionFlags`,
> **some BLE beacons are filtered from the scan results.**"

**สรุปสำหรับโปรเจกต์นี้: ห้ามใช้ `neverForLocation` เด็ดขาด** — จุดประสงค์ทั้งหมด
ของ `beacon_kit` คือการอนุมานว่าผู้ใช้อยู่สาขาไหน ซึ่งคือการอนุมานตำแหน่งตรงตัว
การใส่ flag นี้จะทั้ง**ผิดความจริง**ที่ประกาศต่อระบบ และ**ทำให้ beacon บางตัวถูก
กรองทิ้ง**จนอาการออกมาเป็น "สแกนไม่เจอบางตัว" ที่ดีบักยากมาก

**(ค) `BLUETOOTH_CONNECT` — ก้อนที่ 1 ยังไม่ต้องใช้**

`BLUETOOTH_CONNECT` ใช้สำหรับสื่อสารกับอุปกรณ์ที่จับคู่แล้ว ไม่ใช่การสแกน —
ก้อนที่ 1 ไม่ต้องประกาศ ส่วน GATT connect/config ยังไม่ implement ทั้งสองแพลตฟอร์ม
(README) เมื่อถึงตอนนั้นค่อยเพิ่ม

**(ง) ความสัมพันธ์ระหว่างกัน — สรุปเป็นตาราง**

| สิทธิ์ | ก้อนที่ 1 ต้องมีไหม | ประเภท | หมายเหตุ |
|---|---|---|---|
| `BLUETOOTH_SCAN` | ✅ ต้องมี | runtime (ต้องขอตอนรัน) | **ห้ามใส่ `neverForLocation`** |
| `ACCESS_FINE_LOCATION` | ✅ ต้องมี | runtime | เพราะเราอนุมานตำแหน่งจริง |
| `BLUETOOTH_CONNECT` | ❌ ยังไม่ต้อง | runtime | ไว้ตอนทำ GATT |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` (เก่า) | เฉพาะ `maxSdkVersion="30"` | install-time | สำหรับเครื่องที่ต่ำกว่า Android 12 |

**🔶 ยังไม่ยืนยัน — ต้องทดสอบบนเครื่องจริง:** ผู้ใช้ต้องเปิดสวิตช์ Location
ของระบบด้วยหรือไม่ (คนละเรื่องกับการ grant `ACCESS_FINE_LOCATION`) — ไม่พบประโยค
ที่ระบุตรง ๆ ในเอกสารที่ตรวจ ให้ทดสอบบน Redmi Note 9 แล้วบันทึกผล

### 2. การ throttle การสแกนในเบื้องหลัง

**✅ ยืนยันแล้ว 2 ข้อ จากซอร์สจริง**

**(ก) แอปที่ไม่ได้อยู่ foreground ถูกบังคับเป็นโหมดประหยัดพลังงาน**

`android/bluetooth/le/ScanSettings.java:48-52`:

> "Perform Bluetooth LE scan in low power mode. This is the default scan mode as it
> consumes the least power. **This mode is enforced if the scanning application is
> not in foreground.**"

แปลว่าต่อให้แอปขอ `SCAN_MODE_LOW_LATENCY` ระบบจะบังคับลดเป็น `SCAN_MODE_LOW_POWER`
ทันทีที่แอปไม่ได้อยู่ foreground — **ผลคือความถี่ที่ได้ผลสแกนลดลงอย่างมีนัยสำคัญ**
นี่เป็นเหตุผลตรง ๆ ที่ก้อนที่ 2 (เบื้องหลัง) ต้องออกแบบต่างจากก้อนที่ 1 ไม่ใช่แค่
"เอาโค้ดเดิมไปรันตอน background"

**(ข) สแกนแบบไม่มี filter จะถูกหยุดเมื่อจอดับ**

`BluetoothLeScanner.java:104-107`:

> "For unfiltered scans, **scanning is stopped on screen off** to save power.
> Scanning is resumed when screen is turned on again. To avoid this, use
> `startScan(List, ScanSettings, ScanCallback)` with desired `ScanFilter`."

**ผลต่อการออกแบบ: ต้องส่ง `ScanFilter` เสมอ ห้ามสแกนแบบไม่มี filter** — ตรงกับ
แนวทางที่ฝั่ง iOS ทำอยู่แล้ว (`startBluetoothScan` ไม่มี wildcard scan ตาม ADR-4)

**(ค) มี error code สำหรับ "สแกนถี่เกินไป"**

`android/bluetooth/le/ScanCallback.java:62-63`:

> "Fails to start scan as application tries to scan too frequently."
> `public static final int SCAN_FAILED_SCANNING_TOO_FREQUENTLY = 6;`

**🔶 แต่ตัวเลขจริงยังไม่ยืนยัน** — ตัวเลขที่พูดถึงกันทั่วไป ("เริ่ม/หยุดสแกนได้ไม่
เกิน 5 ครั้งใน 30 วินาที") **ไม่พบในเอกสารทางการหรือในซอร์สที่ตรวจได้ในเครื่อง**
ค่าจริงอยู่ในโค้ดของ Bluetooth apex (`ScanManager`/`AppScanStats`) ซึ่งไม่ได้มาพร้อม
Android SDK — **ห้ามเขียนตัวเลขนี้ลงเอกสารหรือ hard-code ในโค้ดโดยอ้างว่าเป็นสเปก**
สิ่งที่ทำได้แน่นอนคือ **ดัก `SCAN_FAILED_SCANNING_TOO_FREQUENTLY` แล้วรายงานเป็น
error code ที่มีความหมาย** แทนการเงียบ

**(ง) ข้อจำกัดที่กระทบก้อนที่ 2 โดยตรง (บันทึกไว้ก่อน)**

> "Apps that target Android 12 or higher can't start foreground services while
> running in the background, except for a few special cases. If an app attempts to
> start a foreground service while running in the background, an exception occurs."
> — [Behavior changes: Android 12](https://developer.android.com/about/versions/12/behavior-changes-12)

### 3. `PendingIntent` mutability บน Android 12 (บันทึกไว้ก่อน ก้อนที่ 1 ยังไม่ใช้)

> "If your app targets Android 12, you must **specify the mutability of each
> `PendingIntent` object that your app creates.** This additional requirement
> improves your app's security."
> — [Behavior changes: Android 12](https://developer.android.com/about/versions/12/behavior-changes-12)

วิธีตรวจว่าพลาดหรือไม่ (เอกสารหน้าเดียวกัน):

> "Warning: Missing PendingIntent mutability flag [UnspecifiedImmutableFlag]"

**เกี่ยวกับเราตรงไหน:** ก้อนที่ 2 ถ้าเลือกใช้
`BluetoothLeScanner.startScan(List, ScanSettings, PendingIntent)` (API ที่ ADR-9
ยกมาเป็นตัวเลือกสำหรับ background) จะต้องสร้าง `PendingIntent` ซึ่งบังคับระบุ
mutability ทันที

**🔶 ต้องตรวจก่อนใช้จริง:** ยังไม่ได้ยืนยันว่าเคสนี้ต้องใช้ `FLAG_MUTABLE` หรือ
`FLAG_IMMUTABLE` — โดยหลักการ `PendingIntent` ที่ระบบต้องเติมข้อมูลผลสแกนเข้ามา
มักต้องเป็น mutable แต่**ยังไม่พบเอกสารที่ระบุตรง ๆ สำหรับ `startScan` เคสนี้**
ต้องยืนยันก่อนเขียนโค้ดก้อนที่ 2

หมายเหตุอีกข้อจาก `BluetoothLeScanner.java:384-387`: ตอน `stopScan(PendingIntent)`
> "When creating the PendingIntent parameter, please do not use the
> `FLAG_CANCEL_CURRENT` flag. Otherwise, the stop scan may have no effect."

### 4. ตอบ open question ของ ADR-9 ได้บางส่วนแล้ว

| คำถามจาก ADR-9 | ตอบได้หรือยัง |
|---|---|
| ข้อจำกัด background scan throttling มีผลแค่ไหน | **ตอบแล้วบางส่วน** — บังคับ `SCAN_MODE_LOW_POWER` เมื่อไม่ได้อยู่ foreground + สแกนไม่มี filter หยุดเมื่อจอดับ (หัวข้อ 2) ส่วนตัวเลขการ throttle ยังไม่ยืนยัน |
| Android เก็บชุด region ข้าม process แบบ `monitoredRegions` หรือไม่ | **ยังไม่ตอบ** — เป็นเรื่องของก้อนที่ 2 |
| มี enter/exit semantics หรือต้องคำนวณเอง | **ยังไม่ตอบ** — ก้อนที่ 2 |
| พฤติกรรมหลังผู้ใช้ force-stop แอป | **ยังไม่ตอบ** — ก้อนที่ 2 |

### 5. 🛑 สิ่งที่พบแล้วต้องหยุด: **ไม่มี "สัญญากลาง" ให้ implement**

โจทย์ระบุว่า `beacon_kit_android` ต้อง "implement ตามสัญญาที่
`beacon_kit_platform_interface` กำหนดไว้ ห้ามแก้สัญญากลาง" — **ตรวจแล้วพบว่า
`beacon_kit_platform_interface` ไม่ได้กำหนดสัญญาของ platform ไว้เลย**

**หลักฐาน**

`beacon_kit_platform_interface/lib/` มีแค่ 3 กลุ่ม ไม่มี abstract class ของ platform
สักตัว:

| กลุ่ม | ไฟล์ | เป็นสัญญาของ platform ไหม |
|---|---|---|
| entities | `beacon_advertisement.dart`, `ibeacon_frame.dart`, `eddystone_frame.dart`, … | ❌ เป็น data type |
| parsers | `ibeacon_parser.dart`, `eddystone_parser.dart` | ❌ เป็น pure logic |
| usecases | `plan_region_registration.dart`, `resolve_bigc_beacon_metadata.dart` | ❌ เป็น pure logic |

สัญญาจริงชื่อ **`BeaconKitIosPlatform`** และอยู่ใน **`beacon_kit_ios`**
(`packages/beacon_kit_ios/lib/src/beacon_kit_ios_platform.dart`)

และ facade ผูกกับ iOS ตรง ๆ — `generic_ibeacon_eddystone_adapter.dart:3`:

```dart
import 'package:beacon_kit_ios/beacon_kit_ios.dart';
```

`beacon_kit/pubspec.yaml` ก็ endorse เฉพาะ iOS:

```yaml
plugin:
  platforms:
    ios:
      default_package: beacon_kit_ios
```

**ทำไมถึงหยุดแทนที่จะเดินต่อ**

ทางเลือกที่เดินต่อได้โดยไม่ถามมีแค่สองแบบ และทั้งคู่แย่:

1. ให้ `beacon_kit_android` implement `BeaconKitIosPlatform` — แปลว่า package ของ
   Android ต้อง `dependency` บน package ของ iOS และสืบทอด method ที่ชื่อ
   `getIBeaconAuthorizationLevel` กับ `regionStateEvents` ที่นิยามด้วย semantic ของ
   CoreLocation ล้วน **ผิดชัดเจน**
2. สร้าง `BeaconKitAndroidPlatform` ขึ้นมาคู่ขนาน แล้วให้ adapter แตกเป็นสองทางตาม
   แพลตฟอร์ม — ได้ผลลัพธ์ที่ **demo ผ่าน** แต่ทำให้มีสัญญาสองชุดที่ drift จากกันได้
   และเป็นการฝัง `if (Platform.isAndroid)` ไว้ใน facade ซึ่งเป็นสิ่งที่ federated
   plugin pattern มีไว้เพื่อกำจัดตั้งแต่แรก

ADR-9 เขียนดักไว้แล้วว่าจุดนี้จะมาถึง:

> "เมื่อถึงเวลาทำ Android ถ้าพบว่าต้องมี contract กลางจริง **ให้ยกขึ้นไปที่
> `beacon_kit_platform_interface` พร้อมชื่อที่เป็นกลาง** แทนการดัด type ของ iOS
> ให้ครอบ Android"

นั่นคือทางที่ถูก แต่มันคือการ**แก้สัญญากลาง** ซึ่งโจทย์สั่งให้หยุดรายงานก่อน

**ทางเลือกที่เสนอ (รอการตัดสิน)**

| ทางเลือก | ทำอะไร | ผลต่อ iOS | ความเสี่ยง |
|---|---|---|---|
| **A. ยกสัญญาขึ้น platform interface** (ADR-9 แนะนำ) | สร้าง `BeaconKitPlatform` ใน `beacon_kit_platform_interface` ที่มีเฉพาะ **สิ่งที่ทั้งสองแพลตฟอร์มทำได้จริง** = `startBluetoothScan`/`stopBluetoothScan`/`rawAdvertisementEvents` · ส่วน iBeacon monitoring/region state/authorization level **คงไว้ที่ `beacon_kit_ios` ตามเดิม** เพราะเป็นความสามารถเฉพาะ iOS | ต้องแก้ `beacon_kit_ios` ให้ implement สัญญาใหม่เพิ่ม (ไม่ลบของเดิม) + แก้ adapter | ปานกลาง — มี test 80 ตัวคุมอยู่ |
| **B. คู่ขนาน ไม่แตะของกลาง** | `BeaconKitAndroidPlatform` แยก + adapter แตกสองทาง | ไม่แตะ | ต่ำตอนนี้ **แต่หนี้จะโตเร็ว** — สัญญาสองชุด drift ได้ |
| **C. เลื่อนก้อนที่ 1 ไปก่อน** | ทำ refactor สัญญาให้จบก่อนแล้วค่อยเริ่ม Android | — | เสียเวลา demo |

**คำแนะนำของผม: ทางเลือก A** — และขอบเขตของมันเล็กกว่าที่ฟังดู เพราะก้อนที่ 1 ต้องการ
แค่ 3 อย่าง (`startBluetoothScan` / `stopBluetoothScan` / `rawAdvertisementEvents`)
ซึ่งเป็น**เส้นทาง CoreBluetooth ฝั่ง iOS ที่ไม่ผูกกับ CoreLocation เลย** และมี
semantic ตรงกับ `BluetoothLeScanner` ของ Android แทบ 1:1 (ส่ง raw bytes กลับมาให้
Dart parser ถอด) — ส่วนที่ผูกกับ iOS จริง ๆ (region monitoring, authorization level)
**ไม่ต้องยกขึ้นมา** ปล่อยไว้ที่ `beacon_kit_ios` ตามที่ ADR-9 ตั้งใจ

### 6. ข้อจำกัดระดับผลิตภัณฑ์ของ MIUI (บันทึกไว้ตั้งแต่ตอนนี้)

**🔶 ยังไม่ยืนยันด้วยตัวเอง** — ยังไม่ได้รันบนเครื่องจริง และไม่พบเอกสารทางการของ
Xiaomi ที่อ้างอิงได้ บันทึกเป็นสิ่งที่**ต้องทดสอบ** ไม่ใช่ข้อเท็จจริงที่ยืนยันแล้ว

MIUI มีการจัดการพลังงานของตัวเองเพิ่มจาก Android มาตรฐาน ซึ่งอาจต้องให้ผู้ใช้
เปิด Autostart และตั้ง battery saver เป็นไม่จำกัดด้วยมือ ไม่งั้นแอปถูกฆ่า

**ถ้ายืนยันแล้วว่าจริง นี่คือข้อจำกัดระดับผลิตภัณฑ์ ไม่ใช่สิ่งที่แก้ได้ด้วยโค้ด** —
ไม่มี API ให้แอปเปิด Autostart ให้ตัวเอง ทางแก้เดียวคือ **UX ที่พาผู้ใช้ไปตั้งค่า**
(หน้าจออธิบาย + ปุ่มลัดไปหน้า setting ถ้าเปิดได้) ซึ่งต้องวางแผนร่วมกับทีมออกแบบ
ตั้งแต่ต้น ไม่ใช่ปะทีหลัง

⚠️ **ต้องไม่ให้เรื่องนี้ไปปนกับก้อนที่ 1** — ก้อนที่ 1 คือสแกนตอนแอปเปิดอยู่ ซึ่ง
ไม่ได้รับผลจาก Autostart/battery saver ถ้าเอาไปเขียนใน README ตอนนี้ในบริบทของก้อน
ที่ 1 จะทำให้คนเข้าใจผิดว่าต้องตั้งค่าพวกนี้ก่อนถึงจะ demo ได้

---

## ADR-13: ยกสัญญากลางขึ้น platform interface — จาก federated pattern ที่ไม่สมบูรณ์ (เพิ่ม 31 ส.ค. 2026)

**สถานะ:** ตัดสินใจแล้วและ implement แล้ว · ทางเลือก A ตาม ADR-12 หัวข้อ 5

### 1. สิ่งที่ตรวจพบตอนเพิ่มแพลตฟอร์มที่สอง

**federated plugin pattern ของโปรเจกต์นี้ไม่สมบูรณ์มาตั้งแต่ต้น และไม่มีใครรู้
เพราะมีแพลตฟอร์มเดียว**

| ควรเป็น | เป็นจริง (ก่อน ADR นี้) |
|---|---|
| `beacon_kit_platform_interface` ถือสัญญาของ platform | มีแต่ entity / parser / usecase — **ไม่มี abstract class ของ platform เลย** |
| facade `beacon_kit` คุยผ่านสัญญากลาง ไม่รู้จักแพลตฟอร์ม | `generic_ibeacon_eddystone_adapter.dart:3` → `import 'package:beacon_kit_ios/beacon_kit_ios.dart';` |
| สัญญามีชื่อเป็นกลาง | สัญญาจริงชื่อ `BeaconKitIosPlatform` อยู่ใน `beacon_kit_ios` |

โครงสร้างโฟลเดอร์**ดูเหมือน** federated ครบทุกอย่าง แต่เส้นทางการพึ่งพาจริงคือ
`beacon_kit` → `beacon_kit_ios` โดยตรง ซึ่งเป็นสิ่งที่ pattern นี้มีไว้เพื่อกำจัด

**ตรวจพบได้ก็ต่อเมื่อมีแพลตฟอร์มที่สองมาจริง** — ไม่มีเทสต์ไหนจับได้ ไม่มี lint
ไหนเตือน และเอกสารก็เขียนไว้ว่าเป็น federated plugin อย่างถูกต้องตามที่ตั้งใจ

### 2. ยกอะไรขึ้นไป และตั้งใจไม่ยกอะไร

สร้าง **`BeaconKitPlatform`** ใน `beacon_kit_platform_interface` ที่มี **3 อย่าง
เท่านั้น**:

| ยกขึ้น | เหตุผล |
|---|---|
| `startBluetoothScan(List<String> serviceUuids)` | iOS `CBCentralManager` กับ Android `BluetoothLeScanner` รับ service UUID แล้วเริ่มสแกนเหมือนกัน |
| `stopBluetoothScan()` | เหมือนกันทั้งสองฝั่ง |
| `rawAdvertisementEvents` | ทั้งคู่คืน **byte ดิบ** ให้ Dart parser ถอด — semantic ตรงกัน 1:1 |

**ตั้งใจไม่ยก** (คงไว้ที่ `beacon_kit_ios` ตามที่ ADR-9 กำหนดไว้ล่วงหน้า):

| ไม่ยก | เหตุผล |
|---|---|
| `startIBeaconMonitoring` / `stopIBeaconMonitoring` | สัญญาปัจจุบันคือ "ลงทะเบียน region กับ OS แล้วมันอยู่ข้าม process" ซึ่งเป็นความสามารถของ CoreLocation — **ADR-9 ตารางคำถามยังไม่มีคำตอบว่า Android มีเทียบเท่าหรือไม่** |
| `regionStateEvents` | enter/exit ที่ OS คำนวณให้ ยังไม่รู้ว่า Android ต้องคำนวณเองจากการไม่เจอ scan result หรือไม่ |
| `getIBeaconAuthorizationLevel` | `always` / `whenInUse` ของ CoreLocation ไม่มีอะไรเทียบตรงตัวบนโมเดล runtime permission ของ Android |
| flow ขอสิทธิ์ของ Android | กลับกัน — `requestScanPermissions` / `permanentlyDenied` ไม่มีอะไรเทียบบน iOS จึงอยู่ที่ `beacon_kit_android` |

**ทำไมไม่ยกทั้งหมดแล้วให้ฝั่งที่ทำไม่ได้ throw `UnsupportedError`:** สัญญาจะบอกว่า
"มีเมธอดนี้" ทั้งที่ใช้ไม่ได้ ผู้เรียกจะรู้ตอน runtime แทนที่จะรู้ตอน compile —
และ ADR-9 เตือนไว้ตรง ๆ แล้วว่า **ห้าม implement ให้ "ดูเหมือนทำได้"**

### 3. ใครเป็นคน register — และทำไมไม่มี `Platform.isAndroid` ในไลบรารีเลย

ใช้ `dartPluginClass` ของ Flutter: `BeaconKitIos.registerWith()` และ
`BeaconKitAndroid.registerWith()` ตั้ง `BeaconKitPlatform.instance` ให้ตัวเอง
Flutter สร้าง registrant ที่เรียก**เฉพาะของแพลตฟอร์มที่กำลังรันอยู่**

ยืนยันจาก `dart_plugin_registrant.dart` ที่ถูกสร้างจริงหลัง build:

```dart
if (Platform.isAndroid) {
  beacon_kit_android.BeaconKitAndroid.registerWith();
} else if (Platform.isIOS) {
  beacon_kit_ios.BeaconKitIos.registerWith();
}
```

`Platform.is*` ตัวเดียวที่มีอยู่ในระบบจึงเป็นโค้ดที่ **Flutter สร้างให้** ไม่ใช่
โค้ดที่เราเขียน

### 4. หนี้ที่ยังเหลือ และแผนกำจัด

**เส้นทาง iBeacon ยังไม่ผ่านสัญญากลาง** → example app จึงยังต้องรู้ว่ากำลังรันบน
แพลตฟอร์มไหน (ตัวแปร `_splitByPlatformUntilAdr13Step4` ใน `main.dart`)

**ข้อบังคับ: การแยกตามแพลตฟอร์มอยู่ใน example app เท่านั้น** ตรวจได้ด้วย:

```bash
grep -rn "Platform\.is" packages/*/lib | grep -v "///"
# ต้องไม่เจออะไรเลย
```

⚠️ ต้องกรอง `///` ออก ไม่งั้นจะเจอคอมเมนต์ที่**อธิบายว่าทำไมถึงไม่มี** `Platform.is`
แล้วสรุปผิดว่ามี — เป็นกับดักแบบเดียวกับที่เจอตอนตรวจ `neverForLocation` ใน merged
manifest (manifest merger เก็บคอมเมนต์ไว้ด้วย ทำให้ `grep` ธรรมดาได้ false positive)

**แผนกำจัด (ทำหลังก้อนที่ 2 ของ Android):**

1. ก้อนที่ 2 ตอบตารางคำถามใน ADR-9 ให้ครบ — Android เก็บ region ข้าม process ได้
   ไหม / มี enter-exit semantics หรือต้องคำนวณเอง / force-stop แล้วเป็นอย่างไร
2. ถ้าตอบแล้วพบว่า **ทำได้เทียบเท่า** → ยกขึ้นสัญญากลางด้วย**ชื่อที่เป็นกลาง**
   (ไม่ใช่ `IBeacon*` ที่ผูกกับ iOS) แล้วลบตัวแปรแยกแพลตฟอร์มใน example ทิ้ง
3. ถ้าพบว่า **ทำไม่ได้เทียบเท่า** → ห้ามยกขึ้น ให้แยกเป็นความสามารถคนละชื่อตาม
   ที่แต่ละแพลตฟอร์มทำได้จริง แล้วให้แอปเลือกเองอย่างรู้ตัว
4. ทั้งสองทาง `AdvertisementSource` (ที่เปลี่ยนชื่อใน ADR นี้แล้ว) ไม่ต้องแก้อีก

### 5. เปลี่ยนชื่อค่าใน `AdvertisementSource`

| เดิม | ใหม่ |
|---|---|
| `coreLocation` | `osDecoded` |
| `coreBluetooth` | `rawParsed` |
| `android` | **ยุบรวมเข้ากับ `rawParsed`** |

**เหตุผล:** ค่าเดิมตั้งชื่อตาม API ของ iOS สองตัวปนกับชื่อแพลตฟอร์มหนึ่งตัว —
ไม่ใช่แค่ตั้งชื่อไม่สวย แต่**ผิดระดับของ abstraction** สิ่งที่ผู้เรียกต้องตัดสินใจ
จากค่านี้มีอย่างเดียวคือ **"ฟิลด์ `ibeacon*` เชื่อได้แค่ไหน"** ซึ่งขึ้นกับว่า OS
ถอดให้หรือเราถอดเอง ไม่ได้ขึ้นกับว่าเป็น iOS หรือ Android

`coreBluetooth` กับ `android` มีคุณสมบัติเหมือนกันทุกประการในแง่นี้ การแยกสองค่า
จึงล่อให้ผู้เรียกเขียน `if (แพลตฟอร์ม)` ทั้งที่ไม่ควรต้องรู้ — **ยุบเหลือค่าเดียว**

**ข้อมูลไม่หายจากการยุบ:** ถ้าต้องรู้จริง ๆ ว่าอุปกรณ์มาจากวิทยุฝั่งไหน
`BeaconDeviceId.kind` แยก `macAddress` (Android) ออกจาก
`coreBluetoothPeripheralId` (iOS) อยู่แล้วตั้งแต่ ADR-1 — แค่ย้ายไปอยู่ที่ที่
ถูกต้องกว่า

### 6. ⚠️ ข้อสังเกตเชิงระบบ — abstraction ที่มี implementation เดียวยังไม่เคยถูกทดสอบ

`BeaconKitIosPlatform` ถูกออกแบบมาเป็น "สัญญากลาง" ตั้งแต่ต้น มี test 21 ตัวคุม
มีเอกสาร ADR กำกับครบ — **และมันก็ยังไม่ใช่สัญญากลางจริงอยู่ดี** เพราะไม่เคยมี
implementation ที่สองมาพิสูจน์ว่ามันครอบได้จริง

> **abstraction ที่มี implementation เดียว ยังไม่เคยถูกทดสอบในฐานะ abstraction**
> มันถูกทดสอบแค่ในฐานะ "โค้ดที่ทำงานได้" เท่านั้น

**ในโปรเจกต์นี้ยังเหลืออีกตัวที่จะพังแบบเดียวกัน: vendor adapter**

`BeaconAdapter` / `GenericIBeaconEddystoneAdapter` ออกแบบไว้ให้รองรับหลายยี่ห้อ
แต่ปัจจุบันมี**ยี่ห้อเดียวคือ KKM K9P** และทุกการตัดสินใจที่ผ่านมา (รูปแบบ
`deviceId`, การมี `supportsConnect`, สมมติฐานเรื่อง GATT auth) ตั้งอยู่บนข้อมูลของ
ยี่ห้อเดียว

**คาดได้ว่าตอนยี่ห้อที่สองมา จะเจอปัญหาชนิดเดียวกับที่เจอใน ADR นี้** — สัญญาที่
ดูเป็นกลางจะกลายเป็นสัญญาที่ผูกกับ KKM โดยไม่มีใครตั้งใจ

**บันทึกเป็นความเสี่ยงที่รู้แล้ว ไม่ใช่ปัญหาที่ต้องแก้ตอนนี้** — การพยายามทำให้
abstraction เป็นกลางโดยไม่มีตัวอย่างที่สองคือการเดา ซึ่งแพงกว่าและมักเดาผิด
สิ่งที่ทำได้ตอนนี้คือ **รู้ล่วงหน้าว่าจะต้องมีรอบ refactor** และอย่าสัญญากับใครว่า
"เพิ่มยี่ห้อใหม่ = เขียน adapter ใหม่ตัวเดียวจบ" จนกว่าจะผ่านยี่ห้อที่สองมาแล้วจริง

**สิ่งที่ควรทำเมื่อยี่ห้อที่สองมา:** ทำแบบเดียวกับรอบนี้ — implement ให้ทำงานได้
ก่อนโดยยอมรับหนี้ชั่วคราวที่จำกัดขอบเขตไว้ที่จุดเดียว แล้วค่อย refactor สัญญาจาก
ข้อมูลจริงสองชุด ไม่ใช่จากการเดาล่วงหน้า

---

## ADR-14: Android ก้อนที่ 2 — การทำงานเบื้องหลัง (เพิ่ม 31 ส.ค. 2026)

**สถานะ:** ✅ ค้นคว้าเสร็จ (หัวข้อ 1-3) · ✅ ตัดสินใจแล้ว (หัวข้อ 4) ·
✅ implement แล้ว (หัวข้อ 5) · 🛑 **ยังไม่ verified บนอุปกรณ์จริง** (หัวข้อ 7)

**สถานะตามคำที่ CONTRIBUTING ข้อ 4 กำหนด: `code-complete, unverified`**

**เครื่องเป้าหมาย:** Redmi Note 9 (`M2003J15SC`) · Android 12 (SDK 31) ·
MIUI `V13.0.2.0.SJOMIXM` — ยืนยันรุ่นจาก `adb shell getprop` เมื่อ 31 ส.ค. 2026

---

### 1. ตอบตารางคำถามที่ค้างใน ADR-9 ให้ครบ

ADR-9 สั่งไว้ว่า **"ก่อนตัดสิน ต้องรัน `beacon-sdk-verify` หรือการค้นคว้าเทียบเท่า
กับเอกสาร Android อย่างเป็นระบบก่อน — ตอบตารางข้างบนให้ครบพร้อม citation แล้ว
กลับมาเขียน ADR ต่อจากนี้ ไม่ใช่ตัดสินจากความจำ"** นี่คือการตอบนั้น

ทุกข้อยึด**ซอร์สจริงในเครื่อง**ก่อนเอกสารเว็บ ตาม CONTRIBUTING ข้อ 5 —
ซอร์สอยู่ที่ `~/Library/Android/sdk/sources/android-37.0/`

| คำถามจาก ADR-9 | คำตอบ |
|---|---|
| กลไก `PendingIntent` ใช้แทน region monitoring ของ iOS ได้จริงในเชิง use case หรือไม่ | **ได้บางส่วน — ไม่เท่ากัน** (หัวข้อ 1.1) |
| Android เก็บ "ชุด region ที่ลงทะเบียนไว้" ข้าม process แบบ `monitoredRegions` หรือไม่ | **ไม่มี** (หัวข้อ 1.2) |
| มี enter/exit semantics หรือต้องคำนวณเอง | **ต้องคำนวณเองทั้งหมด** (หัวข้อ 1.3) |
| พฤติกรรมหลังผู้ใช้ force-stop แอป เป็นอย่างไร | **หยุดถาวร แก้ด้วยโค้ดไม่ได้** (หัวข้อ 1.4) |
| ข้อจำกัด background scan throttling มีผลแค่ไหน | **ตอบครบแล้ว** (หัวข้อ 1.5 + ADR-12 หัวข้อ 2) |

#### 1.1 `PendingIntent` ปลุก process ที่ตายแล้วได้จริง — นี่คือส่วนที่เทียบได้

`BluetoothLeScanner.java:175-177`:

> "Start Bluetooth LE scan using a `PendingIntent`. The scan results will be
> delivered via the PendingIntent. **Use this method of scanning if your process is
> not always running and it should be started when scan results are available.**"

ประโยคนี้คือคำตอบตรง ๆ ว่ากลไกนี้ **ตั้งใจให้ปลุก process ที่ไม่ได้รันอยู่** ซึ่ง
เป็นความสามารถเดียวกับที่ `CLLocationManager` ให้บน iOS ตาม ADR-10
(`CLLocationManager.h:492-496`: "Even if killed by the user, launch events
triggered by monitoring APIs will cause a relaunch.")

**แต่สิ่งที่ส่งมาไม่ใช่สิ่งเดียวกัน** — `BluetoothLeScanner.java:184-186`:

> "When the PendingIntent is delivered, the Intent passed to the receiver or
> activity will contain one or more of the extras `EXTRA_CALLBACK_TYPE`,
> `EXTRA_ERROR_CODE` and `EXTRA_LIST_SCAN_RESULT` to indicate the result of the
> scan."

ได้ **รายการ `ScanResult`** ไม่ใช่ **`didEnterRegion`/`didExitRegion`** ความต่างนี้
ไม่ใช่เรื่องรูปแบบข้อมูล แต่เป็นเรื่อง**ใครคำนวณ** — ดูหัวข้อ 1.3

#### 1.2 ไม่มี `monitoredRegions` เทียบเท่า

ฝั่ง iOS แอปถามระบบได้ว่า "ตอนนี้เฝ้าอะไรอยู่" และคำตอบรอดข้าม process
(`CLLocationManager.monitoredRegions` — ADR-9 ยกมาแล้ว)

ฝั่ง Android **ค้นแล้วไม่พบ API เทียบเท่า**: `BluetoothLeScanner` ทั้งคลาสมีเมธอด
สาธารณะแค่ `startScan` / `stopScan` / `flushPendingScanResults` — **ไม่มีเมธอด
ใดที่คืนรายการสิ่งที่ลงทะเบียนไว้** และ `stopScan(PendingIntent)` ต้องการให้ผู้เรียก
**สร้าง `PendingIntent` ตัวเดิมขึ้นมาใหม่** เพื่อใช้ถอน ซึ่งเป็นหลักฐานทางอ้อมว่า
ระบบไม่ได้ตั้งใจให้แอปถามย้อนกลับได้

> "Stops an ongoing Bluetooth LE scan started using a PendingIntent. **When
> creating the PendingIntent parameter, please do not use the FLAG_CANCEL_CURRENT
> flag.** Otherwise, the stop scan may have no effect."
> — `BluetoothLeScanner.java:384-387`

**ผลต่อการออกแบบ:** รายการ region และสถานะเข้า/ออก **ต้องเป็นของเราเองทั้งหมด**
เก็บลงดิสก์เอง กู้คืนเอง — `BackgroundRegionStore`

⚠️ **และเป็นความจริงที่ต่างกันในเชิงคุณภาพ ไม่ใช่แค่ต่างที่มา:** ค่าที่ iOS ตอบคือ
*"ระบบกำลังเฝ้าอะไรอยู่จริง"* ค่าที่เราตอบได้คือ *"เราเคยสั่งให้เฝ้าอะไรไว้"*
สองอย่างนี้ต่างกันทันทีที่ระบบล้างการลงทะเบียนทิ้งโดยไม่บอกเรา (หัวข้อ 1.4) —
บันทึกไว้ในเอกสารของ `AndroidBackgroundMonitoringStatus` และในชื่อฟิลด์ของ log
(`restoredRegions=` ฝั่ง Android vs `monitoredRegions=` ฝั่ง iOS **ตั้งใจใช้คนละคำ**)

⚠️ **และเพราะเราเป็นคนอ่านไฟล์เอง เราจึงมีความล้มเหลวชนิดที่ iOS ไม่มี: อ่านไม่ออก**
ฝั่ง iOS ถาม `monitoredRegions` แล้วได้เซ็ตกลับมาเสมอ ส่วนฝั่งนี้ค่าที่เก็บไว้เสียหาย
หรือเปิดไฟล์ไม่ได้ก็เกิดขึ้นได้ **และเดิมมันจบลงที่ `restoredRegions=[]` เหมือนกับ
"ไม่มี region เก็บไว้" เป๊ะ** ซึ่งเป็นความล้มเหลวเงียบที่ชี้การไล่สาเหตุไปผิดทาง
ทั้งรอบทดสอบ — ไฟล์หลักฐานจึงต้องเขียนสองสถานะนี้คนละแบบ:

```
restoredRegions=[k9p-default]                <- อ่านได้ มี region
restoredRegions=[]                           <- อ่านได้ ไม่มี region เก็บไว้จริง ๆ
restoredRegions=<read-failed:invalid-json>   <- อ่านไม่สำเร็จ ตอบไม่ได้ว่ามีหรือไม่มี
```

`BeaconRegionSpec.listFromJsonReporting` / `BackgroundRegionStore.readRegions` /
`BackgroundRegionMonitor.restoredRegions` คืน `ParsedRegionList` ที่มี `readError`
มาด้วย ส่วน `BackgroundRegionStore.regions` (ที่ตรรกะ enter/exit ใช้) ยังคืน list
ว่างตามเดิม — **เส้นทางที่เขียนหลักฐานต้องใช้ตัวที่รายงาน error เท่านั้น**

#### 1.3 ไม่มี enter/exit จากระบบ — ต้องคำนวณเองทั้งหมด

ระบบส่งได้อย่างเดียวคือ "เจอ advertisement" **การไม่เจอไม่ใช่ event มันคือความเงียบ**
และไม่มีใครส่ง broadcast มาบอกว่าตอนนี้เงียบ

ผลคือ "ออกจากโซน" ต้องแปลงจากความเงียบเป็น event ด้วยนาฬิกาปลุก ซึ่งมีเพดานของมัน —
`AlarmManager.java:1286-1289` (`setAndAllowWhileIdle`):

> "Under normal system operation, **it will not dispatch these alarms more than
> about every minute** (at which point every such pending alarm is dispatched);
> **when in low-power idle modes this duration may be significantly longer, such as
> 15 minutes.**"

ทางเลือกที่แม่นกว่า (`setExactAndAllowWhileIdle`) ต้องขอสิทธิ์พิเศษ —
`AlarmManager.java:1352-1356`:

> "Starting with `Build.VERSION_CODES.S`, apps targeting SDK level 31 or higher
> need to request the `SCHEDULE_EXACT_ALARM` permission to use this API, unless the
> app is exempt from battery restrictions. **The user and the system can revoke this
> permission via the special app access screen in Settings.**"

และหน้าเดียวกันระบุว่า "**Exact alarms should only be used for user-facing
features.**" — การตรวจว่าออกจากโซนแล้วหรือยังไม่ใช่ฟีเจอร์ที่ผู้ใช้กดเรียก
**ตัดสินใจ: ไม่ขอสิทธิ์นั้น** และยอมรับเพดานเวลาข้างบนอย่างเปิดเผย

**สรุปความต่างที่ต้องรายงานทุกครั้ง:**

| | iOS | Android |
|---|---|---|
| ใครคำนวณ enter/exit | **ระบบ** (CoreLocation) | **เรา** จากการเห็น/ไม่เห็น |
| ค่าหน่วงก่อนประกาศ exit | ระบบกำหนด — **วัดได้เอง ~30 วินาที** ไม่พบเอกสาร Apple ที่ระบุหรือบอกว่าปรับได้ (ADR-11 หัวข้อ 2) | **เราตั้งเองได้** แต่ถูกจำกัดด้วยความถี่นาฬิกาปลุก (~1 นาที ปกติ / ~15 นาที ใน Doze) |
| ความหมายของ exit | ระบบสรุปให้ว่าออกจากโซน | **ความเงียบ** ซึ่งอาจมาจาก beacon แบตหมด / Bluetooth ปิด / ระบบ throttle / MIUI ฆ่าแอป |

#### 1.4 force-stop — หยุดถาวร และแก้ด้วยโค้ดไม่ได้

`ApplicationInfo.java:416-426` (`FLAG_STOPPED`):

> "...The system tries not to start it unless initiated by a user interaction...
> **Stopped applications will not receive implicit broadcasts unless the sender
> specifies `Intent#FLAG_INCLUDE_STOPPED_PACKAGES`.**"
>
> "Applications should avoid launching activities, binding to or starting services,
> or otherwise causing a stopped application to run unless initiated by the user."
>
> "**An app can also return to the stopped state by a 'force stop'.**"

แปลว่าเมื่อผู้ใช้ force-stop แล้ว **ไม่มีเส้นทางไหนที่แอปจะกลับมาเองได้** ตัวรับ
`BOOT_COMPLETED` ก็ไม่ทำงาน (มันเป็น implicit broadcast) — ทางเดียวคือผู้ใช้เปิดแอปเอง

**นี่คือความต่างที่ใหญ่ที่สุดจาก iOS** ฝั่งนั้น `CLLocationManager.h:492-496` ระบุ
ตรงข้ามเลยว่า "**Even if killed by the user**, launch events triggered by
monitoring APIs will cause a relaunch."

⚠️ **ยังไม่ยืนยันเอง:** เอกสารข้างบนพูดถึง *broadcast* ที่ระบบส่ง ส่วนคำถามว่า
**การลงทะเบียนสแกนใน Bluetooth stack ถูกล้างทิ้งด้วยหรือไม่** ตอนนี้ยังไม่พบเอกสาร
ที่ระบุตรง ๆ — ต้องยืนยันบนเครื่องจริง (เช็คลิสต์ข้อ 3)

#### 1.5 รีบูต — ไม่รอด ต้องลงทะเบียนใหม่เอง

`Intent.java:2814-2821` (`ACTION_BOOT_COMPLETED`):

> "You must hold the `android.Manifest.permission#RECEIVE_BOOT_COMPLETED`
> permission in order to receive this broadcast."
>
> "**Upon receipt of this broadcast, the user is unlocked** and both
> device-protected and credential-protected storage can accessed safely."

**ช่องว่างที่ปิดไม่ได้ด้วยโค้ด:** ระหว่างที่เครื่องบูตเสร็จแล้วแต่ผู้ใช้ยังไม่ปลดล็อก
เรายังไม่ได้เฝ้าอะไรเลย — ต่างจาก iOS ที่ region อยู่ในระบบตั้งแต่ก่อนรีบูต

(หมายเหตุ: `ACTION_LOCKED_BOOT_COMPLETED` ยิงก่อนปลดล็อก แต่ component ที่จะรับได้
ต้องเป็น direct-boot aware และเข้าถึงได้แค่ device-protected storage — **ยังไม่ได้
ทำ** ประกาศตัวรับไว้แล้วแต่ยังไม่ประกาศ `directBootAware` จึงยังไม่มีผลจริงในเคสนั้น
บันทึกเป็นหนี้ในหัวข้อ 6)

---

### 2. เปรียบเทียบทางเลือก — แต่ละแบบให้อะไร แลกอะไร

| | **A. `startScan(PendingIntent)`** | **B. foreground service** | **C. `WorkManager`/`JobScheduler` แล้วสแกนเป็นรอบ** |
|---|---|---|---|
| ทำงานตอน process ตาย | ✅ ระบบสร้าง process ใหม่ให้ (`BluetoothLeScanner.java:175-177`) | ❌ service ตายไปกับ process | ✅ ระบบปลุกให้ |
| ผู้ใช้เห็น notification ค้าง | ❌ ไม่มี | ⚠️ **มี ตลอดเวลา** | ❌ ไม่มี |
| ความถี่การสแกน | `SCAN_MODE_LOW_POWER` (ระบบบังคับ) | ระดับ foreground ได้ | เป็นช่วง ๆ ห่างมาก |
| ความหน่วงในการรู้ว่า "เข้า" | เท่าที่ระบบส่งผลสแกนมา | เร็วที่สุด | **แย่ที่สุด** — ขั้นต่ำของ periodic work คือ 15 นาที |
| ความหน่วงในการรู้ว่า "ออก" | เพดานนาฬิกาปลุก (~1 นาที / ~15 นาที ใน Doze) | เร็ว | ≥ รอบของงาน |
| รอดปัดแอปทิ้ง | ✅ (ต้องยืนยันบนเครื่อง) | ⚠️ แล้วแต่ OEM — MIUI ฆ่าบ่อย | ✅ |
| รอด force-stop | ❌ | ❌ | ❌ |
| รอดรีบูต | ❌ ต้องลงทะเบียนใหม่ผ่าน `BOOT_COMPLETED` | ❌ ต้องเริ่มใหม่ | ⚠️ `WorkManager` กู้คืนงานให้ |
| ต้นทุนแบต | ต่ำสุด | สูงสุด | ต่ำ |

**ทำไมตัด C ทิ้ง:** ความหน่วง 15 นาทีขั้นต่ำทำให้ "เดินเข้าสาขา" ถูกตรวจพบหลังจาก
ลูกค้าออกจากร้านไปแล้ว ซึ่งทำลาย use case ทั้งหมด ไม่ใช่แค่ทำให้แย่ลง

**ทำไมไม่เลือก B เป็นกลไกหลัก — ดูหัวข้อ 3**

#### 2.1 `PendingIntent` mutability — คำถามที่ ADR-12 หัวข้อ 3 ค้างไว้

ADR-12 บันทึกไว้ว่า *"ยังไม่ได้ยืนยันว่าเคสนี้ต้องใช้ `FLAG_MUTABLE` หรือ
`FLAG_IMMUTABLE`... ต้องยืนยันก่อนเขียนโค้ดก้อนที่ 2"*

**คำตอบ: ต้องเป็น `FLAG_MUTABLE`** และหลักฐานเป็นการต่อสองประโยคจากซอร์สจริง:

1. ผลสแกนถูกส่งมาเป็น **extras ของ Intent ที่ส่งออก** —
   `BluetoothLeScanner.java:184-186` (ยกไว้ในหัวข้อ 1.1)
2. `PendingIntent.java:917-919` (`send(Context, int, Intent)`):

> "@param intent Additional Intent data. See `Intent.fillIn()` for information on
> how this is applied to the original Intent. **If flag `FLAG_IMMUTABLE` was set when
> this pending intent was created, this argument will be ignored.**"

`FLAG_IMMUTABLE` จึงหมายถึง **"ได้ broadcast แต่ไม่มีผลสแกนติดมาด้วย"** ซึ่งเป็น
ความล้มเหลวชนิดที่เงียบที่สุด: การลงทะเบียนสำเร็จ broadcast มาถึง แต่ `onReceive`
ไม่มีอะไรให้อ่าน

⚠️ **ยังไม่ยืนยันเองบนเครื่อง** — ข้อสรุปนี้เป็น **การต่อประโยคจากสองหน้าเอกสาร**
ไม่ใช่ประโยคเดียวที่ Android เขียนตรง ๆ ว่า "startScan ต้องใช้ MUTABLE" โค้ดฝั่ง
Bluetooth ที่เป็นคนเรียก `send()` จริงอยู่ใน Bluetooth apex ซึ่ง**ไม่ได้มาพร้อม
Android SDK** จึงอ่านยืนยันในเครื่องไม่ได้ — เช็คลิสต์ข้อ 6 ออกแบบไว้ให้ยืนยัน
ด้วยการทดลองจริง (สลับเป็น `FLAG_IMMUTABLE` แล้วดูว่า extras หายไปหรือไม่)

โค้ดดัก `EXTRA_ERROR_CODE`/รายการว่างไว้แล้วใน `BeaconScanReceiver` เพื่อให้เคสนี้
ไม่ออกมาเป็น "ไม่มี event" เฉย ๆ

`FLAG_UPDATE_CURRENT` ใช้ได้ปกติ (`PendingIntent.java:251-255`: "`FLAG_UPDATE_CURRENT`
still works even if `FLAG_IMMUTABLE` is set") ส่วน `FLAG_CANCEL_CURRENT`
**ห้ามใช้** ตาม `BluetoothLeScanner.java:384-387`

#### 2.2 ข้อกำหนดของ foreground service ในเวอร์ชันใหม่ ๆ

เครื่องทดสอบเป็น Android 12 แต่ SDK ต้อง target เวอร์ชันใหม่กว่าในอนาคต — บันทึกไว้
ล่วงหน้าตามที่โจทย์สั่ง

**Android 12 (API 31) — ห้ามเริ่ม FGS จากเบื้องหลัง** (ADR-12 หัวข้อ 2ง ยกไว้แล้ว)
รายการข้อยกเว้นที่เกี่ยวกับเรา จาก
[Exemptions from background start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start):

> - "Your app transitions from a user-visible state, such as an activity."
> - "After the device reboots and receives the `ACTION_BOOT_COMPLETED`,
>   `ACTION_LOCKED_BOOT_COMPLETED`, or `ACTION_MY_PACKAGE_REPLACED` intent action in
>   a broadcast receiver."
> - "**The user turns off battery optimizations for your app.**"

**Android 14 (API 34) — ต้องประกาศชนิด และต้องมีสิทธิ์ของชนิดนั้น**
([Foreground service types are required](https://developer.android.com/about/versions/14/changes/fgs-types-required)):

> "If an app that targets Android 14 doesn't define types for a given service in the
> manifest, then the system will raise `MissingForegroundServiceTypeException` upon
> calling `startForeground()` for that service."
>
> "If you call `startForeground()` without declaring the appropriate foreground
> service type permission, the system throws a `SecurityException`."

ชนิดที่ตรงกับ use case ของเราคือ **`connectedDevice`** —
`ServiceInfo.java:259-297` ระบุว่าต้องมี `FOREGROUND_SERVICE_CONNECTED_DEVICE`
บวกกับอย่างน้อยหนึ่งใน `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` /
`BLUETOOTH_ADVERTISE` / … ซึ่งเรามี `BLUETOOTH_SCAN` อยู่แล้ว

**ชนิด `location` มีกับดักที่ต้องรู้** — `ServiceInfo.java:236-256` และหน้าเดียวกัน
ของเอกสาร:

> "The location runtime permissions are subject to while-in-use restrictions. For
> this reason, **you cannot create a `location` foreground service while your app is
> in the background**, unless you've been granted the `ACCESS_BACKGROUND_LOCATION`
> runtime permission."

**Android 15 (API 35) — จำกัดชนิดที่เริ่มจาก `BOOT_COMPLETED` ได้**
([Behavior changes: Android 15](https://developer.android.com/about/versions/15/behavior-changes-15)):

> "`BOOT_COMPLETED` receivers are not allowed to launch the following types of
> foreground services: `dataSync`, `camera`, `mediaPlayback`, `phoneCall`,
> `mediaProjection`, `microphone`"

**`connectedDevice` ไม่อยู่ในรายการนี้** — แปลว่าถ้าวันหนึ่งเลือกทาง foreground
service เส้นทาง `BOOT_COMPLETED` ยังใช้ได้ **แต่ต้องตรวจซ้ำเมื่อ target API
สูงขึ้นจริง ไม่ใช่เชื่อบันทึกนี้** เพราะรายการนี้ยาวขึ้นทุกเวอร์ชัน

#### 2.3 การขอยกเว้น battery optimization — ทำได้ แต่ Play Store บล็อกเคสของเรา

**API มีจริงและใช้ได้** — `Settings.java:1715-1737`:

> "Activity Action: Ask the user to allow an app to ignore battery optimizations...
> For an app to use this, it also must hold the
> `android.Manifest.permission#REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission."
>
> "**Note: most applications should not use this**; there are many facilities
> provided by the platform for applications to operate correctly in the various power
> saving modes. This is only for unusual applications that need to deeply control
> their own execution, at the potential expense of the user's battery life."

**แต่นโยบายของ Play Store เป็นตัวตัดสิน ไม่ใช่ API**
([Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby#exemption-cases)):

> "**Google Play policies prohibit apps from requesting direct exemption from Power
> Management features—Doze and App Standby—in Android 6.0 and above unless the core
> function of the app is adversely affected.**"

ตารางในหน้านั้นมีสองแถวที่เป็นเรื่องของเราโดยตรง:

| Use case | ยอมรับได้? |
|---|---|
| "Peripheral device companion app. App's core function is maintaining a persistent connection with the peripheral device **for the purpose of providing the peripheral device internet access**." | Acceptable |
| "Peripheral device companion app. App **only needs to connect to a peripheral device periodically to sync**, or only needs to connect to devices, such as wireless headphones, connected via standard Bluetooth profiles." | **Not Acceptable** |

**เคสของ BigC ตรงกับแถวล่าง** — เราไม่ได้ให้ beacon เข้าอินเทอร์เน็ต เราแค่ฟัง
advertisement เป็นระยะ

**ข้อสรุป: ห้ามให้แอปกดขอยกเว้นเอง** ทางที่เหลือคือ **UX ที่พาผู้ใช้ไปตั้งค่าเอง**
(หน้าอธิบาย + ปุ่มลัดไปหน้า setting) ซึ่งเป็นทางเดียวกับที่ ADR-12 หัวข้อ 6 สรุปไว้
สำหรับ MIUI Autostart — **เรื่องเดียวกัน ปัญหาเดียวกัน แก้ด้วยโค้ดไม่ได้เหมือนกัน**

**หมายเหตุที่ต้องอ่านคู่กัน:** การยกเว้น battery optimization ไม่ได้ยกเว้นทุกอย่าง —
หน้าเดียวกันระบุว่า "An app that is partially exempt can use the network and hold
partial wake locks during Doze and App Standby. **However, other restrictions still
apply to the app**, just as they do to other apps."

#### 2.4 Doze — สิ่งที่เอกสารบอก และสิ่งที่เอกสาร**ไม่ได้**บอก

รายการข้อจำกัดของ Doze จากเอกสารทางการ (คัดมาทั้งรายการ):

> - Suspends network access.
> - Ignores wake locks.
> - Defers standard `AlarmManager` alarms... to the next maintenance window.
> - Doesn't perform Wi-Fi scans.
> - Doesn't let sync adapters run.
> - Doesn't let `JobScheduler` run.

⚠️ **"BLE scanning" ไม่อยู่ในรายการนี้ และห้ามสรุปทั้งสองทางจากการที่มันไม่อยู่**
เอกสารพูดถึง "Wi-Fi scans" ตรง ๆ แต่ไม่พูดถึง Bluetooth เลย — จะตีความว่า
"แปลว่า BLE ไม่ถูกจำกัด" ก็เป็นการเดา จะตีความว่า "ถูกจำกัดเหมือนกัน" ก็เป็นการเดา
**ต้องวัดเอง** (เช็คลิสต์ข้อ 5)

สิ่งที่**รู้แน่**คือ **นาฬิกาปลุกของเราถูกจำกัดแน่นอน** (`AlarmManager.java:1286-1289`
ยกไว้ในหัวข้อ 1.3) ซึ่งกระทบเฉพาะการประกาศ `exit` ไม่ใช่การเห็น `enter`

---

### 3. การตัดสินใจ — **เราสัญญาอะไรบน Android**

โจทย์ระบุว่าประเด็นหลักคือข้อนี้ เพราะ "เหมือน iOS" อาจเป็นไปไม่ได้ — **และมันเป็นไป
ไม่ได้จริง** ตามหลักฐานในหัวข้อ 1

#### 3.1 กลไกที่เลือก: `PendingIntent` เป็นกลไกหลัก · **ไม่มี foreground service**

**เหตุผลที่ไม่เลือก foreground service เป็นกลไกหลัก:**

1. **มันไม่ได้แก้ปัญหาที่ยากที่สุด** ปัญหาคือ "ทำงานต่อเมื่อ process ตายแล้ว"
   foreground service ตายไปกับ process เหมือนกัน มันแค่ทำให้ process ตายช้าลง
   — ซึ่งบน MIUI ก็ยังไม่รับประกัน
2. **ราคาที่จ่ายไปตกกับผู้ใช้ทุกคนตลอดเวลา** notification ค้างถาวรคือสิ่งที่ผู้ใช้
   เห็นทุกครั้งที่ปัดแถบแจ้งเตือน แลกกับความสามารถที่ใช้จริงนาน ๆ ครั้ง
3. **ADR-9 สั่งห้ามไว้ตรง ๆ** ว่าห้าม "เลี้ยง foreground service ไว้เงียบ ๆ แล้ว
   เรียกว่าสำเร็จ" — ข้อนี้เขียนดักไว้ก่อนเริ่มงานนี้แล้ว

**เก็บไว้เป็นทางเลือกในอนาคต ไม่ใช่ตัดทิ้ง:** ถ้าผลทดสอบพบว่าความถี่ของ
`SCAN_MODE_LOW_POWER` ต่ำเกินไปจนพลาดลูกค้าที่เดินผ่านเร็ว ทางแก้คือเพิ่ม
**โหมดที่ผู้ใช้เลือกเปิดเอง** ที่ใช้ foreground service — และถ้าทำ **ต้องเขียนบน
หน้าจอตรง ๆ ว่าจะมี notification ค้างตลอด** ตามข้อบังคับของ ADR-9

#### 3.2 สัญญาที่เขียนเป็นตาราง — ต้องปรากฏทั้งใน dartdoc และบนหน้าจอ example app

| สัญญา | **ไม่สัญญา** |
|---|---|
| รอดข้ามการปัดแอปทิ้งจากรายการแอป — ระบบสร้าง process ใหม่มาส่ง event ให้ | **ไม่รอด force-stop** — ไม่มีทางแก้ด้วยโค้ด (หัวข้อ 1.4) |
| ลงทะเบียนใหม่เองหลังรีบูต ผ่าน `BOOT_COMPLETED` | ช่วงหลังรีบูตจนถึงผู้ใช้ปลดล็อกครั้งแรก **ไม่ได้เฝ้าอะไรเลย** |
| ไม่มี notification ค้างให้ผู้ใช้เห็น | จึงไม่ได้ความถี่การสแกนระดับ foreground |
| `exit` ถูกยิงเมื่อไม่เห็นครบ `exitTimeoutSeconds` | **ไม่สัญญาว่าจะยิงภายในเวลานั้น** — เพดานนาฬิกาปลุก (หัวข้อ 1.3) |
| รายงานความล้มเหลวของการลงทะเบียน **รายอัน** | ไม่ retry ให้เอง — ตัวเลข throttle ยืนยันไม่ได้ (ADR-12 หัวข้อ 2ค) |
| event ที่เกิดตอนไม่มี Flutter engine ถูกคิวลงดิสก์ ไม่หาย | คิวมีเพดาน 200 event · ทิ้งตัวเก่าสุดก่อน |

#### 3.3 **ไม่ยกขึ้นสัญญากลาง** — ทำตาม ADR-13 หัวข้อ 4 ข้อ 3

ADR-13 เขียนแผนไว้ล่วงหน้าสองทาง และคำตอบคือทางที่สอง:

> "3. ถ้าพบว่า **ทำไม่ได้เทียบเท่า** → ห้ามยกขึ้น ให้แยกเป็นความสามารถคนละชื่อตาม
>    ที่แต่ละแพลตฟอร์มทำได้จริง แล้วให้แอปเลือกเองอย่างรู้ตัว"

จึงตั้งชื่อทุกอย่างขึ้นต้นด้วย `Android` (`AndroidBeaconRegion`,
`AndroidBackgroundRegionEvent`, `AndroidRegionState`) และวางไว้ที่
`beacon_kit_android` ไม่ใช่ `beacon_kit_platform_interface`

**ผลข้างเคียงที่ยอมรับ:** `_splitByPlatformUntilAdr13Step4` ใน example app
**ยังต้องอยู่ต่อ** และตอนนี้เรารู้แล้วว่ามัน**จะอยู่ถาวร** ไม่ใช่หนี้ชั่วคราว —
เพราะสองแพลตฟอร์มทำคนละอย่างจริง ๆ ไม่ใช่เพราะเรายังไม่ได้ refactor
(ชื่อตัวแปรยังไม่เปลี่ยนในรอบนี้ บันทึกเป็นงานเก็บกวาดในหัวข้อ 6)

#### 3.4 ค่า N (`exitTimeoutSeconds`) — เชื่อมกับงาน debounce ของ ADR-11

**ค่าเริ่มต้น 30 วินาที** เลือกให้ **ตรงกับค่าหน่วงที่วัดได้จากพฤติกรรมของ iOS**
(ADR-11 หัวข้อ 2: 43.5% ของช่วงที่วัดได้ตกในหน้าต่าง 29.5-30.5 วินาที) เพื่อให้ผล
รอบทดสอบแรกของสองแพลตฟอร์ม **ต่างกันเพราะกลไก ไม่ใช่เพราะตั้งค่าคนละแบบ**

**ตั้งได้ ไม่ hardcode** — ส่งผ่าน `startBackgroundRegionMonitoring(exitTimeoutSeconds:)`
เก็บลง `BackgroundRegionStore` และ example app ถือค่านี้ไว้เอง (`_androidExitTimeoutSeconds`)
ตามข้อกำหนดของ ADR-11 หัวข้อ 7 ที่ว่าค่าพวกนี้เป็นการตัดสินใจของแอป ไม่ใช่ของ SDK

**บันทึกความต่างนี้เป็นข้อดีที่ตั้งใจใช้:**

> บน iOS ค่าหน่วงก่อนประกาศ exit เป็นของระบบ **เราปรับไม่ได้** และ ADR-11 ค้นทั้ง
> `CLRegion.h`, `CLBeaconRegion.h`, `CLLocationManager.h` แล้วไม่พบเอกสาร Apple ที่
> ระบุค่าหรือบอกว่าปรับได้ — เราทำได้แค่ **วัด** แล้วออกแบบ debounce มารองรับ
>
> บน Android ค่านี้เป็นของเรา **จูนจากข้อมูลสาขาจริงได้โดยไม่ต้องรอ Apple** ตาม
> แผนใน ADR-11 หัวข้อ 8 ที่ระบุว่าต้องเก็บข้อมูลอย่างน้อย 3 จุดก่อนล็อกค่าลง
> production — งานนั้นทำบน Android ได้ครบวงจร ตั้งแต่วัดจนถึงปรับ

⚠️ **แต่ไม่ได้แปลว่า Android เหนือกว่า** ชั้น debounce ของ ADR-11 (รวม session
5 นาที + ต้องอยู่ต่อเนื่อง 2 นาที) **ยังจำเป็นเท่าเดิม** เพราะการปรับ N ลดได้แค่
flap ที่เกิดจากค่าหน่วงของกลไก ไม่ได้ลด flap ที่เกิดจากสัญญาณแกว่งจริง

---

### 4. สิ่งที่ implement แล้ว

| ไฟล์ | หน้าที่ |
|---|---|
| `beacon_kit_android/.../BeaconRegionSpec.kt` | region + `ScanFilter` ที่เจาะจงถึงระดับ UUID/major/minor |
| `beacon_kit_android/.../BackgroundRegionStore.kt` | สถานะที่ต้องรอดข้าม process (SharedPreferences + `commit()`) |
| `beacon_kit_android/.../BackgroundRegionMonitor.kt` | ลงทะเบียน/ถอน · เครื่องสถานะ enter/exit · นาฬิกาปลุก |
| `beacon_kit_android/.../BeaconScanReceiver.kt` | รับผลสแกนจาก `PendingIntent` |
| `beacon_kit_android/.../RegionExitAlarmReceiver.kt` | แปลงความเงียบเป็น event `exit` |
| `beacon_kit_android/.../BootCompletedReceiver.kt` | ลงทะเบียนใหม่หลังรีบูต |
| `example/android/.../BackgroundEvidenceLog.kt` | เขียนไฟล์หลักฐาน — **native ล้วน ไม่พึ่ง Flutter** |
| `example/android/.../ProcessState.kt` | แยก "ผู้ใช้เปิดแอป" ออกจาก "ระบบสร้าง process" |
| `example/android/.../ExampleApplication.kt` | ตั้งเครื่องมือวัดก่อนอย่างอื่นทั้งหมด |

#### 4.1 กติกา "ไม่มี parser ในฝั่ง Kotlin" ยังอยู่ครบ

ปัญหา: เส้นทางเบื้องหลังไม่มี Flutter engine ให้เรียก `IBeaconParser` ฝั่ง Dart
ถ้ากรองกว้าง ๆ แล้วมาแยก region ทีหลัง เรา**ถูกบังคับ**ให้เขียน parser ตัวที่สอง
ในฝั่ง Kotlin ซึ่งจะ drift จากตัวหลักโดยไม่มีเทสต์ไหนจับได้

ทางออก: **ลงทะเบียนสแกนหนึ่งครั้งต่อหนึ่ง region** แต่ละครั้งมี `PendingIntent`
ของตัวเองที่พก `identifier` ติดไปด้วย ผลสแกนกลับมาแล้วรู้ทันทีว่าเป็น region ไหน
**โดยไม่ถอด byte แม้แต่ตัวเดียว**

**กับดักที่ต้องรู้:** `PendingIntent` สองตัวถือเป็นตัวเดียวกันถ้า
`Intent.filterEquals` (action/data/type/component/categories) + requestCode ตรงกัน
— **extras ไม่ถูกนับ** ถ้าต่างกันแค่ extras ทุก region จะได้ `PendingIntent`
ตัวเดียวกันและ `identifier` จะเป็นของ region สุดท้ายเสมอ จึงใส่ทั้ง data URI ที่
ไม่ซ้ำ (`beaconkit://scan/<identifier>`) และ requestCode ที่ไม่ซ้ำ

🔶 **ยังไม่ยืนยัน:** จำนวนการลงทะเบียนพร้อมกันสูงสุดที่เครื่องรับได้ ADR-8 กำหนด
เพดาน region ไว้ที่ 20 (ตามข้อจำกัดของ iOS) ซึ่งจะกลายเป็น 20 การลงทะเบียนบน
Android — `ScanCallback.SCAN_FAILED_OUT_OF_HARDWARE_RESOURCES` มีอยู่จริงในซอร์ส
แต่**ไม่มีเอกสารระบุตัวเลข** โค้ดรายงาน error รายอันกลับไปแล้ว (ไม่เงียบ)
แต่ยังไม่ได้ทดสอบว่าเพดานจริงอยู่ที่เท่าไร (เช็คลิสต์ข้อ 8)

#### 4.2 เครื่องมือวัด: process identity marker (ทำก่อนกลไก ตามที่โจทย์สั่ง)

**ปัญหาที่แก้ (ค้างจากข้อเสนอรอบเคส B1 ของ iOS ยังไม่เคยทำ):** ก่อนหน้านี้การตอบว่า
"บรรทัดนี้มาจาก process ใหม่หรือเดิม" ทำได้ทางเดียวคือ **เดาจาก `uptime`** ซึ่งผิด
ได้สองทาง — process เก่าที่ถูกปลุกอีกครั้งมี uptime สูงทั้งที่ไม่ใช่ของใหม่ และ
process ใหม่ที่ส่ง event ช้าก็มี uptime สูงเช่นกัน

**สิ่งที่ทำ:** สุ่ม UUID 8 ตัวอักษรตอน process เริ่ม เขียนเป็น **คอลัมน์ที่ 2 ของทุก
บรรทัด** ทั้ง Android และ iOS — สองบรรทัดที่ `processId` ต่างกันมาจากคนละ process
**แน่นอน ไม่ใช่การอนุมาน**

รูปแบบบรรทัดใหม่ (6 คอลัมน์ TAB คั่น):

```
timestamp(ISO8601+offset) \t processId \t event \t regionIdentifier \t conclusion \t rawSignals
```

**ส่วนขยาย (1 ก.ย. 2026) — ตัวระบุ process แบบ key=value ต้นคอลัมน์สัญญาณดิบ:**
คอลัมน์ที่ 2 ตอบได้แค่ "process ไหน" แต่ตอบไม่ได้ว่า pid ของระบบคือเบอร์อะไร
(ไว้เทียบกับ `logcat`) และบรรทัดนั้นถูกเขียนจากเส้นทางที่ทำงานได้โดยไม่มี UI หรือไม่
คอลัมน์สัญญาณดิบของ**ทุกบรรทัด ทั้งสองแพลตฟอร์ม** จึงขึ้นต้นด้วยชุดนี้เสมอ:

```
procUuid=<8 hex> pid=<os pid> uptimeMs=<ms> receiverEntry=<true|false>
```

| key | ตอบคำถาม | หมายเหตุ |
|---|---|---|
| `procUuid` | process ไหน | **ค่าเดียวกับคอลัมน์ที่ 2 เสมอ** (แหล่งเดียวกัน จึงขัดแย้งกันไม่ได้ มีเทสต์ล็อกไว้ทั้งสองฝั่ง) — ซ้ำโดยตั้งใจเพื่อให้ `grep` คอลัมน์เดียวได้ครบ |
| `pid` | สะพานไปเครื่องมือของระบบ | **ไม่ใช่ตัวระบุ process** ระบบใช้ซ้ำได้หลัง process ตาย |
| `uptimeMs` | อายุ process | **มิลลิวินาทีจำนวนเต็ม** แทน `uptime=<วินาที>s` เดิม เพราะช่วงที่ต้องแยกให้ออกคือหลักร้อยมิลลิวินาที (event ที่มาถึงทันทีหลัง process เกิด) ซึ่ง `%.1f` วินาทีปัดทิ้ง · Android วัดด้วย `SystemClock.elapsedRealtime()` (ไม่กระโดด) ส่วน iOS วัดด้วย `Date` (กระโดดได้ถ้าเครื่อง sync เวลา) เพราะทางเลือกฝั่ง iOS ไม่นับเวลาที่เครื่องหลับ |
| `receiverEntry` | บรรทัดนี้เขียนจากโค้ดที่ **ระบบเรียกเข้ามา** หรือไม่ | Android = อยู่ใน `BroadcastReceiver.onReceive` · iOS = อยู่ใน callback ของ `CLLocationManagerDelegate` — **คนละกลไก** แต่ตอบคำถามเดียวกัน |

`receiverEntry` เป็น **ข้อเท็จจริงของเส้นทางเรียก ไม่ใช่ค่าที่วัดที่ runtime**:
ผู้เรียกทุกจุดต้องส่งค่าเอง (ไม่มี default ให้ลืม) และเหตุผลของแต่ละจุดเขียนกำกับไว้
ที่ call site — บรรทัด `launch` เป็น `false` เสมอ **แม้ process นั้นจะเกิดเพราะ
broadcast/location event ก็ตาม** เพราะ `Application.onCreate()` /
`didFinishLaunchingWithOptions` จบก่อน callback จะถูกเรียก คู่ที่พิสูจน์ว่า "ระบบ
สร้าง process ขึ้นมาเพื่อ event นี้" คือ **`procUuid` ที่ไม่เคยปรากฏมาก่อนในไฟล์
เดียวกัน + บรรทัด `enter`/`exit` ของ `procUuid` นั้นที่มี `receiverEntry=true`
และ `conclusion=relaunchedFromTerminated`**

⚠️ **`conclusion` ของบรรทัด `launch` ไม่ใช่หลักฐาน และห้ามอ้างเป็นหลักฐาน**
ด้วยเหตุผลเดียวกับที่ทำให้ `receiverEntry` ของบรรทัดนั้นเป็น `false` เสมอ:
บรรทัด `launch` ถูกเขียน**ก่อน**ที่แอปจะมี UI ได้ ตอนนั้น `hasEverBeenForeground`
(Android) / `hasEverBecomeActive` (iOS) ยังเป็น `false` ทุกครั้ง ค่าจึงออกมาเป็น
`relaunchedFromTerminated` **เสมอ แม้ผู้ใช้จะกดไอคอนเปิดแอปเอง** — เก็บฟิลด์ไว้ได้
ในฐานะสัญญาณดิบ แต่สิ่งที่พิสูจน์ว่าเป็น process ใหม่คือ **`procUuid` เท่านั้น**
(`tool/analyze_region_log.dart` นับ process ที่ถูกปลุกจากบรรทัด `enter`/`exit`
ไม่ใช่จากบรรทัด `launch` ด้วยเหตุผลนี้)

`uptime=<วินาที>s` รูปแบบเดิมยังต้องอ่านได้ต่อไป (ไฟล์หลักฐานเก่าใช้รูปแบบนั้น) —
`tool/analyze_region_log.dart` อ่าน `uptimeMs` ก่อนแล้วค่อย fallback

**ส่วนขยาย (1 ก.ย. 2026, รอบสอง) — บรรทัด `exit` ต้องอธิบายตัวเองได้:**
รอบทดสอบสนามเจอ exit หน่วง 22 วินาที กับ 3 นาที 15 วินาที **ด้วย
`exitTimeoutSeconds=30` เท่ากันทั้งคู่** ซึ่งจากไฟล์ log แยกไม่ออกว่าเป็นการเลื่อน
ของ `AlarmManager` หรือมีผลสแกนเข้ามาเลื่อนหน้าต่างออกไป — คนละสาเหตุที่แก้คนละทาง
บรรทัด `exit` (เท่านั้น) จึงมีเพิ่มสามฟิลด์:

```
sinceLastSeenMs=<ms> scheduledAtElapsed=<ms> firedAtElapsed=<ms>
```

| ฟิลด์ | ตอบคำถาม |
|---|---|
| `sinceLastSeenMs` | **หน้าต่างที่ได้จริง** — `now − lastSeen` ณ วินาทีที่ตัดสินใจ เทียบกับค่าที่ขอไป |
| `scheduledAtElapsed` / `firedAtElapsed` | **ระยะที่ระบบเลื่อนนาฬิกาปลุก** — เก็บค่าดิบสองตัว **ไม่เก็บผลต่าง** ตามหลักเดียวกับคอลัมน์สัญญาณดิบทั้งคอลัมน์ |

`n/a` ทั้งสามช่อง = มาจากสาขา "เทียบเวลาข้ามรอบบูตไม่ได้" ของ `onExitAlarm`
ซึ่ง**ไม่ใช่หลักฐานว่า beacon หายไป** — ห้ามเรนเดอร์เป็น `0` เพราะตัวเลขที่ดู
สมเหตุสมผลแต่ไม่จริงอันตรายกว่าช่องว่าง (มีเทสต์ล็อกไว้)

และเพิ่มคีย์ `sightingCount.<region>` ใน `SharedPreferences` นับทุกครั้งที่
`recordSighting()` — ไฟล์ log บันทึกเฉพาะตอนสถานะเปลี่ยน ผลสแกนระหว่างที่ยังอยู่ใน
โซนจึงไม่มีร่องรอยเลย · dump prefs สองครั้งห่างกันตามเวลาที่รู้แน่ = อัตราที่**ระบบ
เลือกจะส่งผลมาให้** (ไม่ใช่อัตราที่ beacon advertise)

⚠️ **`exitTimeoutSeconds` เป็นค่าขั้นต่ำ ไม่ใช่ค่าที่รับประกัน** — นาฬิกาปลุกใช้
`setAndAllowWhileIdle` ซึ่งเอกสารระบุว่าเวลาที่ส่งเข้าไปเป็น inexact ("will not be
delivered before this time, but may be deferred and delivered some time later")
ดูคำต่อคำ + URL ที่ `docs/sources/android_background_ble.md` หัวข้อ 8

**ไฟล์เก่า 5 คอลัมน์ยังต้องอ่านได้ และห้ามแก้ไฟล์เก่า** —
`docs/test-data/2026-08-30_overnight_region_flapping.log` เป็นหลักฐานดิบที่ ADR-11
ทั้งฉบับตั้งอยู่บนมัน การแก้ย้อนหลังทำให้มันเชื่อถือไม่ได้ ตัวอ่านทุกตัวจึงแยกรุ่น
ไฟล์ด้วยการดูว่าคอลัมน์ที่ 2 เป็นเลขฐานสิบหก 8 ตัวหรือไม่ (คอลัมน์ที่ 2 ของไฟล์เก่า
คือชื่อ event ซึ่งไม่มีทางตรงกับรูปแบบนั้น)

`tool/analyze_region_log.dart` ตอนนี้มีสองโหมดและ **บอกผู้อ่านเสมอว่าใช้โหมดไหน**:
ไฟล์ที่มี `processId` จัดกลุ่มตามนั้นตรง ๆ (ข้อเท็จจริง) · ไฟล์เก่าต้องเดาจากลำดับ
เวลา แล้วพิมพ์คำเตือนกำกับว่าเป็นการอนุมาน

**สิ่งที่ทุกบรรทัดตอบได้แล้ว ตามที่โจทย์กำหนด:**

| คำถาม | ตอบจาก |
|---|---|
| process ไหน | คอลัมน์ `processId` |
| สถานะแอปตอนนั้น | คอลัมน์ `conclusion` (`foreground`/`background`/`relaunchedFromTerminated`) + `importance=` ที่ **ระบบ** จัดให้ — ⚠️ ใช้ได้เฉพาะบรรทัด `enter`/`exit`/`selftest` · บรรทัด `launch` เป็น `relaunchedFromTerminated` เสมอโดยโครงสร้าง |
| ถูกสร้างขึ้นมาใหม่หรือไม่ | บรรทัด `launch` มี **หนึ่งบรรทัดต่อหนึ่ง process เสมอ** |

**เกณฑ์ที่โจทย์กำหนดว่าถ้าทำไม่ได้ให้หยุด:** ต้องแยก "แอปไม่ถูกปลุกเลย" ออกจาก
"ถูกปลุกแล้วแต่ไม่ได้รับ event" — แยกได้ด้วยการดูว่ามีบรรทัด `launch` ที่ `processId`
ใหม่หรือไม่ ถ้ามี `launch` แต่ไม่มี `enter`/`exit` ตามมา = ถูกปลุกแล้วแต่ event
ไม่ถึง · ถ้าไม่มีบรรทัดใหม่เลย = ไม่ถูกปลุก

⚠️ **กลไกนี้เองก็ยังไม่ verified บนเครื่องจริง** — มันคือเครื่องมือวัด ไม่ใช่ผลการวัด

---

### 5. หนี้และข้อจำกัดที่รู้ตัว

| หนี้ | สถานะ |
|---|---|
| ไม่มีช่องทางรายงาน error ของเส้นทางเบื้องหลัง (`EXTRA_ERROR_CODE`) ไปถึงผู้ใช้ SDK | `BeaconScanReceiver` ดักไว้แล้วแต่**ทิ้งเงียบ** — ต้องเพิ่ม stream ของ error |
| ยังไม่ประกาศ `directBootAware` | `LOCKED_BOOT_COMPLETED` จึงยังไม่มีผลจริง — ต้องประเมินว่าคุ้มกับการย้าย log ไป device-protected storage หรือไม่ |
| `_splitByPlatformUntilAdr13Step4` ชื่อยังสื่อว่าเป็นหนี้ชั่วคราว | ตอนนี้รู้แล้วว่าถาวร — ต้องเปลี่ยนชื่อและแก้เอกสารในรอบเก็บกวาด |
| ยังไม่มี UX พาผู้ใช้ไปตั้งค่า MIUI Autostart / battery optimization | ADR-12 หัวข้อ 6 + หัวข้อ 2.3 ของ ADR นี้ ชี้ไปที่เรื่องเดียวกัน — เป็นงานที่ต้องทำร่วมกับทีมออกแบบ |
| ยังไม่ทดสอบเพดานจำนวนการลงทะเบียนพร้อมกัน | หัวข้อ 4.1 |
| **ยังไม่รู้ว่า `DateFormatter` ฝั่ง iOS มีปัญหา timezone แบบเดียวกับ Android หรือไม่** | ดูหัวข้อ 5.1 |

#### 5.1 คำถามที่ยังไม่มีคำตอบ — เขตเวลาของ formatter ฝั่ง iOS

**ฝั่ง Android เป็นบั๊กจริงที่ยืนยันแล้วและแก้แล้ว** (1 ก.ย. 2026): CI จับได้ว่า
`SimpleDateFormat` จับ default TimeZone ไว้ตั้งแต่ตอน construct และ formatter ถูก
cache ไว้ใน `ThreadLocal` ตลอดอายุ process → บรรทัดที่เขียนหลังเขตเวลาเปลี่ยนยังใช้
offset เดิม และเธรดต่างกันที่สร้าง formatter คนละเวลาให้ offset ไม่ตรงกันในไฟล์เดียวกัน
ไม่เจอบนเครื่องพัฒนาเพราะเครื่องตั้งเป็น `Asia/Bangkok` อยู่แล้ว จึงบังเอิญถูกเสมอ

**ฝั่ง iOS `formatter` เป็น `static let` จึงมีรูปร่างความเสี่ยงเหมือนกันทุกประการ**
— แต่ **ยังพิสูจน์ไม่ได้ว่ามีปัญหาจริงหรือไม่** และตอนนี้ยัง**ไม่ได้แก้**

สิ่งที่ลองแล้วและผลที่ได้:

| ลอง | ผล |
|---|---|
| ตั้ง `formatter.timeZone = TimeZone.current` ก่อน format แล้วเขียน XCTest ที่เปลี่ยน `NSTimeZone.default` ระหว่างเทสต์ | เทสต์ล้ม — `"...+07:00" is not equal to "...Z"` |
| เปลี่ยนเป็น `TimeZone.autoupdatingCurrent` | เทสต์ยังล้มเหมือนเดิม |

**แยกไม่ออกว่าผลนี้แปลว่าอะไร** ระหว่างสองข้อที่ต้องแก้คนละทางโดยสิ้นเชิง:

1. iOS มีบั๊กจริงแบบเดียวกับ Android (เทสต์ถูก โค้ดยังผิด)
2. `NSTimeZone.default` ที่ตั้งใน XCTest ไม่มีผลกับสิ่งที่ `DateFormatter` อ่าน
   จึง**จำลองการเปลี่ยนเขตเวลาบน iOS ด้วยวิธีนี้ไม่ได้เลย** (เทสต์ผิด โค้ดอาจไม่มีปัญหา)

header ของ `NSDateFormatter.h` ที่ตรวจแล้ว **ไม่มีประโยคใดระบุว่ามันอ่านเขตเวลาใหม่
ทุกครั้งหรือไม่** จึงตอบจากเอกสารในเครื่องไม่ได้ตาม CONTRIBUTING ข้อ 5

**ตัดสินใจ: ถอยการแก้ฝั่ง iOS ออกทั้งหมด แล้วบันทึกไว้เป็นคำถามที่ยังไม่มีคำตอบ**
การไล่เปลี่ยน API ของ Swift ไปเรื่อย ๆ จนกว่าเทสต์จะเขียว คือการ**ดัดเทสต์ให้ผ่าน
ไม่ใช่การพิสูจน์** และจะได้ผลลัพธ์ที่ดูเหมือน verified ทั้งที่ไม่ใช่ ซึ่งแย่กว่าการ
ไม่แก้เลย

**วิธีตอบคำถามนี้ให้จบ (ยังไม่ได้ทำ):** ทดสอบบนอุปกรณ์จริง — เปลี่ยนเขตเวลาของ
iPhone ระหว่างที่ process เฝ้า region อยู่ แล้วดูว่าบรรทัดถัดไปในไฟล์หลักฐานใช้
offset ใหม่หรือ offset เดิม เป็นการวัดพฤติกรรมจริงซึ่งตอบได้แน่นอน ต่างจากการ
จำลองใน simulator

---

### 6. 🛑 สถานะการทดสอบบนอุปกรณ์จริง — **ยังไม่ได้ทดสอบ**

**ติดตั้งแอปลงเครื่องไม่ได้** — MIUI ปฏิเสธการติดตั้งผ่าน adb:

```
adb: failed to install app-debug.apk:
  Failure [INSTALL_FAILED_USER_RESTRICTED: Install canceled by user]
```

ตรวจแล้วว่าไม่ใช่ปัญหาที่แก้จากฝั่งเครื่องพัฒนาได้:
`adb shell settings put global adb_install_need_confirm 0` ถูกปฏิเสธด้วย
`SecurityException: Permission denial: writing to settings requires
android.permission.WRITE_SECURE_SETTINGS`

**ต้องให้เจ้าของเครื่องเปิดสวิตช์เอง** — MIUI Developer options →
"ติดตั้งผ่าน USB" (Install via USB) ซึ่งต้องล็อกอินบัญชี Xiaomi และใส่ซิมในเครื่อง

**ตามกฎการรายงานสถานะของ CONTRIBUTING ข้อ 4 สถานะที่ถูกต้องคือ
`code-complete, unverified`** — ห้ามเขียนว่าอะไรทำงานได้ทั้งสิ้น รวมถึงข้อสรุปเรื่อง
`FLAG_MUTABLE` ในหัวข้อ 2.1 ซึ่งเป็นการต่อประโยคจากเอกสาร ไม่ใช่การทดลอง

ขั้นตอนการทดสอบทั้งหมดอยู่ที่
**`docs/test-checklists/android_background_runbook.md`** พร้อมช่องกรอกผลที่ยังว่าง

**สิ่งที่ห้ามทำจนกว่าจะมีผลจริง:**
- ห้ามเขียนว่า Android ทำงานเบื้องหลังได้เท่า iOS
- ห้ามรายงานว่าเคสไหนผ่าน ถ้ายังไม่เห็นบรรทัด **`enter`/`exit`** ที่มี `procUuid`
  ซึ่งไม่เคยปรากฏมาก่อนในไฟล์เดียวกัน พร้อม `conclusion=relaunchedFromTerminated`
  และ `receiverEntry=true` — **บรรทัด `launch` ไม่นับ** เพราะ `conclusion` ของมัน
  เป็น `relaunchedFromTerminated` เสมอโดยโครงสร้างของโค้ด
- ทุกครั้งที่รายงานผล ต้องระบุ **รุ่นเครื่อง / เวอร์ชัน Android / เวอร์ชัน MIUI /
  สถานะ Autostart / สถานะ battery optimization**

---

## ADR-15 (ฉบับร่าง — ยังไม่ตัดสิน): `exitTimeoutSeconds` เป็นสัญญาที่ทำไม่ได้ (เพิ่ม 2 ก.ย. 2026)

> **สถานะ: ร่าง** — ยังไม่ได้แก้โค้ดใด ๆ เอกสารนี้เสนอทางเลือกพร้อมข้อแลกเปลี่ยน
> ให้เลือก ไม่ได้ประกาศการตัดสินใจ

### 1. ปัญหา

`startBackgroundRegionMonitoring(regions:, exitTimeoutSeconds:)` รับตัวเลขวินาทีจาก
ผู้ใช้ SDK แล้ว **ไม่บอกอะไรเลยว่าค่านั้นหมายถึงอะไร** ชื่อพารามิเตอร์อ่านได้เป็น
"ไม่เห็น N วินาทีแล้วจะได้ `exit`" ซึ่ง **ไม่จริง** และแพลตฟอร์มก็ไม่เคยรับปากไว้

**หลักฐานจากเอกสารทางการ** (คำต่อคำ + URL ครบใน
`docs/sources/android_background_ble.md` หัวข้อ 8): นาฬิกาปลุกใช้
`AlarmManager.setAndAllowWhileIdle` (`BackgroundRegionMonitor.kt:365`) ซึ่งเอกสาร
ระบุว่าเวลาที่ส่งเข้าไปเป็น **inexact** — *"the alarm will not be delivered before
this time, **but may be deferred and delivered some time later**"* และ *"it will not
dispatch these alarms more than about every minute…; when in low-power idle modes
this duration may be significantly longer, **such as 15 minutes**"*

> เอกสารรับประกัน **ด้านล่างด้านเดียว** ไม่มีเพดานบนที่รับประกัน

**หลักฐานจากเครื่องจริง** (`docs/test-data/2026-09-01_android_overnight_region_flapping.log`,
หน้าต่าง 17:54 → 08:39, `exitTimeoutSeconds=30` อ่านยืนยันจาก `shared_prefs`):

| ที่วัดได้ | ค่า |
|---|---|
| ช่วง "อยู่ในโซน" ที่ตกในช่วง 25–40 วินาที | **0 จาก 57** |
| ความยาวช่วงที่พบบ่อยที่สุด | **10 นาที ×21 · 15 นาที ×11** |
| วินาที (ในนาที) ของบรรทัด `exit` ที่ตกในช่วง 27–30 | **51 จาก 58 = 87.9%** (ฐานนิยม 28 วิ) |
| เทียบกับบรรทัด `enter` ในหน้าต่างเดียวกัน | 17.2% — **การเกาะกลุ่มเป็นของ `exit` เท่านั้น** |

**ค่า 30 วินาทีที่ตั้งไว้ไม่ได้กำหนดเวลาที่ `exit` เกิดขึ้นเลยแม้แต่ครั้งเดียวใน
57 ครั้ง** สิ่งที่กำหนดคือจังหวะที่ระบบเลือกจะส่งนาฬิกาปลุก

### 2. ทำไมเรื่องนี้ร้ายแรงกว่า "ค่าไม่แม่น"

ผู้ใช้ SDK ตั้ง 30 แล้วออกแบบตรรกะธุรกิจบนสมมติฐาน "รู้ผลภายในครึ่งนาที" — สิ่งที่
ได้จริงคือ **มัธยฐาน 10 นาที** ความคลาดเคลื่อน **20 เท่า** ไม่ใช่ความไม่แม่นยำ
แต่เป็น **สัญญาที่ผิด** และมันผิดแบบเงียบ: ไม่มี error ไม่มี warning ไม่มีอะไรฟ้อง

### 3. ทางเลือก (เลือกได้มากกว่าหนึ่งข้อ)

#### ก. เอกสาร — ระบุว่าเป็นขอบล่าง **(แนะนำ ทำได้ทันที ไม่มีข้อเสีย)**

แก้ KDoc/dartdoc ของ `exitTimeoutSeconds` ทุกชั้น (Dart API, platform interface,
`BackgroundRegionStore.DEFAULT_EXIT_TIMEOUT_SECONDS`) ให้ระบุตรง ๆ ว่า

> **ค่านี้คือเวลา *อย่างน้อยที่สุด* ที่ต้องไม่เห็น beacon ก่อนจะประกาศ `exit`
> ไม่ใช่เวลาที่จะได้รับ `exit` จริง** เวลาจริงถูกกำหนดโดย `AlarmManager` และวัดได้
> จาก log คืน 1 ก.ย. ว่ามัธยฐานอยู่ที่ ~10 นาทีเมื่อตั้งค่าไว้ 30 วินาที

**ข้อแลกเปลี่ยน:** ไม่มี — เป็นการเขียนความจริงที่วัดได้แล้วลงไป · **ไม่ได้แก้ปัญหา**
แค่หยุดโกหก

#### ข. clamp ค่าที่ต่ำกว่าที่แพลตฟอร์มทำได้

ปัดค่าที่ต่ำกว่าเกณฑ์ขึ้นเป็นเกณฑ์ แล้วคืนค่าที่ใช้จริงกลับไปใน
`AndroidBackgroundMonitoringResult` เพื่อให้ผู้เรียก**เห็นว่าถูกปัด**

**ข้อแลกเปลี่ยน:**
- ✅ ผู้เรียกไม่ได้ค่าที่เป็นไปไม่ได้ และรู้ตัวว่าถูกปัด
- ❌ **ยังไม่รู้ว่าเกณฑ์ควรเป็นเท่าไร** — เอกสาร Android ไม่ได้ให้เพดานบนไว้
  (`docs/sources/android_background_ble.md` ระบุว่า **หาแหล่งอ้างอิงไม่ได้**)
  ตัวเลขที่มีตอนนี้คือ **~1 นาที (ปกติ) / ~15 นาที (idle)** ซึ่งเป็น *ความถี่ในการ
  dispatch* คนละเรื่องกับความคลาดเคลื่อนของนาฬิกาปลุกอันหนึ่ง
- ❌ clamp ที่ 60 วินาทีจะ**ดูเหมือนแก้แล้ว** ทั้งที่ข้อมูลจริงชี้ว่ามัธยฐานคือ 10 นาที
- ⚠️ เป็นการเปลี่ยนพฤติกรรมของ API ที่มีผู้ใช้แล้ว

#### ค. ปฏิเสธค่าที่ต่ำเกินไป (`INVALID_ARGUMENT`)

**ข้อแลกเปลี่ยน:**
- ✅ ล้มเสียงดังตั้งแต่ตอนพัฒนา ดีกว่าล้มเงียบตอนอยู่หน้าสาขา
- ❌ breaking change เต็มรูป — โค้ดที่รันอยู่แล้วจะพังทันทีที่อัปเดต SDK
- ❌ มีปัญหาเดียวกับข้อ ข. คือ **ยังไม่รู้เกณฑ์**

#### ง. เปลี่ยนชื่อพารามิเตอร์

`exitTimeoutSeconds` → `minimumSilenceBeforeExitSeconds` (หรือใกล้เคียง)

**ข้อแลกเปลี่ยน:**
- ✅ แก้ที่ต้นเหตุ: ชื่อคือสิ่งที่ทำให้คนอ่านเข้าใจผิดตั้งแต่แรก และไม่มีทางเข้าใจ
  ผิดซ้ำได้อีก
- ❌ breaking change ของ API
- ➖ ทำคู่กับข้อ ก. ได้ และควรทำพร้อมกันถ้าจะเปลี่ยน

#### จ. รายงานเวลาที่ได้จริงกลับไปพร้อม event **(แนะนำ ทำไปแล้วบางส่วน)**

ใส่ `sinceLastSeenMs` / `scheduledAtElapsed` / `firedAtElapsed` ไปกับ event เพื่อให้
ผู้เรียก **วัดเองได้ว่าได้อะไรจริง** แทนที่จะเชื่อค่าที่ตั้งไป

**สถานะ:** โค้ดเขียนและมี unit test แล้ว (1 ก.ย.) **แต่ยังไม่ได้ติดตั้งลงเครื่อง**
จึงยังไม่มีข้อมูลจากสนาม · ตราบใดที่ยังไม่มี การถกเรื่องเกณฑ์ในข้อ ข./ค. จะทำได้
ด้วย **ขอบล่าง** เท่านั้น

**ข้อแลกเปลี่ยน:** ✅ ไม่ breaking (เพิ่มฟิลด์) · ❌ ไม่ได้แก้สัญญาที่ผิด แค่ทำให้
ตรวจสอบได้

### 4. ⚠️ พารามิเตอร์นี้ **ไม่มีผลใด ๆ บน iOS**

`exitTimeoutSeconds` อยู่บนเส้นทาง `beacon_kit_android` **เท่านั้น** ฝั่ง iOS
CoreLocation ยิง `didExitRegion` ให้เอง และ **ADR-11 ค้นแล้วไม่พบเอกสาร Apple ที่
ระบุหรือให้ปรับค่าหน่วงนี้** — ไม่มีอะไรให้ตั้ง

ผลที่ตามมาและต้องเขียนไว้ในเอกสารสาธารณะของ SDK:

> การตั้ง `exitTimeoutSeconds` **ไม่ทำให้พฤติกรรมสองแพลตฟอร์มเท่ากัน** และค่าเดียวกัน
> **ไม่ได้แปลว่าทั้งสองแพลตฟอร์มจะรายงาน `exit` ในเวลาใกล้เคียงกัน** — บน iOS ค่านี้
> ถูกเมินทั้งหมด

ค่าเริ่มต้น 30 วินาทีถูกเลือกให้ตรงกับค่าที่ **วัดได้จากพฤติกรรมของ iOS** (ADR-11
หัวข้อ 2) เพื่อให้ผลรอบทดสอบแรกเทียบกันได้ — **ไม่ใช่เพราะ Android ทำได้ 30 วินาที**
ข้อมูลคืน 1 ก.ย. แสดงว่าทำไม่ได้

### 5. ตัวเลขที่มีสำหรับตั้งเกณฑ์ (ขอบล่างทั้งหมด)

จาก `docs/test-data/2026-09-01_android_overnight_region_flapping.log`:

| | doze=false | doze=true |
|---|---|---|
| ความเงียบที่วัดได้ p95 (ขอบล่าง) | 1 น 36 วิ | 1 น 51 วิ |
| ความเงียบที่วัดได้ สูงสุด (ขอบล่าง) | 1 น 36 วิ | **2 น 50 วิ** |

- ค่าที่จะทำให้ **exit ปลอมเป็นศูนย์** ในชุดข้อมูลนี้: **> 2 นาที 50 วินาที** → ~3 นาที
- เผื่อขอบ = **5 นาที** (ตรงกับเกณฑ์ merge ที่ได้จาก iOS และใช้ได้พอดีกับทั้งสองไฟล์)

⚠️ **ทั้งหมดเป็นขอบล่าง** เพราะ log ที่เก็บด้วยบิลด์นั้นไม่มี `sinceLastSeenMs`
เวลาจริงตั้งแต่เห็นครั้งสุดท้ายจนประกาศ `exit` จึงยังไม่รู้ · **การขยาย timeout
ยังเปลี่ยนว่านาฬิกาปลุกจะไปตก batch ไหนด้วย** ผลลัพธ์จึงคาดเดาตรง ๆ จากตัวเลขชุดนี้
ไม่ได้ ต้องวัดซ้ำหลังเปลี่ยนค่า

### 6. ข้อเสนอลำดับการทำ

1. **ข้อ ก. (เอกสาร)** — ทำได้ทันที ไม่มีข้อเสีย หยุดสัญญาที่ผิดก่อน
2. **ข้อ จ. (ติดตั้งฟิลด์วัดผล)** — เก็บข้อมูลหนึ่งคืนเพื่อให้เลิกเถียงด้วยขอบล่าง
3. **ค่อยตัดสิน ข./ค./ง.** เมื่อมีตัวเลขจริง — **ห้ามเลือกเกณฑ์ clamp จากตัวเลข
   ขอบล่างในข้อ 5** เพราะมันจะดูเหมือนแก้แล้วทั้งที่ยังไม่รู้ค่าจริง

---

## ADR-16: แหล่งความจริงใหม่ของ `hasEverBecomeActive` ภายใต้ UIScene lifecycle — แก้บั๊ก `everActive` ค้าง `false` ตลอดชีพ process (เพิ่ม 3 ก.ย. 2026)

> **สถานะ: ตัดสินใจด้านสถาปัตยกรรมแล้ว — ยังไม่ implement**
> นี่คือขั้นที่ 1/4 ตาม PIPELINE.md (ออกแบบ) เท่านั้น ห้ามมีโค้ด Swift ในเอกสารนี้
> หรือในการเปลี่ยนแปลงรอบนี้ — ขั้นเขียนโค้ดเป็นของ `flutter-dev` เมื่อสถาปัตยกรรม
> ในหัวข้อนี้ถูก sign-off แล้วเท่านั้น
> **ขอบเขต:** เฉพาะ `packages/beacon_kit/example/ios/Runner/AppDelegate.swift`
> (โค้ดวัดผลของ **example app** เหมือน ADR-10 — ไม่แตะ `beacon_kit_ios` SDK,
> ไม่แตะ Android, ไม่แตะสัญญา Dart)

### 0. บั๊กที่ต้องแก้ (สรุปจากงานตรวจสอบก่อนออกแบบรอบนี้)

`AppDelegate.swift:252-255` ตั้ง `hasEverBecomeActive = true` ใน
`override func applicationDidBecomeActive` จุดเดียว แอปนี้ประกาศ
`UIApplicationSceneManifest` ใน `Info.plist:40-60` (`UISceneDelegateClassName =
$(PRODUCT_MODULE_NAME).SceneDelegate`) — ตามหลักฐานเอกสาร Apple ในหัวข้อ 1.1
ด้านล่าง **`applicationDidBecomeActive` ไม่ถูกเรียกเลยเมื่อแอปใช้ scene** ไม่ใช่
"บางเคส" ผลคือ `hasEverBecomeActive` ค้าง `false` **ตลอดชีพ process ทุกกรณี**
รวมถึงตอนแอปอยู่ foreground จริง (`state=active`) ก็ยังรายงาน `everActive=false`
ตามหลักฐานอุปกรณ์จริง 3 ก.ย. 2026 (process `ed11d170`, บรรทัด `exit` เวลา
13:57:11.974 มี `state=active everActive=false` พร้อมกัน — เป็นข้อขัดแย้งที่ยืนยัน
บั๊กได้เอง โดยไม่ต้องอาศัยการตีความ)

ผลกระทบต่อระบบวัดผล: `currentRunContext()` (`AppDelegate.swift:155-164`) แยก
`background` ออกจาก `relaunchedFromTerminated` ด้วยค่านี้เพียงค่าเดียว — เมื่อ
มันค้าง `false` เสมอ ทุกบรรทัดที่ `state` ไม่ใช่ `active` จะถูก stamp เป็น
`relaunchedFromTerminated` **โดยไม่สนใจว่าความจริงเป็นอย่างไร**

### 1. (a) แหล่งความจริงใหม่ของ `hasEverBecomeActive`

#### 1.1 หลักฐานจากเอกสาร Apple (ดึงจาก data endpoint ของหน้าเอกสารทางการจริง 3 ก.ย. 2026 — ไม่ใช่การเดา)

**`applicationDidBecomeActive(_:)`**
<https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationdidbecomeactive(_:)>

> "If you're using scenes (see Scenes), UIKit will not call this method. Use
> `sceneDidBecomeActive(_:)` instead to restart any tasks or refresh your app's
> user interface. **UIKit posts a `didBecomeActiveNotification` regardless of
> whether your app uses scenes.**"
>
> **แก้ไข 3 ก.ย. 2026 — ที่มาของคำพูดด้านล่างนี้ไม่ตรงตามที่บันทึกไว้เดิม:**
> ข้อความก่อนหน้านี้ ("This method is deprecated as of iOS 26.0 ... Use the
> UIScene lifecycle with...") หาคำต่อคำในหน้าเอกสารนี้ไม่เจอ — หน้านี้ไม่มี
> ประโยคดังกล่าว มีแต่คำเตือน deprecation สั้น ๆ (แสดงเป็นกล่องเตือนบนหน้าเว็บ
> มาจากฟิลด์ `deprecationSummary`/`metadata.platforms[].message` ของ JSON data
> endpoint หน้าเดียวกัน) ซึ่งข้อความคำต่อคำคือ:
>
> "Use UIScene lifecycle and sceneDidBecomeActive(_:) from UISceneDelegate or
> the UIApplication.didBecomeActiveNotification instead."
>
> ส่วนเลขเวอร์ชัน **iOS 26.0** มาจากฟิลด์โครงสร้าง
> `metadata.platforms[].deprecatedAt` ของ JSON เดียวกัน (คู่กับ
> `introducedAt: "2.0"`) — เป็นข้อมูลเชิงโครงสร้าง (availability range) ไม่ใช่
> ข้อความที่เขียนเป็นประโยคบนหน้าเว็บ จึงไม่ใส่ในเครื่องหมายคำพูดคู่กับข้อความ
> ข้างบน เนื้อหาที่บันทึกไว้เดิม (deprecated ใน iOS 26.0, แนะนำให้ใช้
> `sceneDidBecomeActive(_:)` หรือ `UIApplication.didBecomeActiveNotification`
> แทน) **ยังถูกต้องทั้งหมด** มีแค่การอ้างว่าเป็นคำพูดคำต่อคำที่ผิด

**`sceneDidBecomeActive(_:)`**
<https://developer.apple.com/documentation/uikit/uiscenedelegate/scenedidbecomeactive(_:)>

> "In addition to calling this method, UIKit posts a `didActivateNotification`
> and a `didBecomeActiveNotification`."
>
> "When you implement this method and enable scenes, UIKit calls this method
> but **does not call the `applicationDidBecomeActive(_:)` method** on
> `UIApplicationDelegate`."

**`UIApplication.didBecomeActiveNotification`**
<https://developer.apple.com/documentation/uikit/uiapplication/didbecomeactivenotification>

> "An app is active when it is receiving events. An active app can be said to
> have focus. It gains focus after being launched, loses focus when an overlay
> window pops up or when the device is locked, and gains focus when the device
> is unlocked."

สามหน้านี้ประกอบกันยืนยันข้อเท็จจริงสามข้อที่จำเป็นต่อการตัดสินใจ:

1. เหตุผลของบั๊กคือสิ่งที่ Apple บอกไว้ตรง ๆ ไม่ใช่การเดา — แอปใช้ scene จึง
   `applicationDidBecomeActive` ไม่ถูกเรียก
2. `sceneDidBecomeActive(_:)` (ถ้า override ใน `SceneDelegate`) จะถูกเรียกแทน
3. **`didBecomeActiveNotification` ถูก post เสมอ "regardless of whether your
   app uses scenes"** — ประโยคนี้คือกุญแจของการตัดสินใจข้อ 1.3

**หมายเหตุความน่าเชื่อถือ:** พบความเห็นจากบุคคลที่สาม (ไม่ใช่ Apple) ใน GitHub
issue ของ SDK อื่น (`OneSignal-iOS-SDK#647`,
<https://github.com/OneSignal/OneSignal-iOS-SDK/issues/647>) ที่ตั้งข้อสังเกตว่า
`UIApplicationDidBecomeActiveNotification` ยังคงถูก post ภายใต้ scene lifecycle
แต่เดาว่า **"this seems like an oversight on Apple's part that might change in
the future"** — ข้อความนี้**ขัดแย้งกับเอกสารทางการที่ยกมาข้างบน** ซึ่งระบุ
"regardless of whether your app uses scenes" อย่างชัดเจนว่าเป็นพฤติกรรมที่ตั้งใจ
ไม่ใช่ oversight เราเลือกเชื่อเอกสารทางการ (first-party, หน้าเอกสาร API ปัจจุบัน)
เหนือความเห็นบุคคลที่สามใน GitHub issue ของ SDK อื่น — แต่บันทึกความเห็นนี้ไว้
เพราะเป็นสัญญาณเดียวที่มีว่า Apple *เคย* ถูกมองว่าพฤติกรรมนี้ไม่ตั้งใจมาก่อน

#### 1.2 ทางเลือกที่พิจารณา และเหตุผลที่ไม่เลือก

| ทาง | เนื้อหา | ผล |
|---|---|---|
| **ก. Override `sceneDidBecomeActive` ใน `SceneDelegate` แล้วเรียกกลับ `AppDelegate`** | ต้อง cast `UIApplication.shared.delegate as! AppDelegate` หรือส่ง reference ให้ `SceneDelegate` ถืออ้างอิงไปยัง `AppDelegate` | **ไม่เลือก** — `SceneDelegate.swift` เป็นคลาสว่างของ **example app** (ไม่ใช่ SDK) ส่วนสถานะที่ต้องแก้อยู่ใน `AppDelegate` คนละคลาส การให้ `SceneDelegate` ต้องรู้จัก `AppDelegate` โดยตรงเป็นการผูก (couple) สองคลาสที่ ADR-10 ตั้งใจแยกให้ `AppDelegate` เป็นเจ้าของสถานะแต่ผู้เดียวอยู่แล้ว (ดูเหตุผล "ผู้เขียน log เพียงรายเดียว" ใน ADR-10 (ฉ)) — ยิ่งไปกว่านั้น ตามหลักฐานหัวข้อ 1.1 การ override `sceneDidBecomeActive` ก็ยังทำให้ UIKit post `didBecomeActiveNotification` เหมือนกันอยู่ดี แปลว่าเป็นการเขียนโค้ดเพิ่มเพื่อได้สัญญาณที่ทางเลือก ข. ได้มาฟรีอยู่แล้ว |
| **ข. สังเกต `UIApplication.didBecomeActiveNotification` ผ่าน `NotificationCenter` จาก `AppDelegate` เอง** | ลงทะเบียน observer ใน `application(_:didFinishLaunchingWithOptions:)` | **เลือก** — เหตุผลเต็มในหัวข้อ 1.3 |
| **ค. สังเกต `UIScene.didActivateNotification`** | แจ้งเมื่อ scene หนึ่ง ๆ active | ไม่เลือกเป็นสัญญาณหลัก — เป็นระดับ **scene** ไม่ใช่ระดับ **app** ถ้าวันหนึ่ง `UIApplicationSupportsMultipleScenes = true` (ปัจจุบันเป็น `false` ที่ `Info.plist:42-43`) ความหมายที่ต้องการคือ "แอปนี้เคย active หรือยัง" (ระดับ app) ไม่ใช่ "scene ตัวนี้เคย active หรือยัง" (ระดับ scene) — `didBecomeActiveNotification` เป็นระดับ app โดยตรงและถูก post คู่กับ `didActivateNotification` เสมอตามหลักฐานหัวข้อ 1.1 จึงไม่มีเหตุผลต้องลงระดับ scene |
| **ง. คงไว้เฉยๆ ไม่แก้ (ปล่อยให้ค้าง `false`)** | — | ไม่เลือก — ตามที่บั๊กนี้ระบุไว้ในหัวข้อ 0 คือสิ่งที่ต้องแก้ |

#### 1.3 การตัดสินใจ

**ลงทะเบียน `NotificationCenter` observer สำหรับ `UIApplication.didBecomeActiveNotification`
จาก `AppDelegate.application(_:didFinishLaunchingWithOptions:)`** เพื่อตั้ง
`hasEverBecomeActive = true` — **`AppDelegate` ยังคงเป็นเจ้าของสถานะและผู้แจ้งแต่
ผู้เดียวเหมือนเดิมทุกประการ ไม่มีคลาสอื่นเข้ามาเกี่ยวข้อง**

**ทำไมจังหวะลงทะเบียนนี้ปลอดภัย (ไม่มี race กับ scene connect):** เอกสาร Apple ของ
`application(_:didFinishLaunchingWithOptions:)` ระบุลำดับเหตุการณ์ของแอปที่รองรับ
scene ไว้ตรง ๆ ว่า "The system calls this method as soon as the process is done
launching. The system then creates the scene(s) that you configured for your
app. The system calls scene life-cycle methods, such as
`scene(_:willConnectTo:options:)`." — `didFinishLaunchingWithOptions` เกิด
**ก่อน** scene ใด ๆ ถูก connect เสมอ การลงทะเบียน observer ที่จุดเริ่มของเมธอดนี้
(จุดเดียวกับที่ ADR-10 เรียก `startBackgroundRegionMonitoring`) จึงรับประกันว่า
observer มีตัวตนก่อนโอกาสแรกที่ `didBecomeActiveNotification` จะถูก post ได้

**เก็บ `override func applicationDidBecomeActive` เดิมไว้ด้วย** (ไม่ลบ) เป็น
defensive fallback ที่ไม่มีต้นทุน — ถ้าวันหนึ่งแอปเลิกใช้ scene (`Info.plist`
ไม่มี `UIApplicationSceneManifest`) เส้นทางเดิมจะกลับมาทำงานได้เองโดยไม่ต้องแก้โค้ด
เพิ่ม ทั้งสองเส้นทางตั้งค่าตัวแปร `Bool` เดียวกันแบบ **idempotent** (ตั้งเป็น
`true` ซ้ำได้ไม่มีผลข้างเคียง) จึงไม่มีความเสี่ยงเรื่อง race ระหว่างสองเส้นทาง

#### 1.4 ตอบข้อกังวลที่ระบุไว้ในโจทย์ครบทุกข้อ

| ข้อกังวล | คำตอบ |
|---|---|
| ใครเป็นเจ้าของสถานะ/ใครแจ้ง | `AppDelegate` เจ้าของและผู้แจ้งแต่ผู้เดียว ทั้งก่อนและหลังแก้ — `SceneDelegate.swift` **ไม่ต้องแก้ไขแม้แต่บรรทัดเดียว** ยังคงว่างเปล่าได้ตามเดิม เพราะสัญญาณที่ใช้เป็นระดับ `UIApplication` ไม่ใช่ระดับ scene |
| `UIApplicationSupportsMultipleScenes = false` วันนี้ ต้องทนถ้าวันหนึ่งเป็น `true` | `didBecomeActiveNotification` เป็น notification ระดับ **app** (มาจาก class `UIApplication` ไม่ใช่ instance ของ scene ใดตัวหนึ่ง) — ความหมายคงเดิมไม่ว่าจะมีกี่ scene: "แอปนี้ active" ไม่ใช่ "scene ตัวนี้ active" จึงไม่ต้องแก้อะไรถ้าวันหนึ่งเปิดหลาย scene |
| process ที่ถูกปลุกเบื้องหลังอาจไม่มี scene เลย ต้องไม่พัง/ไม่รายงานผิด | ถ้าไม่มี scene ถูก connect เลย จะไม่มี `sceneDidBecomeActive` เกิดขึ้น และไม่มีเหตุการณ์ใดทำให้ `didBecomeActiveNotification` ถูก post — observer จึงไม่ทำงาน `hasEverBecomeActive` ค้าง `false` ต่อไป **ซึ่งเป็นคำตอบที่ถูกต้องพอดี** (process ที่ไม่มี UI เลยไม่เคย active จริง) ไม่มี optional การ unwrap ที่จะ crash เพราะ observer ใช้ global notification ไม่ใช่การอ้างอิง scene object ใด ๆ |
| ห้ามเปลี่ยนความหมาย `foreground`/`background`/`relaunchedFromTerminated` ข้ามแพลตฟอร์ม | **ไม่เปลี่ยน** — การแก้นี้เปลี่ยนแค่ **แหล่งที่มาของค่า** `hasEverBecomeActive` (`Bool`) ฝั่ง iOS เท่านั้น ไม่เปลี่ยนชื่อฟิลด์ ไม่เปลี่ยน type ไม่เปลี่ยนตรรกะการแปลผลใน `currentRunContext()` (`AppDelegate.swift:155-164`), ไม่เปลี่ยน `AppRunContext`/`LaunchDiagnostics.context` ฝั่ง Dart (`launch_context.dart:70-78`), และ **ไม่กระทบ Android เลย** เพราะ `ProcessState.kt` ใช้ `Application.ActivityLifecycleCallbacks` ซึ่งไม่มีปัญหานี้ (Android ไม่มีแนวคิด scene) — ตรวจแล้วว่า `ProcessState.kt` และ `launch_context.dart` ไม่ต้องแก้ไขไฟล์ใด ๆ ในงานนี้ |

### 2. (b) `launchedByLocationKey` ยังหาได้ไหมภายใต้ UIScene lifecycle

**คำตอบ: หาไม่ได้อีกต่อไปในทางปฏิบัติ — มีเอกสาร Apple ยืนยันตรง ๆ ว่าเหตุใด**
(ไม่ใช่แค่ deprecation — ตัว dictionary ทั้งก้อนเป็น `nil`)

**`application(_:didFinishLaunchingWithOptions:)` — พารามิเตอร์ `launchOptions`**
<https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:didfinishlaunchingwithoptions:)>

> "A dictionary indicating the reason the person or system launched the app.
> The contents of this dictionary may be empty in situations where a person
> launched the app directly. **If the app supports scenes, this is `nil`.**
> For information about the possible keys in this dictionary and how to handle
> them, see `UIApplication.LaunchOptionsKey`."

**Apple Developer Forums — คำตอบจาก Apple engineer**, กระทู้ "Scene-based Launch
Detection" <https://developer.apple.com/forums/thread/814444>

> "For apps that support UIScene, the UIApplication launch options will be nil.
> Instead the app will be presented with the `UIScene.ConnectionOptions`. **Not
> every launch option will have an equivalent connection option.** Specifically
> for CoreLocation triggered app launches, as after launch there will always be
> a delegate method that will be called to pass on the information, you can use
> that as an indicator that your app was launched by CoreLocation and based on
> the specific method that was called back, you can determine which API has
> triggered it."

**หมายเหตุความน่าเชื่อถือของแหล่งที่สอง:** เป็น Apple Developer Forums ซึ่งเป็น
โดเมนทางการของ Apple และคำตอบระบุว่ามาจาก Apple engineer แต่ WebFetch ที่ใช้ค้น
ไม่สามารถยืนยัน username/badge ของผู้ตอบได้โดยตรง (เห็นเฉพาะเนื้อหาที่ดึงมา ไม่เห็น
หน้าเว็บเต็ม) — ความน่าเชื่อถือจึงต่ำกว่าหน้าเอกสาร API อย่างเป็นทางการหน้าแรก
เล็กน้อย แต่ **สอดคล้องกันเป๊ะ** กับหน้าเอกสาร API ("launchOptions will be nil"
ตรงกับ "this is nil") จึงถือว่ายืนยันซ้ำแล้ว (independent confirmation ตามกติกา
"ห้ามเดา")

**สรุปผลต่อ `launchedByLocationKey`:**

แอปนี้ประกาศ `UIApplicationSceneManifest` (`Info.plist:40-60`) จึง "supports
scenes" ตามคำจำกัดความข้างบน — `launchOptions` ทั้ง dictionary เป็น `nil` เสมอ
ไม่ใช่แค่ key `.location` หายไป **`launchedByLocationKey = launchOptions?[.location]
!= nil` จะได้ `false` เสมอ ไม่ว่าเหตุผลการ launch จะเป็นอะไรก็ตาม** ซึ่งตรงกับ
สิ่งที่วัดได้จากอุปกรณ์จริง 2 รอบเมื่อ 30 ส.ค. 2026 (`launchKey=false` ทั้งสองรอบ
ทั้งที่ยืนยันแล้วว่าเป็นการปลุกจากสถานะ terminated จริง — ADR-10 หัวข้อ 6)

**ผลต่อ open question ในเช็คลิสต์ (`docs/test-checklists/ios_broadcast_scanning.md`
หัวข้อ 12 🔍):** เอกสารนี้**อธิบายกลไกของสมมติฐาน (ข) ได้ตรงและสมบูรณ์กว่าที่บันทึกไว้เดิม**
(เดิมมีแค่ข้อความ deprecation ที่พูดถึง "after scene connection" แบบเป็นนัย
ตอนนี้มีเอกสารบอกตรง ๆ ว่า "launchOptions will be nil") — สมมติฐาน (ก) ในเรื่อง
deprecation กลายเป็น**ไม่จำเป็นต้องพิสูจน์อีกต่อไป** เพราะ (ข) อธิบายผลที่วัดได้ครบ
อยู่แล้วโดยไม่ต้องอาศัย (ก) เลย

**แต่ยังต้องรักษาสถานะ open question ในไฟล์เช็คลิสต์ไว้ตามที่งานนี้ระบุ — ห้ามปิด
เอง:** สิ่งที่ยังพิสูจน์ไม่ได้จริง ๆ คือ**การเทียบกับอุปกรณ์จริง** — เอกสารนี้อธิบาย
เชิงทฤษฎีว่าทำไม `launchKey=false` ถึงเกิดขึ้นได้ (และสอดคล้องกับข้อมูลที่มีอยู่
2/2 รอบ) แต่**ยังไม่มีการทดสอบอุปกรณ์จริงที่ตั้งใจแยกกรณีนี้โดยเฉพาะ** เช่น การ
เทียบกับบิลด์ที่ไม่ใช้ scene lifecycle — ซึ่งตามขอบเขตงานนี้ (`beacon-qa` เป็นคน
ปิดสถานะการทดสอบ) จะให้เหตุผล ไม่ประกาศปิด ไว้ในหัวข้อนี้เท่านั้น การปิดสถานะ
open question ในไฟล์เช็คลิสต์เองเป็นงานของ `beacon-qa` ในขั้นที่ 3

**ทางปฏิบัติ:** เก็บ `launchedByLocationKey` ไว้ในโค้ดต่อไป (ต้นทุนต่ำ ไม่ต้องลบ
อะไร) แต่ให้ปรับคอมเมนต์ในโค้ด (งานของ `flutter-dev`) จาก "ต้องรอพิสูจน์" เป็น
"ทราบแล้วว่าทำไมเป็น `false` เสมอภายใต้ scene lifecycle ปัจจุบัน — เก็บไว้เป็น
สัญญาณสำรองเผื่อวันหนึ่งแอปเลิกใช้ scene เท่านั้น" พร้อม cite สอง URL ข้างบน

### 3. (c) วิธีตีความบรรทัด log เก่าที่ stamp `relaunchedFromTerminated` ไปแล้ว

**หลักการก่อน:** บั๊กนี้ทำให้ `hasEverBecomeActive` ค้าง `false` **ตลอดชีพ process
ทุกกรณี ไม่ใช่บางเคส** (หัวข้อ 0) เพราะเส้นทางเดียวที่เคยตั้งค่ามันเป็น `true`
(`applicationDidBecomeActive`) เป็น dead code ทั้งหมดตราบใดที่แอปประกาศ
`UIApplicationSceneManifest` — ซึ่งเป็นอย่างนั้นมาตั้งแต่ก่อนมีเครื่องมือวัดผลนี้
(ไม่ใช่การเปลี่ยนแปลงเมื่อเร็ว ๆ นี้) ผลคือ **คอลัมน์ข้อสรุป (`background` เทียบกับ
`relaunchedFromTerminated`) ในไฟล์ log ทุกไฟล์ที่เขียนด้วยบิลด์ก่อนแก้ ไม่มีค่า
พิสูจน์อะไรได้ด้วยตัวเอง** — มันจะเป็น `relaunchedFromTerminated` เสมอสำหรับทุก
บรรทัดที่ `state` ไม่ใช่ `active` โดยไม่สนใจว่าความจริงเป็นอย่างไร

**กฎการอ่าน log เก่า (เรียงจากเชื่อได้มากไปน้อย):**

| เงื่อนไขของบรรทัด | เชื่อได้แค่ไหน | เหตุผล |
|---|---|---|
| `state=active` (ข้อสรุป `foreground`) | **เชื่อได้เต็มที่ ไม่ต้องตีความใหม่** | บั๊กอยู่ที่ `hasEverBecomeActive` เท่านั้น ไม่แตะ `UIApplication.shared.applicationState` ซึ่งเป็นค่าที่อ่านจาก OS ตรง ๆ |
| บรรทัดแรกสุดของ `procUuid` นั้น (คือบรรทัด `launch`, `uptimeMs` ≈ 0) ที่เป็น `relaunchedFromTerminated` | **เชื่อได้** | ก่อนบรรทัดนี้ process ยังไม่มีตัวตน (`uptimeMs=0`) ไม่มีเวลาให้ผู้ใช้เปิด-ใช้-พับแอปได้จริงในทางกายภาพ ทางเลือก "จริง ๆ คือ `background`" จึงเป็นไปไม่ได้เอง**โดยไม่ต้องพึ่งความถูกต้องของ `everActive`** — นี่คือเหตุผลเดียวกับที่ทำให้หลักฐาน B5 30 ส.ค. 2026 (`launch` uptime 0.0s → `enter` uptime 0.8s/3-5s ทั้งสองรอบ) ยังน่าเชื่อถือ |
| บรรทัดของ `procUuid` เดียวกัน ที่ตามหลัง `launch` มาไม่นาน (ระยะเวลาสั้นจนไม่พอให้คนเปิด-ปลดล็อก-ใช้แอปได้จริง) และเป็น `relaunchedFromTerminated` | **เชื่อได้ด้วยเหตุผลเดียวกับข้างบน** | ต้องพิจารณาเป็นกรณี ๆ จากค่า `uptimeMs`/timestamp — ไม่มีเลขตายตัวในเอกสารนี้เพราะไม่ใช่ค่าที่วัดได้ ให้ใช้สามัญสำนึกเชิงเวลาบวกกับส่วนต่างของ `uptimeMs` ระหว่างบรรทัด |
| บรรทัดของ `procUuid` เดียวกัน ที่ห่างจาก `launch` มากพอจะให้ผู้ใช้เปิดแอปได้จริง (นาที+) และเป็น `relaunchedFromTerminated` **และไม่มีบรรทัดอื่นของ `procUuid` เดียวกันที่มี `state=active` มาก่อนเวลานั้น** | **แยกไม่ออกอีกต่อไป — ต้องอ่านเป็น "ไม่ทราบ" ไม่ใช่ยึดคอลัมน์ตามตัวอักษร** | นี่คือผลโดยตรงของบั๊ก: ไม่มีทางแยกจากภายในไฟล์เดียวว่าเป็น `relaunchedFromTerminated` จริง หรือเป็น `background` จริงที่ถูกบั๊กบังคับให้แสดงผิด |
| บรรทัดของ `procUuid` เดียวกัน ที่มี **บรรทัดอื่นของ `procUuid` เดียวกันซึ่งมี `state=active` อยู่ก่อนเวลานั้น** (timestamp ของบรรทัด active < timestamp ของบรรทัดที่กำลังพิจารณา) แต่ตัวบรรทัดเองยังถูก stamp `relaunchedFromTerminated` | **กู้ข้อสรุปกลับมาได้ — ต้องอ่านเป็น `background`** | มีหลักฐานอิสระ (บรรทัด active ก่อนหน้า) ยืนยันว่า ณ เวลานั้น process **เคย** active มาแล้วจริง ๆ ไม่ว่าคอลัมน์ข้อสรุปจะเขียนว่าอะไร ข้อเท็จจริงคือ `background` |
| บรรทัดที่มีแต่ `procUuid` เดียวกันซึ่งมี `state=active` อยู่**หลัง**เวลานั้น (ในอนาคตของบรรทัดที่พิจารณา) | **ยังกู้ไม่ได้** | รู้แค่ว่า process เคย active ใน**อนาคต**ของบรรทัดนั้น ไม่ได้บอกว่า ณ เวลาที่บรรทัดนั้นถูกเขียน process เคย active มาก่อนหรือยัง — ต้องอ่านเป็น "ไม่ทราบ" เหมือนแถวก่อนหน้า |

**`launchKey=` ใช้กู้ข้อสรุปอะไรไม่ได้เลยในทุกกรณี** — ตามหัวข้อ 2 (b) ค่านี้เป็น
`false` เสมอภายใต้ scene lifecycle ไม่ว่าความจริงจะเป็นอย่างไร (แก้ไขเพิ่มเติม
จากที่ ADR-10 หัวข้อ 6 บันทึกไว้ว่า "ยังไม่ยืนยัน" — ตอนนี้ยืนยันแล้วว่า **ไม่มี
ข้อมูลอยู่ในค่านี้เลย** ไม่ใช่แค่ "เชื่อไม่ได้เต็มที่")

**ตัวอย่างจริงที่ใช้ตรวจตารางข้างบน (procUuid `ed11d170`, 3 ก.ย. 2026):**

```
13:36:32.008  ed11d170  launch  -          relaunchedFromTerminated   uptime=0.0s   state=background
13:41:11.701  ed11d170  enter   bigc-test  relaunchedFromTerminated   uptime≈5m     state=background
13:57:11.974  ed11d170  exit    bigc-test  foreground                 uptime≈21m    state=active
```

- บรรทัด `13:36:32` (`launch`, `uptime=0.0s`) → **เชื่อได้** (แถวที่ 2 ของตาราง —
  ไม่มีเวลาให้ทางเลือก `background` เป็นไปได้เลยตั้งแต่ก่อนบรรทัดนี้จะมีตัวตนด้วยซ้ำ)
- บรรทัด `13:41:11` (`enter`, ~5 นาทีหลัง `launch`) → **แยกไม่ออก ต้องอ่านเป็น
  "ไม่ทราบ"** (แถวที่ 4) — 5 นาทีนานพอที่ผู้ใช้จะปลดล็อก เปิดแอป แล้วกดออกได้จริง
  ในทางกายภาพ และไม่มีบรรทัด `state=active` ของ `procUuid` เดียวกันอยู่**ก่อน**
  เวลานี้ให้กู้กลับ (บรรทัด active ที่มีอยู่คือ `13:57:11` ซึ่งอยู่**หลัง**) — ตรงกับ
  แถวสุดท้ายของตาราง ไม่ใช่แถวที่ 5 เพราะ mismatched ทิศทางเวลา
- บรรทัด `13:57:11` (`exit`, `state=active`) → **เชื่อได้เต็มที่** (แถวแรกของ
  ตาราง) และเป็นหลักฐานว่า process นี้**เคย active จริงในบางช่วง** ระหว่าง
  36 นาทีที่มีชีวิต — แต่บอกไม่ได้ว่า active ครั้งแรกเกิดตอนไหน (อาจเกิดก่อนหรือ
  หลัง 13:41:11 ก็ได้ ข้อมูลในไฟล์นี้ไม่พอชี้ขาด)

**สรุปสั้นสำหรับตัวอย่างนี้:** เราไม่รู้จริง ๆ ว่าบรรทัด `13:41:11` เป็น
`relaunchedFromTerminated` แท้ หรือ `background` ที่ถูกบั๊กบังคับให้แสดงผิด — และ
**นี่คือคำตอบที่ถูกต้องของ log เก่า** ไม่ใช่การพยายามยืนยันไปทางใดทางหนึ่งด้วย
ข้อมูลที่ไม่พอ

### 4. ผลต่อสถานะ B5 ("ผ่าน" 30 ส.ค. 2026, `docs/test-checklists/ios_broadcast_scanning.md` หัวข้อ 12) — วิเคราะห์เท่านั้น ไม่แก้ไฟล์เช็คลิสต์

**หลักฐานที่ทำให้ B5 ผ่านเมื่อ 30 ส.ค. 2026 ยังน่าเชื่อถืออยู่** — ทั้ง 2 รอบทดสอบ
มีรูปแบบ `launch`(`uptime=0.0s`) ตามด้วย `enter`(`uptime=0.8s` และ ~3-5s) ทันที
ซึ่งตรงกับแถวที่ 2-3 ของตารางในหัวข้อ 3 (บรรทัดที่ใกล้ `launch` มากจนทางเลือก
`background` เป็นไปไม่ได้ทางกายภาพ) **ข้อสรุปยังยืนอยู่ได้**

**แต่เหตุผลที่ ADR-10 หัวข้อ 5 ใช้อธิบายว่าทำไมถึงเชื่อได้ต้องแก้ไข:** ADR-10
หัวข้อ 5 เขียนไว้ว่า "log ยืนยัน `everActive=false` + `state=background`... จึง
ถือว่าผ่าน" — ตามที่วิเคราะห์ในเอกสารนี้ ค่า `everActive=false` **ไม่มีน้ำหนัก
พิสูจน์อะไรเลย** เพราะมันจะเป็น `false` เสมอไม่ว่าความจริงจะเป็นอะไร (บั๊กนี้)
**น้ำหนักที่แท้จริงของการพิสูจน์อยู่ที่ `uptime` ใกล้ศูนย์ทันทีหลัง `launch` ของ
`procUuid` เดียวกัน ไม่ใช่ที่ค่า `everActive`** — ข้อสรุปสุดท้าย (B5 ผ่าน) ไม่
เปลี่ยน แต่**เหตุผลสนับสนุนต้องเปลี่ยนจาก "เพราะ everActive=false" เป็น "เพราะ
เวลาไม่พอให้ทางเลือกอื่นเป็นไปได้"**

**สิ่งที่ต้องส่งต่อให้ `beacon-qa` (ขั้นที่ 3) พิจารณา — ไม่ใช่การตัดสินใจของ
เอกสารนี้:** ควรพิจารณาเติมหมายเหตุในหัวข้อ 12 ของเช็คลิสต์ว่าเหตุผลรองรับ B5
ต้องอ่านคู่กับ ADR-16 นี้ และพิจารณาว่าจำเป็นต้องมีรอบทดสอบเพิ่มที่ตั้งใจสร้าง
เคส "process มีชีวิตนาน + active ช้า ๆ ไม่ติดกับ launch" (แบบ `ed11d170` ในหัวข้อ 3)
เพื่อพิสูจน์ `background` แยกจาก `relaunchedFromTerminated` ได้จริงหลังแก้บั๊กนี้
หรือไม่ — เกณฑ์ผ่านของ B5 เองไม่เปลี่ยน (ยังต้องเห็น `relaunchedFromTerminated`
จริงตามที่กำหนดไว้เดิม)

### 5. สิ่งที่ยังพิสูจน์ไม่ได้จนกว่าจะมี iPhone จริง (หลัง `flutter-dev` implement ตาม ADR นี้)

- ว่า `NotificationCenter` observer ของ `didBecomeActiveNotification` ที่ลงทะเบียน
  ใน `didFinishLaunchingWithOptions` ได้รับ notification จริงตอนแอปขึ้น foreground
  ปกติ (ทางทฤษฎีควรได้ตามหัวข้อ 1.3 แต่ยังไม่มีการรันบนอุปกรณ์จริง)
- ว่าเคส "process ถูกปลุกเบื้องหลัง ไม่มี scene, ไม่มีวัน active" ยังให้
  `hasEverBecomeActive=false` ถูกต้องตามที่ออกแบบไว้ในหัวข้อ 1.4 จริงหรือไม่
  (ทางทฤษฎีใช่ แต่ยังไม่มีรอบทดสอบเทียบก่อน/หลังแก้)
- ว่าหลังแก้แล้ว บรรทัด log ใหม่จะแยก `background` ออกจาก `relaunchedFromTerminated`
  ได้ถูกต้องในเคสแบบ `ed11d170` (process อายุยืน, active ล่าช้าไม่ติดกับ `launch`)
  จริงหรือไม่ — ต้องมีรอบทดสอบใหม่ที่ตั้งใจสร้างเคสนี้โดยเฉพาะ
- ว่า `applicationDidBecomeActive` override เดิมที่เก็บไว้เป็น fallback จะไม่ถูก
  เรียกซ้ำสองครั้ง (จาก override + จาก notification) จนเกิดผลข้างเคียงอื่นที่ยัง
  มองไม่เห็นในตอนออกแบบ — ต้องยืนยันตอน implement/ทดสอบจริง
- สาเหตุที่แท้จริงว่า `launchKey=false` ที่วัดได้ 2/2 รอบเป็นเพราะ "launchOptions
  ทั้งก้อนเป็น nil" (สมมติฐาน ข ตามหัวข้อ 2) แต่เพียงอย่างเดียว หรือมีปัจจัยอื่นร่วม
  ด้วย — ยังไม่มีการทดสอบเทียบกับบิลด์ที่ไม่ใช้ scene lifecycle ตามที่ระบุไว้ใน
  ADR-10 หัวข้อ 6 (และไม่จำเป็นต้องทำ เพราะไม่กระทบการใช้งานจริง)
- แขนรอ `didBecomeActiveNotification` ด้วย `XCTestExpectation` ใน
  `testDidBecomeActiveObserverFiresOnRealAppLifecycle` (`RunnerTests.swift`)
  **ยังไม่เคยถูกใช้จริงเลยสักครั้ง** ในทุกรอบที่รันบนเครื่อง dev — ทุกรอบผ่านทาง
  fast path (แอป active ไปแล้วก่อนเทสต์เริ่ม ใช้เวลา ~0.0005 วินาที) แขนนี้จะถูก
  ใช้จริงเฉพาะสภาพที่แอปยัง `inactive` ตอนเทสต์เริ่มเท่านั้น ซึ่งยังไม่เคยเกิดขึ้น
  ในการรันที่มีอยู่ — ต้องยืนยันว่าแขนนี้ทำงานถูกต้องจริงเมื่อมีโอกาสได้เห็นสภาพ
  แวดล้อมที่ทำให้มันถูกใช้งาน

---

## ADR-17: `reconcile()` — กู้สถานะ `inside` ที่ค้างข้ามคืนเมื่อนาฬิกาปลุกไม่มาถึง (เพิ่ม 4 ก.ย. 2026)

> **สถานะ: code-complete, unverified (Track B)**
> นี่คือขั้นที่ 1/4 ตาม `PIPELINE.md` (ออกแบบ) เท่านั้น **ห้ามมีโค้ด Kotlin ใน
> เอกสารนี้** หรือในการเปลี่ยนแปลงรอบนี้ — ขั้นเขียนโค้ดเป็นของ `flutter-dev` เมื่อ
> สถาปัตยกรรมในหัวข้อนี้ถูก sign-off แล้วเท่านั้น
> **ขอบเขต:** `beacon_kit_android` (`BackgroundRegionMonitor`,
> `BackgroundRegionStore`, `BeaconScanReceiver`, `RegionExitAlarmReceiver`,
> `BootCompletedReceiver`, `BeaconKitAndroidPlugin`) และรูปแบบ `rawSignals` /
> `AndroidBackgroundRegionEvent` ที่เกี่ยวข้อง — **ไม่แตะ iOS** และ **ไม่แตะกฎ 3/4
> ของการเลื่อนนาฬิกาปลุก · `setAndAllowWhileIdle` · `exitTimeoutSeconds`** ซึ่งเป็น
> ของ ADR-15 และยังไม่ตัดสิน (ห้ามแตะตามที่โจทย์รอบนี้สั่งไว้ตรง ๆ)

### 1. บั๊กที่ต้องแก้ — ยืนยันจากโค้ดจริงในเซสชันนี้

**หลักฐานอุปกรณ์จริง 3-4 ก.ย. 2026** (ไฟล์ดิบ commit แล้วที่
`docs/test-data/2026-09-03_android_overnight_stale_inside.log` — ดูแถวใน
`docs/test-data/README.md` สำหรับสภาพการทดสอบ/เครื่อง): `enter bigc-test`
เวลา 18:00:14 → เงียบสนิท ไม่มีบรรทัด log ใด ๆ เลย (ไม่ launch ไม่ exit)
จนถึง 08:39 → `launch` ×3 (08:39-08:41 ไม่มี `enter` ตามมา — process ถูก
สร้างใหม่แต่ไม่ได้มาจาก region event) → 08:42:29 `exit` ทั้งสอง region พร้อม
`sinceLastSeenMs≈50000` (ค่าจริงในไฟล์: 52048/49836) ซึ่งแปลว่า "เห็นล่าสุด
08:41:37" คือ**หลังกลับเข้าระยะตอนเช้าแล้ว** — exit ของคืนนั้นไม่เคยถูกเขียน
และ enter ตอนเช้าก็ไม่เคยถูกเขียนเช่นกัน (ผู้ทดสอบยืนยันว่าเอาเครื่องออกนอกระยะ
ตลอดคืน)

⚠️ **ไฟล์นี้ยืนยันได้แค่ว่าบั๊กเกิดขึ้นจริง (ความเงียบ 14 ชม. 14 น. ไม่มี
`exit`/`enter` ที่ควรมี) — ไม่ใช่หลักฐานว่า K=10 (หัวข้อ 2 ด้านล่าง) เป็นค่าที่
ถูกต้อง** ไฟล์นี้มาจากบิลด์**ก่อน** ADR-17 (ไม่มีคีย์ `exitReason=`/
`standbyBucket=` เลยสักบรรทัด — ตรวจแล้วด้วย `grep -c` ทั้งไฟล์ได้ `0`) จึงใช้
ตอบได้แค่ "บั๊กนี้มีจริง" เท่านั้น การยืนยันว่า `reconcile()`/K=10 แก้ปัญหานี้ได้
จริงต้องรอรอบทดสอบใหม่หลัง implement (หัวข้อ 8)

**สาเหตุที่ตรวจยืนยันจากไฟล์จริงแล้ว (ไม่ใช่การเดา):**

1. `BackgroundRegionMonitor.onSighting` (`BackgroundRegionMonitor.kt:386-426`)
   เมื่อ `wasInside = store.isInside(regionIdentifier)` เป็น `true`
   (บรรทัด 399) **ไม่มีการตรวจ `now − lastSeenElapsedMillis` เลยตรงจุดนี้** —
   โค้ดเลื่อนนาฬิกาปลุกไปอีก `timeoutMillis` (บรรทัด 401-412) แล้วจบ ไม่ยิง `enter`
   เพราะเงื่อนไข `if (!wasInside)` (บรรทัด 415) เป็นเท็จ ผลคือ sighting ตอนเช้าที่
   มาถึงหลังหายไป 14 ชั่วโมง **ถูกตีความว่าเป็นการอยู่ต่อเนื่องในโซนเดิม** ไม่ใช่
   การกลับเข้ามาใหม่
2. `store.markOutside(regionIdentifier)` (`BackgroundRegionStore.kt`,
   ฟังก์ชัน `markOutside`) ถูกเรียกจาก **`BackgroundRegionMonitor.onExitAlarm`
   เท่านั้น** สองจุด (`BackgroundRegionMonitor.kt:451` — สาขา boot-mismatch,
   และ `:478` — สาขาปกติ) สถานะ `inside` จึงมีทางออกได้ทางเดียวคือรอให้
   `RegionExitAlarmReceiver` ถูกเรียก — ถ้า OS ระงับนาฬิกาปลุกทั้งคืน (Doze /
   App Standby bucket, ดูหัวข้อ 2 ด้านล่าง) จะไม่มีเส้นทางอื่นเลยที่ทำให้สถานะ
   หลุดออกจาก `inside=true` ได้

**ผลคือช่องโหว่สองชั้นซ้อนกัน:** (1) ไม่มีใครกู้สถานะเมื่อนาฬิกาปลุกไม่มา และ
(2) ถึงมี sighting ใหม่มาถึงจริง ก็ยังถูก `onSighting` กลืนเงียบเพราะเช็คแค่
`wasInside` บูลีนตัวเดียว ไม่เช็คว่าความเงียบก่อนหน้านั้นนานแค่ไหน — `reconcile()`
ในเอกสารนี้ต้องปิดทั้งสองช่องพร้อมกัน

---

### 2. (a) นิยาม "stale inside" และค่า K

**นิยาม:** region หนึ่งถือว่า **stale** เมื่อเข้าเงื่อนไขข้อใดข้อหนึ่งใน 2 ข้อนี้
(แยกกันโดยสิ้นเชิง ไม่ใช่เงื่อนไขเดียวกัน):

| เงื่อนไข | ความแน่นอน | เหตุผล |
|---|---|---|
| **1. `store.isInside(id) == true` แต่ `store.storedElapsedTimesAreFromThisBoot() == false`** | **แน่นอน — ไม่ต้องใช้ K เลย** | เวลาแบบ `elapsedRealtime` ที่เก็บไว้มาจากคนละรอบบูต เทียบกับ `now` ไม่ได้อยู่แล้ว (`BackgroundRegionStore.kt`, ฟังก์ชัน `storedElapsedTimesAreFromThisBoot`) — นี่คือความแน่นอนระดับเดียวกับสาขา `bootMismatch` ที่ `onExitAlarm` มีอยู่แล้ว (`BackgroundRegionMonitor.kt:448-467`) ไม่ใช่การประมาณ |
| **2. `store.isInside(id) == true` และ boot token ตรงกัน และ `now − lastSeenElapsedMillis > exitTimeoutSeconds × K`** | **ความน่าจะเป็น — ต้องเลือก K** | นี่คือหัวใจของหัวข้อนี้ |

**ทำไมใช้ `now − lastSeenElapsedMillis` ไม่ใช่ `now − scheduledExitAlarmElapsedMillis`:**
ค่าหลังบอกแค่ว่า "เราขอให้นาฬิกาปลุกดังตอนไหน" ซึ่งปนสัญญาณของการ batching ของ
`AlarmManager` เข้าไปด้วย (ADR-15 หัวข้อ 1) ส่วน `lastSeenElapsedMillis` คือความจริง
ล้วน ๆ ว่า "เห็น beacon ครั้งสุดท้ายเมื่อไร" ซึ่งเป็นค่าเดียวกับที่ `onExitAlarm` เอง
ใช้ตัดสิน (`BackgroundRegionMonitor.kt:469`) — `reconcile()` ต้องใช้ตรรกะเดียวกัน
กับเส้นทางที่มีอยู่แล้ว ไม่ใช่ประดิษฐ์เกณฑ์คู่ขนานที่อาจให้คำตอบขัดกัน

**ค่า K ที่เลือก: K = 10** (threshold เริ่มต้น = `30s × 10 = 300s = 5 นาที`
เมื่อ `exitTimeoutSeconds` เป็นค่าเริ่มต้น — K เป็นตัวคูณ ไม่ใช่ค่าคงที่ตายตัว
จึงขยับตามค่าที่ผู้ใช้ SDK ตั้งเองด้วย)

**ข้อมูลที่ใช้ตัดสิน (เรียงจากยืนยันได้มากไปน้อย):**

| แหล่ง | ค่า | น้ำหนัก |
|---|---|---|
| `docs/test-data/2026-09-01_android_overnight_region_flapping.log` (ADR-15 หัวข้อ 5) — **ยืนยันแล้ว มีไฟล์ในคลัง** | p95 ความเงียบที่วัดได้ (ขอบล่าง): 1 น 36 วิ (doze=false) / 1 น 51 วิ (doze=true) · **สูงสุด: 1 น 36 วิ (doze=false) / 2 น 50 วิ (doze=true)** | สูง — เป็นขอบล่างของ "ความเงียบปกติที่สุดขั้ว" จากคืนจริง |
| ข้อมูลที่ระบุมาในโจทย์งานนี้โดยตรง ("exit ปกติมาถึงที่ 43-68 วินาที เมื่อ timeout=30" · "alarm ช้าได้ถึง 38 วินาทีในเบื้องหลัง") | 43-68s / +38s | **ยังไม่ยืนยันในเซสชันนี้** — ค้นทั้ง repo แล้ว **ไม่พบไฟล์ log ที่เก็บตัวเลขนี้ไว้** (`grep` `docs/test-data/`, `docs/test-checklists/` ไม่เจอ) รับมาเป็นข้อมูลที่ผู้สั่งงานให้ ไม่ใช่สิ่งที่ตรวจสอบย้อนกลับได้เองในรอบนี้ — บันทึกไว้ตรง ๆ ตามกติกาห้ามเดา ไม่ปัดตกและไม่ยืนยันเกินจริง |
| App Standby Buckets — official ([developer.android.com/topic/performance/appstandby](https://developer.android.com/topic/performance/appstandby), ดึง 4 ก.ย. 2026) | "**Android 9 (API level 28) and later support App Standby Buckets.**" · "**If an app is in the rare bucket, the system imposes strict restrictions on its ability to run jobs and trigger alarms.**" · bucket `restricted`: "**Your app can invoke one alarm per day.**" | สูง — official first-party — **ยืนยันว่าเพดานบนของความหน่วงไม่ใช่แค่ "ระดับชั่วโมง" แต่เป็นระดับ 1 ครั้ง/วัน** ซึ่งตรงกับขนาดของช่องว่าง 14 ชั่วโมงที่เจอจริง |

**เหตุผลของ K=10 (threshold=5 นาที):**

1. **เผื่อขอบเหนือขอบบนที่วัดได้จริงและยืนยันแล้ว (ADR-15)** — 2 น 50 วิ (170s) ×
   ~1.76 = คือ margin ที่ threshold 300s ให้ แปลว่า reconcile() **จะไม่ตัดสิน
   ว่า stale** ในทุกเคสที่วัดได้จริงจากคืน 1 ก.ย. 2026 แม้แต่เคสที่แย่ที่สุด —
   ไม่สร้าง false positive กับข้อมูลที่มีอยู่แล้วในคลัง
2. **ใช้ค่าเดียวกับที่ทีมเคยตัดสินใจแล้วสำหรับปัญหาโครงสร้างเดียวกัน** — ADR-11
   หัวข้อ 7 (session merge) และ ADR-15 หัวข้อ 5 ("เผื่อขอบ = 5 นาที ... ใช้ได้พอดี
   กับทั้งสองไฟล์") ต่างเลือก 5 นาทีเป็นขอบสำหรับ "ความเงียบที่นานเกินกว่าจะเป็น
   สัญญาณแกว่งปกติ" อยู่แล้ว — เอกสารนี้ **ใช้ค่าเดิมซ้ำแทนการประดิษฐ์ค่าที่สาม**
   เพื่อไม่ให้ระบบทั้งหมดมีเกณฑ์ "5 นาทีๆ ที่ไม่เท่ากัน" กระจายอยู่หลายที่
3. **เทียบกับเพดานของ App Standby bucket ที่ยืนยันแล้ว (ตาราง)** — 5 นาที
   เทียบกับ "1 ครั้ง/วัน" ของ bucket `restricted` คือ margin ~288 เท่า — เมื่อ
   reconcile() ถูกกระตุ้นระหว่างที่นาฬิกาปลุกจริงยังไม่ทันมาถึงเพราะติด
   bucket ที่หน่วงระดับวัน `reconcile()` จะตัดสินว่า stale **ก่อน**เสมอ ซึ่งคือ
   พฤติกรรมที่ตั้งใจ — นี่คือกรณีที่ตรงกับบั๊กจริงที่ต้องแก้พอดี

**ราคาที่ต้องจ่าย (ต้องบันทึกตรง ๆ ไม่ใช่แค่ประโยชน์):** ถ้า `reconcile()` ถูก
กระตุ้น (เช่น sighting แผ่วเบามาถึง หรือผู้ใช้เปิดแอป) ในช่วง **170s < ความเงียบจริง
< 300s** — คือช่วงที่ยังไม่มีข้อมูลจริงยืนยันว่าเคยเกิดขึ้น (170s คือสูงสุดที่วัดได้
จริง) แต่ยังอยู่ในขอบเขตที่เอกสาร `setAndAllowWhileIdle` **ไม่ปฏิเสธว่าเกิดได้**
(ไม่มีเพดานบนที่รับประกัน — `docs/sources/android_background_ble.md` หัวข้อ 8) —
`reconcile()` **จะยังไม่ตัดสินว่า stale** (เพราะ 170-300s ยังอยู่ใต้ threshold) และ
ปล่อยให้รอนาฬิกาปลุกจริงต่อไป ซึ่งถ้านาฬิกาปลุกนั้นดันไม่มาจริง ๆ ผู้ใช้จะยังเห็น
สถานะค้างต่อไปอีกจนกว่าจะมี trigger ถัดไปมาเรียก `reconcile()` ซ้ำ — **K=10 จึงลด
ความเสี่ยง false positive แลกกับความหน่วงในการกู้สถานะที่ยังมีอยู่ในช่วงแคบ ๆ นี้**
K ที่เล็กกว่านี้ (เช่น K=4, threshold=2 นาที) จะกู้สถานะไวกว่าแต่เข้าใกล้ขอบบนที่
วัดได้จริง (170s) มากเกินไปจนเสี่ยง flap ปลอมที่ตัวเราเองสร้างขึ้น (รูปแบบเดียวกับ
ที่ ADR-11 วิเคราะห์ไว้ทั้งฉบับ)

⚠️ **K=10 ยังไม่ได้ทดสอบบนอุปกรณ์จริง** — เป็นค่าที่คำนวณจากข้อมูลที่มีอยู่ ไม่ใช่ค่า
ที่วัดผลแล้วว่าใช้ได้ ต้องอยู่ใน checklist ทดสอบรอบถัดไป (ดูหัวข้อ 8)

---

### 3. (b) จุดเรียก `reconcile()` — ลำดับ และการรับประกัน idempotency

**หลักการออกแบบ:** `reconcile()` วนตรวจ **ทุก region ใน `store.regions`** เสมอ
(ไม่ใช่แค่ region เดียวที่เกี่ยวข้องกับ trigger ที่เรียกมัน) เพราะต้นทุนคือแค่การ
อ่าน `SharedPreferences` สองสามคีย์ต่อ region (ถูกมาก เทียบกับ ADR-8 ที่จำกัด
region ไว้ไม่เกิน 20 ตัว) — ทุกจังหวะที่ process ตื่นอยู่แล้วด้วยเหตุผลใดก็ตาม
คือโอกาสถูกที่จะตรวจ region **อื่น** ที่อาจ stale อย่างเป็นอิสระไปด้วย ไม่ต้องรอ
trigger ของ region นั้นเอง

| ผู้เรียก | ตรวจ region ไหน | ลำดับเทียบกับตรรกะเดิม | เหตุผล |
|---|---|---|---|
| `BeaconKitAndroidPlugin.onAttachedToEngine` | ทุก region | **ก่อน** `drainQueuedBackgroundEvents()` (`BeaconKitAndroidPlugin.kt:143`) | ถ้า `reconcile()` สังเคราะห์ `exit(stale)` ขึ้นมาใหม่ ต้องถูก enqueue **ก่อน** การ drain ครั้งนี้ ไม่งั้น event ที่เพิ่งสังเคราะห์จะตกค้างรอรอบเปิดแอปครั้งถัดไป ทั้งที่มันควรไหลออกไปพร้อมคิวเดิมทันที |
| `BeaconKitAndroidPlugin.onAttachedToActivity` | ทุก region | ไม่ตัดกับ `HostProcessInfo.markForeground()` (`:201`) — ทำก่อน/หลังก็ได้ | แอปขึ้น foreground คือโอกาสที่ CPU ตื่นแน่นอน แม้ผู้ใช้จะไม่ได้เดินเข้าใกล้ beacon เลยก็ตาม |
| `BeaconScanReceiver.onReceive` → ก่อนเรียก `BackgroundRegionMonitor.onSighting` | เฉพาะ region ที่ได้ผลสแกน | **ก่อน** ตรรกะเดิมทั้งหมดของ `onSighting` | ให้ `onSighting` เห็น `store.isInside()` ที่ถูกกู้แล้วก่อนเช็ค `wasInside` — **`onSighting` เดิมไม่ต้องแก้ตรรกะภายในเลยแม้แต่บรรทัดเดียว** แค่เพิ่มการเรียก `reconcile()` เป็นขั้นแรกก่อนโค้ดเดิมทั้งหมด ถ้า sighting นี้เป็นการกลับเข้ามาใหม่จริง ๆ `reconcile()` จะพลิก `inside` เป็น `false` ให้ก่อน แล้ว `onSighting` เดิมจะเห็น `wasInside=false` เองโดยธรรมชาติและยิง `enter` ให้เองตามโค้ดที่มีอยู่แล้ว |
| `RegionExitAlarmReceiver.onReceive` → ก่อนเรียก `BackgroundRegionMonitor.onExitAlarm` | **ทุก region** ไม่ใช่แค่ region ของ alarm ที่ดังนี้ | ก่อนตรรกะเดิมของ `onExitAlarm` | ใช้จังหวะที่ process ถูกปลุกอยู่แล้ว (แม้จะปลุกเพื่อ region อื่น) ตรวจ region ที่เหลือไปด้วยในคราวเดียว — สำคัญเพราะนี่คือกรณีตรงกับบั๊กจริง: ถ้า 2 region ถูกเฝ้าพร้อมกันและนาฬิกาปลุกของ region A ยังทำงานปกติแต่ของ region B ถูกระงับ B จะไม่มีทาง reconcile ได้เลยถ้าไม่อาศัยจังหวะที่ A ปลุก process ขึ้นมา |
| `BootCompletedReceiver.onReceive` (`BOOT_COMPLETED` / `LOCKED_BOOT_COMPLETED`) | — ไม่ต้องเรียกแยก | `restoreAfterBoot()` เดิมล้างสถานะไปแล้วโดยธรรมชาติ | `storedElapsedTimesAreFromThisBoot()` จะเป็น `false` เสมอทันทีหลังบูตจริง ตรงกับเงื่อนไขข้อ 1 ของนิยาม stale ในหัวข้อ 2 อยู่แล้ว — เส้นทางเดิมถูกต้องอยู่แล้วสำหรับเคสนี้เฉพาะ ระบุไว้เพื่อความชัดเจน ไม่ใช่จุดที่ต้องเพิ่มโค้ด |
| `BootCompletedReceiver.onReceive` (`ACTION_MY_PACKAGE_REPLACED`) | ทุก region | **ก่อน** `clearRegionStates()`/`registerScans()` ของ `restoreAfterBoot()` | **บั๊กแฝงที่พบระหว่างออกแบบรอบนี้ แยกจากบั๊กหลักแต่เกี่ยวเนื่องกันโดยตรง:** `MY_PACKAGE_REPLACED` ไม่ใช่การรีบูต — `SystemClock.elapsedRealtime()` **ไม่รีเซ็ต** ตอนแอปอัปเดต (boot token ยังตรงกันได้ตามปกติ) การเรียก `restoreAfterBoot()` ตรง ๆ แบบที่โค้ดปัจจุบันทำอยู่ (`BootCompletedReceiver.kt`) จึงเรียก `clearRegionStates()` แบบไม่มีเงื่อนไข ซึ่ง**ทิ้งสถานะ `inside=true` ที่ยังถูกต้องอยู่จริงไปเงียบ ๆ โดยไม่มีการรายงาน exit เลย** — ต้องเรียก `reconcile()` ก่อนเพื่อให้ `exit`/`exit(stale)` ที่ควรได้ (ถ้ามี) ถูกยิงออกไปก่อนจะถูกล้างทิ้ง |

**ทำไม `reconcile()` ต้องไม่แก้ตรรกะของ `onSighting`/`onExitAlarm` เอง:**
ออกแบบให้เป็น **ขั้นตอนก่อนหน้า (pre-step)** ที่แยกเป็นฟังก์ชันของตัวเอง แทนที่จะ
เขียนเงื่อนไข staleness ปนเข้าไปในทั้งสองฟังก์ชันเดิม — เหตุผล: `onSighting` และ
`onExitAlarm` มี unit test และพฤติกรรมที่ตรวจสอบแล้ว (แม้จะยัง `unverified` บน
เครื่องจริงตาม ADR-14 หัวข้อ 6) การไม่แตะตรรกะเดิมเลยทำให้ diff ของรอบ implement
ถัดไปเล็กและตรวจสอบง่าย และทำให้ `reconcile()` ทดสอบแยกเป็น unit ของตัวเองได้
โดยไม่ต้อง mock ทั้ง state machine ของ enter/exit

#### 3.1 การรับประกัน idempotency — เรียกซ้ำจากหลายทางพร้อมกันต้องไม่ยิง event ซ้ำ

สามชั้นทำงานร่วมกัน ไม่ใช่ชั้นเดียว:

1. **สถานะบนดิสก์คือความจริงหนึ่งเดียว ไม่ใช่ตัวแปรในหน่วยความจำ** — `reconcile()`
   อ่าน `store.isInside(id)` เป็นเงื่อนไขแรกเสมอ (เหมือนที่ `onExitAlarm` ทำอยู่แล้ว
   ที่ `BackgroundRegionMonitor.kt:440`: `if (!store.isInside(regionIdentifier))
   return`) หลังจากรอบแรกที่พลิกเป็น `markOutside()` สำเร็จ (คือ `commit()` แบบ
   synchronous ตามที่ `BackgroundRegionStore` ใช้ทั้งไฟล์ ไม่ใช่ `apply()`) ทุกการ
   เรียกซ้ำถัดไปจะอ่านเจอ `false` ทันทีและ**คืนออกโดยไม่ทำอะไรเลย** — นี่คือกลไก
   หลักที่ทำให้ปลอดภัยที่จะเรียกจากหลายจุดตามตารางข้างบน
2. **critical section ระดับ process** — เนื่องจากผู้เรียกในตารางข้างบนอาจทำงานคน
   ละเธรด (`BroadcastReceiver.onReceive` มาจาก binder thread ส่วน
   `onAttachedToEngine`/`onAttachedToActivity` มาจาก main thread ของ Flutter
   engine) มี TOCTOU race ที่เป็นไปได้จริงถ้าสองเธรดอ่าน `isInside==true` พร้อมกัน
   ก่อนที่ฝ่ายแรกจะ `commit()` เสร็จ — ต้องครอบขั้นตอน "อ่าน → ตัดสิน → เขียน" ของ
   `reconcile()` ด้วย critical section ระดับ `object BackgroundRegionMonitor`
   (เช่น `synchronized` บนอ็อบเจกต์ lock เดียว) **นี่ไม่ใช่รูปแบบใหม่ที่ไม่เคยมี
   บรรทัดฐาน** — `BluetoothLeScanner.java` เองก็ครอบ `mLeScanClients` ด้วย
   `synchronized` block สำหรับปัญหาชนิดเดียวกัน (`doStartScan`,
   `~/Library/Android/sdk/sources/android-37.0/android/bluetooth/le/BluetoothLeScanner.java:319`)
   — โค้ดของแอปนี้ **ยังไม่เคยใช้ `synchronized` เลยสักที่** (ตรวจแล้วในเซสชันนี้)
   จึงเป็นรูปแบบใหม่ของโค้ดฐานนี้ แต่ไม่ใช่รูปแบบใหม่ของแพลตฟอร์ม — cross-process
   lock **ไม่จำเป็น** เพราะแอปนี้มี process เดียวตามที่ `BackgroundRegionStore`
   บันทึกไว้แล้วสำหรับ `sightingCount` (เหตุผลเดียวกันเป๊ะ)
3. **การเขียนสถานะ+เหตุการณ์ต้องเป็น `commit()` เดียว ไม่ใช่สองครั้งต่อกัน** —
   ⚠️ **จุดที่ต้องแก้ไปพร้อมกัน แม้จะไม่ใช่บั๊กที่โจทย์ระบุตรง ๆ:** เส้นทางเดิมของ
   `onExitAlarm` เรียก `store.markOutside(regionIdentifier)` (คอมมิตหนึ่งครั้ง)
   แล้วค่อยเรียก `emit(...)` ซึ่งถ้าไม่มี Flutter engine จะไปเรียก
   `store.enqueueEvent(event)` (คอมมิตอีกครั้งแยกกัน) — ถ้า process ถูกระบบฆ่า
   ระหว่างสองคอมมิตนี้พอดี สถานะจะถูกพลิกเป็น `outside` สำเร็จแล้ว **แต่ event
   ไม่เคยถูกบันทึกเลย** และเพราะ `isInside` กลายเป็น `false` แล้ว การเรียก
   `reconcile()`/`onExitAlarm`/`onSighting` ซ้ำในอนาคตจะไม่มีวันรู้ว่าเคยมี exit
   ที่ควรรายงานแต่หายไป — เป็นความเสี่ยงชนิดเดียวกับบั๊กหลักของเอกสารนี้เป๊ะ เพียง
   แต่เกิดจากคนละสาเหตุ (process ตายกลางคัน ไม่ใช่นาฬิกาปลุกไม่มา) **ข้อกำหนด
   สำหรับ `reconcile()`:** การพลิกสถานะ (`markOutside`) กับการทำให้ event รอด
   (อย่างน้อยที่สุดคือ enqueue ลงดิสก์) **ต้องอยู่ใน `commit()` เดียวกัน** ตาม
   รูปแบบที่ `recordSighting()` วางไว้แล้วในไฟล์เดียวกัน (คอมเมนต์ของมันเอง:
   "ต้องเป็นการเขียนครั้งเดียว ไม่ใช่หลายครั้งต่อกัน") — ส่วนการเรียก `observer`
   (เขียนไฟล์หลักฐานฝั่ง host app) และการส่งเข้า `flutterSink` ยังคงเป็น
   best-effort ตามเดิม (`runCatching`) เพราะทั้งสองทางนั้นมีทางสำรอง (ไฟล์หลักฐาน
   เป็นแค่ log ไม่ใช่ source of truth · `flutterSink` มีคิวดิสก์เป็น fallback
   อยู่แล้ว) มีแค่ "เขียนสถานะแต่ลืม enqueue" เท่านั้นที่ไม่มีทางสำรองเลย

---

### 4. (c) รูปแบบ event ของ `exit` ที่มาจาก `reconcile`

**เลือก: `rawSignals` (คีย์ใหม่) ไม่ใช่ `conclusion`**

เหตุผล: `conclusion` เป็นฟังก์ชันบริสุทธิ์ของ `ProcessState`
(`foreground`/`background`/`relaunchedFromTerminated` เท่านั้น — ดู
`ExampleApplication.kt:59` ที่ set `conclusion = processState.conclusion` ตรง ๆ)
มันตอบคำถาม **"แอปอยู่ในสถานะอะไรตอนเขียนบรรทัดนี้"** ซึ่งเป็นคำถามคนละมิติกับ
**"exit นี้มาจากเส้นทางไหน"** การยัดค่าที่สามเข้าไปใน `conclusion` จะ:

1. ทำลาย invariant ที่ ADR-14 หัวข้อ 4.2 เขียนกำกับไว้ตรง ๆ ว่า `conclusion` ของ
   บรรทัด `enter`/`exit`/`selftest` มาจาก `ProcessState` เท่านั้น
2. ชนกับตรรกะที่มีอยู่แล้วใน `tool/analyze_region_log.dart:364-365` ที่เช็ค
   `e.conclusion == 'relaunchedFromTerminated'` เพื่อระบุ B5 — การเติมค่าที่สาม
   เข้าไปในฟิลด์เดียวกันจะทำให้ enum ที่ปิดอยู่แล้ว (3 ค่า) ต้องเปิดใหม่ และเสี่ยง
   ทำให้ตรรกะเดิมตีความผิดถ้าค่าใหม่บังเอิญไปกระทบเงื่อนไข equality ที่มีอยู่

`rawSignals` เป็น free-form key=value string ที่ทั้ง `tool/analyze_region_log.dart`
(อ่านทั้งคอลัมน์เป็น string เดียวแล้วค่อย regex เฉพาะคีย์ที่รู้จัก — ดู `uptimeSeconds`
getter) และฝั่ง native (สร้างด้วย `buildString { append(...) }` ต่อกันเรื่อย ๆ) ต่าง
ก็ทนต่อการเพิ่มคีย์ใหม่อยู่แล้วโดยไม่ต้องแก้ parser — ตรงกับรูปแบบที่ ADR-15 ข้อ จ.
ใช้เพิ่ม `sinceLastSeenMs`/`scheduledAtElapsed`/`firedAtElapsed` มาแล้วครั้งหนึ่ง

**คีย์ที่เพิ่ม (เฉพาะบรรทัด `exit`):** `exitReason=<alarm|staleReconcile|staleBootMismatch>`
วางต่อท้ายชุด `sinceLastSeenMs=... scheduledAtElapsed=... firedAtElapsed=...` ที่
มีอยู่แล้ว (`exitTimingField`) — `exit` ที่มาจาก `onExitAlarm` ปกติได้ `alarm`,
`exit` ที่มาจาก `reconcile()` ตามเงื่อนไขข้อ 2 ของนิยาม stale (หัวข้อ 2) ได้
`staleReconcile`, และตามเงื่อนไขข้อ 1 (boot mismatch) ได้ `staleBootMismatch` —
**ให้ค่าเริ่มต้นเป็น `alarm` เสมอ ไม่ใช่ปล่อยว่าง** เพื่อให้บรรทัดเก่าที่ยังไม่มี
คีย์นี้ (ก่อน implement รอบนี้) แยกออกจากบรรทัดใหม่ได้ด้วยการเช็ค "มีคีย์นี้หรือไม่"
ล้วน ๆ โดยไม่ต้องเดา — ตรงกับรูปแบบ `n/a` ที่ `exitTimingField` วางไว้แล้วสำหรับ
สาขา boot-mismatch เดิม

**`timestamp` ของบรรทัดนี้ = เวลาที่ `reconcile()` ตัดสิน (`now`) ไม่ใช่เวลาย้อนหลัง
ไปยังตอนที่ silence เริ่มต้น** — ตรงกับหลักการเดิมของทุก event ในระบบนี้ (event
timestamp = เวลาที่ native บันทึก ไม่ใช่เวลาที่เหตุการณ์ "ควรจะ" เกิด ดูคอมเมนต์ของ
`AndroidBackgroundRegionEvent.timestamp` ฝั่ง Dart) **ส่วน `sinceLastSeenMs` ต้อง
เป็นค่าจริงที่คำนวณจาก `now − lastSeenElapsedMillis` เดิม ซึ่งในเคส stale จะเป็น
เลขหลักสิบล้าน ms ได้จริง** (14 ชั่วโมง = 50,400,000 ms) — ตรวจแล้วว่าชนิดข้อมูล
รองรับ: ฝั่ง Kotlin `exitSinceLastSeenMillis: Long?` (`BackgroundRegionStore.kt`)
รองรับถึง ~9.2×10¹⁸ ไม่มีปัญหา ฝั่ง Dart **ยังไม่มีโมเดลที่ parse ฟิลด์นี้เลยในตอนนี้**
(`AndroidBackgroundRegionEvent.tryParse` ใน `android_background_region.dart` อ่าน
แค่ `regionIdentifier`/`state`/`timestampMillis`/`fromBackgroundProcess` — สาม
ฟิลด์เวลาที่ ADR-15 ข้อ จ. เพิ่มไว้ยังอยู่แค่ใน `toMap()` ของ native และถูกใช้ตรง
โดยโค้ด native ของ example app เท่านั้น ไม่เคยไหลผ่าน parser ฝั่ง Dart) — ถ้าจะ
เพิ่ม `exitReason` ต่อจากนี้ให้เพิ่มในจุดเดียวกัน (`toJson`/`toMap` ฝั่ง Kotlin) แต่
**การเปิดให้ `AndroidBackgroundRegionEvent.tryParse` อ่านฟิลด์กลุ่มนี้เป็นการตัดสินใจ
ที่ยังไม่ได้ทำในรอบนี้** — บันทึกเป็นคำถามเปิดไว้ (ไม่ใช่ scope ของบั๊กหลัก) เพราะ
ข้อกำหนดของโจทย์ ("ผู้ใช้ SDK ต้องได้ `exit(stale)` ตามด้วย `enter`") ต้องการแค่ว่า
**ลำดับและจำนวน event ที่ไหลผ่าน `EventChannel` ต้องถูก** ไม่ได้บังคับว่าต้องมี
ฟิลด์บอกเหตุผลไหลไปถึง Dart ด้วย — ถ้า Dart `int` ที่ VM ใช้ (64-bit) รองรับเลข
หลักสิบล้านสบาย ๆ อยู่แล้ว (และแม้จะ compile เป็น JS สักวัน เลขหลักสิบล้านยังอยู่
ในขอบเขต safe-integer ของ `double` ที่ 2^53) จึงไม่มีความเสี่ยงเรื่องขนาดตัวเลขเลย
ถ้าวันหนึ่งมีการต่อสายให้ Dart อ่านฟิลด์นี้จริง

**ลำดับที่ `onSighting` ต้องทำเมื่อเจอ stale — ห้ามกลืน `enter`:**

ตามที่ออกแบบไว้ในหัวข้อ 3 (`reconcile()` เป็น pre-step แยกต่างหาก) ลำดับที่
`BeaconScanReceiver.onReceive` ต้องทำคือ:

1. เรียก `reconcile()` สำหรับ region ที่ได้ผลสแกน **ก่อน**
   — ถ้าพบว่า stale: `reconcile()` เขียน `commit()` เดียว (หัวข้อ 3.1 ข้อ 3) ที่
   พลิก `inside → false` พร้อมกับทำให้ event `exit` (`exitReason=staleReconcile`
   หรือ `staleBootMismatch`) รอดแน่นอน แล้ว `reconcile()` จบการทำงาน — **ยังไม่
   เรียก `onSighting` เลยในขั้นนี้**
2. เรียก `BackgroundRegionMonitor.onSighting(...)` ตามเดิม **โดยไม่ต้องแก้โค้ด
   ภายในเลย** — ฟังก์ชันนี้จะอ่าน `store.isInside(id)` เป็น `wasInside` สดใหม่
   (จากดิสก์ที่เพิ่งถูก `reconcile()` แก้) ได้ `false` เพราะเพิ่งถูกพลิกไปในขั้นที่
   1 → เข้าเงื่อนไข `if (!wasInside)` (`BackgroundRegionMonitor.kt:415`) ตาม
   ตรรกะที่มีอยู่แล้ว → ยิง `enter` ให้เองตามปกติ

ผลคือผู้ใช้ SDK ได้รับ **สอง event เรียงกัน** ในการเรียกครั้งเดียวของ
`BeaconScanReceiver.onReceive`: `exit(exitReason=staleReconcile)` ตามด้วย
`enter` — ตรงตามข้อกำหนดของโจทย์เป๊ะ โดยที่ `onSighting` เดิมไม่ต้องรู้จักคำว่า
"stale" เลยแม้แต่น้อย (แยกความรับผิดชอบสะอาด: `reconcile()` ดูแลอดีต, `onSighting`
ดูแลปัจจุบัน)

---

### 5. (d) การเรียก `startScan` ซ้ำใน `reconcile` — ปลอดภัยหรือไม่ + ผลของ stopped state

**คำถามที่ต้องตอบ: เรียก `startScan(filters, settings, PendingIntent)` ซ้ำด้วย
`PendingIntent` เดิม (เทียบเท่าตาม `FLAG_UPDATE_CURRENT`) ปลอดภัยหรือไม่**

ตรวจซอร์สจริงในเครื่องก่อนเอกสารเว็บ (CONTRIBUTING ข้อ 5) —
`~/Library/Android/sdk/sources/android-37.0/android/bluetooth/le/BluetoothLeScanner.java`,
เมธอด `doStartScan` (บรรทัด 300-362) — **อธิบายเป็นร้อยแก้วแทนการยกโค้ดมา** ตาม
ข้อห้ามของเอกสารนี้ (หัวข้อสถานะด้านบน "ห้ามมีโค้ด Kotlin ในเอกสารนี้" ใช้กับ
การยกโค้ดภาษาอื่นด้วยเจตนาเดียวกัน): เมธอดนี้ครอบทั้งบล็อกด้วย
`synchronized (mLeScanClients)` แล้วแยกสองเส้นทางตามว่าพารามิเตอร์ `callback`
เป็น `null` หรือไม่ — **เฉพาะเส้นทางที่ `callback != null`** (คือ
`ScanCallback`-based scan) เท่านั้นที่มีเงื่อนไขเช็ค
`mLeScanClients.containsKey(callback)` แล้วคืนค่า
`ScanCallback.SCAN_FAILED_ALREADY_STARTED` ทันทีถ้าเจอว่าลงทะเบียนซ้ำ (บรรทัด
319-323) — **เส้นทางที่ `callback == null`** (คือ `PendingIntent`-based scan
ซึ่งตรงกับที่ `BackgroundRegionMonitor.registerScans` ใช้อยู่ บรรทัด 353-358)
**ไม่ผ่านเงื่อนไขเช็คซ้ำนั้นเลย** โค้ดเรียก `scan.registerPiAndStartScan(...)`
ตรงไปยัง Bluetooth stack ผ่าน AIDL (`IBluetoothScan`) ทันทีไม่มีเงื่อนไขใด ๆ
ก่อนหน้า

**สิ่งที่ยืนยันไม่ได้:** พฤติกรรมฝั่ง server (`registerPiAndStartScan`
implementation) ว่าจะปฏิบัติกับ `PendingIntent` ที่ `.equals()` กับตัวที่ลงทะเบียน
ไว้แล้ว (เพราะ `scanPendingIntent(..., create=true)` ใช้ `FLAG_UPDATE_CURRENT` +
data URI/requestCode เดิม — `BackgroundRegionMonitor.kt:296`) เป็น **"แทนที่ของเดิม
แบบ idempotent"** หรือ **"สร้าง registration ซ้ำซ้อน"** — โค้ดของ
`IBluetoothScan`/`registerPiAndStartScan` อยู่ใน Bluetooth APEX module **ไม่ได้
แจกมากับ Android SDK sources** จึงอ่านยืนยันในเครื่องไม่ได้ ตรงกับที่ ADR-14
หัวข้อ 2.1 บันทึกไว้แล้วสำหรับกรณี `PendingIntent.send()` ด้วยเหตุผลเดียวกัน

**หลักฐานบุคคลที่สาม (น้ำหนักต่ำกว่าเอกสารทางการ — บันทึกไว้เพื่อความระมัดระวัง
ไม่ใช่เพื่อสรุปแทนเอกสาร):** GitHub issue
[`NordicSemiconductor/Android-Scanner-Compat-Library#58`](https://github.com/NordicSemiconductor/Android-Scanner-Compat-Library/issues/58)
— ผู้รายงาน `paulpv`: *"This means that the code never actually stops any
PendingIntent started scans. The `pendingIntent` passed to `stopScan` must be
the exact same one that was passed to `startScan`."* พร้อมอาการที่พบจริง:
"you can usually only start about 28, max of 32, scans before the OS blocks
all future scans" — เป็นคนละเงื่อนไขกับคำถามของเรา (เคสนั้นคือ PendingIntent
**ไม่ตรงกัน** ระหว่าง start/stop ไม่ใช่ start ซ้ำด้วย PendingIntent ที่เท่ากัน)
แต่ยืนยันข้อสังเกตร่วมกันว่า **ระบบไม่ได้ป้องกันความซ้ำซ้อนของ PendingIntent scan
ให้อัตโนมัติ** ผู้เรียกต้องรับผิดชอบความถูกต้องเอง — ไม่พบคำตอบจาก Google/AOSP
maintainer ใน issue นี้

**ผลต่อการตัดสินใจของ `reconcile()`:** เพราะไม่มีหลักฐานยืนยันว่าเรียกซ้ำ
ปลอดภัย 100% **`reconcile()` ต้องไม่เรียก `startScan()`/`registerScans()` เป็น
มาตรการป้องกันไว้ก่อน** ในทุกครั้งที่ทำงาน — จำกัดตัวเองไว้แค่การอ่าน/แก้สถานะ
บนดิสก์ (`inside`, `lastSeenElapsedMillis` → ตัดสิน stale → `markOutside` +
enqueue event) เท่านั้น เส้นทางเดียวที่ยังเรียกลงทะเบียนสแกนซ้ำคือเส้นทางที่มี
หลักฐานพิสูจน์แล้วจริง ๆ ว่าการลงทะเบียนหายไป — คือ boot จริง
(`storedElapsedTimesAreFromThisBoot()==false` ผ่าน `BootCompletedReceiver`
เท่านั้น) **ไม่ขยายไปเรียกจากทุกจุดที่ `reconcile()` ถูกเรียก**

**สรุปสิ่งที่เอกสารระบุเรื่อง stopped state / force-stop:**

- `ApplicationInfo.java:411-428` (`FLAG_STOPPED`, ยกมาแล้วใน ADR-14 หัวข้อ 1.4):
  ระบุว่าแอปที่ถูก force-stop "**will not receive implicit broadcasts** unless
  the sender specifies `FLAG_INCLUDE_STOPPED_PACKAGES`" — พูดถึง**การรับ
  broadcast** เท่านั้น
- `AlarmManager.java` (ซอร์สทั้งไฟล์) — **ไม่มีคำว่า "stopped" หรือ "force-stop"
  แม้แต่ครั้งเดียว** (ตรวจด้วย `grep` ทั้งไฟล์) — ตรงกับที่ ADR-14 หัวข้อ 1.4
  บันทึกไว้แล้วว่า "ยังไม่ยืนยันเอง" ว่าการลงทะเบียนใน Bluetooth stack (หรือ
  alarm ที่ตั้งไว้ใน `AlarmManager`) ถูกล้างทิ้งจริงเมื่อ force-stop หรือแค่
  **หยุดส่ง broadcast ไปหา** — สองอย่างนี้ต่างกันในทางปฏิบัติ (ถ้าแค่หยุดส่ง
  การลงทะเบียนอาจยังอยู่และกลับมาทำงานได้เองถ้าแอปถูกเปิดโดยไม่ต้องลงทะเบียนใหม่
  ถ้าถูกล้างทิ้งจริงต้องลงทะเบียนใหม่เสมอ) — **ค้นรอบนี้ก็ยังหาคำตอบไม่ได้เช่นกัน**
- `docs/sources/android_background_ble.md` มีคำถามพี่น้องค้างอยู่ (ท้ายไฟล์ หัวข้อ
  "หาแหล่งอ้างอิงไม่ได้"): "เมื่อ Bluetooth ถูกปิด ระบบยกเลิกการลงทะเบียน
  `startScan(..., PendingIntent)` ทิ้งหรือแค่หยุดส่งผล — หาแหล่งอ้างอิงไม่ได้"
  — ค้นรอบนี้ (โฟกัสที่ force-stop แทนที่จะเป็น Bluetooth off) **ก็ยังหาคำตอบ
  ไม่ได้เช่นกัน** เป็นคำถามคนละมิติของปัญหาเดียวกัน ("การลงทะเบียนหายไปเงียบ ๆ
  ได้จากหลายสาเหตุ แต่ไม่มีเอกสารระบุว่าสาเหตุไหนทำให้หายจริงกับแค่ทำให้เงียบ")
  — **ทั้งสองข้อยังคงสถานะ "หาแหล่งอ้างอิงไม่ได้" ต่อไป ไม่ได้ปิดในรอบนี้**

⚠️ **ผลต่อ `reconcile()` โดยตรง:** เพราะไม่รู้ว่า force-stop ล้าง registration
ทิ้งจริงหรือไม่ `reconcile()` จึงออกแบบให้ **ไม่พึ่งพาสมมติฐานเรื่องนี้เลย** — มัน
ทำงานอยู่บนสมมติฐานเดียวที่พิสูจน์แล้ว (ความเงียบที่ยาวนานผิดปกติ = stale) ไม่ว่า
สาเหตุที่แท้จริงของความเงียบจะเป็นนาฬิกาปลุกถูก Doze ระงับ, registration หายเงียบ ๆ,
หรือเหตุอื่นที่ยังไม่รู้จัก — วิธีนี้ทนต่อความไม่รู้ในหัวข้อนี้ได้โดยไม่ต้องรอคำตอบ

---

### 6. (e) ฟิลด์ที่ต้องเพิ่มลง `rawSignals` ทุกบรรทัด

**`standbyBucket=<name>`** จาก `UsageStatsManager.getAppStandbyBucket()`
(`~/Library/Android/sdk/sources/android-37.0/android/app/usage/UsageStatsManager.java:758`)
— ค่าที่เป็นไปได้ (จากซอร์สเดียวกัน, บรรทัด 124-175):
`exempted`/`active`/`workingSet`/`frequent`/`rare`/`restricted`/`never`
**ไม่พบ annotation จำกัด API level ในซอร์สที่ตรวจได้** (ซอร์สที่มีคือ
android-37.0 ซึ่งเป็น SDK เวอร์ชันสูงมาก ไม่ได้แปลว่าเมธอดมีมาตั้งแต่ API ต่ำ) —
หน้าเอกสาร overview ยืนยันแยกต่างหากว่า "**Android 9 (API level 28) and later
support App Standby Buckets**"
([developer.android.com/topic/performance/appstandby](https://developer.android.com/topic/performance/appstandby))
ต้อง guard ด้วย `Build.VERSION.SDK_INT >= Build.VERSION_CODES.P` ก่อนเรียก
ตามรูปแบบเดียวกับที่ `batteryOptimizationState()` guard ด้วย
`Build.VERSION_CODES.M` อยู่แล้วในไฟล์เดียวกัน (`BackgroundEvidenceLog.kt:391`)
— เครื่องต่ำกว่า API 28 ให้เขียน `n/a`

**`lightIdle=<true|false>`** — ⚠️ **แก้ไขชื่อ API ที่โจทย์ระบุมา** โจทย์อ้างถึง
`isLightDeviceIdleMode` แต่ตรวจซอร์สจริง
(`~/Library/Android/sdk/sources/android-37.0/android/os/PowerManager.java:2676-2686`)
พบว่าเมธอดชื่อนั้น **`@Deprecated` + `@hide` + `@UnsupportedAppUsage(maxTargetSdk
= Build.VERSION_CODES.S)`** — ไม่ใช่ public API ที่เรียกได้จากแอปทั่วไปตั้งแต่
Android S เป็นต้นไป เมธอด public ตัวจริงที่ยังไม่ deprecate คือ
**`PowerManager.isDeviceLightIdleMode()`** (บรรทัด 2657-2668):

> "Returns true if the device is currently in light idle mode... **it will
> return false if the device is in a long-term idle mode but currently
> running a maintenance window where restrictions have been lifted.**"

**`doze=<true|false>` (ฟิลด์เดิม, `isDeviceIdleMode()`) มีประโยคเดียวกันเป๊ะ**
(`PowerManager.java:2637-2649`):

> "Returns true if currently in active device idle mode, else false... **it
> will return false if the device is in a long-term idle mode but currently
> running a maintenance window where restrictions have been lifted.**"

**นี่คือคำต่อคำที่ต้องใช้เป็นข้อความในหัวข้อ §0.1 ของ
`docs/test-checklists/android_background_runbook.md`** (ออกแบบไว้ให้
`beacon-qa` เป็นคนเขียนจริงในขั้นที่ 3 — ไม่แก้ไฟล์นั้นในรอบนี้ตามข้อห้ามของ
โจทย์): ต้องระบุว่า **`doze=false` ระหว่าง maintenance window ไม่ได้แปลว่า
เครื่องไม่ได้อยู่ใน Doze** — ตามคำต่อคำของ `isDeviceIdleMode()` เอง อาการ
"restrictions ถูกยกเว้นชั่วคราวระหว่าง maintenance window" กับ "ออกจาก Doze
แล้วจริง ๆ" **แยกไม่ออกจากค่านี้ค่าเดียว** ผู้ทดสอบต้องดูควบคู่กับความยาวเวลาที่
เครื่องไม่มีการโต้ตอบ (§0.1 ข้อ 9 เดิม เรื่องถอดสาย USB) ไม่ใช่เชื่อ `doze=false`
ว่าปลอดภัยเสมอ

**ประเมินร่องรอยของ "alarm ตื่นแต่ไม่ได้ประกาศ exit" — ควรเพิ่ม:**

ตามที่โจทย์ชี้ไว้ ปัจจุบัน `exitTimingField` มีเฉพาะบรรทัด `exit` เท่านั้น (ADR-15
ข้อ จ.) สาขาที่ `onExitAlarm` **ตัดสินใจเลื่อนนาฬิกาปลุกออกไปแทนการประกาศ exit**
(`BackgroundRegionMonitor.kt:469-476`: `if (sinceLastSeen < timeoutMillis) {
... return }`) **ไม่เรียก `emit()` เลย** จึงไม่มีบรรทัด log ใด ๆ เกิดขึ้น — ตรงกับ
ที่คืน 3-4 ก.ย. 2026 เงียบสนิท 14 ชั่วโมงโดยไม่มีร่องรอยอะไรให้ตรวจสอบย้อนหลังได้เลย

**ตัดสินใจ: ควรเพิ่ม** — ใช้ค่า `event` แบบใหม่ (ไม่ใช่คอลัมน์ใหม่ ไม่กระทบ
รูปแบบ 6 คอลัมน์คงที่) เช่น `exitAlarmDeferred` เขียนจากสาขานั้นโดยตรง — มี
บรรทัดฐานอยู่แล้วในระบบนี้: ตาราง ADR-14 หัวข้อ 4.2 ระบุไว้แล้วว่ามีค่า `event`
มากกว่าแค่ `enter`/`exit`/`launch` (มี `selftest` อยู่ก่อนแล้ว) —
`tool/analyze_region_log.dart` กรอง transition ด้วย
`e.event == 'enter' || e.event == 'exit'` (บรรทัด 364, 429-430, 561 ฯลฯ)
เท่านั้น จึง**เพิกเฉยค่า `event` ใหม่นี้โดยอัตโนมัติ** โดยไม่ต้องแก้ parser เลย
— `rawSignals` ของบรรทัดนี้ใช้รูปร่างเดียวกับ `exitTimingField` (`sinceLastSeenMs`
/ `scheduledAtElapsed` ใหม่ / `firedAtElapsed`=เวลาที่ alarm ดังจริงรอบนี้) เพื่อ
ให้อ่านได้ทันทีว่าทำไมถึงเลื่อนแทนที่จะประกาศ exit

**ราคาที่ต้องจ่าย (ต้องระบุตรง ๆ):** สาขานี้ถูกออกแบบมาให้เกิดซ้ำได้หลายครั้งใน
คืนเดียวถ้าเครื่องอยู่ใน Doze นาน (ทุกครั้งที่นาฬิกาปลุกดังแล้วเจอว่ายังไม่ครบเวลา
จริง จะ reschedule แล้วอาจดังอีกในรอบถัดไป) — ถ้าเขียน log ทุกครั้งไม่มีเพดาน
ไฟล์หลักฐานอาจโตเร็วผิดปกติในคืนที่มีปัญหาแบบนี้พอดี (ซึ่งเป็นคืนที่ log สำคัญ
ที่สุด) — **ขนาด/อัตราการเขียนของ event ชนิดนี้ยังไม่ได้กำหนดเพดานในเอกสารนี้**
บันทึกเป็นคำถามเปิดสำหรับ `flutter-dev` ตัดสินตอน implement ไม่ใช่การตัดสินใจ
ของเอกสารสถาปัตยกรรมนี้

---

### 7. (f) เปิดหัวข้อ ADR-18 — ยังไม่ตัดสิน
---

### 8. สิ่งที่ยังพิสูจน์ไม่ได้จนกว่าจะทดสอบบนเครื่อง Android จริง

- **K=10 (threshold 5 นาที)** — คำนวณจากข้อมูลที่มีอยู่ (ADR-15 + เอกสาร App
  Standby official) ไม่ใช่ค่าที่วัดผลจริงแล้วว่าลด false positive ได้ตามที่
  ออกแบบไว้ — ต้องมีรอบทดสอบที่ตั้งใจสร้างความเงียบยาวนานหลายระดับ (2-3 นาที,
  5-10 นาที, ชั่วโมง+) แล้ววัดว่า `reconcile()` ตัดสินถูกในแต่ละระดับหรือไม่
- **การเรียก `startScan(..., PendingIntent)` ซ้ำด้วย `PendingIntent` เดิมปลอดภัย
  จริงหรือไม่** — เอกสาร/ซอร์สที่มียืนยันได้แค่ว่า **ฝั่ง SDK ไม่กันให้** ส่วน
  ฝั่ง Bluetooth stack จริงทำอะไรยังไม่รู้ — แต่ข้อนี้ไม่กระทบการ implement ตาม
  ADR-17 เพราะ `reconcile()` ถูกออกแบบไม่ให้เรียกซ้ำเลยตามหัวข้อ 5 ไม่ต้องรอ
  คำตอบข้อนี้ก็ implement ได้
- **`synchronized` critical section ตามหัวข้อ 3.1 ข้อ 2** — ยังไม่เคยมีในโค้ดฐาน
  นี้เลย ต้องมี unit test ที่จำลอง concurrent call จริง (สอง thread เรียก
  `reconcile()` พร้อมกันสำหรับ region เดียวกัน) เพื่อยืนยันว่า event ยิงแค่ครั้ง
  เดียวจริง ก่อนเชื่อว่าออกแบบถูก
- **`exitReason=staleReconcile` ตามด้วย `enter` ในไฟล์หลักฐานจริงบนอุปกรณ์** —
  ยังไม่เคยเห็นบนเครื่องจริงเลยสักครั้ง (เพราะยังไม่ได้ implement) ต้องรอรอบ
  ทดสอบที่จำลองสถานการณ์ "หายไปนานผิดปกติแล้วกลับมา" จริง
- **บรรทัด `exitAlarmDeferred` ใหม่ (หัวข้อ 6)** — ปริมาณ log ที่เกิดขึ้นจริงใน
  คืนที่มี Doze รุนแรง ยังไม่รู้ว่าจะโตแค่ไหน ต้องวัดจากคืนทดสอบจริงก่อนตัดสินใจ
  เรื่องเพดาน/throttle
- **MY_PACKAGE_REPLACED + `reconcile()` ก่อน `clearRegionStates()` (หัวข้อ 3)** —
  เป็นบั๊กแฝงที่พบจากการอ่านโค้ด ยังไม่เคยจำลองสถานการณ์ "อัปเดตแอปขณะอยู่ใน
  โซน" บนเครื่องจริงเลย ต้องเพิ่มเป็นเคสทดสอบใหม่ทั้งเคส
- **ข้อ 3 ของ ADR-18** (ว่า broadcast receiver ที่ระบบเรียกเข้ามาเพื่อ
  `PendingIntent` scan เริ่ม foreground service ได้หรือไม่) — ยังไม่ได้ค้นคว้า
  เลย เป็นเงื่อนไขตัดสินว่า ADR-18 มีทางเป็นไปได้หรือไม่ตั้งแต่ต้น



## ADR-18 (ฉบับร่าง — ยังไม่ตัดสิน): foreground service เฉพาะช่วง `inside` เป็นทางเลือกเสริมของ `reconcile()`

> **สถานะ: เปิดหัวข้อ ไม่ใช่ข้อเสนอที่พร้อม implement** — เอกสารนี้มีไว้บันทึก
> ทางเลือกและ trade-off ที่ต้องพิจารณาต่อ ไม่ใช่การตัดสินใจ ห้ามเริ่ม implement
> จนกว่าจะมีการตัดสินใจแยกต่างหาก (รอบถัดไป)

**แนวคิด:** เมื่อ `BackgroundRegionMonitor` พลิกสถานะเป็น `inside=true` (จาก
`enter`) เปิด foreground service ชั่วคราว **เฉพาะช่วงที่ยังอยู่ในโซน** แล้วใช้
timer ในหน่วยความจำของ service นั้นตรวจ exit แทนที่จะพึ่ง `AlarmManager` เป็น
กลไกหลัก — ปิด service ทันทีที่ตรวจพบ exit (ไม่ว่าจะจาก timer หรือจาก
`reconcile()`) โดยให้ `AlarmManager` (กลไกเดิม) ยังคงทำงานเป็น **fallback**
คู่ขนาน ไม่ใช่แทนที่ — ถ้า service ถูกระบบฆ่าระหว่างทาง (ซึ่งเกิดได้แม้เป็น
foreground service) นาฬิกาปลุกเดิมยังทำหน้าที่กู้สถานะต่อได้เหมือนที่ ADR-17
ออกแบบไว้

**ทำไมถึงยังไม่ตัดสิน — ประเด็นที่ต้องชั่งน้ำหนัก:**

1. **UX/notification — ราคาที่ผู้ใช้จ่ายทุกครั้งที่อยู่ในสาขา:** foreground
   service ตาม
   [ข้อกำหนดของ Android](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
   **ต้องมี notification ที่มองเห็นได้ตลอดเวลาที่ service ทำงาน** — แปลว่า
   **ทุกครั้งที่ลูกค้าเดินเข้าสาขา** (ซึ่งคือเงื่อนไขปกติของการใช้งาน ไม่ใช่เคส
   พิเศษ) จะมี notification ค้างอยู่ในแถบแจ้งเตือนตลอดเวลาที่อยู่ในสาขา — ต่างจาก
   ADR-14 หัวข้อ 3.1 ที่ปฏิเสธ foreground service เป็น**กลไกหลัก**เพราะเหตุผลนี้
   เป๊ะ ข้อเสนอนี้จำกัดขอบเขตให้เกิดเฉพาะ**ช่วง `inside`** ซึ่งลดความถี่ลงมาก
   (ไม่ใช่ตลอดเวลาที่แอปเฝ้าอยู่) แต่ **ไม่ได้ทำให้ปัญหา UX หายไป** เพียงลด
   ขอบเขตเวลาที่ผู้ใช้ต้องเห็นมันเท่านั้น — ยังต้องตัดสินใจว่าลูกค้าที่เดินเข้า
   ร้านทุกวันเห็น notification แบบนี้ทุกครั้งเป็นสิ่งที่ยอมรับได้หรือไม่
2. **`foregroundServiceType` ของ Android 14 (API 34):** ตาม ADR-14 หัวข้อ 2.2
   ที่ค้นไว้แล้ว ชนิดที่ตรงกับ use case คือ **`connectedDevice`** ต้องมี
   `FOREGROUND_SERVICE_CONNECTED_DEVICE` บวกกับ `BLUETOOTH_SCAN` (มีอยู่แล้ว)
   — แอปที่ target Android 14 ขึ้นไปที่ **ไม่ประกาศชนิด** จะได้
   `MissingForegroundServiceTypeException` ทันทีที่เรียก `startForeground()`
   (อ้างจาก
   [Foreground service types are required](https://developer.android.com/about/versions/14/changes/fgs-types-required),
   ยกคำต่อคำไว้แล้วใน ADR-14 หัวข้อ 2.2) — ข้อจำกัดนี้**ใช้ได้กับข้อเสนอนี้เช่น
   เดียวกับที่ ADR-14 บันทึกไว้** ไม่มีอะไรเปลี่ยน แต่ต้องตรวจซ้ำเมื่อ target
   API สูงขึ้นจริง (ตามที่ ADR-14 เตือนไว้แล้วว่ารายการข้อจำกัดยาวขึ้นทุกเวอร์ชัน)
3. **ต้องเริ่ม service จากเบื้องหลังได้จริงหรือไม่ในจังหวะที่ `enter` เกิด** —
   `enter` ส่วนใหญ่เกิดจาก `BeaconScanReceiver.onReceive` ซึ่งเป็น
   `BroadcastReceiver` — ADR-14 หัวข้อ 2.2 ยกรายการข้อยกเว้นของ "ห้ามเริ่ม FGS
   จากเบื้องหลัง" ของ Android 12 ไว้แล้ว ("Your app transitions from a
   user-visible state" ฯลฯ) **ยังไม่ได้ตรวจว่า broadcast receiver ที่ระบบเรียก
   เข้ามาเพื่อ `PendingIntent` scan (ไม่ใช่ user-visible transition) เข้าข้อ
   ยกเว้นข้อไหนหรือไม่** — ถ้าเข้าข้อยกเว้นไม่ได้เลย แนวคิดนี้ **ใช้งานไม่ได้ตั้งแต่
   ต้น** ไม่ว่าจะตัดสินใจเรื่อง UX/notification อย่างไรก็ตาม ต้องวิจัยข้อนี้ก่อน
   เป็นอันดับแรกในรอบตัดสินใจถัดไป — **ยังไม่มีคำตอบในเอกสารนี้**
4. **`MATCH_LOST` เป็นทางเลือกเสริม** — คำนี้เป็นศัพท์ของ
   `ScanSettings.CALLBACK_TYPE_MATCH_LOST` (Android BLE scanning API) ซึ่ง
   **ยังไม่ได้ค้นคว้าในรอบนี้เลย** — ต้องวิจัยแยกว่าใช้ร่วมกับ `PendingIntent`-based
   scan ได้หรือไม่ (`ScanSettings` ที่ใช้ `CALLBACK_TYPE_MATCH_LOST` ต้องมี
   `setMatchMode`/`setNumOfMatches` กำกับ ซึ่งมีเงื่อนไขของตัวเอง) และให้ความหน่วง
   เท่าไรเทียบกับกลไก `AlarmManager` เดิม — **ต้องวิจัยเพิ่มก่อน ห้ามสมมติว่าใช้ได้
   หรือใช้ไม่ได้จนกว่าจะตรวจซอร์ส/เอกสารจริง**

**สิ่งที่ตั้งใจไม่ตัดสินในรอบนี้:** จะใช้แนวคิดนี้เป็นโหมดเสริมที่ผู้ใช้ SDK เลือก
เปิดเอง (ตามที่ ADR-14 หัวข้อ 3.1 เขียนไว้ล่วงหน้าแล้วว่าเป็นทางเลือกในอนาคต) หรือ
ไม่ทำเลย, K ค่าไหนควรใช้คู่กับ timer ในหน่วยความจำ (อาจไม่ใช่ K เดียวกับ ADR-17
เพราะกลไกต่างกัน), และจะแทนที่หรืออยู่คู่กับ `reconcile()` ตลอดไป — ทั้งหมดนี้รอ
รอบตัดสินใจถัดไปที่มีคำตอบของข้อ 3 ก่อน
