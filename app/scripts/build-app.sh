#!/bin/bash
#
# build-app.sh
# ── ประกอบ ClaudeUsageBar.app จาก SwiftPM package (ไม่มี Xcode, ใช้ CLT ล้วน) ──
#
#   ใช้:  bash app/scripts/build-app.sh          (arm64 เครื่องปัจจุบันเท่านั้น)
#         UNIVERSAL=1 bash app/scripts/build-app.sh   (arm64 + x86_64 — อาจใช้ไม่ได้บน CLT ล้วน)
#
# ทำอะไรบ้าง:
#   1) swift build -c release --package-path app --product ClaudeUsageBar
#   2) หา path ไบนารีจาก --show-bin-path แล้วประกอบ app/dist/ClaudeUsageBar.app
#   3) copy Info.plist, claude-usage.sh, capybeats.png (+ resource bundle ถ้ามี) เข้า Contents/Resources
#   4) ลองสร้าง AppIcon.icns จาก capybeats.png (best-effort — พังก็ข้ามไป ไม่ทำให้ build ล้ม)
#   5) ad-hoc codesign + verify + plutil -lint แล้ว print path สุดท้าย

set -euo pipefail

# ── paths (resolve ตำแหน่งสคริปต์เอง ใช้ได้จาก cwd ไหนก็ได้) ──────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$APP_DIR/.." && pwd)"

PRODUCT_NAME="ClaudeUsageBar"
INFO_PLIST_SRC="$APP_DIR/Resources/Info.plist"
CLAUDE_USAGE_SH_SRC="$REPO_DIR/claude-usage.sh"
CAPYBEATS_SRC="$REPO_DIR/capybeats.png"
ICON_SRC="$REPO_DIR/claude_limit.png"
DIST_DIR="$APP_DIR/dist"
APP_BUNDLE="$DIST_DIR/${PRODUCT_NAME}.app"

echo ""
echo "  🔨  build-app.sh — ประกอบ ${PRODUCT_NAME}.app"
echo "  ─────────────────────────────────────────────"
echo "  app dir : $APP_DIR"
echo "  repo dir: $REPO_DIR"

fail() {
  echo "  ❌ $1" >&2
  exit 1
}

# ── เช็กไฟล์ต้นทางที่จำเป็นก่อนเริ่ม build (fail loudly ให้ชัดตั้งแต่ต้น) ──
[ -f "$APP_DIR/Package.swift" ] || fail "ไม่พบ $APP_DIR/Package.swift — ยังไม่มี SwiftPM package (ต้องรอ agent อีกตัวเขียนก่อน)"
[ -f "$INFO_PLIST_SRC" ] || fail "ไม่พบ $INFO_PLIST_SRC"
[ -f "$CLAUDE_USAGE_SH_SRC" ] || fail "ไม่พบ $CLAUDE_USAGE_SH_SRC (root ของ repo)"
[ -f "$CAPYBEATS_SRC" ] || fail "ไม่พบ $CAPYBEATS_SRC (root ของ repo)"

# ── 1) swift build ────────────────────────────────────────────────────
BUILD_ARGS=(build -c release --package-path "$APP_DIR" --product "$PRODUCT_NAME")
if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "  • UNIVERSAL=1 — build arm64 + x86_64 (อาจล้มเหลวถ้า SDK ไม่รองรับใน CLT ล้วน)"
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "  • swift ${BUILD_ARGS[*]}"
swift "${BUILD_ARGS[@]}" || fail "swift build ล้มเหลว (ดู error ด้านบน)"

# ── 2) หา path ไบนารี ────────────────────────────────────────────────
BIN_PATH="$(swift "${BUILD_ARGS[@]}" --show-bin-path)"
[ -n "$BIN_PATH" ] || fail "หา --show-bin-path ไม่ได้"
BIN_FILE="$BIN_PATH/$PRODUCT_NAME"
[ -f "$BIN_FILE" ] || fail "build เสร็จแต่ไม่พบไบนารีที่ $BIN_FILE"
echo "  ✓ ไบนารี: $BIN_FILE"

