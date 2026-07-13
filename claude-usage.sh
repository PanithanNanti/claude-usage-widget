#!/bin/bash
#
# claude-usage.sh — ดึงข้อมูลการใช้งาน Claude (session / weekly / per-model)
#                   ผ่าน OAuth token ของ Claude Code (endpoint เดียวกับคำสั่ง /usage)
#
#   ใช้งาน:
#     bash claude-usage.sh                  # แสดงผลแบบอ่านง่ายใน terminal (ดีบั๊ก)
#     bash claude-usage.sh --json           # พ่น JSON (สำหรับให้ widget ใช้ต่อ)
#     bash claude-usage.sh --json --force   # ข้าม TTL cache (แต่ไม่ข้าม backoff หลัง 429)
#
# กัน 429 ที่ตัว script (ไม่ใช่ฝั่งคนเรียก):
#   • TTL cache 5 นาที (env CU_TTL) — เรียกกี่ครั้งก็ยิง API จริงไม่เกิน 1 ครั้ง/TTL
#   • เจอ 429 → พักยิง 15 นาที (env CU_BACKOFF, ไฟล์ ~/.claude/usage-backoff)
#     ระหว่างพักตอบ cache เดิมเป็น stale + _error:"rate_limit"
#   • token หมดอายุ + ต่ออายุไม่ได้ → ไม่ยิง usage เลย (เอา token เน่ายิงซ้ำๆ
#     ทุก 10 นาทีจะสะสมจน edge ตบ 429 ใส่ — เคสจริง 2026-07-13)
#   • refresh ล้มเหลว → พักลอง refresh 1 ชม. (~/.claude/usage-refresh-backoff)
#
# ทุกการยิง API จริง + ผล refresh ลง log ที่ ~/.claude/usage-widget.log (ตัดท้ายอัตโนมัติ)
#
# ไม่ต้องใส่ sessionKey — อ่าน token ที่ Claude Code เก็บไว้ (และต่ออายุให้เอง)
# ยิงที่ api.anthropic.com/api/oauth/usage → ไม่ติด Cloudflare (ต่างจาก claude.ai)
#
# โหมด --json จะ:
#   • สำเร็จ  → บันทึก cache ล่าสุดไว้ที่ ~/.claude/usage-cache.json แล้วพ่น JSON (_status:"live")
#   • ล้มเหลว → พ่น cache ก้อนล่าสุด (ถ้ามี) พร้อม _status:"stale" + _error
#              (เผื่อ token หมดอายุ/อ่าน keychain ไม่ได้ → widget ยังโชว์ค่าเดิมได้)

set -u
MODE="${1:-pretty}"
FORCE=0
for A in "$@"; do [ "$A" = "--force" ] && FORCE=1; done
# กัน HOME ไม่ถูกตั้ง (บาง launch context ของ GUI มี env น้อย) — bash `~` ดึงจาก passwd ได้แม้ HOME ว่าง
export HOME="${HOME:-$(cd ~ && pwd)}"
CACHE="$HOME/.claude/usage-cache.json"
BACKOFF_FILE="$HOME/.claude/usage-backoff"   # เก็บ epoch ที่ห้ามยิง API ก่อนถึงเวลานั้น (หลังเจอ 429)
TTL="${CU_TTL:-300}"            # cache สดกว่า 5 นาที → ตอบจาก cache ไม่ยิง API
BACKOFF="${CU_BACKOFF:-900}"    # เจอ 429 → พักยิง 15 นาที
NOW=$(date +%s)

