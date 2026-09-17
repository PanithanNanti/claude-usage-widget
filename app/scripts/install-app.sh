#!/bin/bash
#
# install-app.sh
# ── build + ติดตั้ง ClaudeUsageBar.app ลง ~/Applications แล้วเปิด ──
#
#   ใช้:  bash app/scripts/install-app.sh
#         UNIVERSAL=1 bash app/scripts/install-app.sh   (ส่งต่อให้ build-app.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PRODUCT_NAME="ClaudeUsageBar"
BUNDLE_ID="io.github.panithannanti.ClaudeUsageBar"
SRC_APP="$APP_DIR/dist/${PRODUCT_NAME}.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/${PRODUCT_NAME}.app"

echo ""
echo "  📦  install-app.sh — ติดตั้ง ${PRODUCT_NAME}"
echo "  ─────────────────────────────────────────────"

fail() {
  echo "  ❌ $1" >&2
  exit 1
}

# ── 1) build ─────────────────────────────────────────────────────────
echo "  • build…"
bash "$SCRIPT_DIR/build-app.sh" || fail "build ล้มเหลว — ดู error ด้านบน"
[ -d "$SRC_APP" ] || fail "build เสร็จแต่ไม่พบ $SRC_APP"

# ── 2) ปิดแอปตัวที่รันอยู่ (ถ้ามี) ────────────────────────────────────
echo "  • ปิด ${PRODUCT_NAME} ตัวที่รันอยู่ (ถ้ามี)…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1
pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

# ── 3) copy ไป ~/Applications ────────────────────────────────────────
mkdir -p "$DEST_DIR"
if [ -d "$DEST_APP" ]; then
  # ลบเฉพาะ .app ตัวนี้ตัวเดียว ไม่แตะไฟล์อื่นใน ~/Applications
  rm -rf "$DEST_APP"
fi
ditto "$SRC_APP" "$DEST_APP" || fail "copy ไป $DEST_APP ล้มเหลว"
echo "  ✓ ติดตั้งแล้ว: $DEST_APP"

# ── 4) เปิดแอป ───────────────────────────────────────────────────────
open "$DEST_APP" || fail "เปิดแอปไม่สำเร็จ (ลองเปิดเองจาก Finder: $DEST_APP)"

echo "  ─────────────────────────────────────────────"
echo "  ✅ เสร็จ! ${PRODUCT_NAME} ควรขึ้นที่เมนูบาร์แล้ว"
echo "     (ถ้าไม่ขึ้น: เปิดจาก Finder → $DEST_APP)"
echo ""
echo "  หมายเหตุ: ถ้ายังมี widget Übersicht ตัวเก่าอยู่ ลบได้ด้วย:"
echo "     bash \"$(cd "$APP_DIR/.." && pwd)/uninstall-claude-usage-widget.command\""
echo "  (สคริปต์นี้ไม่ได้รันให้อัตโนมัติ — ลบเองเมื่อพร้อม)"
echo ""
