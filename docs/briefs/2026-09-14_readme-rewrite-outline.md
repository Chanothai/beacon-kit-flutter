# โครง README rewrite — beacon_kit

- branch: `docs/readme-rewrite`
- base: `ea604e0` (main ที่รวม PR #30 แล้ว)
- สถานะ: โครงอนุมัติแล้วโดย reviewer (14 ก.ย. 2026) — รอ flutter-dev เขียนเนื้อหาจริง
- วันที่สร้างโครง: 11 ก.ย. 2026 (beacon-architect) · แก้ error + บันทึกคำตัดสิน: 14 ก.ย. 2026

---

# โครง README rewrite — beacon_kit (architect handoff ให้ flutter-dev)

อ่านอย่างเดียวรอบนี้ — repo ที่ตรวจ: `/Users/Ball/Desktop/bigc-special-forst/beacon-kit`
branch `docs/readme-rewrite`, HEAD `ea604e0` (main ที่รวม PR #30 แล้ว)
ไม่มีการแก้ไฟล์ใดใน repo ระหว่างทำงานนี้ — ทุกข้ออ้างอิงยืนยันจากการอ่านจริง ณ commit นี้เท่านั้น

ทุกจุดที่เขียนว่า "path:บรรทัด" คือพิกัดที่อ่านแล้วจริง — ถ้า flutter-dev พบว่าบรรทัดขยับ
(เพราะมี commit ใหม่ก่อนเริ่มเขียนจริง) ให้ grep ชื่อ symbol ซ้ำ ไม่ใช่เชื่อเลขบรรทัดเป๊ะ ๆ

---

## 0. ส่วนต่างจากบรีฟ (อ่านก่อนเขียนโค้ดจริง — สำคัญ)

1. **"vendor-agnostic (ADR-2)" ในบรีฟ §1 ไม่ตรง** — ADR-2 จริงคือ
   `### ADR-2: แหล่งที่มาของข้อมูล + shape เต็มของ \`BeaconAdvertisement\`` (ARCHITECTURE.md:208)
   ไม่ใช่เรื่อง vendor-agnostic เลย
   หลักการ vendor-agnostic อยู่ที่ **"หลักการออกแบบ" ข้อ 2** (ARCHITECTURE.md:8)
   และขยายความที่หัวข้อ **"ข้อค้นพบสำคัญ: 'รองรับหลายยี่ห้อ' ไม่ต้องแยก adapter ต่อยี่ห้อ"**
   (ARCHITECTURE.md:68) — README ต้องลิงก์สองจุดนี้แทน ADR-2

2. **ADR-1 ถึง ADR-4 เป็นหัวข้อระดับ `###` ซ้อนใต้ `## ADR: iOS-first Sprint — Domain Layer & Platform Channel Contract`**
   (ARCHITECTURE.md:157) ไม่ใช่ `##` ระดับเดียวกับ ADR-5 ขึ้นไป — ตรวจแล้วว่า
   `tool/check_adr_banners.sh` ใช้ `grep -E '^#{1,6} '` จึงจับได้ทั้งสองระดับ ไม่กระทบ
   แต่ถ้า flutter-dev เขียนลิงก์ README แบบ `#adr-2` (anchor) ต้องรู้ว่าอยู่ใต้หัวข้อ
   ADR ปี iOS-first ไม่ใช่หัวข้อเดี่ยว

3. **ไม่มี ADR ชื่อ "watchdog" สำหรับเคส BT toggle เงียบจนกด start ใหม่** ตามที่บรีฟ §5
   สมมติไว้ ("BT toggle Android เงียบจนกด start ใหม่ (ADR watchdog รอ)") — ค้นด้วย
   `grep -n "watchdog\|Bluetooth ปิดกลางคัน\|BLUETOOTH_UNAVAILABLE"` แล้ว ไม่พบ ADR
   ที่ผูกกับคำว่า watchdog ในชื่อหรือเนื้อหา สิ่งที่ใกล้เคียงที่สุดคือหัวข้อ
   "7. Bluetooth ปิดกลางคัน (`BLUETOOTH_UNAVAILABLE`)" ใน
   `docs/test-checklists/ios_broadcast_scanning.md:430` (เป็น "ยังไม่ทดสอบ" ไม่ใช่
   ADR ที่ตัดสินใจแล้ว) — README §5 ต้องเขียนว่า **"ยังไม่มี ADR ยืนยันพฤติกรรมนี้
   บนพฤติกรรม Android — อ้างอิงได้แค่ checklist ข้อ 7 ของ ios ซึ่งเป็นฝั่ง iOS เท่านั้น
   Android ต้องวิจัยเพิ่มก่อนเขียนอ้างในเอกสาร"** ห้ามแต่งเลข ADR ขึ้นมาเอง

4. **ไม่มี ADR-23 ในโปรเจกต์นี้เลย** — ยืนยันซ้ำด้วย `grep -n "ADR-23" ARCHITECTURE.md`
   ไม่พบ ดังนั้นบรีฟ §7 ที่เขียน "breaking ที่รู้แล้ว (minSdk 26 — ADR-23 รอ)" **ไม่มี
   หลักฐาน** — grep `minSdk` / `minSdk = 26` ทั่ว repo ก็ไม่พบการพูดถึงแผนขยับเป็น 26
   ที่ไหนเลย (ปัจจุบัน `minSdk = 24` ที่ `packages/beacon_kit_android/android/build.gradle.kts:48`)
   README §7 **ต้องไม่อ้าง ADR-23** — ถ้าจะพูดเรื่องแผนขยับ minSdk ให้เขียนตรง ๆ ว่า
   "ยังไม่มี ADR บันทึกแผนนี้ — ต้องวิจัย/ตัดสินใจเพิ่มก่อนประกาศเป็น breaking change
   ที่จะเกิด" หรือถ้าเจ้าของโปรเจกต์ยืนยันปากเปล่าว่าจะมีจริง ให้เปิด ADR ใหม่ก่อน
   ไม่ใช่ให้ README อ้างถึง ADR ที่ยังไม่เกิด

5. **"Playbook" ในบรีฟ (integration-guide: "ลิงก์ Playbook")** — ไม่พบไฟล์ชื่อ Playbook
   ในโครง repo ปัจจุบัน (`git ls-files | grep -i playbook` ว่างเปล่า) เอกสารที่ใกล้เคียง
   ที่สุดที่ถูกอ้างถึงคือ **"K9P Playbook"** ซึ่งถูกอ้างใน ARCHITECTURE.md เป็นเอกสาร
   ก่อนหน้า (ARCHITECTURE.md:7, 66, 118, 119) แต่ **ไม่มีไฟล์จริงใน repo นี้ที่ชื่อนั้น**
   — สันนิษฐานว่าเป็นเอกสารก่อนหน้าที่ไม่ได้ถูก commit เข้ามา หรืออยู่นอก repo
   flutter-dev **ห้ามใส่ลิงก์ไปไฟล์ที่ไม่มีอยู่จริง** — integration-guide ต้องเขียนว่า
   "อ้างอิงเพิ่มเติม: K9P Playbook (เอกสารภายนอก ไม่มีไฟล์ใน repo นี้ ณ ตอนเขียน)"
   หรือขอให้เจ้าของโปรเจกต์ยืนยัน path ก่อนใส่ลิงก์จริง

6. **`docs/sources/kkm_k9p.md` ยังไม่มีหัวข้อ "Provisioning: เขียน UUID/Major/Minor"**
   ตามที่ skill `beacon-sdk-verify` กำหนด (ตรวจหัวข้อจริงด้วย
   `grep -n "^## " docs/sources/kkm_k9p.md` ได้ 5 หัวข้อ: `Dependency & License`,
   `GATT UUID (verified...)`, `Auth flow (verified)`, `ไม่พบ / ไม่ยืนยัน`, `แหล่งอ้างอิง`
   — ไม่มีหัวข้อ provisioning 6 ข้อที่ skill บังคับ) ดังนั้น **SECURITY.md ต้องเขียนว่า
   "ยังไม่ยืนยันว่า K9P เขียน UUID/Major/Minor ผ่าน SDK ที่ integrate ได้จริงหรือไม่
   (6 เช็คของ beacon-sdk-verify ยังไม่ถูกบันทึกไว้ในไฟล์นี้)"** ไม่ใช่สรุปว่า provision ได้
   เพราะเห็นว่ามี auth/write characteristic อยู่แล้วเฉย ๆ (ตรงกับกติกาเหล็กของ skill เอง)
   — นี่ไม่ใช่งานที่ต้องทำรอบนี้ (README rewrite ไม่ใช่ verify SDK ใหม่) แค่ต้อง**ไม่พูด
   เกินสิ่งที่ยืนยันแล้ว** ใน SECURITY.md

7. **ไม่มีช่องทางรายงานช่องโหว่ (security contact) อยู่ในโปรเจกต์เลย** — ค้น
   `security@`, `SECURITY.md`, "รายงานช่องโหว่", "responsible disclosure" ทั่ว repo
   (LICENSE, NOTICE, ทุก .md) ไม่พบอีเมลหรือช่องทางใด ๆ **flutter-dev ห้ามแต่งอีเมล/
   ช่องทางขึ้นเอง** — ต้องถามเจ้าของโปรเจกต์ก่อนเขียนหัวข้อนี้ใน SECURITY.md หรือใส่
   placeholder ที่ระบุตรง ๆ ว่า "TODO: เจ้าของโปรเจกต์ต้องระบุช่องทางจริง"

8. **CONTRIBUTING.md ข้อ 8 (ตาราง "เอกสารที่ต้องอัปเดตคู่กับโค้ด") ยังอ้างว่า
   "เปลี่ยนสถานะฟีเจอร์ → ต้องอัปเดตตารางใน README.md **และ**
   docs/test-checklists/ios_broadcast_scanning.md ให้ตรงกัน"** (CONTRIBUTING.md:258)
   ซึ่ง**ขัดตรง ๆ กับกติกาข้อ 2 ของบรีฟนี้ที่สั่งให้ลบตารางสถานะออกจาก README ทั้งหมด**
   — งานรอบนี้ไม่รวมการแก้ CONTRIBUTING.md (นอกขอบเขตไฟล์ที่บรีฟอนุญาต) ดังนั้น
   หลัง merge README ใหม่แล้ว **แถวนั้นใน CONTRIBUTING.md จะกลายเป็นเอกสารที่ขัดกับ
   ความจริง** ต้องแจ้งเจ้าของโปรเจกต์ให้เปิดงานแก้ CONTRIBUTING.md แยกต่างหาก (ไม่ใช่
   งานของรอบนี้ แต่ต้อง flag ไว้ไม่ให้หาย) — ข้อสังเกตของ `check_adr_banners.sh` เอง
   ก็เตือนเรื่อง "ตัวชี้ที่ชี้ผิด" ในทำนองเดียวกัน

9. **"beacon=<major>/<minor> ทั้งสอง platform · mac= เฉพาะ Android" ในบรีฟ §6 — ตรวจแล้ว
   ถูกต้องหลัง commit ล่าสุด** (ยืนยัน 2 ทางอิสระ: ฝั่ง Android
   `packages/beacon_kit/example/android/app/src/main/kotlin/com/beaconkit/example/ExampleProximityWatcher.kt:157-179`
   คอมเมนต์บอกตรง ๆ ว่า `beacon=<major>/<minor>` "ตรงกับฝั่ง iOS" ส่วน `mac=<2 ไบต์ท้าย>`
   เป็นตัวแยกเชิงกายภาพเฉพาะ Android · ฝั่ง iOS
   `packages/beacon_kit/example/ios/Runner/AppDelegate.swift:428-453` มีแต่ `beacon=`
   ไม่มี `mac=`) — **ไม่ใช่ส่วนต่างจากบรีฟ** แต่บันทึกไว้เพราะตอนอ่านรอบแรกเจอ
   grep ผลเก่าใน `docs/test-checklists/android_background_scanning.md` ที่ดูเหมือน
   ขัดกัน (บอกว่า beacon= เป็น MAC 2 ไบต์ท้าย) — นั่นคือ**ประวัติของบั๊กที่แก้ไปแล้ว**
   ไม่ใช่พฤติกรรมปัจจุบัน ให้ flutter-dev อ้างอิงจากไฟล์ Kotlin/Swift ตรง ๆ เท่านั้น
   ไม่ใช่จากข้อความบรรยายเก่าใน checklist

10. **§6 ของบรีฟพูดถึง "ปุ่มแต่ละปุ่ม" ของ example app** — ยังไม่ได้ตรวจรายชื่อปุ่มทั้งหมด
    ใน `ScanPage` (`packages/beacon_kit/example/lib/main.dart` ยาว 1508 บรรทัด) รอบนี้
    เพราะไม่ใช่ขอบเขตของโครง (flutter-dev ต้องเปิดไฟล์นี้เองตอนเขียนจริงเพื่อลิสต์ปุ่ม
    ให้ตรง — **ห้ามเดารายชื่อปุ่มจากโครงนี้**)

---

## 1. โครง `README.md` (เป้า < 200 บรรทัด)

โครงสร้าง 8 หัวข้อ (`## §N ชื่อ`) เรียงตามบรีฟ ประมาณบรรทัดรวมกันต้อง < 200 —
งบต่อหัวข้อโดยประมาณ (ปรับได้ ขอแค่รวมไม่เกิน):

### §1 คืออะไร (~20 บรรทัด)
- ประโยคเปิด: Flutter SDK กลางของ BigC สำหรับรับข้อมูล BLE beacon แบบ broadcast
  (iBeacon/Eddystone) ทั้งตอนเปิดแอปและตอนแอปตาย (background) บน iOS + Android
  → อ้างอิง: `GenericIBeaconEddystoneAdapter` (`packages/beacon_kit/lib/src/generic_ibeacon_eddystone_adapter.dart:18`)
  เป็นตัว implement จริง, background region monitoring: iOS = ADR-6
  (ARCHITECTURE.md:560 "จาก ranging-only เป็น region monitoring (enter/exit)"),
  Android = ADR-14 (ARCHITECTURE.md:1688 "Android ก้อนที่ 2 — การทำงานเบื้องหลัง")
- vendor-agnostic → อ้างอิง ARCHITECTURE.md:8 ("หลักการออกแบบ" ข้อ 2) +
  ARCHITECTURE.md:68 ("ข้อค้นพบสำคัญ...") **ไม่ใช่ ADR-2** (ดูข้อ 1 ใน "ส่วนต่างจากบรีฟ")
- ไม่มี GATT → อ้างอิง `connect()` ที่
  `packages/beacon_kit/lib/src/generic_ibeacon_eddystone_adapter.dart:148-156`
  โยน `UnsupportedError('$vendorId ไม่รองรับ connect (supportsConnect=false, broadcast-only)')`
  ตรง ๆ — เขียนได้ตรง ๆ ว่า "connect-path (GATT) ยังไม่ implement ในตอนนี้"
- ตาราง platform support:
  | Platform | OS ขั้นต่ำ | สิทธิ์ที่ต้องขอ |
  |---|---|---|
  | iOS | 15.0 — `packages/beacon_kit_ios/ios/beacon_kit_ios.podspec` (`s.platform = :ios, '15.0'`) | `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription` / `NSBluetoothAlwaysUsageDescription` — ยืนยันจาก `packages/beacon_kit/example/ios/Runner/Info.plist` |
  | Android | minSdk 24 — `packages/beacon_kit_android/android/build.gradle.kts:48` (compileSdk 36 ที่บรรทัด 31) | `BLUETOOTH_SCAN` + `ACCESS_FINE_LOCATION` — plugin ประกาศให้เองใน `packages/beacon_kit_android/android/src/main/AndroidManifest.xml` (มีคอมเมนต์อ้าง ADR-12 กำกับ) |
- Badge CI: อ้างจาก `.github/workflows/ci.yml` — ชื่อ workflow คือ `CI` (`.github/workflows/ci.yml:1`)
  **flutter-dev ต้องตรวจ URL badge เองจาก remote จริงของ repo** (ไม่ยืนยันในรอบนี้
  เพราะไม่ได้เช็ค `git remote -v` — ใส่ placeholder ถ้าไม่แน่ใจ URL org/repo)

### §2 Quick start 5 นาที (~55 บรรทัด รวม snippet block ที่อ้าง path ไม่ paste เต็ม)
- (a) dependency —ยังไม่ publish pub.dev → อ้างอิง README เดิมมีคำอธิบายที่ดีอยู่แล้ว
  (README.md:183-199 เดิม, ดูหัวข้อ 8 "สิ่งที่ต้องลบ/ย้าย" — เก็บโครง git dependency +
  pin tag ไว้ ปรับคำที่เป็นสถานะออก) **หมายเหตุ:** ต้องยืนยัน remote URL จริงกับ
  เจ้าของโปรเจกต์ก่อนใส่ตัวอย่างที่ระบุ URL จริง (README เดิมใช้ placeholder
  `<URL ของ private remote>` ก็เพียงพอ)
- (b) iOS setup — คัดลอก key จริงจาก
  `packages/beacon_kit/example/ios/Runner/Info.plist` (อ่านแล้วมีครบ 4 key:
  `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationWhenInUseUsageDescription`,
  `NSBluetoothAlwaysUsageDescription`, `UIBackgroundModes` = `[location, bluetooth-central]`)
  — เขียนว่า "ขอ Always" ต้องอธิบายว่า best UX คือขอ When In Use ก่อนแล้วค่อย upgrade
  เป็น Always (ไม่มีหลักฐานในโค้ดตอนนี้ว่า example ทำ progressive request หรือไม่ —
  **ต้องเปิด `main.dart` ตรวจ flow ขอสิทธิ์จริงก่อนเขียนยืนยัน** อย่าสมมติ)
- (c) Android permission — สิทธิ์ที่ plugin merge ให้ (install-time + runtime ที่ประกาศ
  ใน manifest): `BLUETOOTH_SCAN`, `ACCESS_FINE_LOCATION`, `BLUETOOTH`/`BLUETOOTH_ADMIN`
  (maxSdk 30), `RECEIVE_BOOT_COMPLETED` — ทั้งหมดยืนยันจาก
  `packages/beacon_kit_android/android/src/main/AndroidManifest.xml` (มีคอมเมนต์
  อ้าง ADR-12/ADR-14 กำกับทุกบรรทัด) · runtime request ทำผ่าน
  `BeaconKitAndroid().requestScanPermissions()`
  (`packages/beacon_kit_android/lib/beacon_kit_android.dart:52`)
  · **`POST_NOTIFICATIONS` ไม่ได้อยู่ใน manifest ของ plugin เลย** — เป็นหน้าที่ host
  app ต้องขอเอง ยืนยันจาก `packages/beacon_kit/example/android/app/src/main/AndroidManifest.xml:15`
  และ `packages/beacon_kit/example/android/app/src/main/kotlin/com/beaconkit/example/MainActivity.kt:189-232`
  (โค้ดตัวอย่างจริงของ "host app ต้องทำเอง" อยู่ตรงนี้ ไม่ใช่ในแพ็กเกจ)
- (d) snippet ~20 บรรทัด — ต้องเป็นไฟล์จริง ดูหัวข้อ 3 "รายการ snippet" ไฟล์
  `region_monitoring_quickstart.dart`
- (e) "จะเห็นอะไร" 1 บรรทัด — เขียนดิบ ๆ ว่า stream ของ region state event
  (`IBeaconRegionStateEvent` บน iOS / `AndroidBackgroundRegionEvent` บน Android)
  จะยิง enter/exit เข้ามา **ห้ามใส่ตัวเลขเวลา/ความเร็ว** (ขัดกติกาข้อ 2)

### §3 ฟีเจอร์/แนวคิด (~45 บรรทัด — ตารางเต็มอยู่หัวข้อ 2 ด้านล่างของไฟล์นี้)
ดูตารางเต็มที่หัวข้อ "2. ตาราง §3" ด้านล่าง — ในนี้แค่ใส่ตารางนั้นเข้า README ตรง ๆ
พร้อมประโยคเปิดสั้น ๆ ว่า SDK ส่ง **event ดิบ** เท่านั้น debounce/visit/session/
notification policy/cooldown/mapping เป็นหน้าที่ host app ทั้งหมด (ADR-11 —
ARCHITECTURE.md:1110 "Region flapping — ข้อกำหนดเรื่อง debounce และการรวม session")

### §4 Integration guide (สรุป ~15 บรรทัด + ลิงก์)
- ลิงก์ `docs/integration-guide.md` (ไฟล์ใหม่ — ดูหัวข้อ 4)
- bullet สั้น: notification policy + cooldown เป็นของ host app · ตาราง
  major/minor → สาขา/โซน + cache เป็นของ host app (ไม่มีโค้ดของเรื่องนี้ใน
  `beacon_kit` — ยืนยันด้วย `grep -rn "major.*branch\|สาขา" packages/beacon_kit/lib`
  ไม่พบ) · outbox/upload เป็นของ host app (ไม่มีโค้ด network ใน `beacon_kit`
  เลย — ตรวจจาก `packages/beacon_kit/pubspec.yaml` ไม่มี dependency http/dio ใด ๆ)
  · consent/PDPA เป็นของ host app · provisioning ไม่อยู่ใน SDK นี้ (มี
  `docs/sources/bigc_provisioning.md` เป็นเอกสารอ้างอิงแยก ไม่ใช่โค้ดใน `beacon_kit`)

### §5 ข้อจำกัดต่อ platform (~35 บรรทัด — 6-8 bullet, ห้ามใส่ตัวเลข)
ทุก bullet ต้องมี ADR/ไฟล์กำกับ รายการที่ยืนยันแล้ว:
1. exit ไม่ใช่ real-time → ADR-15 **(ฉบับร่าง — ยังไม่ตัดสิน)**
   (ARCHITECTURE.md:2325 `exitTimeoutSeconds` เป็นสัญญาที่ทำไม่ได้) — README ต้อง
   เขียนกำกับว่า "ฉบับร่าง ยังไม่ตัดสินใจสุดท้าย" ตรง ๆ ตามสถานะจริงของ ADR
2. MIUI battery/autostart behavior → อ้างอิง ADR-14 หัวข้อ 2.3
   (ARCHITECTURE.md:1688 ขึ้นไป, ตรวจเลขหัวข้อย่อยจริงตอนเขียนจริงด้วย grep
   `grep -n "หัวข้อ 2.3\|^### " ARCHITECTURE.md` ในช่วง ADR-14) **ไม่มี "runbook §0"
   ตามที่บรีฟเขียน** — ไฟล์ที่ใกล้เคียงคือ `docs/test-checklists/android_background_runbook.md`
   ซึ่งเป็นไฟล์ผลทดสอบ (มีตัวเลข/วันที่) **ห้ามลิงก์จากใน README** (ขัดกติกาข้อ 2)
   ให้ลิงก์เฉพาะ ADR/AndroidManifest comment เท่านั้นสำหรับข้อจำกัดเชิงพฤติกรรม
3. iOS 20 region limit → ADR-8 (ARCHITECTURE.md:778 "Two-tier region registration")
   + อ้างอิง Apple official (ARCHITECTURE.md:786, 495) "An app can register up to
   20 regions at a time." — enforce จริงที่ `BeaconKitIosPlugin.swift` (ตามที่ ADR-5
   อธิบายไว้ที่ ARCHITECTURE.md:466)
4. iOS region event major/minor = null เมื่อ wildcard (ไม่ใช่ 0) — **ยืนยันแล้ว**
   ที่ `packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift:824-830`
   คอมเมนต์อ้าง Apple docs ตรง ๆ (`CLBeaconIdentityConstraint.major`/`.minor` เป็น
   `UInt16?`) และโค้ดส่ง `NSNull()` ผ่าน `StandardMethodCodec` เมื่อเป็น wildcard
   (`constraint.major.map { NSNumber(value: $0) } ?? NSNull()`) ระบุอ้างอิง ADR-5
   กำกับในคอมเมนต์เดียวกัน
5. BT toggle เงียบจนกด start ใหม่ → **ไม่มี ADR ยืนยัน** (ดูข้อ 3 ใน
   "ส่วนต่างจากบรีฟ") เขียนตามที่ยืนยันได้จริงเท่านั้น หรือข้ามข้อนี้ถ้าไม่มีแหล่งอ้างอิง
6. iOS background sample ห่าง/unknown สูง → ไม่มีตัวเลขในบรรทัดนี้ตามกติกาข้อ 2
   อ้างอิงได้แค่แนวคิดทั่วไปจาก
   `docs/test-checklists/ios_broadcast_scanning.md` ข้อ "4. Background mode
   (`location`)" (บรรทัด 366) — **ห้าม copy ตัวเลข/วันที่จากไฟล์นั้นมาลง README**
7. ยังไม่มี GATT → อ้างอิงเดียวกับ §1 (`connect()` throw `UnsupportedError`)

### §6 Example app (~25 บรรทัด)
- รันแอป: `cd packages/beacon_kit/example && flutter run`
- ปุ่มแต่ละปุ่ม: **flutter-dev ต้องเปิด `main.dart` เองเพื่อลิสต์ให้ตรง** (ดูข้อ 10
  ใน "ส่วนต่างจากบรีฟ" — ไม่ได้ลิสต์ในโครงนี้)
- evidence log 6 คอลัมน์ — ยืนยันจาก
  `packages/beacon_kit/example/lib/diagnostics/evidence_log_line.dart:11-15`
  (`timestamp \t processId \t event \t regionIdentifier \t conclusion \t rawSignals`)
  — README ลิงก์ไฟล์นี้ตรง ๆ ไม่ต้องอธิบายซ้ำ (ตามที่บรีฟสั่ง)
- convention: `beacon=<major>/<minor>` ทั้งสอง platform, `mac=<2 ไบต์ท้าย>` เฉพาะ
  Android, `build=<sha>`, `store=ok|<error>` → ยืนยันแล้ว (ดูข้อ 9 ใน
  "ส่วนต่างจากบรีฟ" สำหรับ path:บรรทัดครบ)
- ลิงก์ `docs/beacon-inventory.md` (มีอยู่จริง — อ่านแล้วเป็นทะเบียนบีคอนจริงที่ใช้
  ทดสอบ พร้อมคำเตือนเรื่อง password ค่าโรงงาน — **มีข้อมูลที่เป็น "ผลทดสอบ" ปนอยู่
  เยอะ** (วันที่/ชื่อคน/สถานะ) — README **ลิงก์ไปเฉยๆ ห้าม quote เนื้อหาเข้ามา**

### §7 Versioning (~10 บรรทัด)
- semver + CHANGELOG ต่อ package → **มีไฟล์จริงครบทั้ง 4 package**
  (`packages/beacon_kit/CHANGELOG.md`, `packages/beacon_kit_android/CHANGELOG.md`,
  `packages/beacon_kit_ios/CHANGELOG.md`, `packages/beacon_kit_platform_interface/CHANGELOG.md`)
  แต่ **เนื้อหายังเป็น template ที่ `flutter create` ให้มา** (ยืนยันจาก
  `packages/beacon_kit/CHANGELOG.md`: มีแค่ `## 0.0.1` + `* TODO: Describe initial
  release.`) — README §7 เขียนได้แค่ "ลิงก์ CHANGELOG ต่อ package" ตรง ๆ **ห้ามอ้างว่า
  CHANGELOG มีเนื้อหาบันทึกการเปลี่ยนแปลงจริงแล้ว** เพราะยังเป็น placeholder ทั้งหมด
- breaking ที่รู้แล้ว: **ห้ามอ้าง "minSdk 26 — ADR-23"** (ดูข้อ 4 ใน "ส่วนต่างจากบรีฟ")
- API experimental ติดป้าย → เวอร์ชันปัจจุบันของทั้ง 4 package คือ `0.0.1`
  (`version: 0.0.1` ยืนยันจาก pubspec ทั้ง 4 ไฟล์ ดูตารางเวอร์ชันหัวข้อ 7) —
  เขียนได้ตรงว่า "0.x = API ยังไม่ stable ตาม semver" (สอดคล้องกับคำเตือนใน
  README เดิมบรรทัด 7 ซึ่งใช้คำเดียวกัน — เก็บโทนนี้ไว้ได้ ไม่ใช่สถานะผลทดสอบ)

### §8 ลิงก์ (~10 บรรทัด)
`ARCHITECTURE.md` (ADR index) · `CONTRIBUTING.md` · `PIPELINE.md` · `SPRINT.md`
(มีอยู่จริง — ยืนยันจาก `ls` root) · `SECURITY.md` (ไฟล์ใหม่) · `LICENSE`

---

## 2. ตาราง §3 — ฟีเจอร์/แนวคิด (ร่างเต็ม)

| ฟีเจอร์ | 1 บรรทัด | ADR (เลข + หัวข้อจริง) | โค้ด |
|---|---|---|---|
| Region enter/exit ตอน background | SDK ยิง event enter/exit ของ region ที่ลงทะเบียนไว้ แม้แอปถูกฆ่า (เส้นทาง iOS) หรือระบบยังจำ registration ไว้ (Android หลัง reboot) | ADR-6 "จาก ranging-only เป็น region monitoring (enter/exit)" (ARCHITECTURE.md:560) + ADR-10 "รับ region event ได้ตั้งแต่รอบ launch" (ARCHITECTURE.md:921) | `packages/beacon_kit/lib/src/generic_ibeacon_eddystone_adapter.dart:195` (`startIBeaconMonitoring`), `packages/beacon_kit_android/lib/beacon_kit_android.dart:71` (`startBackgroundRegionMonitoring`) |
| reconcile() กู้สถานะข้ามคืน | กู้สถานะ `inside` ที่ค้างเมื่อนาฬิกาปลุกไม่มาถึง | ADR-17 "`reconcile()` — กู้สถานะ `inside` ที่ค้างข้ามคืนเมื่อนาฬิกาปลุกไม่มาถึง" (ARCHITECTURE.md:2769) | `packages/beacon_kit_android/android/src/main/kotlin/com/bigc/beacon_kit_android/BackgroundRegionMonitor.kt:597` (`fun reconcile(context: Context)`) |
| Two-tier region registration | ตาข่ายกว้าง 1 region + เจาะจงสาขาไม่เกิน 19 region (รวม 20 ตามเพดาน iOS) | ADR-8 "Two-tier region registration — ตาข่ายกว้าง 1 อัน + เจาะจงสาขาไม่เกิน 19 อัน" (ARCHITECTURE.md:778) | `packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift:182` (error code `TOO_MANY_REGIONS`) — **หมายเหตุ: ARCHITECTURE.md:466 เขียนว่า enforce ที่ `BeaconKitIosPlugin.swift` แต่โค้ดจริงตอนนี้อยู่ใน `IBeaconRangingManager.swift` แทน — ARCHITECTURE.md จุดนี้คลาดเคลื่อนจากโค้ดปัจจุบัน (`grep -rn "TOO_MANY_REGIONS" packages/beacon_kit_ios/ios/` เจอที่เดียว) ให้ README/integration-guide อ้าง path จริงจากโค้ด ไม่ใช่คัดจาก ARCHITECTURE.md ตรง ๆ และควรแจ้งเจ้าของโปรเจกต์ให้แก้ ARCHITECTURE.md แยกอีกงาน** |
| UUID scheme กลางของ BigC | UUID เดียวทั้งบริษัท แยกอุปกรณ์ด้วย major/minor | ADR-5 "BigC ID Scheme สำหรับ multi-vendor provisioning" (ARCHITECTURE.md:485) | `docs/sources/bigc_provisioning.md` (ไม่ใช่โค้ด — เป็นเอกสารค่า/วิธี derive) |
| ProximityGate (foreground) | ชั้นตัดสินใจ "ใกล้พอหรือยัง" จาก RSSI/proximity เหนือ scan/ranging ที่มีอยู่แล้ว ระดับ Dart | ADR-19 "`ProximityGate` — ชั้นตัดสินใจ 'ใกล้พอหรือยัง' จาก RSSI/proximity ระดับ Dart" (ARCHITECTURE.md:3294) | `packages/beacon_kit/lib/src/proximity/proximity_gate.dart:259` (class `ProximityGate`), `:474` (`push`), `:581` (`sweepStale`) |
| Background proximity — Android | port ตรรกะ ProximityGate เดียวกันเป็น Kotlin ให้ทำงานตอน background ได้ คีย์บีคอนอ่านจากเฟรมจริง | ADR-20 "ProximityGate ตอนแอปไม่ทำงาน — port ตรรกะเป็น Kotlin ใน `BeaconScanReceiver`" (ARCHITECTURE.md:3766) | `packages/beacon_kit_android/android/src/main/kotlin/com/bigc/beacon_kit_android/BackgroundProximityMonitor.kt` (ยืนยันมีไฟล์จริงจาก grep ก่อนหน้านี้) |
| Background proximity — iOS | ProximityGate ตัวที่สองฝั่ง iOS พอร์ตเป็น Swift + ตัวที่ทำงานตอน background ตั้งเป็น passthrough | ADR-21 "ProximityGate ฝั่ง iOS — port เป็น Swift ใน `IBeaconRangingManager`" (ARCHITECTURE.md:4102) + ADR-22 "ชั้นที่ 2 ตอน background — `ProximityGate` ตัวที่สองที่ตั้งค่าแบบ passthrough" (ARCHITECTURE.md:4485) | `packages/beacon_kit_ios/ios/beacon_kit_ios/Sources/beacon_kit_ios/IBeaconRangingManager.swift`, `BackgroundProximityMonitor.swift` (ยืนยันมีไฟล์จริงจาก grep ก่อนหน้านี้) |
| Cooldown ต่อบีคอน (ตัวอย่าง policy) | ไม่ใช่ default ของ SDK — เป็นตัวอย่างนโยบายที่ example app ตั้งค่าเอง | ADR-19 §8 (ค่าเริ่มต้นสำหรับ POC — ต้อง grep เลขหัวข้อย่อยจริงตอนเขียน `grep -n "หัวข้อ 8\|หัวข้อ 7/8" ARCHITECTURE.md` ในช่วง ADR-19) | `packages/beacon_kit/example/lib/main.dart:42-62` (ค่าคงที่ `_proximityEnterMeters` ฯลฯ พร้อมคอมเมนต์ "ค่าตั้งต้นสำหรับ POC ... ยังไม่ผ่านการ calibrate") |
| Evidence log | บันทึกเหตุการณ์ดิบ 6 คอลัมน์จากโค้ด native ทั้งสองแพลตฟอร์ม เทียบผลข้ามแพลตฟอร์มได้ | ADR-10 "รับ region event ได้ตั้งแต่รอบ launch" (ARCHITECTURE.md:921) — เป็นที่มาของความจำเป็นต้องมี evidence log ตั้งแต่ launch | `packages/beacon_kit/example/lib/diagnostics/evidence_log_line.dart` (parser), เขียนจริงที่ `ios/Runner/BackgroundEvidenceLog.swift` และ `android/app/.../BackgroundEvidenceLog.kt` |
| Debounce / visit / session | ไม่ได้ทำใน SDK — SDK ส่ง event ดิบ (enter/exit ดิบ) เท่านั้น host app ต้องใส่ชั้นกรองเอง | ADR-11 "Region flapping — ข้อกำหนดเรื่อง debounce และการรวมsession" (ARCHITECTURE.md:1110) | ไม่มีโค้ดใน `beacon_kit` — ต้นแบบอยู่ที่ `prototype/visit_filter/` (**ยังไม่ต่อเข้า SDK** ต้องเขียนตรง ๆ ว่าเป็น prototype ไม่ใช่ของที่ใช้ได้จาก `beacon_kit` เลย) |

**หมายเหตุสำคัญสำหรับ flutter-dev:** แถวที่เขียนว่า "ยังไม่ได้เปิดไฟล์ตรวจ path จริง"
ในตารางข้างบน **ต้องกลับไปยืนยัน path:บรรทัดจริงก่อนใส่ลง README** — ห้ามคัดลอกไปทั้งที่
ยังไม่ verified เพราะจะขัดกับ requirement ที่ reviewer จะ grep หา symbol ใน `lib/`

---

## 3. รายการ snippet ที่ต้องมีใน `packages/beacon_kit/example/lib/snippets/`

พื้นฐาน: package ตัวอย่างมี dependency `beacon_kit` (path) และ `beacon_kit_android`
(path) อยู่แล้วใน `packages/beacon_kit/example/pubspec.yaml:31,36-37` — snippet
import ได้ตรงทั้งสองแพ็กเกจโดยไม่ต้องเพิ่ม dependency ใหม่ ทุกไฟล์ผ่าน
`flutter analyze --fatal-infos` เพราะ CI job `analyze-test` มี
`packages/beacon_kit/example` อยู่ใน matrix อยู่แล้ว (`.github/workflows/ci.yml`
บรรทัดของ matrix `package:` มี `- packages/beacon_kit/example`)

### ไฟล์ 1: `region_monitoring_quickstart.dart`
- **จุดประสงค์:** snippet ~20 บรรทัดของ README §2(d) — แสดงการแยก platform ตามที่
  ใช้จริงในระบบตอนนี้ (ไม่มี unified facade — ADR-13 หัวข้อ 4 ยังไม่ทำ)
- **API ที่ใช้ (ยืนยันมีจริงใน `lib/`):**
  - `import 'dart:io' show Platform;`
  - `import 'package:beacon_kit/beacon_kit.dart';`
    → `GenericIBeaconEddystoneAdapter` (`packages/beacon_kit/lib/src/generic_ibeacon_eddystone_adapter.dart:18`)
    → `IBeaconRegionConfig` (`packages/beacon_kit/lib/src/ibeacon_region_config.dart:7`, field `identifier`/`uuid`)
    → `adapter.startIBeaconMonitoring()` (`generic_ibeacon_eddystone_adapter.dart:195`)
    → `adapter.regionStateEvents` (`generic_ibeacon_eddystone_adapter.dart:176`, ชนิด `Stream<IBeaconRegionStateEvent>`)
  - `import 'package:beacon_kit_android/beacon_kit_android.dart' show BeaconKitAndroid, AndroidBeaconRegion, AndroidBackgroundRegionEvent;`
    → `BeaconKitAndroid` (`packages/beacon_kit_android/lib/beacon_kit_android.dart:34`)
    → `AndroidBeaconRegion` constructor `({required identifier, required uuid, major, minor})`
      (`packages/beacon_kit_android/lib/src/android_background_region.dart:32-41` — **assert: ถ้าระบุ `minor` ต้องระบุ `major` ด้วย**
      snippet ต้องหลีกเลี่ยง error นี้โดยใส่ major ก่อนเสมอถ้าจะใส่ minor)
    → `BeaconKitAndroid().startBackgroundRegionMonitoring(regions: [...], exitTimeoutSeconds: ...)`
      (`packages/beacon_kit_android/lib/beacon_kit_android.dart:71-76`)
    → `beaconKitAndroid.backgroundRegionEvents` (getter ท้ายไฟล์เดียวกัน บรรทัด ~89)
- **โครงสร้าง:** `if (Platform.isIOS) { ... } else if (Platform.isAndroid) { ... }`
  ใช้ region เดียวกันทั้งสองสาขา (UUID ตัวอย่าง — **ต้องใช้ placeholder ไม่ใช่ UUID จริง
  ของ BigC** ตาม ADR-5 ที่ห้าม hardcode ใน production code, แต่ snippet เป็นตัวอย่าง
  ท่าทีการเรียก API ใส่ placeholder ชัดเจนได้ เช่น `'<PROXIMITY_UUID>'`)
- **ข้อควรระวังให้ compile ผ่าน:**
  - ต้อง `dispose`/`cancel` subscription ก่อนจบ widget หรือเขียนเป็น top-level
    function ที่ไม่ผูก widget lifecycle เลย (เลือกแบบ standalone function
    `Future<void> runQuickstart() async { ... }` จะ analyze ผ่านง่ายกว่า ไม่ต้องมี
    StatefulWidget)
  - import `beacon_kit_android` ต้องไม่ conditional ด้วย `dart:io` — คอมไพล์ได้ทุก
    แพลตฟอร์มเพราะ Dart-side ของ plugin เป็น pure Dart เหมือนที่ `main.dart` ทำ
    (`packages/beacon_kit/example/lib/main.dart:5-13`)

### ไฟล์ 2: `proximity_gate_foreground.dart`
- **จุดประสงค์:** แสดงแถว "ProximityGate (foreground)" ของตาราง §3 — วิธีป้อน
  `scan()` เข้า `ProximityGate` และเรียก `sweepStale()` ซ้ำด้วย `Timer`
- **API ที่ใช้ (ยืนยันมีจริง):**
  - `ProximityGate` (`packages/beacon_kit/lib/src/proximity/proximity_gate.dart:259`)
    constructor ต้องมี `clock: DateTime.now` เป็นอย่างน้อย (required) — พารามิเตอร์
    อื่น (`enterMeters`, `exitMeters`, `immediateMeters`, `windowSize`,
    `dwellSamples`, `pathLossExponent`, `staleAfter`) มี default ในตัว (เห็นจาก
    `ProximityGate({required this.clock, this.enterMeters = 3.0, ...` ที่บรรทัด 260-264)
    — snippet ใช้ default ได้ ไม่ต้องก็อปค่าจาก `main.dart` ทั้งหมด (ค่าพวกนั้นเป็น
    POC policy ของ example ตาม ADR-19 §8 ไม่ใช่ default ที่ต้อง demo ซ้ำ)
  - `proximityGate.push(advertisement)` คืน `ProximityTransition?`
    (`proximity_gate.dart:474`, พารามิเตอร์คือ `BeaconAdvertisement` ตัวเดียว)
  - `proximityGate.sweepStale()` คืน `List<ProximityTransition>`
    (`proximity_gate.dart:581`)
  - `adapter.scan()` คืน `Stream<BeaconAdvertisement>`
    (`generic_ibeacon_eddystone_adapter.dart:45`)
- **โครงสร้าง:** subscribe `adapter.scan()` → ทุก advertisement เรียก
  `proximityGate.push(advertisement)` → ถ้าไม่ null ให้ print/handle transition
  → แยก `Timer.periodic(...)` เรียก `proximityGate.sweepStale()` ซ้ำ (ตาม
  ที่ `main.dart:129-133,209-247` ทำ — ProximityGate **ห้ามมี Timer ในตัวเอง**
  ต้องเป็น host app เรียกเอง)
- **ข้อควรระวังให้ compile ผ่าน:**
  - ต้อง `cancel()` ทั้ง `StreamSubscription` และ `Timer` ตอนจบ (ตัวอย่างใน
    `main.dart:709` มี `_proximitySweepTimer?.cancel();` เป็นแบบอย่าง)
  - ระวัง unused variable ที่ `flutter analyze --fatal-infos` จะ fail — ทุก
    ตัวแปรที่ประกาศต้องถูกใช้จริงอย่างน้อยหนึ่งจุด (เช่น print หรือ callback)

**สิ่งที่บรีฟขอแต่ยังไม่ได้ยืนยัน sweepStale Timer "ตาม example/lib/main.dart อย่างไร"
ในเชิง exact snippet ของ Timer construction** — แนะนำให้ flutter-dev เปิด
`packages/beacon_kit/example/lib/main.dart:209-219` ตรง ๆ ก่อนเขียนไฟล์ 2 เพราะ
มีรายละเอียด (เช่น `Timer.periodic(_proximitySweepInterval, ...)`) ที่ยังไม่ได้
คัดลอกมาไว้ในโครงนี้ครบ 100%

---

## 4. โครง `docs/integration-guide.md`

ไฟล์ใหม่ทั้งฉบับ — โครงหัวข้อ:

1. **Setup ทีละขั้นทั้งสอง platform** — ขยาย README §2(b)/(c) ให้ละเอียดกว่า
   (ทุก key ของ Info.plist พร้อมคำอธิบาย "จำเป็นเมื่อ" — ใช้ตารางเดิมจาก README
   เก่าบรรทัด 206-211 เป็นฐาน แต่ตัดคำที่เป็นสถานะทดสอบออก)
2. **Flow สองชั้น (region → proximity)** — อ้างอิง ADR-6 (region) + ADR-19
   (proximity) — วาด sequence เป็น bullet ว่า region enter ก่อน แล้ว ProximityGate
   ค่อยตัดสิน bucket ทีหลังจาก RSSI/proximity sample
3. **Notification 2 ระดับ (enter ทั่วไป / near เจาะจง) + ทำไม iOS ต่างจาก Android**
   — อ้างอิง ADR-20 (Android — key จากเฟรมจริง) และ ADR-21/ADR-22 (iOS —
   foreground gate + background passthrough) เป็นเหตุผลว่าทำไม "near" ตอน
   background มีพฤติกรรมต่างกันสองแพลตฟอร์ม — **ต้องเขียนโดยไม่ใส่ตัวเลข
   latency ใด ๆ** (กติกาข้อ 2 ใช้กับไฟล์นี้เหมือนกัน แม้จะเป็นไฟล์ลึกกว่า README)
4. **Outbox pattern (at-least-once + idempotency key + WorkManager /
   background URLSession)** — **ไม่มีโค้ดของเรื่องนี้ใน repo นี้เลย** (ตรวจแล้วว่า
   `beacon_kit` ไม่มี dependency network ใด ๆ) — เขียนเป็นคำแนะนำสถาปัตยกรรม
   ล้วน ๆ ไม่ผูกกับไฟล์จริง ต้องระบุชัดว่า "นี่คือคำแนะนำสำหรับ host app ไม่ใช่สิ่งที่
   `beacon_kit` ทำให้"
5. **Mapping table (major/minor → สาขา/โซน) + cache** — เดียวกับข้อ 4 ไม่มีโค้ดรองรับ
   ใน repo นี้ เขียนเป็นคำแนะนำ ชี้ว่าต้องอิง UUID scheme จาก ADR-5/`docs/sources/bigc_provisioning.md`
6. **Consent/PDPA** — **ไม่พบเอกสาร PDPA ใด ๆ ในโปรเจกต์นี้** (ดูข้อ 7 ใน
   "ส่วนต่างจากบรีฟ" — เหมือนกับ SECURITY.md) ต้องเขียนเป็นคำเตือนทั่วไปว่า
   ข้อมูลตำแหน่งที่ SDK ให้มาเข้าข่าย PDPA และ host app ต้องมีกลไก consent เอง
   ไม่ใช่หน้าที่ของ `beacon_kit`
7. **ลิงก์ Playbook** — **ไม่มีไฟล์นี้ใน repo** (ดูข้อ 5 ใน "ส่วนต่างจากบรีฟ") ห้ามใส่
   ลิงก์ที่ไม่มีจริง
8. **ตัวอย่าง policy ค่าเริ่มต้นจาก ADR-19 §8** — คัดลอกแนวคิดจาก
   `packages/beacon_kit/example/lib/main.dart:42-62` (ค่าคงที่ทั้งหมดพร้อม
   คอมเมนต์ "ยังไม่ผ่านการ calibrate กับสาขาจริง ห้ามใช้เป็นค่า production") —
   **ต้องคัดลอกคำเตือนนี้มาด้วย ห้ามตัดออก** เพราะเป็นคำเตือนที่ ADR สั่งไว้ตรง ๆ

---

## 5. โครง `SECURITY.md`

ไฟล์ใหม่ทั้งฉบับ — โครงหัวข้อ:

1. **Accepted risk: iBeacon spoof/clone** — iBeacon standard ไม่มี authentication
   ในตัวเฟรม (plaintext broadcast) → อ้างอิง ADR-5 หัวข้อย่อยที่พูดถึง trade-off
   ของ UUID เดียวทั้งบริษัท (ARCHITECTURE.md:547 "การใช้ UUID เดียวทั้งบริษัท
   เปลี่ยนลักษณะความเสี่ยงนี้อย่างไร... การรั่วของ UUID เดียวนี้กระทบทั้งฟลีตพร้อมกัน")
2. **Password โรงงาน K9P** — ค่า default `"0000000000000000"` (16 เลข 0) ต้องเปลี่ยน
   ก่อน pilot → อ้างอิงคู่ **2 แหล่งอิสระ**: `docs/sources/kkm_k9p.md:21`
   ("Password 8–16 ตัวอักษร, default จากโรงงาน `0000000000000000`") และ
   `docs/beacon-inventory.md` หัวข้อ "⚠️ ความเสี่ยงที่ยอมรับไว้ — password ค่าโรงงาน"
   (ยืนยันว่า #2/#3 ในฟลีตจริงยังไม่เปลี่ยน ณ ตอนเขียน — **ห้ามลิงก์ไฟล์ inventory
   จาก SECURITY.md ตรง ๆ เพราะไฟล์นั้นมีวันที่/ชื่อคน/ผลทดสอบปนอยู่** ให้สรุปเป็น
   คำเตือนทั่วไปแทน ไม่ต้องระบุเลขบีคอน)
3. **ข้อมูลตำแหน่ง = PDPA** — **ไม่มีเอกสาร PDPA ในโปรเจกต์นี้** เขียนเป็นคำเตือน
   ทั่วไป ไม่ผูกกับกฎหมายไทยแบบละเอียด (ไม่ใช่ขอบเขตของ SDK repo นี้) แนะนำให้
   host app ปรึกษาทีมกฎหมาย/compliance ของบริษัทเอง
4. **ช่องทางรายงานช่องโหว่** — **ยังไม่มีช่องทางที่ยืนยันได้ในโปรเจกต์**
   (ดูข้อ 7 ใน "ส่วนต่างจากบรีฟ") ใส่ placeholder ชัดเจนว่าต้องรอเจ้าของโปรเจกต์
   ระบุ ห้ามแต่งอีเมล/ช่องทางขึ้นเอง
5. **สิ่งที่ SDK ไม่ทำ** — ไม่ส่ง network เอง (ยืนยันจาก `packages/beacon_kit/pubspec.yaml`
   ไม่มี dependency http/dio/network ใด ๆ), ไม่ทำ GATT/auth เอง (`connect()` throw
   `UnsupportedError`), ไม่เก็บ consent/PDPA ให้ (เป็นของ host app ตาม §4 ของ
   integration-guide)

**อ้างอิงที่ยังหาไม่เจอ ต้องทำเครื่องหมายในไฟล์จริงว่า "ยังไม่ยืนยัน":**
- `docs/sources/bigc_provisioning.md` — อ่านหัวข้อแล้วไม่มีเรื่อง security risk
  โดยตรง (หัวข้อคือ derive UUID + คำเตือนเรื่องห้ามใช้ปนกับ demo UUID) **ไม่ใช่
  แหล่งอ้างอิงสำหรับความเสี่ยงด้านความปลอดภัย** ตามที่บรีฟข้อ 5 สมมติไว้ — ใช้
  `docs/sources/kkm_k9p.md` + `docs/beacon-inventory.md` แทนสำหรับเรื่อง password

---

## 6. โครง README ของ 4 package ย่อย (~10-20 บรรทัดต่อไฟล์)

โครงเดียวกันทั้ง 4 ไฟล์ ปรับแค่ชื่อ/บทบาท:

```
# <ชื่อ package>

ส่วนหนึ่งของ federated plugin `beacon_kit` — <บทบาทสั้น 1 บรรทัด>

## ใครควร depend ตรงนี้

ปกติแอปไม่ต้อง depend package นี้ตรง ๆ — ใช้ `beacon_kit` (ดู
[README หลัก](../beacon_kit/README.md)) ซึ่งดึง <ชื่อ package> เข้ามาให้เอง
ยกเว้นกรณี <ระบุเหตุผลเฉพาะของ package นั้น — ดูด้านล่าง>

## เอกสารหลัก

- [`beacon_kit` README](../beacon_kit/README.md) — วิธีใช้งานทั่วไป
- [`ARCHITECTURE.md`](../../ARCHITECTURE.md) — เหตุผลของ federated plugin pattern
```

บทบาทเฉพาะ (สำหรับให้ flutter-dev เติม 1 บรรทัดต่อไฟล์):
- `beacon_kit_platform_interface` — สัญญา method channel กลาง (federated plugin
  contract) → เหตุผล federated plugin อยู่ที่ ARCHITECTURE.md:12-21
- `beacon_kit_android` — implementation ฝั่ง Android (Kotlin) — **ระบุตรง ๆ ว่า
  ใครควร depend ตรงนี้บ้าง** เพราะไฟล์นี้มี API เฉพาะ Android ที่ไม่ได้ยกขึ้น
  platform interface (`BeaconKitAndroid`, permission methods, background region
  monitoring — ตาม comment ที่ `beacon_kit_android.dart:1-13`) ซึ่งแปลว่า **แอปที่
  ต้องการ background region monitoring บน Android ต้อง import
  `beacon_kit_android` ตรง ๆ ด้วย ไม่ใช่แค่ `beacon_kit`** — ต้องเขียนข้อยกเว้นนี้ชัด
  ต่างจาก `beacon_kit_ios`/`platform_interface` ที่ไม่ต้อง
- `beacon_kit_ios` — implementation ฝั่ง iOS (Swift)

---

## 7. ตารางเวอร์ชันจริง (อ่านจากไฟล์ต้นทางจริง ณ commit `ea604e0`)

| ตัวแปร | ค่า | ที่มา (path:บรรทัด) |
|---|---|---|
| Dart SDK (ทั้ง 4 package) | `^3.13.0` | `packages/beacon_kit/pubspec.yaml:8`, `packages/beacon_kit_platform_interface/pubspec.yaml:7`, `packages/beacon_kit_android/pubspec.yaml:8`, `packages/beacon_kit_ios/pubspec.yaml:8` |
| Flutter (beacon_kit, platform_interface) | `>=1.17.0` | `packages/beacon_kit/pubspec.yaml:9`, `packages/beacon_kit_platform_interface/pubspec.yaml:8` |
| Flutter (beacon_kit_android, beacon_kit_ios) | `>=3.3.0` | `packages/beacon_kit_android/pubspec.yaml:9`, `packages/beacon_kit_ios/pubspec.yaml:9` |
| version ของทั้ง 4 package | `0.0.1` | `packages/*/pubspec.yaml:3` (ทุกไฟล์) |
| Android compileSdk | `36` | `packages/beacon_kit_android/android/build.gradle.kts:31` |
| Android minSdk | `24` | `packages/beacon_kit_android/android/build.gradle.kts:48` **(ยังไม่มีแผนขยับเป็น 26 ที่มีหลักฐานในโค้ด/ADR — ดูข้อ 4 ใน "ส่วนต่างจากบรีฟ")** |
| Kotlin version | `2.4.0` | `packages/beacon_kit_android/android/build.gradle.kts:5` |
| Android Gradle Plugin | `9.1.0` (classpath) | `packages/beacon_kit_android/android/build.gradle.kts:12` |
| Java compat | `VERSION_17` | `packages/beacon_kit_android/android/build.gradle.kts:33-34` |
| iOS deployment target | `15.0` | `packages/beacon_kit_ios/ios/beacon_kit_ios.podspec` (`s.platform = :ios, '15.0'`) |
| Swift version (podspec) | `5.0` | `packages/beacon_kit_ios/ios/beacon_kit_ios.podspec` (`s.swift_version = '5.0'`) |

**หมายเหตุ:** ตัวเลขข้างบนอ่านจากไฟล์จริง ณ ตอนค้นคว้า (11 ก.ย. 2026 ตามวันที่ของ
สภาพแวดล้อม) — บรีฟกำหนดกติกาข้อ 5 ว่าต้องอ่านจริง ณ ตอนเขียน ดังนั้น flutter-dev
**ต้องเปิดไฟล์เหล่านี้ซ้ำก่อนใส่ลง README จริง** โดยเฉพาะถ้ามี commit ใหม่เข้ามา
ระหว่างที่รอ merge งานนี้

---

## 8. สิ่งที่ต้องลบ/ย้ายจาก README เดิม (320 บรรทัด)

| ส่วนเดิม (บรรทัดใน README ปัจจุบัน) | ไปที่ไหน |
|---|---|
| หัวข้อ "ตารางสถานะฟีเจอร์" ทั้งก้อน (บรรทัด 12-38) รวมคำอธิบายศัพท์ (29-37) | **ทิ้ง** — ขัดกติกาข้อ 2 (ห้ามมีสถานะทดสอบ) แทนที่ด้วยลิงก์ `docs/test-checklists/{ios_broadcast_scanning,android_background_scanning}.md` + ประโยค "สถานะล่าสุดอยู่ที่นั่นที่เดียว" |
| "⚠️ ขอบเขตของ background region monitoring" (39-53) | **ทิ้งเนื้อหาตัวเลข/สถานะ** — แนวคิด "อย่าเหมารวมว่า background scan ใช้งานได้ทุกเคส" ย้ายไปเป็น bullet แบบไม่มีตัวเลขใน README §5 |
| "🔴 ต้องมีชั้น debounce เสมอ — ห้าม deploy โดยไม่มี" (55-68) | **แนวคิดย้ายไป README §3 (แถว Debounce/visit/session) + integration-guide** — ตัวเลข "86 ครั้ง" / วันที่ทดสอบ **ทิ้งทั้งหมด** เหตุผลเชิงสถาปัตยกรรม (CoreLocation ไม่กรองให้เอง ต้องมีชั้น debounce เอง) เก็บไว้แบบไม่มีตัวเลข อ้าง ADR-11 แทน |
| "🤖 Android — สิ่งที่ต้องรู้ก่อนใช้" (70-124) | **แยกสองทาง**: ข้อเท็จจริงเชิง permission/policy ที่ไม่มีตัวเลขทดสอบ (เช่น "ตัดสิทธิ์ `neverForLocation` ไม่ได้", "ขอยกเว้น battery optimization เองไม่ได้ตามนโยบาย Google Play") ย้ายไป README §2(c)/§5 หรือ integration-guide · ส่วนที่เป็นผลวัด/วันที่ (เช่น "ทดสอบบน Xiaomi... 2 ก.ย.", "14 ชม. 45 นาที") **ทิ้ง — อยู่ใน checklist อยู่แล้ว** |
| "⚠️ Android ทำงานเบื้องหลัง ไม่เท่ากับ iOS" (126-145) | **ตารางเปรียบเทียบ iOS/Android ย้ายไป integration-guide** (เนื้อหาไม่มีตัวเลขทดสอบ เป็นข้อเท็จจริงเชิงสถาปัตยกรรม อ้าง ADR-14 หัวข้อ 1 อยู่แล้ว) — ประโยค "**เลือกไม่ใช้ foreground service โดยตั้งใจ**" เก็บไว้ได้ อ้าง ADR-14 หัวข้อ 3.1 |
| "ขอบเขตของการทดสอบบนอุปกรณ์จริง" (147-179) | **ทิ้งทั้งหมด** — เป็นผลทดสอบล้วน ๆ (UUID จริงที่ทดสอบ, dBm, ชื่ออุปกรณ์) ชี้ไป checklist แทน |
| "วิธีติดตั้ง" (183-199) | **เก็บไว้ใน README §2(a)** ปรับคำเล็กน้อย (ยังไม่ publish pub.dev ยังจริงอยู่ — ต้องยืนยันซ้ำตอนเขียนว่ายังจริงไหม) |
| "สิ่งที่ต้องตั้งค่าเพิ่มฝั่ง iOS" (201-233) รวม AppDelegate snippet | **เก็บแนวคิดไว้ใน README §2(b) + integration-guide** — snippet Swift ของ AppDelegate เป็นโค้ด native ไม่ใช่ Dart จึงไม่เข้าเงื่อนไข "ต้องอยู่ใน example/lib/snippets/" (กติกาข้อ 3 พูดถึงโค้ด Dart) — **ยืนยันกับเจ้าของโปรเจกต์ว่า Swift snippet ยัง inline ใน README ได้หรือไม่ เพราะ CI ไม่ analyze Swift** ถ้าจะ inline ต้องระบุว่าไม่ได้ผ่านการ compile-check อัตโนมัติ |
| "ตัวอย่างการใช้งาน" (237-276, Dart code block) | **ย้ายเป็นไฟล์ snippet จริง** — เนื้อหาตรงกับ `region_monitoring_quickstart.dart` แต่ code เดิมใช้ `BeaconManager.scanAll()`/`AdvertisementSource` ซึ่งเป็น API คนละเส้นทางจาก region monitoring (คนละ use case) — **flutter-dev ต้องตัดสินใจว่าจะทำ 2 snippet แยก (scan ดิบ กับ region monitoring) หรือรวมเป็นไฟล์เดียว** โครงนี้แนะนำแยก เพราะ README §2(d) ต้องการ region monitoring เป็นหลัก (ตามกติกาข้อ 4 ของบรีฟ) ส่วน `scanAll()`/`AdvertisementSource` เก็บไว้เป็นตัวอย่างเสริมได้ถ้ามีพื้นที่ |
| "โครงสร้าง repo" (280-306) | **เก็บไว้ใน README** (ไม่มีสถานะ/ตัวเลข) แต่ต้องอัปเดตให้ตรงปัจจุบัน — บรรทัด 295-296 อ้าง "ADR-1 ถึง ADR-15" ซึ่งล้าสมัยแล้ว (ตอนนี้มีถึง ADR-22) **ต้องแก้เลขให้ตรง** |
| "เอกสารที่ควรอ่านต่อ" (308-316) | **ปรับเป็น README §8** เพิ่มลิงก์ `docs/integration-guide.md`, `SECURITY.md`, `PIPELINE.md`, `SPRINT.md` |
| "License" (318-320) | **เก็บไว้ใน README §8** |

---

จบไฟล์โครง — ทุกจุดที่ทำเครื่องหมาย "ต้องวิจัยเพิ่ม / ยังไม่ยืนยัน / ยังไม่ได้เปิดไฟล์ตรวจ"
คือสิ่งที่ flutter-dev **ต้องปิดก่อนเขียนเนื้อหาจริง** ไม่ใช่ข้ามไปเขียนแล้วเดาแทน