# UA สำคัญ: Cloudflare หน้า platform.claude.com บล็อก UA แนว bot ดิบๆ
# (Python-urllib → 403 code 1010, curl default/browser → 429) — ชื่อ lib/แอปทั่วไปผ่านได้
UA="claude-usage-widget/1.0"
LOG_FILE="$HOME/.claude/usage-widget.log"
log() {
  printf '%s %s\n' "$(date '+%F %T')" "$1" >> "$LOG_FILE" 2>/dev/null
  if [ "$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE" 2>/dev/null
  fi
}

# ── 0) cap ที่ตัว script: ต่อให้ถูกเรียกถี่แค่ไหน ก็ยิง API จริงไม่เกิน 1 ครั้ง/TTL ──
#     (กัน 429 จากกรณี Übersicht reload widgets, ตื่นจาก sleep, กดรีเฟรชรัวๆ, หลายจอ)
if [ "$MODE" = "--json" ] && [ "$FORCE" = "0" ] && [ -f "$CACHE" ]; then
  AGE=$(( NOW - $(stat -f %m "$CACHE" 2>/dev/null || echo 0) ))
  if [ "$AGE" -ge 0 ] && [ "$AGE" -lt "$TTL" ]; then
    cat "$CACHE"; echo ""
    exit 0
  fi
fi
# ── 0.5) อยู่ในช่วง backoff หลัง 429 → ไม่ยิง API เลย ตอบ cache เดิม (stale) ──
#     (--force ก็ไม่ข้ามอันนี้ — 429 คือ server บอกให้พัก การยิงซ้ำมีแต่ยืดเวลาโดนแบน)
if [ "$MODE" = "--json" ] && [ -f "$BACKOFF_FILE" ]; then
  UNTIL=$(cat "$BACKOFF_FILE" 2>/dev/null || echo 0)
  case "$UNTIL" in (*[!0-9]*|"") UNTIL=0;; esac
  if [ "$NOW" -lt "$UNTIL" ]; then
    # helper emit_stale ประกาศทีหลัง — inline ตรงนี้แบบสั้นๆ
    if [ -f "$CACHE" ]; then
      CACHE="$CACHE" python3 -c '
import os, json
try: d = json.load(open(os.environ["CACHE"]))
except Exception: d = {}
d["_status"] = "stale"; d["_error"] = "rate_limit"
print(json.dumps(d))'
    else
      printf '{"_status":"error","_error":"rate_limit"}\n'
    fi
    exit 0
  fi
fi

# ── โปรแกรม python เก็บเป็นตัวแปร แล้วรันผ่าน `python3 -c` ─────────
# (ห้ามใช้ heredoc `python3 - <<EOF` คู่กับการ pipe ข้อมูลเข้า stdin
#  เพราะ heredoc จะยึด stdin ไปเป็น "โปรแกรม" ทำให้ข้อมูลที่ pipe หายไป)

PY_EXTRACT='import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
o = d.get("claudeAiOauth", d) if isinstance(d, dict) else {}
t = o.get("accessToken", "")
if t:
    print(t)'

# แปลง credential blob → ป้าย plan (เช่น "Max (20×)") ให้ widget โชว์ถูกต้องต่อคน
PY_PLAN='import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
o = d.get("claudeAiOauth", d) if isinstance(d, dict) else {}
tier = (o.get("rateLimitTier") or "").lower()
sub = (o.get("subscriptionType") or "").lower()
m = {"default_claude_max_20x": "Max (20×)", "default_claude_max_5x": "Max (5×)"}
label = m.get(tier)
if not label:
    if "pro" in tier or sub == "pro": label = "Pro"
    elif "max" in tier or sub == "max": label = "Max"
    elif sub: label = sub.capitalize()
    else: label = "Claude"
print(label)'

# โปรแกรม refresh: อ่าน blob เดิม → ใช้ refreshToken ขอ accessToken ใหม่ →
# พ่น blob ที่อัปเดตแล้ว (คงฟิลด์อื่นครบ เช่น mcpOAuth) ถ้าสำเร็จ, ไม่พ่นอะไรถ้าล้มเหลว
PY_REFRESH='import sys, os, json, time, urllib.request, urllib.error
CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"   # client_id ของ Claude Code (จากไบนารี)
ENDPOINT = "https://platform.claude.com/v1/oauth/token"
try:
    d = json.load(sys.stdin)
except Exception:
    sys.stderr.write("bad_blob"); sys.exit(1)
wrapped = isinstance(d, dict) and "claudeAiOauth" in d
o = d.get("claudeAiOauth", d) if isinstance(d, dict) else {}
rt = o.get("refreshToken")
if not rt:
    sys.stderr.write("no_refresh_token"); sys.exit(1)
body = json.dumps({"grant_type": "refresh_token", "refresh_token": rt, "client_id": CLIENT_ID}).encode()
req = urllib.request.Request(ENDPOINT, data=body,
    headers={"Content-Type": "application/json", "Accept": "application/json",
             "User-Agent": os.environ.get("UA") or "claude-usage-widget/1.0"}, method="POST")
try:
    with urllib.request.urlopen(req, timeout=15) as r:
        tok = json.load(r)
except urllib.error.HTTPError as e:
    try: detail = e.read().decode("utf-8", "replace")[:200].replace("\n", " ")
    except Exception: detail = ""
    sys.stderr.write("http %s %s" % (e.code, detail)); sys.exit(1)
except Exception as e:
    sys.stderr.write(str(e)[:200]); sys.exit(1)
at = tok.get("access_token")
if not at:
    sys.stderr.write("no_access_token_in_response"); sys.exit(1)
o["accessToken"] = at
if tok.get("refresh_token"): o["refreshToken"] = tok["refresh_token"]
if tok.get("expires_in"): o["expiresAt"] = int((time.time() + int(tok["expires_in"])) * 1000)
if wrapped: d["claudeAiOauth"] = o; out = d
else: out = o
print(json.dumps(out))'

# ── 1) หา OAuth access token ของ Claude Code ────────────────────
USER_NAME="${USER:-$(id -un)}"
TOKEN=""
CRED_BLOB=""
CRED_SRC=""   # แหล่งที่มา: "file:<path>" หรือ "keychain:<service>" (ใช้ตอนเขียน token ใหม่กลับ)

# 1a) ไฟล์ ~/.claude/.credentials.json (บาง setup เก็บที่นี่)
CRED_FILE="$HOME/.claude/.credentials.json"
if [ -z "$TOKEN" ] && [ -f "$CRED_FILE" ]; then
  CRED_BLOB=$(cat "$CRED_FILE" 2>/dev/null)
  TOKEN=$(printf '%s' "$CRED_BLOB" | python3 -c "$PY_EXTRACT" 2>/dev/null)
  [ -n "$TOKEN" ] && CRED_SRC="file:$CRED_FILE"
fi

# 1b) macOS Keychain — service "Claude Code-credentials", account = ชื่อผู้ใช้
#     (ยืนยันแล้วบนเครื่องนี้: /usr/bin/security อ่านได้โดยไม่มี prompt แม้จาก GUI context)
if [ -z "$TOKEN" ] && command -v security >/dev/null 2>&1; then
  for SVC in "Claude Code-credentials" "Claude Code"; do
    BLOB=$(security find-generic-password -a "$USER_NAME" -w -s "$SVC" 2>/dev/null) \
      || BLOB=$(security find-generic-password -w -s "$SVC" 2>/dev/null)
    if [ -n "${BLOB:-}" ]; then
      TOKEN=$(printf '%s' "$BLOB" | python3 -c "$PY_EXTRACT" 2>/dev/null)
      [ -n "$TOKEN" ] && { CRED_BLOB="$BLOB"; CRED_SRC="keychain:$SVC"; break; }
    fi
  done
fi

# ── 1.5) auto-refresh: ต่ออายุ accessToken ด้วย refreshToken ────
# สถานะ token: ok (เหลือ >15 นาที) / near (ใกล้หมด) / expired (ตายแล้ว)
TOKEN_STATE="ok"
if [ -n "$CRED_BLOB" ]; then
  TOKEN_STATE=$(printf '%s' "$CRED_BLOB" | python3 -c '
import sys, json, time
try: d = json.load(sys.stdin)
except Exception: print("ok"); sys.exit(0)
o = d.get("claudeAiOauth", d) if isinstance(d, dict) else {}
exp = (o.get("expiresAt") or 0) / 1000
left = exp - time.time()
# buffer 900s (>รอบ poll 10 นาที) → จับ token ต่ออายุก่อนหมดได้ทัน
print("expired" if left <= 0 else ("near" if left < 900 else "ok"))' 2>/dev/null)
  [ -n "$TOKEN_STATE" ] || TOKEN_STATE="ok"
fi

REFRESH_BACKOFF_FILE="$HOME/.claude/usage-refresh-backoff"
REFRESH_OK=0
WANT_REFRESH=0
case "$TOKEN_STATE" in
  expired) WANT_REFRESH=1 ;;
  near)
    # ยังไม่ตายและ Claude Code รันอยู่ → ให้มันต่ออายุเอง
    # (กัน refresh token ชนกัน — ถ้า token เป็นแบบหมุนทิ้งหลังใช้ การแย่งกัน refresh
    #  อาจทำให้ฝั่งใดฝั่งหนึ่งถือ token ตายและเด้งให้ล็อกอินใหม่)
    pgrep -qx claude 2>/dev/null || WANT_REFRESH=1 ;;
