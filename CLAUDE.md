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

### 5) ⚠️ ไฟล์ `.credentials.json` เก่าค้าง "บัง" keychain (บั๊กจริง 2026-08-17)
อาการ: widget ค้างเลขเดิมของ **4 วันก่อน** (13 ส.ค. 10:08) ทั้งที่ใช้ `claude` อยู่ตลอด,
log มี `refresh FAIL: http 400 invalid_grant "Refresh token expired"` + `skip usage` ทุก 10 นาที
- ต้นเหตุ: script เลือก credential แบบ **"แหล่งแรกที่มี token ชนะ"** → ไฟล์
  `~/.claude/.credentials.json` (ค้างจากการล็อกอินครั้งก่อน, accessToken หมด 13 ส.ค. 10:08 /
  refreshToken หมด 13 ส.ค. 05:01 — **ไม่มีอะไรมาอัปเดตไฟล์นี้อีกเลย**) ถูกอ่านก่อน keychain
  → keychain ที่ Claude Code หมุนให้สดตลอด (`expiresAt` วันนี้, refreshToken ถึง 4 ก.ย.)
  ไม่เคยถูกแตะเลย
- โซ่ความล้มเหลว: token ตาย → refresh ด้วย refreshToken ที่ตายแล้ว → 400 → กติกา
  "token ตาย + refresh ไม่ได้ = ไม่ยิง usage" (ข้อ 4) ทำงานถูกต้อง → ตอบ cache เดิมเป็น stale
  ตลอดไป **ระบบไม่มีทางฟื้นเอง** เพราะไฟล์เก่าไม่มีวันสด
- ✅ แก้แล้ว: `claude-usage.sh` อ่าน **ทุกแหล่ง** (ไฟล์ + keychain 2 service) แล้วเลือกอันที่
  `expiresAt` มากสุด (`consider_cred()`), ตั้ง `TOKEN`/`CRED_BLOB`/`CRED_SRC` จากตัวชนะพร้อมกัน
  → write-back ตอน refresh ยังลงแหล่งที่ถูกต้อง. ทดสอบแล้ว: เอาไฟล์เก่ากลับมาวางก็ยังได้ `live`
- **script ไม่ลบไฟล์ credential ให้เอง** (อันตราย) — แค่ไม่เลือกมัน; ไฟล์เก่าบนเครื่องนี้ถูก
  ย้ายไป `~/.claude/.credentials.json.bak-20260817` แล้ว
- ดีบั๊กเคสนี้เร็วๆ: `tail ~/.claude/usage-widget.log` เจอ `Refresh token expired` ซ้ำ =
  มี credential เก่าค้าง (ไม่ใช่ session หลุดจริง — เทียบ `expiresAt` ใน keychain ดูได้เลย)

#### ไทม์ไลน์จริง (จาก `usage-widget.log`) — ทำไมมันพังถาวร
| เวลา | เหตุการณ์ |
|------|-----------|
| 12 ส.ค. | ปกติ — `usage ok` 96 ครั้ง |
| 13 ส.ค. ~05:01 | **refreshToken ในไฟล์หมดอายุ/ถูกหมุนทิ้ง** (Claude Code ต่ออายุแล้วเขียนกลับ *keychain อย่างเดียว*) |
| 13 ส.ค. 09:58:38 | `refresh FAIL … invalid_grant` ครั้งแรก — **สถานะ token ตอนนั้นคือ `near` ไม่ใช่ `expired`** คือ script พยายามต่ออายุล่วงหน้า (เหลือ <15 นาที + ไม่มีโปรเซส `claude` รันอยู่) แต่ refreshToken ในไฟล์ตายไปแล้ว → นี่คือ**จุดตายจริง** |
| 13 ส.ค. 10:08:40 | `usage ok` **ครั้งสุดท้าย** (accessToken ในไฟล์หมดอายุ 10:08:41 — ยิงทันเสี้ยววินาทีสุดท้าย) |
| 13 ส.ค. 10:18:40 | `skip usage` ครั้งแรก → widget ค้างตั้งแต่นาทีนี้ |
| 13–17 ส.ค. | `skip usage` วันละ ~255 ครั้ง + `refresh FAIL` วันละ 24 ครั้งเป๊ะ (= backoff 1 ชม.) รวม **~854 skip / ~89 fail** กว่าจะถูกพบ |