# ── 3) ประกอบ .app bundle ───────────────────────────────────────────
# ป้องกันการลบผิดที่: ต้องอยู่ใต้ app/dist เท่านั้น
case "$APP_BUNDLE" in
  "$DIST_DIR"/*) ;;
  *) fail "internal: APP_BUNDLE path ผิดที่ ($APP_BUNDLE)" ;;
esac
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_FILE" "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"

cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

cp "$CLAUDE_USAGE_SH_SRC" "$APP_BUNDLE/Contents/Resources/claude-usage.sh"
chmod +x "$APP_BUNDLE/Contents/Resources/claude-usage.sh"

cp "$CAPYBEATS_SRC" "$APP_BUNDLE/Contents/Resources/capybeats.png"

echo "  ✓ copy claude-usage.sh, capybeats.png, Info.plist เข้า bundle แล้ว"

# resource bundle ที่ SwiftPM อาจสร้างไว้ข้างๆ ไบนารี (เช่น *_ClaudeUsageBar.bundle)
shopt -s nullglob
BUNDLES=("$BIN_PATH"/*.bundle)
shopt -u nullglob
if [ "${#BUNDLES[@]}" -gt 0 ]; then
  for b in "${BUNDLES[@]}"; do
    cp -R "$b" "$APP_BUNDLE/Contents/Resources/"
    echo "  ✓ copy resource bundle: $(basename "$b")"
  done
fi

# ── 4) ไอคอน (best-effort — ห้ามทำให้ build ล้มถ้าพัง) ────────────────
ICON_ADDED=0
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  ICON_TMP="$(mktemp -d)"
  # หมายเหตุ: รันเป็น subshell ในเงื่อนไข if (…) เพื่อไม่ให้ set -e ของสคริปต์หลัก
  # ตัดจบทั้งสคริปต์ถ้าขั้นตอนไอคอนพัง — ต้อง "ข้ามอย่างเดียว" ตามสเปก
  if (
    set -e
    mkdir -p "$ICON_TMP/AppIcon.iconset"
    if [ -f "$ICON_SRC" ]; then
      # ✅ claude_limit.png — ไอคอนสไตล์ macOS squircle สำเร็จรูป (1254x1254, มีขอบโปร่งใสแล้ว)
      # ใช้ตรงๆ ไม่ crop ไม่เติม padding/พื้นหลัง — สร้าง iconset มาตรฐานจากไฟล์นี้เลย
      echo "  • ใช้ $ICON_SRC เป็นไอคอน"
      for s in 16 32 128 256 512; do
        sips -z "$s" "$s" "$ICON_SRC" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z "$d" "$d" "$ICON_SRC" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
      done
    else
      # fallback เดิม: frame เดียวจาก spritesheet 8x192 x 9x208 — offset ที่ทดสอบแล้วว่า
      # sips --cropOffset ให้ผลลัพธ์ครบตัว ไม่ค่อมเฟรม (ค่า offset ที่ใกล้ขอบ/เป๊ะ
      # ครึ่งหนึ่งของช่องว่างที่เหลือ ทำให้ sips คืนภาพเพี้ยน/ว่างในบางเวอร์ชัน —
      # เลี่ยงด้วยการใช้ offset กลางๆ ที่ทดสอบแล้วว่าเฟรมไม่ค่อม)
      echo "  • ไม่พบ $ICON_SRC — ใช้ fallback ตัด frame จาก capybeats.png"
      sips -c 208 192 --cropOffset 0 400 "$CAPYBEATS_SRC" --out "$ICON_TMP/frame.png" >/dev/null
      sips -p 224 224 "$ICON_TMP/frame.png" --out "$ICON_TMP/square.png" >/dev/null
      for s in 16 32 128 256 512; do
        sips -z "$s" "$s" "$ICON_TMP/square.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z "$d" "$d" "$ICON_TMP/square.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
      done
    fi
    iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$ICON_TMP/AppIcon.icns" >/dev/null
    [ -f "$ICON_TMP/AppIcon.icns" ]
  ); then
    cp "$ICON_TMP/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1 || true
    ICON_ADDED=1
    echo "  ✓ สร้างไอคอน AppIcon.icns สำเร็จ"
  else
    echo "  ⚠ สร้างไอคอนไม่สำเร็จ — ข้าม (แอปจะใช้ไอคอน default ของระบบ)"
  fi
  rm -rf "$ICON_TMP"
else
  echo "  ⚠ ไม่พบ sips/iconutil — ข้ามการสร้างไอคอน"
fi

if [ "$ICON_ADDED" != "1" ]; then
  # กันไว้เผื่อ Info.plist ต้นทางมี CFBundleIconFile ค้างจากการรันครั้งก่อน (ไม่ควรมี แต่กันเหนียว)
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1 || true
fi

# ── 5) ad-hoc codesign + verify ──────────────────────────────────────
echo "  • ad-hoc codesign…"
codesign --force --deep --sign - "$APP_BUNDLE" || fail "codesign ล้มเหลว"
codesign --verify --verbose "$APP_BUNDLE" || fail "codesign --verify ล้มเหลว"
plutil -lint "$APP_BUNDLE/Contents/Info.plist" || fail "Info.plist ไม่ผ่าน plutil -lint"

echo "  ─────────────────────────────────────────────"
echo "  ✅ เสร็จ: $APP_BUNDLE"
echo ""