esac
if [ "$WANT_REFRESH" = "1" ] && [ -f "$REFRESH_BACKOFF_FILE" ]; then
  RUNTIL=$(cat "$REFRESH_BACKOFF_FILE" 2>/dev/null || echo 0)
  case "$RUNTIL" in (*[!0-9]*|"") RUNTIL=0;; esac
  [ "$NOW" -lt "$RUNTIL" ] && WANT_REFRESH=0
fi

if [ "$WANT_REFRESH" = "1" ]; then
  RERR=$(mktemp "${TMPDIR:-/tmp}/cu-refresh-err.XXXXXX" 2>/dev/null || echo /dev/null)
  NEWBLOB=$(printf '%s' "$CRED_BLOB" | UA="$UA" python3 -c "$PY_REFRESH" 2>"$RERR")
  if [ -n "$NEWBLOB" ]; then
    # เขียน blob ใหม่กลับแหล่งเดิม (เฉพาะตอน refresh สำเร็จ)
    case "$CRED_SRC" in
      keychain:*)
        W_SVC="${CRED_SRC#keychain:}"
        security add-generic-password -U -a "$USER_NAME" -s "$W_SVC" -w "$NEWBLOB" 2>/dev/null
        ;;
      file:*)
        W_FILE="${CRED_SRC#file:}"
        umask 077; printf '%s' "$NEWBLOB" > "$W_FILE.tmp" 2>/dev/null && mv "$W_FILE.tmp" "$W_FILE" 2>/dev/null
        ;;
    esac
    NT=$(printf '%s' "$NEWBLOB" | python3 -c "$PY_EXTRACT" 2>/dev/null)
    [ -n "$NT" ] && { TOKEN="$NT"; CRED_BLOB="$NEWBLOB"; REFRESH_OK=1; }
    rm -f "$REFRESH_BACKOFF_FILE" 2>/dev/null
    log "refresh ok (token was $TOKEN_STATE)"
  else
    echo $(( NOW + 3600 )) > "$REFRESH_BACKOFF_FILE" 2>/dev/null
    log "refresh FAIL: $(tr '\n' ' ' < "$RERR" 2>/dev/null) (token $TOKEN_STATE, พัก 1h)"
  fi
  [ "$RERR" != "/dev/null" ] && rm -f "$RERR" 2>/dev/null
