# beacon_kit

[![CI](https://github.com/Chanothai/beacon-kit-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Chanothai/beacon-kit-flutter/actions/workflows/ci.yml)

Flutter SDK กลางของ BigC สำหรับรับข้อมูล BLE beacon แบบ broadcast (iBeacon /
Eddystone) ทั้งตอนเปิดแอปและตอนแอปตาย (background) บน iOS + Android — ผ่าน
[`GenericIBeaconEddystoneAdapter`](packages/beacon_kit/lib/src/generic_ibeacon_eddystone_adapter.dart)

ออกแบบให้ **ไม่ผูกกับยี่ห้อ** ใช้มาตรฐานเปิด (iBeacon/Eddystone) เป็นหลัก
(ดู [หลักการออกแบบ ข้อ 2](ARCHITECTURE.md#หลักการออกแบบ) และ
["รองรับหลายยี่ห้อ" ไม่ต้องแยก adapter ต่อยี่ห้อ](ARCHITECTURE.md#ข้อค้นพบสำคัญ-รองรับหลายยี่ห้อ-ไม่ต้องแยก-adapter-ต่อยี่ห้อ-แก้ไข-27-สค-2026))
— **ยังไม่รองรับ GATT** (connect/auth/config/OTA) การเรียก `connect()` จะ throw
`UnsupportedError` ทันที
([`generic_ibeacon_eddystone_adapter.dart:148-157`](packages/beacon_kit/lib/src/generic_ibeacon_eddystone_adapter.dart#L148-L157))

> **สถานะ: 0.x — API ยังไม่ stable** อาจมี breaking change ระหว่าง minor
> version สถานะการทดสอบบนอุปกรณ์จริงล่าสุดอยู่ที่
> [`docs/test-checklists/ios_broadcast_scanning.md`](docs/test-checklists/ios_broadcast_scanning.md)
> และ [`docs/test-checklists/android_background_scanning.md`](docs/test-checklists/android_background_scanning.md)
> ที่เดียวเท่านั้น — README ฉบับนี้ไม่ซ้ำสถานะนั้น

| Platform | OS ขั้นต่ำ | สิทธิ์ที่ต้องขอ |
|---|---|---|
| iOS | 15.0 | `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription` / `NSBluetoothAlwaysUsageDescription` / `UIBackgroundModes` = `[location, bluetooth-central]` |
| Android | minSdk 24 (compileSdk 36) | `BLUETOOTH_SCAN` + `ACCESS_FINE_LOCATION` (plugin ประกาศให้เองใน manifest) |

---

## Quick start

`beacon_kit` **ไม่ได้เผยแพร่บน pub.dev** (internal SDK — ดู `LICENSE`) ใช้ผ่าน
git dependency และ **pin ที่ tag เสมอ อย่า pin ที่ branch** (`ref: main` จะดึง
commit ล่าสุดทุกครั้งที่ resolve ใหม่ — reproduce บิลด์เก่าไม่ได้):

```yaml
dependencies:
  beacon_kit:
    git:
      url: <URL ของ private remote>
      ref: v0.1.0            # <-- pin ที่ tag เสมอ
      path: packages/beacon_kit
```

**iOS** — ใส่ 4 key นี้ใน `Info.plist` ของแอป (ตัวอย่างครบใน
[`example/ios/Runner/Info.plist`](packages/beacon_kit/example/ios/Runner/Info.plist)):
`NSLocationWhenInUseUsageDescription`,
`NSLocationAlwaysAndWhenInUseUsageDescription`,
`NSBluetoothAlwaysUsageDescription`, `UIBackgroundModes` = `[location, bluetooth-central]`
iOS ไม่ให้แอปขอสิทธิ์ Always ซ้ำเองหลังผู้ใช้เลือก When In Use ไปแล้ว — ผู้ใช้ต้อง
ไปเปิดเป็น Always ที่ Settings เอง ([`example/lib/main.dart:1180-1181`](packages/beacon_kit/example/lib/main.dart#L1180-L1181))

**Android** — สิทธิ์ที่ plugin ประกาศให้เองใน manifest แล้ว: `BLUETOOTH_SCAN`,
`ACCESS_FINE_LOCATION`, `BLUETOOTH`/`BLUETOOTH_ADMIN` (maxSdk 30),
`RECEIVE_BOOT_COMPLETED` ([`AndroidManifest.xml`](packages/beacon_kit_android/android/src/main/AndroidManifest.xml))
— ยังต้องขอ runtime เอง ผ่าน
[`BeaconKitAndroid().requestScanPermissions()`](packages/beacon_kit_android/lib/beacon_kit_android.dart#L52)
`POST_NOTIFICATIONS` (Android 13+) **ไม่ได้อยู่ในสิทธิ์ของ plugin** — เป็นหน้าที่
host app ขอเอง (ตัวอย่างจริงที่
[`example/.../MainActivity.kt:189-232`](packages/beacon_kit/example/android/app/src/main/kotlin/com/beaconkit/example/MainActivity.kt#L189-L232))

เริ่มเฝ้า region แล้วฟัง enter/exit — ดูโค้ดเต็มที่
[`example/lib/snippets/region_monitoring_quickstart.dart`](packages/beacon_kit/example/lib/snippets/region_monitoring_quickstart.dart)
(API แยกกันจริงตามแพลตฟอร์มตอนนี้ — ดู §ฟีเจอร์ด้านล่าง)

จะเห็น stream ของ region state event
([`IBeaconRegionStateEvent`](packages/beacon_kit_ios/lib/src/ibeacon_region_state_event.dart)
บน iOS / `AndroidBackgroundRegionEvent` บน Android) ยิง enter/exit เข้ามาดิบ ๆ
ไม่มีการกรองใด ๆ

---

## ฟีเจอร์/แนวคิด

SDK ส่ง **event ดิบ** เท่านั้น — debounce/visit/session, notification policy,
cooldown, และ mapping (major/minor → สาขา/โซน) เป็นหน้าที่ **host app ทั้งหมด**
(ดู [ADR-11](ARCHITECTURE.md#adr-11-region-flapping--ข้อกำหนดเรื่อง-debounce-และการรวม-session-เพิ่ม-31-สค-2026))

| ฟีเจอร์ | คำอธิบาย | ADR | โค้ด |
|---|---|---|---|
| Region enter/exit background | ยิง event enter/exit แม้แอปถูกฆ่า (iOS) หรือระบบจำ registration ไว้หลัง reboot (Android) | [ADR-6](ARCHITECTURE.md#adr-6-จาก-ranging-only-เป็น-region-monitoring-enterexit--เพิ่ม-28-สค-2026), [ADR-10](ARCHITECTURE.md#adr-10-รับ-region-event-ได้ตั้งแต่รอบ-launch--แก้เหตุที่-b5-ไม่ผ่าน-เพิ่ม-30-สค-2026) | [`generic_ibeacon_eddystone_adapter.dart:195`](packages/beacon_kit/lib/src/generic_ibeacon_eddystone_adapter.dart#L195), [`beacon_kit_android.dart:71`](packages/beacon_kit_android/lib/beacon_kit_android.dart#L71) |
| `reconcile()` กู้สถานะข้ามคืน | กู้สถานะ `inside` ที่ค้างเมื่อนาฬิกาปลุกไม่มาถึง (Android) | [ADR-17](ARCHITECTURE.md#adr-17-reconcile--กู้สถานะ-inside-ที่ค้างข้ามคืนเมื่อนาฬิกาปลุกไม่มาถึง-เพิ่ม-4-กย-2026) | [`BackgroundRegionMonitor.kt:597`](packages/beacon_kit_android/android/src/main/kotlin/com/bigc/beacon_kit_android/BackgroundRegionMonitor.kt#L597) |
| Two-tier region registration | ตาข่ายกว้าง 1 region + เจาะจงสาขาไม่เกิน 19 (รวม 20 ตามเพดาน iOS) | [ADR-8](ARCHITECTURE.md#adr-8-two-tier-region-registration--ตาข่ายกว้าง-1-อัน--เจาะจงสาขาไม่เกิน-19-อัน-เพิ่ม-29-สค-2026) | [`IBeaconRangingManager.swift:182`](packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift#L182) (`TOO_MANY_REGIONS`) |
| UUID scheme กลางของ BigC | UUID เดียวทั้งบริษัท แยกอุปกรณ์ด้วย major/minor | [ADR-5](ARCHITECTURE.md#adr-5-bigc-id-scheme-สำหรับ-multi-vendor-provisioning-เพิ่ม-28-สค-2026) | [`docs/sources/bigc_provisioning.md`](docs/sources/bigc_provisioning.md) |
| `ProximityGate` (foreground) | ชั้นตัดสินใจ "ใกล้พอหรือยัง" จาก RSSI/proximity เหนือ scan ที่มีอยู่แล้ว | [ADR-19](ARCHITECTURE.md#adr-19-proximitygate--ชั้นตัดสินใจ-ใกล้พอหรือยัง-จาก-rssiproximity-ระดับ-dart-เพิ่ม-8-กย-2026) | [`proximity_gate.dart:259`](packages/beacon_kit/lib/src/proximity/proximity_gate.dart#L259) |
| Background proximity — Android | พอร์ตตรรกะ `ProximityGate` เป็น Kotlin คีย์บีคอนอ่านจากเฟรมจริง | [ADR-20](ARCHITECTURE.md#adr-20-proximitygate-ตอนแอปไม่ทำงาน--port-ตรรกะเป็น-kotlin-ใน-beaconscanreceiver-เพิ่ม-9-กย-2026) | [`BackgroundProximityMonitor.kt`](packages/beacon_kit_android/android/src/main/kotlin/com/bigc/beacon_kit_android/BackgroundProximityMonitor.kt) |
| Background proximity — iOS | พอร์ตเป็น Swift + gate ตัวที่ทำงานตอน background ตั้งเป็น passthrough | [ADR-21](ARCHITECTURE.md#adr-21-proximitygate-ฝั่ง-ios--port-เป็น-swift-ใน-ibeaconrangingmanager-เพิ่ม-10-กย-2026), [ADR-22](ARCHITECTURE.md#adr-22-ชั้นที่-2-ตอน-background--proximitygate-ตัวที่สองที่ตั้งค่าแบบ-passthrough-เพิ่ม-10-กย-2026) | [`IBeaconRangingManager.swift`](packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift), `BackgroundProximityMonitor.swift` |
| Cooldown ต่อบีคอน | **ไม่ใช่ default ของ SDK** — ตัวอย่าง policy ที่ example app ตั้งเอง | [ADR-19 §8](ARCHITECTURE.md#8-ค่าตั้งต้นของ-sdk-สำหรับ-poc--ไม่ใช่ค่าที่ได้จากภาคสนาม) | [`example/lib/main.dart:42-62`](packages/beacon_kit/example/lib/main.dart#L42-L62) |
| Evidence log | บันทึกเหตุการณ์ดิบ 6 คอลัมน์จากโค้ด native ทั้งสองแพลตฟอร์ม | [ADR-10](ARCHITECTURE.md#adr-10-รับ-region-event-ได้ตั้งแต่รอบ-launch--แก้เหตุที่-b5-ไม่ผ่าน-เพิ่ม-30-สค-2026) | [`evidence_log_line.dart`](packages/beacon_kit/example/lib/diagnostics/evidence_log_line.dart) |
| Debounce / visit / session | ไม่ได้ทำใน SDK — ส่ง event ดิบเท่านั้น host app ต้องใส่ชั้นกรองเอง | [ADR-11](ARCHITECTURE.md#adr-11-region-flapping--ข้อกำหนดเรื่อง-debounce-และการรวม-session-เพิ่ม-31-สค-2026) | ไม่มีใน `beacon_kit` — ต้นแบบที่ [`prototype/visit_filter/`](prototype/visit_filter/) ยังไม่ต่อเข้า SDK |

**หมายเหตุ:** notification policy, cooldown ต่อบีคอน, และ mapping
major/minor → สาขา/โซน **ไม่ใช่หน้าที่ของ `beacon_kit`** — ดูหัวข้อ Integration
guide ด้านล่าง

---

## Integration guide

สิ่งที่ host app ต้องทำเอง (SDK ไม่ทำให้): notification policy + cooldown ·
mapping table major/minor → สาขา/โซน + cache · outbox/upload ขึ้น server
(`beacon_kit` ไม่มี dependency network ใด ๆ) · consent/PDPA · provisioning
(ไม่อยู่ใน SDK นี้ — ดู [`docs/sources/bigc_provisioning.md`](docs/sources/bigc_provisioning.md))

รายละเอียดเต็มอยู่ที่ [`docs/integration-guide.md`](docs/integration-guide.md)

---

## ข้อจำกัด

- **exit ไม่ใช่ real-time** — [ADR-15](ARCHITECTURE.md#adr-15-ฉบับร่าง--ยังไม่ตัดสิน-exittimeoutseconds-เป็นสัญญาที่ทำไม่ได้-เพิ่ม-2-กย-2026)
  (**ฉบับร่าง ยังไม่ตัดสินใจสุดท้าย**)
- **MIUI battery/autostart** อาจกระทบการทำงานเบื้องหลัง — พฤติกรรมที่สังเกตได้
  อยู่ใน [`docs/test-checklists/android_background_runbook.md` หัวข้อ 0.1](docs/test-checklists/android_background_runbook.md)
  · เหตุผลเชิงนโยบายของ Google Play ที่บล็อกการขอยกเว้นเองอยู่ที่
  [ADR-14 หัวข้อ 2.3](ARCHITECTURE.md#23-การขอยกเว้น-battery-optimization--ทำได้-แต่-play-store-บล็อกเคสของเรา)
- **เพดาน 20 region บน iOS** — [ADR-8](ARCHITECTURE.md#adr-8-two-tier-region-registration--ตาข่ายกว้าง-1-อัน--เจาะจงสาขาไม่เกิน-19-อัน-เพิ่ม-29-สค-2026)
  enforce จริงที่ [`IBeaconRangingManager.swift:182`](packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift#L182)
- **iOS region event `major`/`minor` = `null` เมื่อ wildcard** (ไม่ใช่ `0`) —
  [`IBeaconRangingManager.swift:826-831`](packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift#L826-L831)
- **ปิด-เปิด Bluetooth ระหว่างเฝ้าบน Android** — ยังไม่มี ADR ยืนยันพฤติกรรมนี้บน
  Android เอกสารที่ใกล้เคียงที่สุดคือฝั่ง iOS ใน
  [`docs/test-checklists/ios_broadcast_scanning.md` หัวข้อ 7](docs/test-checklists/ios_broadcast_scanning.md)
  ซึ่งเป็นคนละแพลตฟอร์ม — ต้องวิจัยเพิ่มก่อนเขียนอ้างในเอกสารสำหรับ Android
- **iOS background sample ห่าง/`unknown` สูงกว่าตอน foreground** — แนวคิดทั่วไป
  อ้างที่ [`docs/test-checklists/ios_broadcast_scanning.md` หัวข้อ 4](docs/test-checklists/ios_broadcast_scanning.md)
- **ยังไม่มี GATT** (connect/auth/config/OTA) — ดูหัวข้อคืออะไรด้านบน

---

## Example app

```
cd packages/beacon_kit/example && flutter run
```

ปุ่มหลักในหน้าจอเดียว: **Start scan**/**Stop scan** (สแกนดิบตอน foreground) ·
**Start region monitoring** (iOS iBeacon region monitoring) ·
**เช็คสิทธิ์ใหม่** · **เริ่มเฝ้าเบื้องหลัง**/**หยุดเฝ้า**/**รีเฟรชสถานะ** (Android
background region monitoring) · **ขอสิทธิ์อีกครั้ง**/**เปิดหน้าตั้งค่า** ·
**ทดสอบแจ้งเตือน** และ **อ่าน error ล่าสุด** (เครื่องมือวัด evidence log) ·
**ดู log** เปิดหน้า log เต็ม

Evidence log 6 คอลัมน์ — รูปแบบเต็มดูที่
[`evidence_log_line.dart`](packages/beacon_kit/example/lib/diagnostics/evidence_log_line.dart)
ไม่อธิบายซ้ำที่นี่ Convention ของคอลัมน์ raw signals: `beacon=<major>/<minor>`
ตรงกันทั้งสอง platform (ตัวระบุเชิงตรรกะจับคู่ข้าม platform ได้) ·
`mac=<2 ไบต์ท้าย>` เฉพาะ Android (ตัวแยกเชิงกายภาพ) · `build=<sha>` ·
`store=ok|<error>` — ดูทะเบียนบีคอนที่ใช้ทดสอบที่
[`docs/beacon-inventory.md`](docs/beacon-inventory.md)

---

## Versioning

Semver ต่อ package — CHANGELOG อยู่ที่ `packages/*/CHANGELOG.md` ของแต่ละ
package (ยังเป็น placeholder เริ่มต้น) · ทุก package เป็น `0.x` = API ยังไม่
stable ตาม semver · ยังไม่มี breaking change ที่บันทึกเป็น ADR ในตอนนี้

---

## เอกสารที่ควรอ่านต่อ

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — ทุกการตัดสินใจเชิงสถาปัตยกรรม (ADR index)
- [`docs/integration-guide.md`](docs/integration-guide.md) — สิ่งที่ host app ต้องทำเอง
- [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`PIPELINE.md`](PIPELINE.md) · [`SPRINT.md`](SPRINT.md)
- [`SECURITY.md`](SECURITY.md) — ความเสี่ยงที่ยอมรับไว้ + ช่องทางรายงานช่องโหว่

## License

Proprietary / internal use only — ดู `LICENSE` และ `NOTICE`
