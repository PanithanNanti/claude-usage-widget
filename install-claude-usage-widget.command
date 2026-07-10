#!/bin/bash
#
# install-claude-usage-widget.command
# ── ติดตั้ง Claude Usage widget (แบบ A) ลง Übersicht บน macOS ──
#
#   ดับเบิลคลิกไฟล์นี้ได้เลย (จะเปิดใน Terminal)
#   หรือรัน:  bash install-claude-usage-widget.command
#
# ทำอะไรบ้าง:
#   1) เช็ก/ติดตั้ง Übersicht (ผ่าน Homebrew)
#   2) copy claude-usage.jsx ไปโฟลเดอร์ widgets ของ Übersicht
#      พร้อมแก้ path ให้ชี้ไปที่ claude-usage.sh ตัวจริงในเครื่องนี้
#   3) วอร์ม cache (ดึง usage ครั้งแรก)
#   4) เปิด + รีเฟรช Übersicht

set -u
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_SH="$REPO_DIR/claude-usage.sh"
SRC_JSX="$REPO_DIR/claude-usage.jsx"
WIDGETS_DIR="$HOME/Library/Application Support/Übersicht/widgets"
DEST_JSX="$WIDGETS_DIR/claude-usage.jsx"

echo ""
echo "  ✳  ติดตั้ง Claude Usage widget"
echo "  ─────────────────────────────────────────────"
echo "  repo: $REPO_DIR"

# ── ตรวจไฟล์ต้นทาง ──────────────────────────────────────
if [ ! -f "$SCRIPT_SH" ] || [ ! -f "$SRC_JSX" ]; then
  echo "  ❌ ไม่พบ claude-usage.sh หรือ claude-usage.jsx ในโฟลเดอร์นี้"
  echo "     ($REPO_DIR)"
  exit 1
fi
chmod +x "$SCRIPT_SH" 2>/dev/null

# ── 1) เช็ก/ติดตั้ง Übersicht ────────────────────────────
# ตรวจหลายทาง: ชื่อ "Übersicht" มีตัว Ü (Unicode) ทำให้ test -d/open -a พลาดได้บางเครื่อง
#   → เชื่อ process ที่รันอยู่ (pgrep) เป็นหลัก, เสริมด้วย test -d และ LaunchServices
ubersicht_present() {
  pgrep -if 'bersicht.app' >/dev/null 2>&1 && return 0
  [ -d "/Applications/Übersicht.app" ] && return 0
  osascript -e 'id of application "Übersicht"' >/dev/null 2>&1 && return 0
  return 1
}

if ubersicht_present; then
  echo "  ✓ พบ Übersicht แล้ว"
else
  echo "  • ยังไม่พบ Übersicht"
  if command -v brew >/dev/null 2>&1; then
    echo "    กำลังติดตั้งด้วย Homebrew (brew install --cask ubersicht)…"
    brew install --cask ubersicht || {
      echo "  ❌ ติดตั้ง Übersicht ไม่สำเร็จ — ลองติดตั้งเองจาก https://tracesof.net/uebersicht/"
      exit 1
    }
  else
    echo "  ❌ ไม่พบ Homebrew — ติดตั้ง Übersicht เองจาก https://tracesof.net/uebersicht/"
    echo "     แล้วรันสคริปต์นี้อีกครั้ง"
    exit 1
  fi
fi

# ── 2) copy widget + แก้ path สคริปต์ ────────────────────
mkdir -p "$WIDGETS_DIR"
# แทนที่บรรทัด command ให้ชี้ไป claude-usage.sh ตัวจริง (escape & / \ ให้ sed)
ESC_PATH=$(printf '%s' "$SCRIPT_SH" | sed 's/[&/\]/\\&/g')
sed "s|^  \"bash .*claude-usage.sh --json\";|  \"bash ${ESC_PATH} --json\";|" \
  "$SRC_JSX" > "$DEST_JSX"

# ยืนยันว่าแก้ path สำเร็จ (ต้องมี path จริงอยู่ในไฟล์ปลายทาง)
if grep -q "bash ${SCRIPT_SH} --json" "$DEST_JSX"; then
  echo "  ✓ ติดตั้ง widget: $DEST_JSX"
else
  # เผื่อรูปแบบบรรทัดเปลี่ยน — copy ดิบแล้วเตือน
  cp "$SRC_JSX" "$DEST_JSX"
  echo "  ⚠ copy widget แล้ว แต่แก้ path อัตโนมัติไม่ได้"
  echo "     เปิด $DEST_JSX แล้วแก้บรรทัด command ให้เป็น:"
  echo "       bash $SCRIPT_SH --json"
fi

# ── 3) วอร์ม cache (ดึงครั้งแรก) ─────────────────────────
echo "  • ดึง usage ครั้งแรก…"
FIRST=$(bash "$SCRIPT_SH" --json)
STATUS=$(printf '%s' "$FIRST" | python3 -c "import sys,json; print(json.load(sys.stdin).get('_status','?'))" 2>/dev/null)
echo "    สถานะ: ${STATUS:-unknown}"
if [ "$STATUS" != "live" ]; then
  echo "    (ถ้าไม่ใช่ live: เปิด Claude Code พิมพ์ claude สักครั้งเพื่อรีเฟรช token แล้วรอ widget อัปเดต)"
fi

# ── 4) เปิด + รีเฟรช Übersicht ──────────────────────────
# Übersicht เฝ้าดูโฟลเดอร์ widgets อยู่แล้ว → พอ copy ไฟล์เข้าไปมันจะโหลดเองอัตโนมัติ
# คำสั่ง open/refresh ด้านล่างเป็นตัวช่วย (ไม่สำเร็จก็ไม่เป็นไร)
if ! pgrep -if 'bersicht.app' >/dev/null 2>&1; then
  open -a "Übersicht" 2>/dev/null
  sleep 2
fi
osascript -e 'tell application "Übersicht" to refresh' 2>/dev/null

echo "  ─────────────────────────────────────────────"
echo "  ✅ เสร็จ! การ์ด Claude Usage จะขึ้นมุมขวาบนของ desktop ภายในไม่กี่วินาที"
echo "     (ถ้าไม่ขึ้น: คลิกไอคอน Übersicht บนเมนูบาร์ → Refresh All Widgets)"
echo ""