fi

# ป้าย plan (จาก credential blob) — ใช้กับ widget
PLAN="Max"
if [ -n "$CRED_BLOB" ]; then
  P=$(printf '%s' "$CRED_BLOB" | python3 -c "$PY_PLAN" 2>/dev/null)
  [ -n "$P" ] && PLAN="$P"
fi

# ── helper: พ่น cache เดิม (stale) หรือ error ให้ --json ─────────
emit_stale() {  # $1 = เหตุผล error
  if [ -f "$CACHE" ]; then
    CACHE="$CACHE" REASON="$1" python3 -c '
import os, json
try:
    d = json.load(open(os.environ["CACHE"]))
except Exception:
    d = {}
d["_status"] = "stale"
d["_error"] = os.environ["REASON"]
print(json.dumps(d))'
  else
    printf '{"_status":"error","_error":"%s"}\n' "$1"
  fi
}

if [ -z "$TOKEN" ]; then
  if [ "$MODE" = "--json" ]; then
    emit_stale "no_token"
  else
    echo "❌ หา OAuth token ของ Claude Code ไม่เจอ"
    echo "   เปิด Claude Code (พิมพ์ claude) สักครั้งเพื่อให้แน่ใจว่าล็อกอินอยู่ แล้วรันใหม่"
  fi
  exit 0
fi

# token ตายและต่ออายุไม่สำเร็จ → หยุดตรงนี้ ไม่เอา token เน่าไปยิง usage
# (ยิงซ้ำทุก 10 นาทีข้ามคืน = สะสม 401 จน edge ตบ 429 ใส่ทั้ง IP — เคสจริง 2026-07-13)
if [ "$TOKEN_STATE" = "expired" ] && [ "$REFRESH_OK" = "0" ]; then
  log "skip usage: token expired + refresh ไม่สำเร็จ"
  if [ "$MODE" = "--json" ]; then
    emit_stale "auth"
  else
    echo "❌ token หมดอายุและต่ออายุเองไม่ได้ — เปิด Claude Code (claude) เพื่อรีเฟรช token"
  fi
  exit 0
fi

# ── 2) เรียก endpoint usage (เก็บ HTTP status ด้วย) ─────────────
RAW=$(curl -s -m 15 -w $'\n%{http_code}' https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "User-Agent: $UA" \
  -H "Content-Type: application/json")
CODE="${RAW##*$'\n'}"     # บรรทัดสุดท้าย = http code
RESP="${RAW%$'\n'*}"      # ที่เหลือ = body

# แยกประเภท error ตาม HTTP status (429 = rate limit ≠ 401 = auth)
REASON=""
if [ "$CODE" = "200" ] && printf '%s' "$RESP" | grep -q 'utilization'; then
  REASON=""   # สำเร็จ
  rm -f "$BACKOFF_FILE" 2>/dev/null
  log "usage ok"
else
  case "$CODE" in
    401|403) REASON="auth" ;;        # token หมดอายุ/ถูกปฏิเสธจริง
    429)     REASON="rate_limit"     # ยิงถี่ไป — พักยิง $BACKOFF วิ ก่อนลองใหม่
             echo $(( NOW + BACKOFF )) > "$BACKOFF_FILE" 2>/dev/null ;;
    "")      REASON="network" ;;     # ต่อเน็ตไม่ได้/timeout
    *)       REASON="http_$CODE" ;;
  esac
  log "usage FAIL http=${CODE:-none} ($REASON)"
