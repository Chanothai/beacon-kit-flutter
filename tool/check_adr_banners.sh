#!/usr/bin/env bash
#
# ตรวจว่า "ตัวชี้" ในแบนเนอร์ของทุก ADR ชี้ไปยังของที่มีอยู่จริง
#
# ## ทำไมต้องมีสคริปต์นี้
#
# กฎ CONTRIBUTING ข้อ 8 บังคับให้แบนเนอร์ ADR ไม่เก็บสถานะผลทดสอบเอง แต่ให้ชี้ไป
# ไฟล์เช็คลิสต์แทน (`implemented — ดูสถานะผลทดสอบที่ <ไฟล์> ข้อ <n>`) — กฎนั้นแก้
# ปัญหา "สถานะอยู่สองที่แล้วไม่ตรงกัน" ได้จริง **แต่สร้างช่องผิดใหม่ขึ้นมาแทน:
# ตัวชี้ที่ชี้ผิด** ซึ่งเงียบกว่าเดิมมากเพราะ `grep` ของกฎข้อ 8 จับไม่ได้เลย
#
# เกิดขึ้นจริงแล้ว: แบนเนอร์ ADR-20 เคยชี้ไป "ข้อ 8 · 9 · 10" ของ
# `android_background_scanning.md` ซึ่ง**เป็นคนละเรื่องทั้งสามข้อ** (8 = สวิตช์
# Location · 9 = เพดาน region · 10 = ADR-17) และไม่มีใครจับได้จนต้องไล่ดูด้วยตา
#
# ## ใช้อย่างไร
#
#   tool/check_adr_banners.sh            # ตรวจ ARCHITECTURE.md
#   tool/check_adr_banners.sh path.md    # ตรวจไฟล์อื่น
#
# exit 0 = ตัวชี้ทุกตัวถูกต้อง · exit 1 = มีอย่างน้อยหนึ่งตัวชี้ไปที่ไม่มีอยู่
#
# ## สิ่งที่สคริปต์นี้ **ไม่** ตรวจ (อ่านก่อนเชื่อ)
#
# - **ไม่ได้ตรวจว่าเนื้อหาที่ชี้ไป "ตรงเรื่อง" หรือไม่** — ตรวจแค่ว่ามีแถว/หัวข้อนั้น
#   อยู่จริง · แบนเนอร์ที่ชี้ไปแถวที่มีอยู่แต่พูดคนละเรื่องยังผ่านได้
# - **ช่วง `ข้อ a-b` ตรวจแค่สองปลาย** ไม่ไล่ทุกเลขระหว่างกลาง เพราะเลขกลางบางตัว
#   ไม่มีอยู่จริงโดยตั้งใจ (เช่น มี `19.7ก`/`19.7ข` แต่ไม่มี `19.7`)

set -uo pipefail

# ⚠️ **ห้ามเปลี่ยนเป็น `set -e` เฉย ๆ** — สคริปต์นี้ต้องเดินให้ครบทุกแบนเนอร์แล้วค่อย
# สรุป (ไม่หยุดที่ตัวแรกที่ผิด) แต่ **ข้อผิดพลาดของตัวสคริปต์เอง (คำสั่งไม่มี ตัวแปร
# ไม่ได้ตั้ง) ต้องทำให้ทั้งงานล้ม ห้ามรายงานว่าผ่าน** — เคยเกิดจริงตอนเขียน: `mapfile`
# ไม่มีบน bash 3.2 ของ macOS แล้วสคริปต์พิมพ์ ✅ ออกมาทั้งที่ไม่ได้ตรวจอะไรเลย
trap 'echo "❌ สคริปต์ล้มเองที่บรรทัด $LINENO — ผลตรวจใช้ไม่ได้" >&2; exit 2' ERR

FILE="${1:-ARCHITECTURE.md}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

if [[ ! -f "$FILE" ]]; then
  echo "❌ ไม่พบไฟล์ที่จะตรวจ: $FILE" >&2
  exit 1
fi

fail=0
checked_files=0
checked_items=0
checked_headings=0

note_fail() {
  echo "❌ $*" >&2
  fail=1
}

# แถวในตารางเช็คลิสต์เขียนได้หลายรูปแบบ: `| 10 (ใหม่) |` · `| 19.12 |` · `| 1. ข้อความ |`
# จึงยอมรับตัวคั่นหลังเลขเป็น `|` `.` `(` หรือช่องว่างแล้วตามด้วยหนึ่งในนั้น
row_exists() {
  local target="$1" ref="$2"
  grep -qE "^\| *$(sed 's/[.[\*^$()+?{|]/\\&/g' <<<"$ref") *[.|(]" "$target"
}

