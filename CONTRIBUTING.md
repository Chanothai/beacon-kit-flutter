# CONTRIBUTING — กติกาก่อนส่ง PR เข้า beacon_kit

เอกสารนี้เขียนให้ **ทุกคนอ่านรู้เรื่อง ไม่ว่าจะใช้ Claude Code หรือไม่**

โปรเจกต์นี้มี hook อัตโนมัติที่บล็อกการทำผิดกติกาบางข้อให้ — **แต่ hook ทำงานเฉพาะกับ
คนที่แก้โค้ดผ่าน Claude Code เท่านั้น** ถ้าคุณแก้ด้วย IDE ปกติ, `vim`, หรือแก้บน GitHub
โดยตรง **ไม่มีอะไรมาห้ามคุณเลย** — กติกาข้างล่างนี้จึงเป็นความรับผิดชอบของคุณเอง
ด่านสุดท้ายที่บังคับกับทุกคนเท่ากันคือ CI และคนรีวิว

---

## 1. ห้ามเขียน adapter ของยี่ห้อใหม่โดยไม่มีไฟล์ค้นคว้าก่อน

ก่อนเขียนโค้ดที่คุยกับ beacon ยี่ห้อใหม่ ต้องมีไฟล์ `docs/sources/<vendor>.md` ที่บันทึก
ผลการค้นคว้า SDK/โปรโตคอลของยี่ห้อนั้นก่อนเสมอ **พร้อม URL ต้นทางกำกับทุกข้อเท็จจริง**

**ทำไม:** โปรโตคอล BLE ของแต่ละยี่ห้อไม่มีมาตรฐานกลาง การเดา UUID หรือ command code
แล้วเขียนโค้ดตามจะได้โค้ดที่คอมไพล์ผ่านและเทสต์เขียว แต่ใช้กับอุปกรณ์จริงไม่ได้ และจะรู้ตัว
ตอนอยู่หน้างานพร้อมอุปกรณ์แล้วเท่านั้น — แพงที่สุดในบรรดาจุดที่จะรู้ตัวได้

ในไฟล์ต้องแยกให้ชัดว่าอะไร **ยืนยันแล้ว** (มีแหล่งอ้างอิง) กับอะไร **ยังไม่ยืนยัน**
ห้ามเติมช่องว่างด้วยการเดาเพื่อให้เอกสารดูครบ

ถ้ายี่ห้อนั้นจะถูกซื้อเข้าฟลีตของ BigC ต้องผ่าน checklist ก่อนอนุมัติซื้อด้วย
(ต้องเขียน UUID/Major/Minor ผ่าน GATT ได้จริง — ดู `.claude/skills/beacon-sdk-verify/SKILL.md`)

*(ผู้ใช้ Claude Code: hook `require-vendor-sources.sh` บล็อกให้อัตโนมัติ)*

## 2. domain layer ต้องเป็น pure Dart

ไฟล์ใต้ `lib/features/*/domain/` ห้าม `import`:

- `package:flutter/...`
- `package:beacon_kit...`
- `dart:io`, `dart:ui`, `dart:html`
- ไฟล์ข้ามชั้นไปยัง `data/` หรือ `presentation/`

ทิศทาง dependency ที่อนุญาต: `presentation → domain → data` เท่านั้น

**ทำไม:** ชั้น domain ที่ไม่ผูกกับ Flutter ทดสอบได้ด้วย `dart test` ล้วน ๆ รันเร็ว ไม่ต้อง
มี widget binding และย้ายไปใช้ที่อื่นได้ (เช่น gateway บน Linux) โดยไม่ต้องรื้อ

*(ผู้ใช้ Claude Code: hook `enforce-clean-architecture.sh` บล็อกให้อัตโนมัติ)*

## 3. ต้องผ่าน 3 คำสั่งนี้ก่อนเปิด PR

รันจาก root ของ repo:

```bash
# 1. format — หมายเหตุ: --output=none เป็นโหมด "ตรวจอย่างเดียว ไม่เขียนไฟล์"
#    ถ้ามันบอกว่ามีไฟล์ changed ต้องรัน `dart format .` จริงก่อน แล้วค่อยตรวจซ้ำ
dart format --output=none --set-exit-if-changed .

# 2. analyze — ต้องสะอาดทุก package (--fatal-infos คือ info ก็ถือว่าไม่ผ่าน)
for p in packages/beacon_kit_platform_interface packages/beacon_kit_ios \
         packages/beacon_kit packages/beacon_kit/example; do
  (cd "$p" && flutter analyze --fatal-infos) || exit 1
done

# 3. test — ต้องผ่านทุก package
for p in packages/beacon_kit_platform_interface packages/beacon_kit_ios \
         packages/beacon_kit packages/beacon_kit/example; do
  (cd "$p" && flutter test) || exit 1
done
```

