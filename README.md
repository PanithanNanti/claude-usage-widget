# Claude Usage — Desktop Widget (macOS / Übersicht)

การ์ดแสดง **plan usage limits ของ Claude** (session / weekly / per-model) เป็น widget บน
desktop ของ Mac อัปเดตอัตโนมัติทุก ~5 นาที มีปุ่ม refresh ทันที, ล็อกเลือกจอ, และล็อกอิน/รีเฟรช
token ในตัว

> ทำงานได้เพราะดึงผ่าน **OAuth endpoint ของ Claude Code** (`/api/oauth/usage`) โดยตรง —
> ไม่ผ่าน `claude.ai` ที่ติด Cloudflare จึงยิงจาก background script ได้ (ดู [ความรู้เบื้องหลัง](#-ความรู้เบื้องหลัง-สำคัญ))

![แบบ A · การ์ดเต็ม — พื้นเข้ม glassy มุมขวาบน]

---

## ✨ ฟีเจอร์

- 🟦 **Progress bar** ต่อ limit: session / weekly (ทุกโมเดล) / weekly per-model
  (สีน้ำเงิน → เหลืองเมื่อ ≥80% → แดงเมื่อ ≥95%)
- ⏱️ เวลา reset: session แสดง "รีเซ็ตใน Xh Ym", weekly แสดงวัน+เวลา (เวลาเครื่อง)
- 🏷️ **ป้าย plan อัตโนมัติ** (Max 20× / Max 5× / Pro …) อ่านจาก credential ของแต่ละคน
- 🖱️ **ลากย้ายได้** — จับที่แถบหัวการ์ด จำตำแหน่งไว้ (localStorage)
- 🖥️ **รองรับหลายจอ** — คลิก "📍 ล็อกจอนี้" เพื่อให้โชว์เฉพาะจอที่เลือก
- 🔄 **ปุ่ม Refresh now** — ดึงข้อมูลทันทีไม่ต้องรอ 5 นาที
- 🔑 **ปุ่มล็อกอิน/รีเฟรช token** — เปิด Terminal รัน `claude` เมื่อ session หลุด
- 💾 **Cache/stale** — ถ้า token หมดอายุจะโชว์ค่าเดิม + ไฟเตือน แทนที่จะว่างเปล่า

---

## 📦 ความต้องการของระบบ

- macOS (Apple Silicon หรือ Intel)
- [Claude Code CLI](https://claude.com/claude-code) ติดตั้งและ **ล็อกอินอยู่** (widget อ่าน OAuth token ที่มันเก็บ)
- [Übersicht](https://tracesof.net/uebersicht/) (installer ติดตั้งให้ผ่าน Homebrew ได้)
- `python3` (มากับ macOS)

---

## 🚀 ติดตั้ง (เครื่องใหม่ / เพื่อนร่วมทีม)

```bash
git clone <repo-url> claude-usage-widget
cd claude-usage-widget
bash install-claude-usage-widget.command      # หรือดับเบิลคลิกไฟล์นี้ใน Finder
```

installer จะ:
1. เช็ก/ติดตั้ง Übersicht (ผ่าน `brew install --cask ubersicht`)
2. copy `claude-usage.jsx` ไปโฟลเดอร์ widgets ของ Übersicht **พร้อมแก้ path สคริปต์ให้ตรงเครื่องอัตโนมัติ**
3. ดึง usage ครั้งแรก (วอร์ม cache)
4. เปิด + รีเฟรช Übersicht

การ์ดจะขึ้นมุมขวาบนของ desktop ภายในไม่กี่วินาที

> ครั้งแรกกับหลายจอ: การ์ดจะขึ้นทุกจอ — คลิก **"📍 ล็อกจอนี้"** บนจอที่ต้องการ จออื่นจะซ่อนเอง
> (เปลี่ยนใจภายหลังกด **"⇄ ย้ายจอ"** เพื่อเลือกใหม่)

### ถอนการติดตั้ง
```bash
bash uninstall-claude-usage-widget.command
```

---

## 🧩 ไฟล์ในโปรเจกต์

| ไฟล์ | หน้าที่ |
|------|---------|
| `claude-usage.sh` | ดึง usage ผ่าน OAuth token — โหมด `--json` (ให้ widget ใช้) และโหมด pretty (ดีบั๊กใน terminal) |
| `claude-usage.jsx` | Übersicht widget (แบบ A การ์ดเต็ม) — เรนเดอร์จาก `limits[]`, ลาก/ล็อกจอ/refresh/login |
| `install-claude-usage-widget.command` | ตัวติดตั้ง (idempotent — รันซ้ำเพื่ออัปเดต widget ได้) |
| `uninstall-claude-usage-widget.command` | ตัวถอน |
| `CLAUDE.md` | บันทึกการทำงาน/ความรู้แบบละเอียด (ภาษาไทย) |

รันสคริปต์ตรงๆ เพื่อทดสอบ:
```bash
bash claude-usage.sh            # แสดงผลอ่านง่ายใน terminal
bash claude-usage.sh --json     # JSON ดิบ (แบบที่ widget ใช้)
```

---

## 🔍 ความรู้เบื้องหลัง (สำคัญ)

### ใช้ OAuth endpoint ของ Claude Code — ไม่ใช่ claude.ai
```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <ACCESS_TOKEN>
```
- endpoint นี้คือตัวที่คำสั่ง `/usage` ใน Claude Code ใช้ → **ไม่ติด Cloudflare** ยิงจากสคริปต์ได้
- ตรงข้ามกับ `https://claude.ai/api/.../usage` (cookie `sessionKey`) ที่ยิงนอกเบราว์เซอร์แล้วโดน
  Cloudflare เด้ง (403 / "Just a moment...") — **ทางตัน** สำหรับ background script

### token เก็บที่ไหน (macOS)
Claude Code เก็บ OAuth credential ไว้ที่ **Keychain**:
- service: `Claude Code-credentials`  ·  account: `$USER`
- โครงสร้าง (ห่อด้วย `claudeAiOauth`):
  ```json
  { "claudeAiOauth": { "accessToken": "sk-ant-oat01-…", "refreshToken": "…",
    "expiresAt": 0, "subscriptionType": "max", "rateLimitTier": "default_claude_max_20x" } }
  ```
- อ่านด้วย: `security find-generic-password -a "$USER" -w -s "Claude Code-credentials"`
- `/usr/bin/security` อ่านได้โดย **ไม่มี GUI prompt** แม้ถูกเรียกจาก Übersicht (ทดสอบด้วย `launchctl asuser`)
- บาง setup เก็บเป็นไฟล์ `~/.claude/.credentials.json` แทน (สคริปต์รองรับทั้งสองแบบ)
- **แกะ token ด้วย `python3` (parse JSON)** ไม่ใช่ `sed` — blob เป็นบรรทัดเดียวยาว sed พลาดง่าย

### โครงสร้าง response (`/api/oauth/usage`)
```
five_hour.utilization / .resets_at     ← session (0-100 %)
seven_day.utilization / .resets_at     ← weekly ทุกโมเดล
limits[]  { kind: session|weekly_all|weekly_scoped, percent, severity,
            resets_at, scope.model.display_name }   ← มี label สวย + per-model
```
> oauth endpoint **ก็มี `limits[]`** (ไม่ใช่แค่ฝั่ง claude.ai) — widget เรนเดอร์จากตรงนี้เป็นหลัก

### token refresh / session หลุด
- accessToken หมดอายุทุกไม่กี่ชั่วโมง (`expiresAt`) — **Claude Code ต่ออายุให้เองตอนมันรัน**
- ถ้า widget เจอ 401 → โชว์ค่าเดิม (stale) + ปุ่ม 🔑 เปิด Terminal รัน `claude` (ล็อกอิน/รีเฟรช token)
- ถ้าอยากให้สดตลอดแม้ไม่เปิด claude → ทำ LaunchAgent รัน `claude-usage.sh --json` เป็นระยะ

---

## 🛠️ ปรับแต่ง

- **ตำแหน่ง/ขนาดเริ่มต้น**: แก้ `.cu-card { top / right / width }` ใน `claude-usage.jsx`
  (หรือแค่ลากการ์ดเอา แล้วมันจำตำแหน่งให้)
- **ความถี่รีเฟรช**: `refreshFrequency` (มิลลิวินาที) ใน `claude-usage.jsx`
- **สี threshold**: ฟังก์ชัน `barColor()` ใน `claude-usage.jsx`
- **ป้าย plan**: ตรวจอัตโนมัติจาก credential — เพิ่ม mapping ได้ที่ `PY_PLAN` ใน `claude-usage.sh`

---

## ❓ แก้ปัญหา

| อาการ | วิธีแก้ |
|-------|---------|
| การ์ดไม่ขึ้นเลย | คลิกไอคอน Übersicht บนเมนูบาร์ → **Refresh All Widgets** / เปิด **Show widgets on desktop** |
| ไม่มีไอคอน Übersicht บนเมนูบาร์ | เปิดแอป Übersicht จาก Launchpad (หรือ `brew install --cask ubersicht` ใหม่) แล้วรัน installer อีกครั้ง |
| การ์ดโชว์ไฟเหลือง/แดง "token หมดอายุ" | กดปุ่ม 🔑 บนการ์ด (หรือเปิด Terminal พิมพ์ `claude` เอง) แล้วกด ↻ รีเฟรช |
| โชว์ทุกจอ | คลิก **📍 ล็อกจอนี้** บนจอที่ต้องการ |
| ป้าย plan ไม่ตรง | เพิ่ม mapping tier ที่ `PY_PLAN` ใน `claude-usage.sh` |

---

## English (short)

Desktop widget for macOS ([Übersicht](https://tracesof.net/uebersicht/)) showing **Claude plan
usage limits**. It reads Claude Code's OAuth token from the macOS Keychain
(`security … -s "Claude Code-credentials"`) and calls
`GET https://api.anthropic.com/api/oauth/usage` — the same endpoint `/usage` uses, which is **not
behind Cloudflare** (unlike `claude.ai`). Features: draggable, per-monitor lock, refresh-now, and
a key button to re-login/refresh the token when the session drops.

Install: `bash install-claude-usage-widget.command` (handles Übersicht install + path rewrite).
See [ความรู้เบื้องหลัง](#-ความรู้เบื้องหลัง-สำคัญ) for the reverse-engineering notes.