**3 ชั้นที่ประกอบกันเป็นความพัง** (แต่ละชั้นเดี่ยวๆ ไม่พอ):
1. **สมมติฐานผิดตั้งแต่ commit แรก** (`30db928`) — เลือก credential แบบ *"แหล่งแรกที่มี token ชนะ"*
   โดยถือว่าไฟล์กับ keychain เหมือนกัน ซึ่ง**จริงตอนนั้น** จึงไม่มีใครเห็นว่าเป็นบั๊ก
2. **สมมติฐานถูกทำลายเงียบๆ** — Claude Code หมุน token แล้วเขียนกลับ keychain อย่างเดียว
   ไฟล์ค้างกับ token รุ่นที่ถูกเพิกถอนแล้ว → 2 แหล่ง diverge โดยไม่มีสัญญาณเตือน
3. **กติกากัน 429 กลายเป็นกับดัก** — "token ตาย + refresh ไม่ได้ = ไม่ยิง usage" (บทเรียน 13 ก.ค.)
   ทำงาน**ถูกต้องตามสเปก** แต่เมื่อรวมกับข้อ 1 = ล็อกตัวเองถาวร เพราะแหล่งที่มันเลือกอยู่
   ไม่มีวันสดขึ้นมาเองได้

**ทำไมไม่มีใครสังเกต 4 วัน:** widget ไม่ได้ขึ้น error ชัดๆ — มันโชว์ตัวเลขเก่าเป็น `stale` ดูเหมือนปกติ
สัญญาณเดียวคือบรรทัดเล็กๆ "ค่าล่าสุด 10:08" กับไฟเหลือง → **บทเรียน: ค่าที่ค้างเกิน N ชม.
ควรเด่นกว่านี้** (ยังไม่ได้ทำ — ถ้าจะทำต่อ ให้เทียบ `_fetched_at` กับเวลาปัจจุบันแล้วเตือนเมื่อเกิน ~1 ชม.)

### 6) ⚠️ "widget ไม่ขึ้นหลังอัปเดต macOS 27" — ไม่ใช่ OS พัง แต่เป็น screen lock ของเราเอง (2026-09-17)
อาการ: อัปเดตเป็น macOS 27.0 แล้วการ์ดหายทั้งจอ ทั้งที่ Übersicht 1.6.82 รันปกติ, script `usage ok` ทุก 10 นาที,
หน้าต่าง desktop-level ของ Übersicht อยู่ครบและอยู่เหนือ wallpaper (เช็กด้วย `CGWindowListCopyWindowInfo`)
- ต้นเหตุ: localStorage `claudeUsageWidgetScreen = "1080x1920"` (ล็อกไว้กับจอแนวตั้ง) แต่หลังรีบูต
  ระบบเห็นแค่จอ `3440x1440` → `applyScreenVisibility()` ซ่อนการ์ดบน**ทุกจอที่มี** = หายเกลี้ยง
  และปุ่ม 🖥️ ที่ใช้แก้ก็อยู่บนการ์ดที่ถูกซ่อน → ผู้ใช้แก้เองไม่ได้
- ✅ แก้: ซ่อนเฉพาะเมื่อจอที่ล็อก **ยังมีชีวิต** (`screenAlive()` — heartbeat `registerThisScreen()` ทุก 15 วิ
  จากลูป sync, ถือว่าตายเมื่อเงียบเกิน 60 วิ). ค่าที่ล็อกไม่ถูกลบ → เสียบจอกลับมาการ์ดย้ายกลับเอง
- 🐞 บั๊กแฝงที่เจอตอน deploy: guard `!window.__cuVisTimer` ทำให้ hot-reload เหลือ **timer ของโค้ดรุ่นเก่า**
  รันต่อ (ซ่อนการ์ดซ้ำทุก 1.5 วิ) → เปลี่ยนเป็น `clearInterval` แล้วตั้งใหม่ทุกครั้งที่โมดูลโหลด.
  เครื่องที่ยังรันโค้ดเก่าต้อง **Quit + เปิด Übersicht ใหม่ 1 ครั้ง** หลังอัปเดต jsx
