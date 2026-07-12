#!/bin/bash
#
# ตัวถอนการติดตั้ง Claude Usage Widget (+ ถอน Übersicht ถ้าต้องการคืนเครื่องสู่สภาพเดิม)
# รันด้วย:  bash uninstall-claude-usage-widget.command
#
set -u

echo ""
echo "══════════════════════════════════════════"
echo "  ▶  ถอนการติดตั้ง Claude Usage Widget"
echo "══════════════════════════════════════════"

WIDGETS_DIR="$HOME/Library/Application Support/Übersicht/widgets"

# 1) ลบไฟล์ widget + spritesheet คาปิบาร่า
rm -f "$WIDGETS_DIR/claude-usage.jsx"
rm -f "$WIDGETS_DIR/claude-usage-capy.png"
echo "✓ ลบ widget และ CapyBeats ออกจากโฟลเดอร์ widgets แล้ว"

# 2) ลบ cache/state ของสคริปต์ (ไม่แตะ credential ของ Claude Code)
rm -f "$HOME/.claude/usage-cache.json" "$HOME/.claude/usage-backoff"
rm -rf "$HOME/.config/claude-usage"   # config ยุคเก่า (sessionKey) เผื่อเคยติดตั้งเวอร์ชันแรก
echo "✓ ลบ cache/backoff และ config เก่าแล้ว"

# 3) รีเฟรช Übersicht ให้การ์ดหายทันที (ไม่สำเร็จก็ไม่เป็นไร — เดี๋ยวมัน reload เอง)
osascript -e 'tell application "Übersicht" to refresh' >/dev/null 2>&1 || true

# 4) ถอนแอป Übersicht ด้วยไหม (เผื่อใช้ widget อื่นอยู่ — ถามก่อน)
printf "ถอนแอป Übersicht ออกด้วยเลยไหม? [y/N] "
read -r ANS
if [ "${ANS:-n}" = "y" ] || [ "${ANS:-n}" = "Y" ]; then
  osascript -e 'tell application "Übersicht" to quit' >/dev/null 2>&1 || true
  sleep 1
  if command -v brew >/dev/null 2>&1 && brew list --cask ubersicht >/dev/null 2>&1; then
    brew uninstall --cask ubersicht >/dev/null 2>&1 \
      && echo "✓ ถอน Übersicht (brew) แล้ว" \
      || echo "⚠ ถอนผ่าน brew ไม่สำเร็จ — ลากแอปไปถังขยะเองได้"
  elif [ -d "/Applications/Übersicht.app" ]; then
    osascript -e 'tell application "Finder" to delete POSIX file "/Applications/Übersicht.app"' >/dev/null 2>&1 \
      && echo "✓ ย้าย Übersicht ไปถังขยะแล้ว" \
      || echo "⚠ ย้ายอัตโนมัติไม่ได้ — เปิด Finder > Applications แล้วลากไปถังขยะเองนะครับ"
  else
    echo "• ไม่พบแอป Übersicht (อาจถอนไปแล้ว)"
  fi
else
  echo "• เก็บแอป Übersicht ไว้ (ลบเฉพาะ widget)"
fi

echo ""
echo "══════════════════════════════════════════"
echo "  🎉 เรียบร้อย"
echo "  (โฟลเดอร์ repo นี้ลบทิ้งเองได้เลยถ้าไม่ใช้แล้ว)"
echo "══════════════════════════════════════════"
