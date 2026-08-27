#!/bin/bash
# PreToolUse hook — matcher: "Write|Edit"
#
# บังคับกฎ dependency direction ของ feature-first Clean Architecture:
# ไฟล์ใต้ lib/features/*/domain/ ต้องเป็น pure Dart — ห้าม import
#   1) package:flutter / package:beacon_kit  (ชัดเจน)
#   2) relative import ข้ามชั้นไป data/ หรือ presentation/  ← เคสที่เกิดบ่อยที่สุดจริง
#   3) dart:io / dart:ui / dart:html          (ทำให้ domain ไม่ pure และเทสต์ยาก)
#
# เช็คเนื้อหาที่ "กำลังจะถูกเขียน" จาก tool_input รองรับทั้ง Write (content)
# และ Edit (new_string)
#
# หมายเหตุ: hook นี้กันเคสที่พบบ่อย ไม่ได้กันครบ 100% (เช่น import ผ่าน
# package: ของตัวเองแบบ absolute หรือ export ซ้อนหลายชั้น) — ด่านสุดท้าย
# ยังเป็น beacon-reviewer + CI เสมอ

set -uo pipefail
input=$(cat)

file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

deny() {
  jq -n --arg reason "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

if [[ "$file" =~ lib/features/[a-zA-Z0-9_]+/domain/ ]]; then
  new_content=$(echo "$input" | jq -r '(.tool_input.content // .tool_input.new_string // "")')

  # ตัดคอมเมนต์บรรทัดเดียวออกก่อน กัน false positive จากตัวอย่างใน comment
  code=$(echo "$new_content" | sed 's|//.*||')

  if echo "$code" | grep -Eq "import[[:space:]]+['\"]package:flutter"; then
    deny "domain/ layer ห้าม import package:flutter — ต้องเป็น pure Dart เท่านั้น ย้าย logic ที่พึ่ง Flutter ไปที่ data/ หรือ presentation/ แทน"
  fi

  if echo "$code" | grep -Eq "import[[:space:]]+['\"]package:beacon_kit"; then
    deny "domain/ layer ห้าม import beacon_kit โดยตรง — ประกาศ repository interface ใน domain/repositories/ แล้วให้ data/ เป็นคน implement เรียก beacon_kit แทน"
  fi

  # relative import ข้ามชั้น เช่น '../../data/models/x.dart' หรือ '../presentation/y.dart'
  if echo "$code" | grep -Eq "import[[:space:]]+['\"][^'\"]*\.\./(data|presentation)/"; then
    deny "domain/ layer ห้าม import ข้ามชั้นไปยัง data/ หรือ presentation/ (เจอ relative import ข้ามชั้น) — dependency ต้องไหลทางเดียว presentation → domain → data เท่านั้น domain ห้ามรู้จักชั้นอื่น"
  fi

  if echo "$code" | grep -Eq "import[[:space:]]+['\"]dart:(io|ui|html)"; then
    deny "domain/ layer ห้าม import dart:io / dart:ui / dart:html — ทำให้ domain ผูกกับ platform และเทสต์แบบ pure Dart ไม่ได้ ย้ายไปที่ data/ แทน"
  fi
fi

exit 0