- ดีบั๊กเคสแบบนี้: อ่าน localStorage ของ webview ได้ตรงๆ ที่
  `~/Library/WebKit/tracesOf.Uebersicht/WebsiteData/Default/*/*/LocalStorage/localstorage.sqlite3`
  (ตาราง `ItemTable`, value เป็น UTF-16LE — copy ออกมาก่อนเปิด). เปิด `127.0.0.1:41416` ใน Chrome
  **ใช้ไม่ได้** (client ต้องมี `window.webkit.messageHandlers`)

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

### 🧾 กฎ "Fable 50%" (มีผล 2026-07-20) — ที่มาของ bar `weekly_scoped: Fable`
Anthropic รวม **Claude Fable 5** เข้าแผน Max/Team Premium โดยใช้ได้**สูงสุด 50% ของ weekly limit**
(Pro/Team Standard ไม่รวม — ต้องซื้อ usage credits; ได้เครดิตชดเชยครั้งเดียว $100)
- **ไม่ใช่โควตาแถม** — Fable ดึงจาก weekly ก้อนเดียวกับโมเดลอื่น แค่ถูกแคปไม่ให้กินเกินครึ่ง
  → ใช้ Fable แล้วเลขขึ้น **2 bar พร้อมกัน**: weekly_all + weekly_scoped(Fable)
- **% ของ bar Fable คิดเทียบกับแคป 50% ของมันเอง** — Fable bar เต็ม 100% = Fable กินไป
  50 จุดของ weekly รวม (Fable 0→100% ดัน weekly_all ขึ้น +50 จุด)
- **Fable โดนตัดเมื่ออย่างใดอย่างหนึ่งเต็มก่อน**: Fable bar เต็ม (ยังใช้โมเดลอื่นต่อได้)
  หรือ weekly_all เต็ม (หยุดหมดทุกโมเดล) — ชนแคป Fable แล้วอยากใช้ต่อ = ซื้อ credits
- **ผลกับ widget:** เรนเดอร์จาก `limits[]` อยู่แล้ว bar Fable ก็คือแคปนี้. ถ้าเห็น bar Fable
  เต็มทั้งที่ weekly รวมยังเหลือ = พฤติกรรมถูกต้องตามกฎ ไม่ใช่ bug
- ⚠️ **แต่ daily pacing ต้องคิด 2 ชั้น (แก้ 2026-09-02)** — เดิม `dailyBudget()` ถูกเรียก
  **แยกกันต่อ limit ไม่คุยกันเลย** → เส้น Fable เดินไปหา 100% ของแคปตัวเองโดยไม่รู้ว่า
  weekly รวมเหลือเท่าไหร่. วันที่ใช้โมเดลอื่นหนัก (เช่น weekly_all 70% / Fable 20%)
  มันจะยังบอก "ใช้ Fable ได้อีก ~16%" ทั้งที่ใช้ตามนั้นแล้ว**ชน weekly_all = หยุดหมดทุกโมเดล**
  → เพิ่ม `capScopedBudget()` ใน `claude-usage.jsx`:
  ```
  room  = (เป้า weekly_all − weekly_all ปัจจุบัน) / 0.5   // 1 จุด weekly_all = 2% บน bar Fable
  เป้า Fable = min(เป้าของตัวเอง, fablePct + room)
  ```
  ตัวไหนตึงกว่าชนะ — ใช้ Fable ล้วนเส้น Fable ตึงกว่า (ไม่โดนแคป), ใช้โมเดลอื่นหนัก
  weekly รวมตึงกว่าแล้วดึง Fable ลงมา (โชว์ต่อท้ายว่า "จำกัดโดยโควตาสัปดาห์รวม").
  เป้าติดลบ (weekly รวมเกินเป้าไปแล้ว) → แสดงเป็น 0% + เส้นขีดหนีบไว้ที่ขอบซ้าย
- 🐞 **บั๊กที่เจอพร้อมกัน:** `toRows()` กรอง `weekly_scoped` ด้วย `pct > 0` → วันแรกของสัปดาห์
  ที่ Fable ยัง 0% bar หายไปทั้งแถว **แล้ว anchor ของวันนั้นไม่ถูกตั้ง** → เอาเงื่อนไขออกแล้ว
