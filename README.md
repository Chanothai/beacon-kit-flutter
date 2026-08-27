# beacon_kit — AI Agent Team Scaffold

ชุดโครงสร้าง Claude Code (subagent + skill + hook) สำหรับพัฒนา `beacon_kit` — Flutter cross-platform library เชื่อมต่อ/รับข้อมูลจาก BLE beacon หลายยี่ห้อ (เริ่มจากมาตรฐานเปิด iBeacon/Eddystone + KKM K9P) ต่อยอดจาก K9P Integration Playbook ก่อนหน้าในบทสนทนาเดียวกัน

## วิธีติดตั้งเข้าโปรเจกต์จริง

1. คัดลอกโฟลเดอร์ `.claude/` ทั้งหมดไปวางที่ root ของ repo โปรเจกต์ Flutter จริง (ถ้ามี `.claude/` อยู่แล้ว ให้ merge ไฟล์ทีละส่วน อย่าทับของเดิม)
2. คัดลอก `docs/sources/` ไปวางที่ root เดียวกัน — มีไฟล์ `kkm_k9p.md` ให้แล้วเป็นตัวอย่าง/ใช้งานจริง
3. เอา `ARCHITECTURE.md` และ `PIPELINE.md` ไปวางที่ root เช่นกัน (หรือย้ายเข้า `docs/` ตามธรรมเนียมของทีม — แค่ต้องอัปเดต path ในไฟล์ hook ให้ตรงถ้าย้าย)
4. ตรวจสอบว่า `jq` ติดตั้งอยู่ในเครื่องที่จะรัน Claude Code (hook ทั้ง 3 ตัวใช้ `jq` parse JSON) และติดตั้ง `flutter_lints` ด้วย `flutter pub add --dev flutter_lints` เมื่อสร้างโปรเจกต์ Flutter จริงแล้ว
5. เปิด Claude Code ในโปรเจกต์นั้น แล้วลองพิมพ์ `/agents` เพื่อดูว่าเห็น `beacon-architect`, `flutter-dev`, `beacon-qa`, `beacon-reviewer` ครบหรือไม่

## สิ่งที่อยู่ในนี้

```
.claude/
  agents/                    # 5 subagent: sprint-lead, architect, dev (BLoC+Clean Arch), qa, reviewer
  skills/beacon-sdk-verify/  # skill วิจัย SDK ยี่ห้อใหม่แบบห้ามเดา
  settings.json              # ลงทะเบียน hook 3 ตัว
  hooks/                     # สคริปต์ hook (ทดสอบ logic แล้วด้วย mock input ทุกตัว)
.github/workflows/ci.yml     # GitHub Actions: format check → analyze → test
analysis_options.yaml        # flutter_lints (มาตรฐานทีม Flutter เอง)
SPRINT.md                    # นิยาม "เสร็จ" + แบ่ง Track A (จบวันนี้ได้) / Track B (ต้องมีฮาร์ดแวร์)
docs/fixtures/README.md      # วิธีเทสต์ ADV decoder 100% โดยไม่ต้องมี beacon
docs/sources/kkm_k9p.md      # ผลวิจัย K9P แบบย่อ (ตัวอย่าง citation file)
ARCHITECTURE.md              # federated plugin pattern + app layer (feature-first/Clean Arch/BLoC)
PIPELINE.md                  # ใครทำอะไรในแต่ละขั้น + ตัวอย่างสั่งงาน E2E + โหมดสปรินต์
```

## เริ่มเร็วสุด (โหมดสปรินต์)

```
ใช้ sprint-lead แตกงานทั้งหมดเป็น Track A/B ตาม SPRINT.md
แล้วสั่งงานขนานกันให้จบภายในวันนี้
```

## สิ่งที่ยังไม่ได้ทำในรอบนี้ (ตามที่ตกลงกันไว้)

- ยังไม่มีการเขียนโค้ด Dart/Kotlin/Swift จริง — งานนี้คือการเตรียม "ทีม AI agent" ตามที่ขอ ขั้นถัดไปคือให้ `beacon-architect` เริ่มดีไซน์ละเอียด แล้ว `flutter-dev` เริ่ม implement
- ยังไม่มี adapter ของยี่ห้ออื่นนอกจาก KKM K9P — รอระบุยี่ห้อที่ต้องการจริง แล้วรัน skill `beacon-sdk-verify`
- Hook ยังไม่ได้รันจริงในสภาพแวดล้อม Claude Code + repo จริง (ทดสอบแค่ logic ของสคริปต์ด้วย mock input) — ให้ทดสอบอีกรอบหลังติดตั้งจริง โดยเฉพาะ path pattern `lib/src/vendors/...` ที่ต้องตรงกับโครงสร้างโฟลเดอร์จริงที่ทีมจะสร้าง
