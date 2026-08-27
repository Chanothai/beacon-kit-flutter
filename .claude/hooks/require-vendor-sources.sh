#!/bin/bash
# PreToolUse hook — matcher: "Write|Edit"
#
# บังคับนโยบาย "ห้ามเดา": ถ้ากำลังจะสร้าง/แก้ไฟล์ vendor adapter ตัวใหม่
# (lib/src/vendors/<vendor>_adapter.dart ที่ไม่ใช่ตัว generic) จะต้องมีไฟล์
# docs/sources/<vendor>.md อยู่ก่อนแล้ว (ผลจาก skill beacon-sdk-verify)
# ไม่งั้น block การเขียนไฟล์นั้นทันที
#
# ปรับ path pattern ด้านล่างให้ตรงกับโครงสร้างโปรเจกต์จริงของทีมก่อนใช้งาน

set -euo pipefail
input=$(cat)

file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# สนใจเฉพาะไฟล์ adapter ของยี่ห้อเฉพาะ ไม่ใช่ตัว generic/interface กลาง
# หมายเหตุ: ต้องดึง BASH_REMATCH ออกมาเก็บทันทีหลัง match แรก ก่อนรัน [[ =~ ]] ครั้งที่สอง
# เพราะการ match ครั้งที่สองจะเขียนทับ BASH_REMATCH เดิม
if [[ "$file" =~ lib/src/vendors/([a-zA-Z0-9_]+)_adapter\.dart$ ]]; then
  vendor="${BASH_REMATCH[1]}"

  if [[ "$vendor" != generic_* ]]; then
    sources_file="${CLAUDE_PROJECT_DIR:-.}/docs/sources/${vendor}.md"

    if [[ ! -f "$sources_file" ]]; then
      reason="ยังไม่พบไฟล์ docs/sources/${vendor}.md — ก่อนเขียน adapter ของยี่ห้อ '${vendor}' ต้องรัน skill beacon-sdk-verify เพื่อค้นคว้า SDK ทางการและบันทึกผลไว้ที่ไฟล์นี้ก่อน (นโยบายโปรเจกต์: ห้ามเดา ต้องมี citation)"
      jq -n --arg reason "$reason" \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
      exit 0
    fi
  fi
fi

exit 0
