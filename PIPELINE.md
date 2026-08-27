# Pipeline: Architecture → Develop → Test → Review

สรุปว่า subagent / skill / hook ตัวไหนรับผิดชอบขั้นตอนไหนของการพัฒนา `beacon_kit`

> **ถ้ากำลังเร่งให้จบตามเดดไลน์** ให้เริ่มที่ `sprint-lead` แทนการไล่ 4 ขั้นตามลำดับ — มันจะแตกงานเป็น Track A/B ตาม `SPRINT.md` แล้วสั่งงานขนานกันให้ ดูหัวข้อ "โหมดสปรินต์" ท้ายเอกสาร

## ภาพรวม

| ขั้นตอน | Subagent | เครื่องมือสนับสนุน | Output |
|---|---|---|---|
| 1. Architecture | `beacon-architect` | skill `beacon-sdk-verify` (preload ไว้แล้ว) เมื่อต้องวิจัยยี่ห้อใหม่ | `ARCHITECTURE.md` อัปเดต, ตัดสินใจ trade-off มีบันทึก |
| 2. Develop | `flutter-dev` (ผู้เชี่ยวชาญ BLoC + feature-first Clean Architecture) | hook `require-vendor-sources.sh` (บล็อกถ้าไม่มี citation), hook `enforce-clean-architecture.sh` (บล็อกถ้า domain/ import Flutter/beacon_kit ผิดกฎ), hook `dart-format-analyze.sh` (format/lint อัตโนมัติ) | โค้ด Dart/Kotlin/Swift ตาม ARCHITECTURE.md, แอปชั้น feature-first + BLoC |
| 3. Test | `beacon-qa` | `flutter test`, `bloc_test` สำหรับ Bloc, checklist hardware-in-the-loop | ผลเทสต์จริง + `docs/test-checklists/` |
| 4. Review | `beacon-reviewer` | อ่านโค้ด + `docs/sources/` เทียบกัน + เช็คสถานะ CI | รายชื่อปัญหา (blocking/ควรแก้/แนะนำ) |
| (ต่อเนื่อง) CI | GitHub Actions | `.github/workflows/ci.yml`: format check → analyze → test ทุก push/PR | เขียวก่อนถึง merge ได้ |

## วิธีสั่งงานจริง

เรียก subagent ผ่าน Task/Agent tool ของ Claude Code ตามลำดับ หรือปล่อยให้ main session มอบหมายงานเองตาม `description` ของแต่ละตัว (ทุกตัวเขียน description ให้ trigger เองตามบริบทอยู่แล้ว "Use PROACTIVELY...") ตัวอย่างการสั่งแบบ manual:

```
> ใช้ beacon-architect ออกแบบว่า adapter ของ Minew ควรมีหน้าตายังไง
> ใช้ flutter-dev implement KkmK9pAdapter ตาม ARCHITECTURE.md
> ใช้ beacon-qa เขียนเทสต์ให้ KkmK9pAdapter
> ใช้ beacon-reviewer รีวิว diff ล่าสุดก่อน merge
```

## ตัวอย่างการสั่งงานแบบ E2E ครบ 4 ขั้น

### แบบที่ 1 — สั่งครั้งเดียว ปล่อยให้ cascade เอง

ใช้ได้เมื่อฟีเจอร์นั้นมี `docs/sources/<vendor>.md` อยู่แล้ว (เช่น KKM K9P) พิมพ์ในเซสชัน Claude Code ที่ root ของโปรเจกต์:

```
พัฒนา KkmK9pAdapter ให้รองรับ scan() และ connect() ตาม ARCHITECTURE.md
ให้ครบทั้ง 4 ขั้นตอน ตั้งแต่ออกแบบละเอียด → implement → เขียนเทสต์ → รีวิว
ก่อนถือว่าเสร็จ
```

สิ่งที่เกิดขึ้นจริงเบื้องหลัง (ไม่ต้องสั่งเอง แต่ควรรู้ไว้เพื่อ debug ได้ถ้าติดขัด):