# รองรับการอ้างหัวข้อแบบซ้อน `"A → B"` ซึ่งอ่านง่ายกว่าการยกหัวข้อเต็มมาทั้งบรรทัด
# — ตรวจว่า**ทุกส่วน**ปรากฏในบรรทัดหัวข้อของไฟล์นั้น (คนละบรรทัดได้)
heading_exists() {
  local target="$1" text="$2" part
  local headings; headings="$(grep -E '^#{1,6} ' "$target")"
  local IFS=$'\n'
  for part in $(sed 's/ *→ */\n/g' <<<"$text"); do
    [[ -n "$part" ]] || continue
    grep -qF "$part" <<<"$headings" || return 1
  done
  return 0
}

# อ่านทีละ "บล็อกแบนเนอร์": บรรทัดที่ขึ้นต้นด้วย `> ` ติดกันเป็นก้อนเดียว
# แล้วรวมเป็นบรรทัดเดียวเพื่อให้ตัวชี้ที่ตัดข้ามบรรทัดยังอ่านออก
python3 - "$FILE" <<'PY' > /tmp/adr_banner_blocks.$$
# ดึงเฉพาะ "ประโยคตัวชี้" ออกมา ไม่ใช่ทั้งบล็อกแบนเนอร์
#
# สำคัญมาก: แบนเนอร์มีข้อความอื่นที่หน้าตาคล้ายตัวชี้ปนอยู่เยอะ — ชื่อไฟล์ในย่อหน้า
# "ขอบเขต" และการอ้างหัวข้อของ ADR เอง (เช่น "หัวข้อ 7 ข้อ 4") ถ้าดึงทั้งบล็อกมาตรวจ
# จะได้ false positive เพียบ (พิสูจน์แล้วตอนเขียน: 9 บรรทัดผิดซึ่งเป็นของสคริปต์เอง 7)
# ตัวชี้จริงคือข้อความที่อยู่ระหว่างวลีนำ กับ `**` ที่ปิด bold ตัวเดียวกัน
import io, re, sys
path = sys.argv[1]
lines = io.open(path, encoding="utf-8").read().split("\n")
LEAD = ("ดูสถานะผลทดสอบที่", "สถานะการทดสอบบนอุปกรณ์จริงอยู่ที่")
adr = "?"
block, start = [], 0
def flush():
    if not block:
        return
    joined = " ".join(x.lstrip("> ").rstrip() for x in block)
    for lead in LEAD:
        i = joined.find(lead)
        if i < 0:
            continue
        rest = joined[i + len(lead):]
        end = rest.find("**")
        print(f"{adr}\t{start}\t{rest if end < 0 else rest[:end]}")
        break
for i, l in enumerate(lines, 1):
    m = re.match(r"^## (ADR-[0-9]+)", l)
    if m:
        flush(); block.clear(); adr = m.group(1)
    if l.startswith(">"):
        if not block: start = i
        block.append(l)
    else:
        flush(); block.clear()
flush()
PY