- อ้างอิง: help center "Claude Fable 5 on your plan" + ประกาศ @claudeai 2026-07-18
  (หมายเหตุ: โปรโมชัน +50% weekly ของ Claude Code จบ 20 ก.ค. เช่นกัน — ฐาน limit หดกลับก่อน
  แล้วแคป Fable 50% คิดจากฐานใหม่)

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
| `claude-usage.jsx` | ✅ widget Übersicht **แบบ A (การ์ดเต็ม)** — เรียก `claude-usage.sh --json`, เรนเดอร์จาก `limits[]`, รีเฟรช 10 นาที, สถานะ stale/error, ปุ่ม ↻ ใช้ `--force` และ**ไม่มีทางวาดทับข้อมูลดีด้วย error** (ผลเพี้ยน→คงค่าเดิม; `run()` ที่คืน Error ถูก reject ไม่ใช่ resolve), มี **CapyBeats** คาปิบาร่า sprite 72 เฟรม (8×9, CSS steps) ดุ๊กดิ๊กบนหัวการ์ด, มี **daily pacing**: weekly limit โชว์ "วันนี้ควรหยุดที่ ~X%" + เส้นขีดบน bar — anchor %ต้นวันไว้ใน localStorage (`claudeUsageDailyAnchor2`, anchor ใหม่เมื่อขึ้นวันใหม่/รอบสัปดาห์ใหม่ เฉพาะจากข้อมูลที่ fetch วันนี้จริง กัน cache ค้าง) แล้วคิด เป้า = anchor + (100−anchor)/วันที่เหลือ (**เศษทศนิยม** เป๊ะตามชั่วโมงจริงถึง reset เช่น 4.18 วัน; วันรีเซ็ตเหลือ <1 วัน → เป้าชน cap 100 = ปลดล็อกที่เหลือทั้งหมด) → ใช้เกิน/ต่ำกว่าเป้า วันถัดไปปรับโควตาเองอัตโนมัติ |
| `capybeats.png` | spritesheet คาปิบาร่า (จาก `~/.codex/pets/capybeats`) — installer copy ไป widgets เป็น `claude-usage-capy.png` (widget อ้าง relative URL ผ่าน server ของ Übersicht) |
| `install-claude-usage-widget.command` | ✅ installer ใหม่ — เช็ก/ติดตั้ง Übersicht, copy jsx + แก้ path สคริปต์ให้อัตโนมัติ, วอร์ม cache, รีเฟรช |
| `uninstall-claude-usage-widget.command` | ตัวถอน widget/Übersicht + ลบ config เก่า |
| `~/Library/Application Support/Übersicht/widgets/claude-usage.jsx` | ✅ **ติดตั้งลงแล้ว** (path สคริปต์ถูกแก้เป็น absolute แล้ว) |
| `~/.claude/usage-cache.json` | cache ก้อนล่าสุด (widget ใช้โชว์ค่าเดิมตอน token หมดอายุ) |
| `app/` | ✅ **ClaudeUsageBar** — แอป native macOS (SwiftPM, menu bar + การ์ดระดับ desktop) **แทน Übersicht**, ใช้ `claude-usage.sh --json` ตัวเดิม (bundle ไว้ใน `.app`). สเปก/บทเรียนอยู่ที่ `app/PLAN.md`. เทสต์ `cd app && swift run UsageCoreChecks` (176 ข้อ), ติดตั้ง `bash app/scripts/install-app.sh` → `~/Applications/ClaudeUsageBar.app` |

> หมายเหตุ: `widget-mockups.html` (ดีไซน์ 3 แบบ) และ installer เก่าที่ใช้ sessionKey **ไม่มีอยู่แล้ว**
> ในโฟลเดอร์ — สเปกดีไซน์แบบ A ที่เลือกไว้อยู่ท้ายไฟล์นี้ (widget สร้างตามสเปกนั้น)

---

## 🎯 สถานะงาน (อัปเดต 2026-09-17)