1. main session อ่าน description ของแต่ละ subagent แล้วเห็นว่างานยังไม่มี design ที่ finalize → มอบให้ `beacon-architect` ก่อน (ตรงกับ "Use PROACTIVELY before any new adapter... is implemented")
2. `beacon-architect` เขียน method contract ของ `KkmK9pAdapter.scan()`/`connect()` ลง `ARCHITECTURE.md` ให้ละเอียดขึ้น แล้วส่งต่อ
3. main session มอบให้ `flutter-dev` → สร้าง/แก้ `lib/src/vendors/kkm_k9p_adapter.dart` → **hook `require-vendor-sources.sh` ยิงก่อนเขียนไฟล์ทุกครั้ง** เช็คว่า `docs/sources/kkm_k9p.md` มีอยู่แล้ว (มีอยู่แล้วในแพ็กเกจนี้) → ผ่าน ไม่บล็อก → เขียนไฟล์สำเร็จ → **hook `dart-format-analyze.sh` ยิงตามหลัง** รัน `dart format`/`flutter analyze` ให้ทันทีแบบไม่ต้องรอ CI
4. `flutter-dev` ทำเสร็จ ส่งต่อให้ `beacon-qa` → เขียน unit test + checklist hardware-in-the-loop สำหรับ auth/connect จริง
5. ส่งต่อให้ `beacon-reviewer` (ไม่มีสิทธิ์แก้โค้ด อ่านอย่างเดียว) → ตรวจ citation/security/license/สถาปัตยกรรมตาม checklist ใน `beacon-reviewer.md` → รายงานว่ามี blocking item เหลือหรือไม่

### แบบที่ 2 — สั่งทีละขั้น (คุมได้มากกว่า เหมาะตอนอยากเช็คก่อนไปขั้นถัดไป)

```
1) ใช้ beacon-architect ออกแบบ method signature และ platform-channel contract
   ของ KkmK9pAdapter.connect() ให้ละเอียด
   [ตรวจ ARCHITECTURE.md ที่อัปเดตก่อนไปขั้นต่อไป]

2) ใช้ flutter-dev implement KkmK9pAdapter ตามที่ beacon-architect เพิ่งออกแบบ

3) ใช้ beacon-qa เขียนเทสต์ + checklist hardware-in-the-loop ให้ KkmK9pAdapter

4) ใช้ beacon-reviewer รีวิว diff ทั้งหมดของฟีเจอร์นี้ก่อน merge
```

### ตัวอย่าง guardrail ทำงานจริง — ลองข้ามขั้นตอนดู

```
ใช้ flutter-dev สร้าง MinewAdapter ให้เลย ไม่ต้องรอ
```

`flutter-dev.md` เขียนกำกับไว้แล้วว่าต้องหยุดถ้าไม่มีไฟล์ sources ของยี่ห้อนั้น แต่ต่อให้ subagent ลืม/มองข้ามคำสั่งนี้ไป **hook ก็ยังกันไว้อีกชั้น**: ทันทีที่มีการ Write ไฟล์ `lib/src/vendors/minew_adapter.dart` hook `require-vendor-sources.sh` จะคืนค่า `permissionDecision: deny` พร้อมเหตุผล เพราะยังไม่มี `docs/sources/minew.md` — ไฟล์จะไม่ถูกสร้างจนกว่าจะรัน skill `beacon-sdk-verify` เพื่อวิจัย Minew แล้วมีไฟล์ citation ก่อน นี่คือเหตุผลที่ออกแบบให้มีทั้ง "คำสั่งใน subagent" และ "hook บังคับ" ซ้อนกัน — ชั้นแรกป้องกันไม่ให้เดาตั้งแต่ต้น ชั้นสองกันพลาดตอนที่ชั้นแรกหลุด

## กติกาที่ hook บังคับอัตโนมัติ (ไม่ต้องพึ่งวินัยคนอย่างเดียว)