while IFS=$'\t' read -r adr lineno text; do
  # การกรองว่า "บล็อกนี้มีตัวชี้ไหม" ทำไปแล้วในขั้น python ข้างบน — ที่มาถึงตรงนี้
  # คือ **ประโยคตัวชี้ล้วน ๆ** ไม่ใช่ทั้งแบนเนอร์
  # 1) ไฟล์ที่ถูกอ้างในเครื่องหมาย backtick และลงท้าย .md
  # ใช้ while-read แทน `mapfile` เพราะ macOS มาพร้อม bash 3.2 ซึ่งไม่มี `mapfile`
  # — สคริปต์นี้ต้องรันได้ทั้งบนเครื่องนักพัฒนาและใน CI (ubuntu) ด้วยผลเดียวกัน
  targets=()
  while IFS= read -r t; do
    [[ -n "$t" ]] && targets+=("$t")
  done < <(grep -oE '`[^`]+\.md`' <<<"$text" | tr -d '`' | sort -u)
  if [[ ${#targets[@]} -eq 0 ]]; then
    note_fail "$adr (บรรทัด $lineno): แบนเนอร์บอกว่าชี้ไปไฟล์เช็คลิสต์ แต่ไม่มีชื่อไฟล์ใน backtick"
    continue
  fi

  ok_targets=()
  for t in "${targets[@]}"; do
    checked_files=$((checked_files + 1))
    if [[ -f "$t" ]]; then
      ok_targets+=("$t")
    else
      # เอกสารในโปรเจกต์นี้อ้างไฟล์เช็คลิสต์ด้วย**ชื่อเปล่า**เป็นปกติ
      # (เช่น `ios_broadcast_scanning.md`) — หาให้ใต้ docs/ ก่อนจะฟ้องว่าไม่มี
      resolved="$(find docs -name "$(basename "$t")" -type f 2>/dev/null | head -1)"
      if [[ -n "$resolved" ]]; then
        ok_targets+=("$resolved")
      else
        note_fail "$adr (บรรทัด $lineno): ชี้ไปไฟล์ที่ไม่มีอยู่ — $t"
      fi
    fi
  done
  [[ ${#ok_targets[@]} -gt 0 ]] || continue

  # 2) หัวข้อที่อ้างในเครื่องหมายคำพูด: หัวข้อ "..."
  while IFS= read -r h; do
    [[ -n "$h" ]] || continue
    checked_headings=$((checked_headings + 1))
    found=0
    for t in "${ok_targets[@]}"; do heading_exists "$t" "$h" && { found=1; break; }; done
    (( found )) || note_fail "$adr (บรรทัด $lineno): ไม่พบหัวข้อ \"$h\" ในไฟล์ที่ชี้ไป (${ok_targets[*]})"
  done < <(grep -oE 'หัวข้อ "[^"]+"' <<<"$text" | sed 's/^หัวข้อ "//; s/"$//')

  # 3) เลขข้อที่อ้าง: `ข้อ 10` · `ข้อ 19.7ก · 19.7ข` · `ข้อ 19.1-19.12` · `ข้อ 1-6 · 3ก`
  refs_raw="$(grep -oE 'ข้อ [0-9][0-9.ก-ฮ·\ -]*' <<<"$text" | sed 's/^ข้อ //')"
  [[ -n "$refs_raw" ]] || continue
  refs=()
  while IFS= read -r r; do
    [[ -n "$r" ]] && refs+=("$r")
  done < <(tr '·' '\n' <<<"$refs_raw" | tr -s ' ' '\n' | grep -E '^[0-9]' | sed 's/[^0-9.ก-ฮ-]*$//' | sort -u)
  [[ ${#refs[@]} -gt 0 ]] || continue

  for ref in "${refs[@]}"; do
    [[ -n "$ref" ]] || continue
    # ช่วง a-b → ตรวจแค่สองปลาย (ดูหมายเหตุหัวไฟล์)
    if [[ "$ref" == *-* ]]; then
      ends=("${ref%%-*}" "${ref##*-}")
    else
      ends=("$ref")
    fi
    for e in "${ends[@]}"; do
      [[ -n "$e" ]] || continue
      checked_items=$((checked_items + 1))
      found=0
      for t in "${ok_targets[@]}"; do row_exists "$t" "$e" && { found=1; break; }; done
      (( found )) || note_fail "$adr (บรรทัด $lineno): อ้าง \"ข้อ $e\" แต่ไม่พบแถวนั้นในไฟล์ที่ชี้ไป (${ok_targets[*]})"
    done
  done
done < /tmp/adr_banner_blocks.$$

rm -f /tmp/adr_banner_blocks.$$

if (( fail )); then
  echo "" >&2
  echo "แบนเนอร์ ADR มีตัวชี้ที่ชี้ไปที่ไม่มีอยู่ — แก้ที่ $FILE หรือเพิ่มแถว/หัวข้อในไฟล์เช็คลิสต์" >&2
  exit 1
fi

# กันเคส "ผ่านเพราะไม่ได้ตรวจอะไรเลย" — ถ้าไม่เจอแบนเนอร์ที่มีตัวชี้เลยแม้แต่อันเดียว
# แปลว่ารูปแบบแบนเนอร์เปลี่ยนไปแล้วและสคริปต์นี้ตามไม่ทัน ไม่ใช่ว่าทุกอย่างถูกต้อง
if (( checked_files == 0 )); then
  echo "❌ ไม่พบแบนเนอร์ที่มีตัวชี้เลยใน $FILE — รูปแบบแบนเนอร์เปลี่ยนไปหรือไฟล์ผิด?" >&2
  echo "   (ผลว่าง ≠ ผ่าน — ดูกฎ CONTRIBUTING ข้อ 8 ว่ารูปแบบที่คาดไว้คืออะไร)" >&2
  exit 1
fi

echo "✅ ตัวชี้ในแบนเนอร์ ADR ถูกต้องทั้งหมด ($FILE)"
echo "   ไฟล์ที่ตรวจ $checked_files · เลขข้อ $checked_items · หัวข้อ $checked_headings"
