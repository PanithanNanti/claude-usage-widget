# Claude Usage Desktop Widget — โปรเจกต์

> เป้าหมาย: แสดง **plan usage limits ของ Claude** (current session / weekly / per-model)
> เป็น **widget บน desktop ของ Mac** อัปเดตอัตโนมัติทุก ~5 นาที

เครื่อง: macOS (arm64), เชลล์ zsh/iTerm2, มี Claude Code CLI ติดตั้งและล็อกอินอยู่
ผู้ใช้ต่อจากนี้ทำงานใน Claude Code บนเครื่องตัวเอง (มีสิทธิ์ Terminal เต็ม)

---

## ✅ ข้อค้นพบสำคัญ (อ่านก่อน — ประหยัดเวลาหลายชั่วโมง)

### 1) อย่าใช้ endpoint ฝั่ง claude.ai — มันติด Cloudflare
`GET https://claude.ai/api/organizations/{org}/usage` (cookie `sessionKey`)
- ดึงได้เฉพาะ**จากในเบราว์เซอร์**เท่านั้น
- ยิงจาก curl/สคริปต์ = โดน Cloudflare เด้ง (`HTTP 403`, `cf-mitigated: challenge`, หน้า "Just a moment...")
- → **ทางตัน** สำหรับ widget/background script (เคยลองแล้ว widget ขึ้น "session หมดอายุ" ตลอด เพราะ request ไปไม่ถึง API)

### 2) ✅ ใช้ endpoint OAuth ของ Claude Code แทน — ไม่ติด Cloudflare
นี่คือ endpoint ที่คำสั่ง `/usage` ใน Claude Code ใช้:

```
GET https://api.anthropic.com/api/oauth/usage
Headers:
  Authorization: Bearer <ACCESS_TOKEN>
  Content-Type: application/json
```

- ทดสอบแล้ว: ยิงด้วย token มั่ว → ตอบ **HTTP 401** (ไม่ใช่ 403/Cloudflare) = request ถึง API จริง ใช้ Bearer token ธรรมดาได้
- token นี้ **Claude Code จัดการ + ต่ออายุให้เอง** → ไม่ต้องใส่ sessionKey เอง ไม่ต้องคอยต่ออายุ
- (อ้างอิงในไบนารีของ Claude Code: `fetchUtilization: GET /api/oauth/usage`)

### 3) ที่เก็บ OAuth token
โครงสร้าง credential (JSON):
```json
{ "claudeAiOauth": { "accessToken": "sk-ant-oat01-...", "refreshToken": "...", "expiresAt": 0, "scopes": [] } }
```
เก็บที่ (อย่างใดอย่างหนึ่ง):
- **ไฟล์:** `~/.claude/.credentials.json`
- **macOS Keychain:** อ่านด้วย
  ```bash
  security find-generic-password -a "<ACCOUNT>" -w -s "<SERVICE>"
  ```
  จากการถอดไบนารี Claude Code:
  - account (`-a`) = `process.env.USER || userInfo().username`
  - service (`-s`) = `` `Claude Code${OAUTH_FILE_SUFFIX}${e}${o}` `` โดย prod `OAUTH_FILE_SUFFIX=""`, `e=""`,
    และ `o=""` ถ้าใช้ config dir ปกติ (ไม่ตั้ง `CLAUDE_CONFIG_DIR`) — มิฉะนั้น `o="-<sha256(configdir)[:8]>"`
  - → ค่า default ที่คาดคือ service = **`"Claude Code"`**

### 4) endpoint ต่ออายุ token (`platform.claude.com/v1/oauth/token`) บล็อกตาม User-Agent
บทเรียนจริง 2026-07-13 (อาการ: widget ค้าง 429 ตั้งแต่ ~ตี 5 ทุกวัน):
- accessToken อายุ **8 ชม.** — ใช้ Claude Code ถึงดึก token ตายราวๆ ตี 5 เป๊ะทุกวัน
- auto-refresh ใน script **ไม่เคยทำงานเลย** เพราะ Cloudflare หน้า endpoint นี้บล็อกเป็น
  **denylist ตาม UA**: `Python-urllib` → **403** (code 1010), curl default/browser UA → **429**
  แต่ UA ชื่อธรรมดาอย่าง `claude-usage-widget/1.0` หรือ `axios/1.7.0` → **ผ่าน** (ได้ 400
  invalid_grant กับ token ทดสอบ = ถึงตัว API จริง) → แค่ตั้ง UA เองก็พอ **ไม่ต้องปลอมเป็น claude-code**
- 429 ที่เห็นบน widget ไม่ได้มาจาก refresh — มาจากการเอา **token เน่ายิง usage ซ้ำทุก 10 นาที
  ข้ามคืน** จนสะสม 401 แล้ว edge ของ `api.anthropic.com` ตบ 429 ใส่ → ต้องหยุดยิงทันที
  ที่รู้ว่า token ตายและต่อไม่ได้ (script กันให้แล้ว)