ถ้าแตะโค้ด Swift ต้องรันเพิ่ม:

```bash
cd packages/beacon_kit/example
flutter build ios --debug --no-codesign
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

`flutter test` **ไม่รัน** XCTest ใน `example/ios/RunnerTests/` (คนละ test runner)
ถ้าแก้ Swift แล้วรันแค่ `flutter test` เท่ากับไม่ได้ทดสอบสิ่งที่แก้เลย

CI (`.github/workflows/ci.yml`) รันข้อ 1-3 ซ้ำทุก push/PR

## 4. กฎการรายงานสถานะ — ข้อที่สำคัญที่สุดในเอกสารนี้

**ห้ามเขียนว่าอะไร "ทำงานได้" / "verified" / "รองรับแล้ว" ถ้ายังไม่เคยรันกับอุปกรณ์จริง**

ใช้คำเหล่านี้แทน:

| สถานะจริง | เขียนว่า |
|---|---|
| มีคนรันบนอุปกรณ์จริงและเห็นผลจริง | `verified บน <อุปกรณ์> เมื่อ <วันที่>` |
| โค้ดครบ คอมไพล์ผ่าน เทสต์เขียว แต่ไม่เคยรันบนอุปกรณ์ | `code-complete, unverified` |
| ยังไม่มีโค้ด | `ยังไม่ implement` |

**unit test ที่เขียวไม่นับเป็นการยืนยัน** สำหรับอะไรก็ตามที่คุยกับ OS หรือฮาร์ดแวร์ —
mock พิสูจน์ได้แค่ว่าโค้ดเราเรียกตามสัญญาที่เรา*คิดว่า*ถูก ไม่ได้พิสูจน์ว่า CoreLocation,
CoreBluetooth หรือตัว beacon ตอบแบบนั้นจริง

**นี่ไม่ใช่กฎเชิงทฤษฎี** — โปรเจกต์นี้เจอบั๊กมาแล้ว 2 ตัวติดกันที่คอมไพล์ผ่าน เทสต์เขียวหมด
แต่พังทันทีที่มีคนกดปุ่มจริงบน iPhone (ดูประวัติใน `docs/test-checklists/ios_broadcast_scanning.md`)
ถ้าตอนนั้นมีใครเขียนว่า "verified" ทีมจะสร้างของต่อบนฐานที่ไม่จริง

เมื่อทดสอบกับอุปกรณ์จริงแล้ว ให้กรอกผลลงตารางใน `docs/test-checklists/` พร้อมรุ่นเครื่อง
เวอร์ชัน OS และวันที่ — ผลที่ไม่ระบุอุปกรณ์ตรวจสอบย้อนกลับไม่ได้

## 5. ห้าม commit ของพวกนี้

- ค่าเฉพาะเครื่อง — `Local.xcconfig` (ดู `Local.xcconfig.example`), `DEVELOPMENT_TEAM`
  ห้ามกลับไป hardcode ใน `project.pbxproj` อีก
- password / secret ทุกชนิด รวมถึง default password ของอุปกรณ์ — ยกเว้นใน unit test
- ผลลัพธ์ build — `build/`, `.dart_tool/`, `Pods/`, `Flutter/ephemeral/`

**หมายเหตุ:** `flutter build ios` จะแก้ `example/ios/Runner/Base.lproj/Main.storyboard`
เอง (Xcode auto-format) ถ้าเห็นไฟล์นี้โผล่ใน `git status` โดยที่คุณไม่ได้แตะ ให้ revert ทิ้ง

## 6. เอกสารที่ต้องอัปเดตคู่กับโค้ด

| แก้อะไร | ต้องอัปเดต |
|---|---|
| ตัดสินใจเชิงสถาปัตยกรรม | `ARCHITECTURE.md` (เพิ่ม ADR ใหม่ ไม่แก้ทับ ADR เดิม) |
| เพิ่ม/แก้ contract ของ platform channel | ADR ที่เกี่ยวข้องใน `ARCHITECTURE.md` |
| เพิ่มยี่ห้อใหม่ | `docs/sources/<vendor>.md` |
| เปลี่ยนสถานะฟีเจอร์ | ตารางใน `README.md` **และ** `docs/test-checklists/` ให้ตรงกัน |

ถ้าเอกสารกับโค้ดขัดกัน คนอ่านจะเชื่อเอกสาร แล้วตัดสินใจผิด — การอัปเดตเอกสารจึงเป็น
ส่วนหนึ่งของงาน ไม่ใช่ของแถม