fi

if [ -n "$REASON" ]; then
  if [ "$MODE" = "--json" ]; then
    emit_stale "$REASON"   # โชว์ค่าเดิม + บอกเหตุผลจริง
  else
    case "$REASON" in
      auth)       echo "❌ token หมดอายุ/ถูกปฏิเสธ — เปิด Claude Code (claude) เพื่อรีเฟรช token" ;;
      rate_limit) echo "⏳ โดน rate limit (429) — ยิงถี่ไป รออีกสักครู่แล้วลองใหม่" ;;
      network)    echo "📡 ต่อ API ไม่ได้ — เช็กอินเทอร์เน็ต" ;;
      *)          echo "❌ ดึงข้อมูลไม่ได้ (HTTP ${CODE:-?})" ;;
    esac
  fi
  exit 0
fi

# ── 3) โหมด JSON: ฝัง _status/_fetched_at, บันทึก cache, แล้วพ่น ──
if [ "$MODE" = "--json" ]; then
  OUT=$(printf '%s' "$RESP" | PLAN="$PLAN" python3 -c '
import sys, os, json, datetime
try:
    d = json.load(sys.stdin)
except Exception:
    print("{\"_status\":\"error\",\"_error\":\"bad_json\"}"); sys.exit(0)
d["_status"] = "live"
d["_plan"] = os.environ.get("PLAN") or "Claude"
d["_fetched_at"] = datetime.datetime.now().astimezone().isoformat()
print(json.dumps(d))')
  # เขียน cache แบบ atomic (เผื่อคราวหน้าดึงไม่ได้ จะได้มีของเดิมโชว์)
  mkdir -p "$HOME/.claude" 2>/dev/null
  if printf '%s' "$OUT" > "$CACHE.tmp" 2>/dev/null; then
    mv "$CACHE.tmp" "$CACHE" 2>/dev/null
  fi
  printf '%s\n' "$OUT"
  exit 0
fi

# ── 4) โหมดอ่านง่าย: เรนเดอร์จาก limits[] (มี label + per-model) ──
printf '%s' "$RESP" | PLAN="$PLAN" python3 -c '
import sys, os, json, datetime

try:
    d = json.load(sys.stdin)
except Exception:
    print("  ❌ อ่าน response ไม่ได้"); sys.exit(0)

def bar(pct, width=24):
    pct = max(0, min(100, int(round(pct))))
    filled = pct * width // 100
    return "[" + "#" * filled + "·" * (width - filled) + "] %d%%" % pct

def parse_iso(s):
    if not s:
        return None
    try:
        return datetime.datetime.fromisoformat(s).astimezone()
    except Exception:
        return None

def rel(dt):
    if not dt:
        return ""
    diff = max(0, (dt - datetime.datetime.now().astimezone()).total_seconds())
    return "รีเซ็ตใน %dh %dm" % (diff // 3600, (diff % 3600) // 60)

def when(dt):
    return dt.strftime("รีเซ็ต %a %d/%m %H:%M") if dt else ""

rows = []
limits = d.get("limits") or []
if limits:
    for lim in limits:
        kind = lim.get("kind"); pct = lim.get("percent", 0) or 0
        rst = parse_iso(lim.get("resets_at"))
        if kind == "session":
            rows.append(("Current session", pct, rel(rst)))
        elif kind == "weekly_all":
            rows.append(("Current week", pct, when(rst)))
        elif kind == "weekly_scoped":
            name = (((lim.get("scope") or {}).get("model") or {}).get("display_name")) or "scoped"
            rows.append(("Weekly · " + name, pct, when(rst)))
else:
    fh = d.get("five_hour") or {}; sd = d.get("seven_day") or {}
    rows.append(("Current session", fh.get("utilization", 0), rel(parse_iso(fh.get("resets_at")))))
    rows.append(("Current week", sd.get("utilization", 0), when(parse_iso(sd.get("resets_at")))))

print("")
print("  ✳  Claude Usage  ·  " + (os.environ.get("PLAN") or "Claude"))
print("  " + "─" * 44)
for label, pct, sub in rows:
    print("  %-16s %s" % (label, bar(pct)))
    if sub:
        print("  %-16s %s" % ("", sub))
print("  " + "─" * 44)
print("  อัปเดต " + datetime.datetime.now().strftime("%H:%M น. %d/%m/%Y"))
print("")'