1. **ห้าม commit adapter ของยี่ห้อใหม่โดยไม่มี citation** — `require-vendor-sources.sh` (PreToolUse) จะ block การเขียนไฟล์ `lib/src/vendors/<vendor>_adapter.dart` ถ้ายังไม่มี `docs/sources/<vendor>.md` คู่กัน
2. **ห้าม domain/ layer import Flutter SDK หรือ beacon_kit** — `enforce-clean-architecture.sh` (PreToolUse) เช็คเนื้อหาที่กำลังจะเขียนลงไฟล์ใต้ `lib/features/*/domain/` ถ้าเจอ `import 'package:flutter...'` หรือ `import 'package:beacon_kit...'` จะ block ทันที (ทดสอบแล้วทั้งกรณี block และกรณีปล่อยผ่านที่ data/ layer)
3. **ทุกไฟล์ .dart ที่แก้จะถูก format + analyze ทันที** — `dart-format-analyze.sh` (PostToolUse) รันให้อัตโนมัติ ไม่ต้องรอ CI
4. **CI บน GitHub Actions บังคับซ้ำอีกชั้นระดับ PR** — แม้ hook ในเครื่องจะเผลอปิดหรือ bypass ได้ (เช่นแก้ไฟล์นอก Claude Code) `.github/workflows/ci.yml` จะรัน `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `flutter test` ซ้ำทุก push/PR เป็นด่านสุดท้ายก่อน merge

## โหมดสปรินต์ (เมื่อมีเดดไลน์)

pipeline 4 ขั้นแบบเรียงลำดับด้านบนออกแบบมาเพื่อความถูกต้อง แต่ทำให้ทุกอย่างรอกันเป็นทอด ๆ เมื่อมีเดดไลน์ให้สลับมาใช้โหมดนี้แทน:

```
ใช้ sprint-lead แตกงานทั้งหมดเป็น Track A/B ตาม SPRINT.md
แล้วสั่งงานขนานกันให้จบภายในวันนี้ รายงานสถานะตามรูปแบบใน sprint-lead.md
```

`sprint-lead` จะ:

1. แบ่งงานตาม "ต้องใช้ฮาร์ดแวร์จริงหรือไม่" — Track A (จบได้ 100% วันนี้) / Track B (ได้แค่ code-complete)
2. สั่ง `flutter-dev` กับ `beacon-qa` ทำงานขนานกันเมื่อไฟล์ไม่ทับกัน (เช่น dev เขียน decoder ขณะที่ qa เขียน fixture+เทสต์ของ decoder ตัวเดียวกัน)
3. ข้าม `beacon-architect` ถ้า `ARCHITECTURE.md` ครอบคลุมงานนั้นแล้ว — เรียกเฉพาะตอนต้องตัดสินใจสิ่งใหม่จริง ๆ
4. ให้ `beacon-reviewer` รีวิวเป็นก้อนตอนจบแต่ละ track ไม่ใช่ทีละไฟล์
5. ไม่ปล่อยให้ Track B บล็อก Track A — ติดฮาร์ดแวร์เมื่อไหร่ mark `unverified` แล้วเดินหน้าต่อ

**สิ่งที่โหมดนี้ไม่ยอมแลก:** ความจริงของสถานะงาน — `beacon-reviewer` ข้อ 10-11 จะ block ทันทีถ้าเจอการอ้างว่างาน Track B "ทำงานได้" โดยไม่มีหลักฐานจากอุปกรณ์จริง เร่งได้แต่ห้ามโกหก

## ข้อจำกัดที่ต้องรู้ก่อนใช้จริง

- Hook สองตัวนี้เป็น **draft ที่ผ่านการทดสอบ logic แล้วในระดับ shell script** (จำลอง input JSON แล้วเช็คว่า block/ปล่อยผ่านถูกช่วง) แต่ **ยังไม่ได้รันจริงในสภาพแวดล้อม Claude Code + โปรเจกต์ Flutter จริงของทีม** — ก่อนใช้งานจริงต้องปรับ path pattern (`lib/src/vendors/...`) ให้ตรงกับโครงสร้างโฟลเดอร์จริงที่ทีมจะสร้าง และตรวจสอบว่า `${CLAUDE_PROJECT_DIR}` ชี้ไปที่ root ของโปรเจกต์ Flutter จริง
- Schema ของ subagent/skill/hook ในเอกสารนี้ตรวจสอบกับเอกสารทางการของ Claude Code โดยตรง (`code.claude.com/docs`) แล้ว ไม่ได้เดา — แต่ Claude Code มีการอัปเดตฟีเจอร์บ่อย ควรเช็คอีกครั้งก่อนใช้งานจริงหากเวลาผ่านไปนาน
- ทีมยังไม่ได้ระบุยี่ห้อ beacon อื่นนอกจาก KKM K9P จึงยังไม่มีไฟล์ `docs/sources/` ของยี่ห้ออื่นให้ — เมื่อพร้อมจะเพิ่มยี่ห้อไหน ให้เรียก skill `beacon-sdk-verify` ก่อนเสมอ