- กัน refresh token ชนกับ Claude Code ที่รันอยู่ (เผื่อเป็นแบบหมุนทิ้งหลังใช้): token แค่ "ใกล้หมด"
  + `pgrep -x claude` เจอโปรเซส → ไม่แย่ง refresh, ให้ Claude Code ต่อเอง; script จะ refresh เอง
  เฉพาะตอน token ตายสนิท (ตอนนั้นไม่มีอะไรรันอยู่แล้ว)

> ✅ **ยืนยันบน macOS จริง:** token อยู่ที่
> **keychain service = `"Claude Code-credentials"`, account = `$USER`**
> โครงสร้าง blob **ห่อด้วย `{"claudeAiOauth":{...}}`** (ไม่ใช่ flat)
> และ **`/usr/bin/security` อ่านได้โดยไม่มี GUI prompt** แม้จาก clean-env / `launchctl asuser`
> → widget เรียกผ่าน Übersicht (GUI context) อ่าน keychain ได้ ไม่ติด ACL
>
> หมายเหตุ: สาเหตุที่ script เดิมหาไม่เจอมี 2 อย่าง (1) service ผิด (2) แกะ token ด้วย `sed`
> ล้มเหลว → เปลี่ยนมาแกะด้วย `python3` (parse JSON จริง, รองรับ wrapper) แล้วใช้ได้

---

## 📊 โครงสร้าง response ของ /api/oauth/usage
ฟิลด์ที่ Claude Code อ่าน (ยืนยันจากไบนารี):
```
five_hour.utilization      (0-100)   ← current session %
five_hour.resets_at        (ISO)
seven_day.utilization      (0-100)   ← weekly (all models) %
seven_day.resets_at        (ISO)
seven_day_opus.utilization   (อาจมี) ← per-model weekly
seven_day_sonnet.utilization (อาจมี)
seven_day_overage_included   (อาจมี)
```
> ✅ **ยืนยัน JSON จริงแล้ว (2026-07-10):** oauth endpoint **ก็มี array `limits[]`** เหมือนกัน!
> (`kind: session|weekly_all|weekly_scoped`, `percent`, `severity`, `resets_at`,
>  `scope.model.display_name` เช่น "Fable") → script/widget เรนเดอร์จาก `limits[]` เป็นหลัก
> (fallback ไป five_hour/seven_day ถ้าไม่มี). บาง field เช่น `seven_day_opus/sonnet`
> อาจเป็น `null` แล้วแต่บัญชี — โค้ดต้องกันกรณี null/ไม่มี field เสมอ

---

## 🔑 ค่าเฉพาะบัญชี (อ่านจาก credential อัตโนมัติ — ไม่ต้อง hardcode)
- **plan tier:** อยู่ในฟิลด์ `subscriptionType`/`rateLimitTier` ของ blob → map เป็น label
  (`default_claude_max_20x` → "Max (20×)", `default_claude_max_5x` → "Max (5×)", `default_claude_pro` → "Pro" ฯลฯ)
- **timezone:** ใช้ของเครื่องผู้ใช้เอง → เวลา reset (ISO/UTC) แปลงเป็น local ตอนแสดงผล

---