**✅ แอป native `ClaudeUsageBar` ใช้งานจริงแล้ว (2026-09-17):** ติดตั้งที่ `~/Applications`, เปิด
"เปิดแอปตอนล็อกอินเข้าเครื่อง" แล้ว (SMAppService: enabled/allowed — เช็กด้วย `sfltool dumpbtm | grep -A8 ClaudeUsageBar`),
ยืนยันบนเครื่องจริง: เมนูบาร์/การ์ดโชว์ตรงกับ API (session 15% · weekly 30%), CPU 0%, RAM ~55 MB, ไม่มีโปรเซสค้าง.
Übersicht ไม่ได้รันแล้ว — widget jsx เดิมยังอยู่ในโฟลเดอร์ widgets (ถอนด้วย `uninstall-claude-usage-widget.command` เมื่อพร้อม)

**✅ เก็บงานก่อน push ขึ้น GitHub สาธารณะ (2026-09-17):**
- bundle id เปลี่ยนเป็น **`io.github.panithannanti.ClaudeUsageBar`** (id เดิมผูกกับชื่อองค์กร ไม่ควรอยู่ใน repo สาธารณะ)
  → ย้าย prefs ด้วย `defaults export/import`, ปิด login item ของ id เก่าก่อน แล้วเปิดของ id ใหม่ (เช็กในเมนูแอปมี ✓)
- ปุ่ม **`>_`** ท้ายการ์ด + เมนู "เปิด terminal ที่ ~/dev" (⌘T): เปิด iTerm2 (ไม่มีใช้ Terminal.app) ที่ `~/dev`
  ด้วย `NSWorkspace.open([folder], withApplicationAt:)` — **ไม่ประกอบ shell/AppleScript จาก path** (กัน injection);
  เปลี่ยนโฟลเดอร์: `defaults write io.github.panithannanti.ClaudeUsageBar terminal.folder "~/อื่น"`; โฟลเดอร์ไม่มี → home
- security ของ `claude-usage.sh`: (1) Bearer token เคยอยู่ใน argv ของ `curl` = โปรเซสอื่นเห็นผ่าน `ps` → ส่งผ่าน stdin
  (`printf … | curl -H @-`) (2) `umask 077` → cache/log/backoff สร้างเป็น 600
  ⚠️ ที่ยังเหลือ: ตอน refresh สำเร็จ `security add-generic-password -w "$NEWBLOB"` ยังส่ง blob ใน argv ชั่วขณะ
  (`security` ไม่มีทางอ่าน password จาก stdin แบบไม่ใช้ tty) — เกิดเฉพาะตอน script refresh เอง (นานๆ ครั้ง)
- ก่อน push ทุกครั้ง scan: `git grep -nIE 'sk-ant-(oat|ort)|/Users/[a-z]|@[a-z0-9-]+\.(com|co\.th)' HEAD` + ชื่อองค์กร/โปรเจกต์อื่น
  (token ปลอมในเทสต์ = `TESTTOKEN` ได้) และเช็กทุก commit ที่ยังไม่ push ด้วย ไม่ใช่แค่ HEAD

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

**✅ Daily pacing — เป้าใช้งานรายวันบน weekly limits (เพิ่ม 2026-07-23):**
ผู้ใช้อยากรู้ว่า "วันนี้ควรหยุดใช้ที่ประมาณเท่าไหร่" แทนที่จะเห็นแค่ % สะสม
- **สูตร:** เป้าวันนี้ = `anchor + (100 − anchor) / daysLeft` — แบ่งโควตาที่**เหลือจริง**
  เท่าๆ กันตามเวลาที่เหลือถึงรีเซ็ต → วันไหนใช้เกิน/ต่ำกว่าเป้า โควตาต่อวันของวันถัดไป
  หด/ขยายเองอัตโนมัติ (adaptive ตามที่ผู้ใช้ต้องการ)
- **anchor:** จำ % ตอนต้นวันไว้ใน localStorage key `claudeUsageDailyAnchor2`
  (แยก entry ต่อ limit: `weekly_all` / `weekly_scoped:<ชื่อโมเดล>`) → เป้า**คงที่ทั้งวัน**
  ไม่วิ่งหนีตามการใช้ระหว่างวัน; re-anchor เมื่อขึ้นวันใหม่ (local date เปลี่ยน) หรือ
  `resets_at` เปลี่ยน (ขึ้นรอบสัปดาห์ใหม่) — **เฉพาะจากข้อมูลที่ `_fetched_at` เป็นวันนี้จริง**
  (กัน cache ค้างจากเมื่อวานมาตั้ง anchor เพี้ยนตอนเพิ่งตื่นเครื่อง)
