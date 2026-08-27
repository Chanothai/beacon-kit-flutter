#!/bin/bash
# PostToolUse hook — matcher: "Write|Edit"
#
# หลังแก้ไฟล์ .dart ใด ๆ ให้รัน dart format + flutter analyze ทันที
# เป็นข้อมูลเตือนเท่านั้น (PostToolUse block ไม่ได้ตามสเปกของ Claude Code)
# ถ้าไฟล์ที่แก้เป็น vendor adapter เฉพาะยี่ห้อ ให้เตือนเรื่อง citation/license เพิ่ม

set -uo pipefail
input=$(cat)

file=$(echo "$input" | jq -r '.tool_input.file_path // empty')
project_dir="${CLAUDE_PROJECT_DIR:-.}"

if [[ "$file" == *.dart ]]; then
  cd "$project_dir" 2>/dev/null || exit 0

  if command -v dart >/dev/null 2>&1; then
    echo "--- dart format: $file ---" >&2
    dart format "$file" 2>&1 >&2
  fi

  if command -v flutter >/dev/null 2>&1; then
    echo "--- flutter analyze (touched file only) ---" >&2
    flutter analyze "$file" 2>&1 >&2
  fi

  if [[ "$file" =~ lib/src/vendors/ ]] && [[ ! "$file" =~ /generic_ ]]; then
    echo "เตือน: ไฟล์นี้เป็น vendor adapter เฉพาะยี่ห้อ — ตรวจสอบว่า (1) มี docs/sources/<vendor>.md อ้างอิงครบ (2) ถ้าพอร์ตโค้ดจากซอร์สยี่ห้อนั้น มีคอมเมนต์ credit ต้นทางและ license เข้ากันได้ (3) ไม่มี hardcoded password/secret" >&2
  fi
fi

exit 0
