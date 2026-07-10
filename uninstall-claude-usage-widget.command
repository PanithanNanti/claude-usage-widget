#!/bin/bash
#
# ตัวถอนการติดตั้ง Claude Usage Widget + Übersicht (คืนเครื่องสู่สภาพเดิม)
# รันด้วย:  bash /Users/user/Developer/dev/claudelimit/uninstall-claude-usage-widget.command
#
set -u

echo ""
echo "══════════════════════════════════════════"
echo "  ▶  ถอนการติดตั้ง Claude Usage Widget"
echo "══════════════════════════════════════════"

# 1) ปิด Übersicht ก่อน
osascript -e 'tell application "Übersicht" to quit' >/dev/null 2>&1 || true
sleep 1

# 2) ลบไฟล์ widget + config (รวม sessionKey)
rm -f "$HOME/Library/Application Support/Übersicht/widgets/claude-usage.jsx"
rm -rf "$HOME/.config/claude-usage"
echo "✓ ลบไฟล์ widget และไฟล์ตั้งค่าแล้ว (รวม sessionKey ที่เก็บไว้)"

# 3) ถอนแอป Übersicht
if command -v brew >/dev/null 2>&1 && brew list --cask ubersicht >/dev/null 2>&1; then
  echo "▶ ถอน Übersicht ผ่าน Homebrew..."
  brew uninstall --cask ubersicht >/dev/null 2>&1 && echo "✓ ถอน Übersicht แล้ว" || echo "⚠ ถอนผ่าน brew ไม่สำเร็จ — ลากแอปไปถังขยะเองได้"
elif [ -d "/Applications/Übersicht.app" ]; then
  echo "▶ ย้าย Übersicht ไปถังขยะ..."
  osascript -e 'tell application "Finder" to delete POSIX file "/Applications/Übersicht.app"' >/dev/null 2>&1 \
    && echo "✓ ย้าย Übersicht ไปถังขยะแล้ว" \
    || echo "⚠ ย้ายอัตโนมัติไม่ได้ — เปิด Finder > Applications แล้วลาก Übersicht ไปถังขยะเองนะครับ"
else
  echo "• ไม่พบแอป Übersicht (อาจถอนไปแล้ว หรือยังไม่ได้ติดตั้ง)"
fi

# 4) ลบไฟล์ที่วางไว้ในโฟลเดอร์ claudelimit
rm -f "$HOME/Developer/dev/claudelimit/install-claude-usage-widget.command"
rm -f "$HOME/Developer/dev/claudelimit/claude-usage.jsx"
echo "✓ ลบไฟล์ installer/widget ในโฟลเดอร์ claudelimit แล้ว"

echo ""
echo "══════════════════════════════════════════"
echo "  🎉 เรียบร้อย — เครื่องกลับสู่สภาพเดิม"
echo "  (ตัวถอนนี้ลบทิ้งเองได้เลย)"
echo "══════════════════════════════════════════"