- **daysLeft เป็นเศษทศนิยมเป๊ะตามชั่วโมง** (เช่น 4.18 วัน — ผู้ใช้เลือกเองหลังเทียบกับ
  แบบ ceil): ไม่มีโควตาไปกองวันสุดท้าย; วันรีเซ็ตเหลือ <1 วัน → หารด้วยค่า <1 เป้าพุ่งชน
  cap 100 = ปลดล็อกที่เหลือทั้งหมดให้ใช้ก่อนรีเซ็ต
  (key เดิม `claudeUsageDailyAnchor` ของสูตร ceil ถูกทิ้ง — เปลี่ยนชื่อ key เพื่อบังคับ re-anchor)
- **แสดงผล:** เส้นขีดขาว (`.cu-mark`) บน progress bar ที่ตำแหน่งเป้า + บรรทัด `.cu-daily`
  ใต้ bar — ปกติสีฟ้า "วันนี้ควรหยุดที่ ~X% · ใช้ได้อีก Y% · เหลือ Z.Z วัน",
  เกินเป้าเป็นสีเหลือง "เกินเป้าวันนี้ +Y% (เป้า ~X%)" — โชว์ทั้ง weekly_all และ weekly_scoped
  (session ไม่มี — pacing รายวันไม่มีความหมายกับ limit 5 ชม.)
- ทดสอบกับข้อมูลจริง: ใช้ไป 33%, เหลือ 4.18 วัน → เป้า ~49% (ใช้ได้อีก ~16%) ✓
  deploy ลง Übersicht แล้ว (sed แก้ path แบบเดียวกับ installer)
- 🐞 **บั๊ก jitter ของ `resets_at` (พบ 2026-09-17 ตอน port ไป Swift):** `resets_at` จาก API
  ขยับเศษวินาทีทุกครั้งที่ fetch (เช่น `...06:00:00.891471` vs `...06:00:01.126168` — รีเซ็ต
  เดียวกัน) → เดิม `dailyBudget()` เทียบ ISO ดิบ เห็นเป็น "รอบใหม่" เกือบทุก poll (~ทุก 10 นาที)
  → anchor รีเซ็ตทับตัวเองด้วยค่า pct ปัจจุบันตลอด = เป้าวิ่งไล่ตามการใช้งานแทนที่จะคงที่
  → **แก้:** เพิ่ม `resetKey(iso)` ปัดเป็นนาทีที่ใกล้ที่สุด (`Math.round(t/60000)`, คืน `null`
  ถ้า parse ไม่ออก) แล้วเทียบ key แทน ISO ดิบ ทั้งตอนเช็ค re-anchor และเช็ค cycle ตรงกัน;
  anchor เก่าที่ยังเก็บ ISO ดิบอยู่ (`a.reset`) ใช้ `anchorResetKey()` normalize ก่อนเทียบ
  กัน anchor วันนี้ที่มีอยู่แล้วโดนทิ้งฟรีๆ ตอน deploy รอบนี้ (`capScopedBudget` ไม่ได้เทียบ
  reset string เอง — ใช้แค่ target ตัวเลขจาก `dailyBudget` จึงไม่ต้องแก้)

---

## ดีไซน์ widget แบบ A (การ์ดเต็ม) ที่ผู้ใช้เลือก
การ์ดมุมขวาบน desktop, พื้นเข้ม glassy:
- หัว: ไอคอน ✳ (พื้นส้ม #d97757) + "Claude Usage" + ป้าย plan (เช่น "Max (20×)" — อ่านจาก credential)
- แต่ละ limit: ชื่อ + เวลา reset + progress bar (น้ำเงิน #4f7cff; เหลือง #f0a728 เมื่อ ≥80%; แดง #f0554a เมื่อ ≥95%) + "X% used"
- ท้าย: จุดเขียว + "อัปเดตล่าสุด HH:MM · รีเฟรชทุก 5 นาที"
- เวลา reset: session แสดง "รีเซ็ตใน Xh Ym", weekly แสดงวัน+เวลา (timezone ของเครื่องผู้ใช้)

ดูตัวอย่างเต็มใน `widget-mockups.html` (เปิดในเบราว์เซอร์)