## 📁 ไฟล์ในโฟลเดอร์นี้
| ไฟล์ | สถานะ |
|------|-------|
| `CLAUDE.md` | ← ไฟล์นี้ |
| `claude-usage.sh` | ✅ ใช้ได้จริง — ดึง usage ผ่าน OAuth token (pretty + `--json` + `--force`), แกะ token ด้วย python3, มี cache/stale fallback ที่ `~/.claude/usage-cache.json` **+ กัน 429 ในตัว**: TTL cache 5 นาที (`CU_TTL`) → เรียกถี่แค่ไหนก็ยิง API ไม่เกิน 1 ครั้ง/TTL, เจอ 429 → พักยิง 15 นาที (`CU_BACKOFF`, state ที่ `~/.claude/usage-backoff`, `--force` ก็ไม่ข้าม) **+ auto-refresh ที่ทำงานจริง** (ส่ง UA `claude-usage-widget/1.0` — ดูข้อค้นพบ #4): token ตาย/ใกล้หมด → ต่ออายุเองแล้วเขียนกลับ keychain/ไฟล์, refresh ล้มเหลว → พัก 1 ชม. (`~/.claude/usage-refresh-backoff`), token ตาย+ต่อไม่ได้ → **ไม่ยิง usage เลย** (กัน edge แบน) **+ log** ทุกการยิง API/refresh ที่ `~/.claude/usage-widget.log` (ตัดท้ายเอง) |
| `claude-usage.jsx` | ✅ widget Übersicht **แบบ A (การ์ดเต็ม)** — เรียก `claude-usage.sh --json`, เรนเดอร์จาก `limits[]`, รีเฟรช 10 นาที, สถานะ stale/error, ปุ่ม ↻ ใช้ `--force` และ**ไม่มีทางวาดทับข้อมูลดีด้วย error** (ผลเพี้ยน→คงค่าเดิม; `run()` ที่คืน Error ถูก reject ไม่ใช่ resolve), มี **CapyBeats** คาปิบาร่า sprite 72 เฟรม (8×9, CSS steps) ดุ๊กดิ๊กบนหัวการ์ด |
| `capybeats.png` | spritesheet คาปิบาร่า (จาก `~/.codex/pets/capybeats`) — installer copy ไป widgets เป็น `claude-usage-capy.png` (widget อ้าง relative URL ผ่าน server ของ Übersicht) |
| `install-claude-usage-widget.command` | ✅ installer ใหม่ — เช็ก/ติดตั้ง Übersicht, copy jsx + แก้ path สคริปต์ให้อัตโนมัติ, วอร์ม cache, รีเฟรช |
| `uninstall-claude-usage-widget.command` | ตัวถอน widget/Übersicht + ลบ config เก่า |
| `~/Library/Application Support/Übersicht/widgets/claude-usage.jsx` | ✅ **ติดตั้งลงแล้ว** (path สคริปต์ถูกแก้เป็น absolute แล้ว) |
| `~/.claude/usage-cache.json` | cache ก้อนล่าสุด (widget ใช้โชว์ค่าเดิมตอน token หมดอายุ) |

> หมายเหตุ: `widget-mockups.html` (ดีไซน์ 3 แบบ) และ installer เก่าที่ใช้ sessionKey **ไม่มีอยู่แล้ว**
> ในโฟลเดอร์ — สเปกดีไซน์แบบ A ที่เลือกไว้อยู่ท้ายไฟล์นี้ (widget สร้างตามสเปกนั้น)

---

## 🎯 สถานะงาน (อัปเดต 2026-07-10)

**✅ ข้อ 1–3 เสร็จแล้ว:** token discovery แก้ได้, ยืนยัน JSON จริง (`limits[]`),
สร้าง+ติดตั้ง widget แบบ A ลง Übersicht เรียบร้อย (ดึงข้อมูลได้สถานะ `live`)

**เหลือขั้นสุดท้าย — ผู้ใช้ยืนยันด้วยตา (heasless verify ไม่ได้):**
1. ดูมุมขวาบน desktop ว่ามีการ์ด "Claude Usage" ขึ้นไหม
   - ถ้าไม่ขึ้น: คลิกไอคอน Übersicht บนเมนูบาร์ → **Refresh All Widgets**
   - ถ้ายังไม่ขึ้น: เมนูบาร์ Übersicht ต้องเปิด "Show widgets on desktop"
2. ตรวจว่าเลข %/เวลา reset ตรงกับ `/usage` ใน Claude Code
> ⚠️ หมายเหตุสถานะเครื่องนี้: Übersicht รันอยู่ (server port 41416, เฝ้าโฟลเดอร์ widgets)
> แต่ **LaunchServices หา `/Applications/Übersicht.app` ไม่เจอ** (ตัว Ü Unicode + แอปไม่ได้
> register) → `open -a "Übersicht"` / `osascript refresh` อาจไม่ทำงาน แต่ตัว server
> auto-reload โฟลเดอร์เอง. ถ้าเมนูบาร์ไม่มีไอคอน Übersicht ให้ **ติดตั้ง/เปิดใหม่ให้เรียบร้อย**
> (`brew install --cask ubersicht` แล้วเปิดจาก Launchpad) แล้วรัน installer อีกครั้ง

**✅ token refresh อัตโนมัติ — ใช้งานได้จริงแล้ว (แก้ 2026-07-13):** accessToken อายุ 8 ชม.
เดิม refresh ล้มเหลวเงียบๆ ทุกครั้งเพราะ UA โดน Cloudflare บล็อก (ดูข้อค้นพบ #4) → token ตาย
~ตี 5 ทุกวันแล้ว widget ค้าง 429 ยันเปิด Claude Code. ตอนนี้ script refresh เองได้ + มี log ที่
`~/.claude/usage-widget.log` — เช้าไหน widget เพี้ยนให้ `grep -i 'refresh\|FAIL' ~/.claude/usage-widget.log` ดูก่อน

---

## ดีไซน์ widget แบบ A (การ์ดเต็ม) ที่ผู้ใช้เลือก
การ์ดมุมขวาบน desktop, พื้นเข้ม glassy:
- หัว: ไอคอน ✳ (พื้นส้ม #d97757) + "Claude Usage" + ป้าย plan (เช่น "Max (20×)" — อ่านจาก credential)
- แต่ละ limit: ชื่อ + เวลา reset + progress bar (น้ำเงิน #4f7cff; เหลือง #f0a728 เมื่อ ≥80%; แดง #f0554a เมื่อ ≥95%) + "X% used"
- ท้าย: จุดเขียว + "อัปเดตล่าสุด HH:MM · รีเฟรชทุก 5 นาที"
- เวลา reset: session แสดง "รีเซ็ตใน Xh Ym", weekly แสดงวัน+เวลา (timezone ของเครื่องผู้ใช้)

ดูตัวอย่างเต็มใน `widget-mockups.html` (เปิดในเบราว์เซอร์)
