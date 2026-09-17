#!/bin/bash
#
# uninstall-app.sh
# ── ถอน ClaudeUsageBar.app ออกจากเครื่อง (ไม่แตะ ~/.claude หรือ credential ใดๆ) ──
#
#   ใช้:  bash app/scripts/uninstall-app.sh

set -euo pipefail

PRODUCT_NAME="ClaudeUsageBar"
BUNDLE_ID="io.github.panithannanti.ClaudeUsageBar"
DEST_APP="$HOME/Applications/${PRODUCT_NAME}.app"

echo ""
echo "  🗑  uninstall-app.sh — ถอน ${PRODUCT_NAME}"
echo "  ─────────────────────────────────────────────"

# ── 1) ปิดแอปตัวที่รันอยู่ ────────────────────────────────────────────
echo "  • ปิด ${PRODUCT_NAME} (ถ้ากำลังรัน)…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1
pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true

# ── 2) ลบ .app ───────────────────────────────────────────────────────
if [ -d "$DEST_APP" ]; then
  rm -rf "$DEST_APP"
  echo "  ✓ ลบแล้ว: $DEST_APP"
else
  echo "  • ไม่พบ $DEST_APP (อาจถอนไปแล้ว หรือยังไม่เคยติดตั้ง)"
fi

# ── 3) login item ────────────────────────────────────────────────────
echo "  • ถ้าเคยเปิด \"Launch at login\" ไว้ (SMAppService) macOS อาจยังมีรายการ"
echo "    ค้างอยู่ใน System Settings → General → Login Items — เข้าไปลบเองได้"
echo "    (สคริปต์นี้ไม่ลบให้อัตโนมัติ เพราะไม่มีสิทธิ์เข้าถึง UI นั้นโดยตรง)"

echo "  ─────────────────────────────────────────────"
echo "  ✅ เสร็จ — ไม่แตะไฟล์ใน ~/.claude หรือ credential ใดๆ ทั้งสิ้น"
echo ""
