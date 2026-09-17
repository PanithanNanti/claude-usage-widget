// claude-usage.jsx — Übersicht widget แสดง Claude plan usage (แบบ A · การ์ดเต็ม)
//
// ดึงข้อมูลจาก claude-usage.sh --json (OAuth token ของ Claude Code)
// ยิงตรง api.anthropic.com/api/oauth/usage — ไม่ยุ่ง claude.ai/Cloudflare
//
// ฟีเจอร์:
//   • การ์ด glassy — session / weekly / per-model + ป้าย plan อัตโนมัติ
//   • ลากย้ายที่แถบหัว (จำตำแหน่ง)  • ปุ่ม ✕ ย่อเป็นวงกลมเล็ก (คลิกกางคืน)
//   • 🖥️ เลือกจอจาก dropdown (หลายจอ) — คลิกแล้วย้ายไปจอนั้นทันที
//   • ↻ Refresh now  • 🔑 เปิด Claude ล็อกอิน/รีเฟรช token เมื่อ session หลุด

import { run } from "uebersicht";

// installer จะแก้บรรทัด command นี้ให้ชี้ path จริงในเครื่องโดยอัตโนมัติ
// (ถ้าติดตั้งเอง: เปลี่ยน /PATH/TO ให้เป็น absolute path ของ repo นี้)
export const command =
  "bash /PATH/TO/claude-usage.sh --json";

const CMD = command;
export const refreshFrequency = 600000; // 10 นาที (เบาต่อ rate limit; usage ไม่ต้องสดวินาทีต่อวินาที)

export const className = `
  font-family: -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif;
  color: #ececf1;
  -webkit-font-smoothing: antialiased;

  .cu-card {
    position: fixed; top: 20px; right: 20px; width: 320px;
    box-sizing: border-box;
    background: rgba(24, 24, 28, 0.72);
    backdrop-filter: blur(24px) saturate(140%);
    -webkit-backdrop-filter: blur(24px) saturate(140%);
    border: 1px solid rgba(255, 255, 255, 0.09);
    border-radius: 18px; padding: 18px 20px 15px;
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.45);
  }

  .cu-head { display: flex; align-items: center; gap: 10px; margin-bottom: 16px;
    cursor: move; user-select: none; -webkit-user-select: none; }
  .cu-head:active { cursor: grabbing; }
  .cu-logo { width: 26px; height: 26px; border-radius: 8px; background: #d97757;
    display: flex; align-items: center; justify-content: center;
    font-size: 15px; color: #fff; flex-shrink: 0; }
  .cu-title { font-size: 14px; font-weight: 600; letter-spacing: 0.2px; }
  .cu-badge { margin-left: auto; font-size: 10.5px; font-weight: 600;
    padding: 3px 9px; border-radius: 999px;
    background: rgba(217, 119, 87, 0.16); color: #e8a48a;
    border: 1px solid rgba(217, 119, 87, 0.3); }
  .cu-close { cursor: pointer; font-size: 14px; line-height: 1; color: #8a8a93;
    padding: 2px 4px; border-radius: 6px; flex-shrink: 0; }
  .cu-close:hover { color: #fff; background: rgba(255,255,255,0.12); }

  .cu-row { margin-bottom: 13px; }
  .cu-row:last-child { margin-bottom: 4px; }
  .cu-row-top { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 6px; }
  .cu-name { font-size: 12.5px; font-weight: 500; color: #f2f2f5; }
  .cu-pct { font-size: 11.5px; font-weight: 600; color: #b6b6be; }
  .cu-reset { font-size: 10.5px; color: #86868f; margin-top: 5px; }
  .cu-track { position: relative; height: 7px; border-radius: 999px; background: rgba(255,255,255,0.08); overflow: hidden; }
  .cu-fill { height: 100%; border-radius: 999px; transition: width 0.4s ease; }
  .cu-mark { position: absolute; top: 0; width: 2px; height: 100%;
    background: rgba(255,255,255,0.85); box-shadow: 0 0 3px rgba(0,0,0,0.6); }
  .cu-daily { font-size: 10px; color: #9db4e8; margin-top: 4px; }
  .cu-daily.over { color: #f0a728; }
  .cu-err { font-size: 12px; color: #d6d6dc; line-height: 1.55; padding: 4px 0 8px; }

  .cu-foot { display: flex; align-items: center; gap: 7px; margin-top: 14px;
    padding-top: 12px; border-top: 1px solid rgba(255,255,255,0.07);
    font-size: 10.5px; color: #86868f; }
  .cu-dot { width: 7px; height: 7px; border-radius: 50%; flex-shrink: 0; }
  .cu-foot-text { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .cu-actions { margin-left: auto; display: flex; gap: 6px; flex-shrink: 0; position: relative; }
  .cu-btn { cursor: pointer; font-size: 10px; color: #9a9aa2;
    background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.09);
    border-radius: 6px; padding: 2px 8px; white-space: nowrap;
    user-select: none; -webkit-user-select: none; }
  .cu-btn:hover { color: #ececf1; background: rgba(255,255,255,0.12); }
  .cu-btn:active { transform: translateY(1px); }
  .cu-btn.spin { color: #4f7cff; }
  .cu-btn.cu-login { color: #e8a48a; border-color: rgba(217,119,87,0.32); }
  .cu-btn.cu-login:hover { color: #fff; background: rgba(217,119,87,0.28); }

  /* dropdown เลือกจอ */
  .cu-dd { position: absolute; right: 0; bottom: 26px; min-width: 168px;
    background: rgba(32,32,37,0.98);
    backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
    border: 1px solid rgba(255,255,255,0.12); border-radius: 10px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.5); padding: 5px;
    display: none; z-index: 50; }
  .cu-dd.open { display: block; }
  .cu-dd-title { font-size: 9.5px; color: #75757d; padding: 3px 8px 5px; text-transform: none; }
  .cu-dd-item { font-size: 11px; color: #d6d6dc; padding: 6px 9px; border-radius: 7px;
    cursor: pointer; white-space: nowrap; display: flex; align-items: center; gap: 6px; }
  .cu-dd-item:hover { background: rgba(255,255,255,0.1); }
  .cu-dd-item.cur { color: #fff; background: rgba(79,124,255,0.22); }
  .cu-dd-item.cur:after { content: "✓"; margin-left: auto; color: #7fa0ff; }

  /* วงกลมย่อ (collapsed) */
  .cu-pill { position: fixed; top: 20px; right: 20px;
    min-width: 46px; height: 46px; border-radius: 14px; padding: 0 10px;
    background: rgba(24,24,28,0.72);
    backdrop-filter: blur(24px) saturate(140%); -webkit-backdrop-filter: blur(24px) saturate(140%);
    border: 1px solid rgba(255,255,255,0.09); box-shadow: 0 8px 26px rgba(0,0,0,0.42);
    display: flex; align-items: center; justify-content: center; gap: 6px;
    cursor: pointer; user-select: none; -webkit-user-select: none; }
  .cu-pill:hover { border-color: rgba(255,255,255,0.2); }
  .cu-pill-logo { width: 22px; height: 22px; border-radius: 7px; background: #d97757;
    display: flex; align-items: center; justify-content: center; font-size: 13px; color: #fff; }
  .cu-pill-pct { font-size: 12px; font-weight: 600; color: #ececf1; }
`;

// ════════════════ helpers ════════════════
function esc(s) {
  return String(s).replace(/[&<>"]/g, function (c) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
  });
}
function barColor(pct) { return pct >= 95 ? "#f0554a" : pct >= 80 ? "#f0a728" : "#4f7cff"; }
function pad2(n) { return n < 10 ? "0" + n : "" + n; }
function fmtClock(d) { return pad2(d.getHours()) + ":" + pad2(d.getMinutes()); }
function resetRelative(iso) {
  if (!iso) return "";
  let diff = Math.max(0, Math.floor((new Date(iso).getTime() - Date.now()) / 1000));
  return "รีเซ็ตใน " + Math.floor(diff / 3600) + "ชม. " + Math.floor((diff % 3600) / 60) + "นาที";
}
function resetAbsolute(iso) {
  if (!iso) return "";
  const d = new Date(iso), days = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"];
  return "รีเซ็ต " + days[d.getDay()] + " " + d.getDate() + "/" + pad2(d.getMonth() + 1) + " " + fmtClock(d);
}
// ── เป้าใช้งานรายวัน (daily pacing) สำหรับ weekly limits ──
// หลักการ: แบ่งโควตาที่ "เหลือจริง" เท่าๆ กันตามจำนวนวันที่เหลือถึงรีเซ็ต
// ต้นวันแรกที่เห็นข้อมูล → anchor ค่า % ไว้ แล้วเป้าวันนี้ = anchor + (100−anchor)/วันที่เหลือ
// เป้าคงที่ทั้งวัน (ไม่ขยับตามการใช้ระหว่างวัน) — พอขึ้นวันใหม่ค่อย anchor ใหม่จากค่าจริง
// → วันไหนใช้เกิน/ต่ำกว่าเป้า โควตาต่อวันของวันถัดๆ ไปจะปรับลด/เพิ่มให้เองอัตโนมัติ
const ANCHOR_KEY = "claudeUsageDailyAnchor2"; // v2: daysLeft เป็นเศษทศนิยม (เป๊ะตามชั่วโมง)
function dayKeyLocal(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()); }
// resets_at จาก API jitter เศษวินาที (เช่น ...:00.891471 vs ...:01.126168 ของรีเซ็ตเดียวกัน)
// เทียบ ISO ดิบตรงๆ เลยเห็นเป็น "รอบใหม่" เกือบทุก poll → anchor รีเซ็ตทุก ~10 นาที เป้าวิ่งตามการใช้
// ปัดลง key เป็นนาทีที่ใกล้ที่สุดแทน กันค่าที่คร่อมวินาที :59.xx/:00.xx ให้ตกคนละนาทีจริงๆ เท่านั้น
function resetKey(iso) {
  const t = new Date(iso).getTime();
  return isNaN(t) ? null : String(Math.round(t / 60000));
}
// anchor เก่า (ก่อนแก้ bug นี้) เก็บ ISO ดิบไว้ใน a.reset → normalize ให้เทียบกับ key ใหม่ได้
// (resetKey parse ไม่ออกแปลว่าเป็น key ที่ normalize แล้วอยู่แล้ว คืนค่าเดิมกลับไป) กัน anchor
// วันนี้ที่มีอยู่แล้วโดน re-anchor ทิ้งฟรีๆ ตอน deploy รอบนี้
function anchorResetKey(raw) { const k = resetKey(raw); return k != null ? k : raw; }
function dailyBudget(id, pct, resetIso, fetchedIso) {
  if (!resetIso) return null;
  const now = new Date(), msLeft = new Date(resetIso).getTime() - now.getTime();
  if (!(msLeft > 0)) return null;
  const daysLeft = msLeft / 86400000; // เศษทศนิยม เช่น 4.18 วัน — เศษวันท้ายได้โควตาตามสัดส่วนชั่วโมงจริง
  // ต่ำกว่า 1 วัน (วันรีเซ็ต) → หารด้วยค่า <1 ทำให้เป้าพุ่งถึง 100 (ถูก cap) = ปลดล็อกโควตาที่เหลือทั้งหมด
  const rKey = resetKey(resetIso);
  if (rKey == null) return null;
  let store = {};
  try { store = JSON.parse(lsGet(ANCHOR_KEY)) || {}; } catch (e) {}
  const today = dayKeyLocal(now);
  let a = store[id];
  // anchor ใหม่เมื่อขึ้นวันใหม่/ขึ้นรอบสัปดาห์ใหม่ — เฉพาะจากข้อมูลที่ดึงมา "วันนี้" จริงๆ
  // (กัน cache ค้างจากเมื่อวานมาตั้ง anchor ต่ำเกินตอนเพิ่งตื่นเครื่อง)
  const fetchedToday = fetchedIso && dayKeyLocal(new Date(fetchedIso)) === today;
  if ((!a || a.day !== today || anchorResetKey(a.reset) !== rKey) && fetchedToday) {
    a = { day: today, pct: pct, days: daysLeft, reset: rKey };
    store[id] = a; lsSet(ANCHOR_KEY, JSON.stringify(store));
  }
  if (!a || anchorResetKey(a.reset) !== rKey) return null;
  const target = Math.min(100, a.pct + (100 - a.pct) / a.days);
  return { target: target, left: target - pct, days: daysLeft };
}
// ── แคปเป้าของ bar per-model (เช่น Fable) ด้วยโควตาที่ weekly รวมเหลือให้วันนี้ ──
// bar per-model คิด % เทียบ "แคป 50% ของตัวเอง" → 1 จุดบน weekly_all = 2% บน bar นี้
// เป้าของมันจึงเดินตามจังหวะตัวเองได้แค่เท่าที่ weekly รวมยังเหลือให้ ไม่งั้นเดินตามเส้น
// per-model แล้วไปชน weekly_all ก่อน = หยุดหมดทุกโมเดล (ดูกฎ Fable 50% ใน CLAUDE.md)
const SCOPED_SHARE = 0.5; // สัดส่วนของ weekly รวมที่ bar per-model กินได้เต็มที่
function capScopedBudget(b, pct, allPct, allB) {
  if (!b || !allB || allPct == null) return b;
  const room = (allB.target - allPct) / SCOPED_SHARE; // weekly รวมเหลือให้อีกกี่ % บนสเกลของ bar นี้
  const capped = Math.min(b.target, pct + room);
  if (capped >= b.target - 0.05) return b; // เส้นตัวเองตึงกว่าอยู่แล้ว — ไม่ต้องแคป
  return { target: capped, left: capped - pct, days: b.days, capped: true };
}
function toRows(data) {
  const rows = [], limits = (data && data.limits) || [];
  const fetched = data && data._fetched_at;
  if (limits.length) {
    // weekly_all ต้องคิดก่อน — bar per-model เอาโควตาที่ weekly รวมเหลือให้มาแคปเป้าอีกชั้น
    const all = limits.find((l) => l.kind === "weekly_all");
    const allPct = all ? (all.percent || 0) : null;
    const allBudget = all ? dailyBudget("weekly_all", allPct, all.resets_at, fetched) : null;
    for (const lim of limits) {
      const pct = Math.round(lim.percent || 0);
      if (lim.kind === "session") rows.push({ name: "เซสชันปัจจุบัน", pct, reset: resetRelative(lim.resets_at) });
      else if (lim.kind === "weekly_all") rows.push({ name: "สัปดาห์นี้ (ทุกโมเดล)", pct, reset: resetAbsolute(lim.resets_at),
        budget: allBudget });
      else if (lim.kind === "weekly_scoped") {
        // ไม่กรอง pct > 0 แล้ว — วันแรกของสัปดาห์ที่ยัง 0% ต้องโชว์ ไม่งั้น anchor ไม่ถูกตั้ง
        const nm = ((lim.scope || {}).model || {}).display_name || "โมเดล";
        const own = dailyBudget("weekly_scoped:" + nm, lim.percent || 0, lim.resets_at, fetched);
        rows.push({ name: "สัปดาห์ · " + nm, pct, reset: resetAbsolute(lim.resets_at),
          budget: capScopedBudget(own, lim.percent || 0, allPct, allBudget) });
      }
    }
  } else if (data) {
    const fh = data.five_hour || {}, sd = data.seven_day || {};
    rows.push({ name: "เซสชันปัจจุบัน", pct: Math.round(fh.utilization || 0), reset: resetRelative(fh.resets_at) });
    rows.push({ name: "สัปดาห์นี้ (ทุกโมเดล)", pct: Math.round(sd.utilization || 0), reset: resetAbsolute(sd.resets_at),
      budget: dailyBudget("weekly_all", sd.utilization || 0, sd.resets_at, fetched) });
  }
  return rows;
}
function sessionPct(data) {
  const r = toRows(data).find((x) => x.name === "เซสชันปัจจุบัน");
  return r ? r.pct : null;
}
// แปลงรหัส error → ข้อความ + ต้องโชว์ปุ่มกุญแจไหม (rate limit/network ไม่ต้องล็อกอิน)
function errInfo(err) {
  switch (err) {
    case "no_token": return { msg: "ยังไม่ได้ล็อกอิน Claude Code หรือหา token ไม่เจอ", short: "ยังไม่ได้ล็อกอิน", login: true };
    case "auth": return { msg: "token หมดอายุ — เปิด Claude เพื่อรีเฟรช", short: "token หมดอายุ", login: true };
    case "rate_limit": return { msg: "โดน rate limit (429) — พักยิง ~15 นาทีแล้วลองใหม่เอง", short: "พัก 429 · รอรอบใหม่", login: false };
    case "network": return { msg: "ต่ออินเทอร์เน็ตไม่ได้", short: "เน็ตมีปัญหา", login: false };
    default: return { msg: "ดึงข้อมูลไม่ได้", short: "ดึงข้อมูลไม่ได้", login: false };
  }
}

// ════════════════ localStorage state ════════════════
const POS_KEY = "claudeUsageWidgetPos";
const SCREEN_KEY = "claudeUsageWidgetScreen";
const SCREENS_KEY = "claudeUsageScreens";
const COLLAPSE_KEY = "claudeUsageWidgetCollapsed";
function lsGet(k) { try { return window.localStorage.getItem(k); } catch (e) { return null; } }
function lsSet(k, v) { try { window.localStorage.setItem(k, v); } catch (e) {} }
function lsDel(k) { try { window.localStorage.removeItem(k); } catch (e) {} }

function savedPos() {
  try { const p = JSON.parse(lsGet(POS_KEY)); if (p && typeof p.left === "number" && typeof p.top === "number") return p; } catch (e) {}
  return null;
}
function posAttr() {
  const p = savedPos();
  return p ? ' style="top:' + p.top + "px;left:" + p.left + "px;right:auto\"" : "";
}

// ── screens registry ──
function thisScreenSig() {
  const s = window.screen || {};
  return (s.width || window.innerWidth) + "x" + (s.height || window.innerHeight);
}
function chosenScreen() { return lsGet(SCREEN_KEY); }
function registerThisScreen() {
  let reg = {};
  try { reg = JSON.parse(lsGet(SCREENS_KEY)) || {}; } catch (e) {}
  const s = window.screen || {}, sig = thisScreenSig(), now = Date.now();
  reg[sig] = { sig, w: s.width || window.innerWidth, h: s.height || window.innerHeight, ts: now };
  for (const k in reg) { if (now - (reg[k].ts || 0) > 600000) delete reg[k]; } // ตัดจอที่หายเกิน 10 นาที
  lsSet(SCREENS_KEY, JSON.stringify(reg));
}
// จอนี้ยังมี widget instance เต้นอยู่ไหม (heartbeat ทุก ~15 วิ จากลูป sync ด้านล่าง)
const SCREEN_ALIVE_MS = 60000;
function screenAlive(sig) {
  try {
    const reg = JSON.parse(lsGet(SCREENS_KEY)) || {};
    return !!reg[sig] && Date.now() - (reg[sig].ts || 0) < SCREEN_ALIVE_MS;
  } catch (e) { return false; }
}
function listScreens() {
  try {
    const reg = JSON.parse(lsGet(SCREENS_KEY)) || {};
    return Object.keys(reg).map((k) => reg[k]).sort((a, b) => b.w * b.h - a.w * a.h);
  } catch (e) { return []; }
}
function screenLabel(w, h) {
  const base = w + "×" + h;
  if (w >= 2560 && w > h) return base + " (ไวด์)";
  if (h > w) return base + " (แนวตั้ง)";
  return base;
}
// ซ่อน/โชว์ตามจอที่เลือก — เขียน DOM เฉพาะตอนค่าเปลี่ยน (กันแฟลชจาก backdrop-filter)
function applyScreenVisibility() {
  const root = document.querySelector(".cu-root");
  if (!root) return;
  const el = root.firstElementChild; // .cu-card หรือ .cu-pill
  if (!el) return;
  const chosen = chosenScreen(), sig = thisScreenSig();
  // จอที่ล็อกไว้ต้อง "ยังต่ออยู่จริง" ถึงจะซ่อนจออื่น — ไม่งั้นถอดจอนั้น (หรือ OS อัปเดตแล้วจอหาย)
  // = widget ซ่อนตัวเองทุกจอ (บั๊กจริง 2026-09-17). ค่าที่ล็อกไว้ไม่ถูกลบ → เสียบจอกลับมาก็ย้ายไปเอง
  const wantHidden = !!chosen && chosen !== sig && screenAlive(chosen);
  const isHidden = el.style.display === "none";
  if (wantHidden !== isHidden) el.style.display = wantHidden ? "none" : "";
}
// กันการ์ดตกนอกขอบจอ (เช่น ตำแหน่งที่บันทึกจากจอกว้าง แล้วย้ายมาจอเล็ก/แนวตั้ง)
// เขียน style เฉพาะตอนหลุดจอจริง → ไม่แฟลช
function ensureOnScreen(el) {
  if (!el || el.style.display === "none") return;
  const rect = el.getBoundingClientRect();
  if (!rect.width) return;
  // การ์ดที่มีคาปิบาร่าเกาะหัว ต้องเผื่อที่ด้านบนให้น้องโผล่พ้นจอด้วย
  const minTop = el.querySelector(".cu-capy") ? 8 + (typeof CAPY_OVERHANG !== "undefined" ? CAPY_OVERHANG : 96) : 8;
  const maxLeft = window.innerWidth - rect.width - 8, maxTop = window.innerHeight - rect.height - 8;
  let left = rect.left, top = rect.top, changed = false;
  if (left > maxLeft) { left = Math.max(8, maxLeft); changed = true; }
  if (top > maxTop) { top = Math.max(minTop, maxTop); changed = true; }
  if (left < 8) { left = 8; changed = true; }
  if (top < minTop) { top = minTop; changed = true; }
  if (changed) { el.style.left = left + "px"; el.style.top = top + "px"; el.style.right = "auto"; }
}
// เรียกท้าย paint + ในลูป sync
function finishPaint(root) {
  applyScreenVisibility();
  const el = root && root.firstElementChild;
  if (el) ensureOnScreen(el);
}
// เคลียร์ timer เก่าทุกครั้งที่โมดูลถูกโหลดใหม่ — ไม่งั้น hot-reload จะเหลือ closure ของโค้ดรุ่นเก่ารันต่อ
if (typeof window !== "undefined") {
  if (window.__cuVisTimer) clearInterval(window.__cuVisTimer);
  window.__cuVisTimer = setInterval(function () {
    const now = Date.now();
    if (now - (window.__cuScreenBeat || 0) > 15000) { window.__cuScreenBeat = now; registerThisScreen(); } // heartbeat ให้ screenAlive()
    finishPaint(document.querySelector(".cu-root")); // sync ข้ามจอ + กันหลุดจอ (change-guarded ไม่แฟลช)
  }, 1500);
}

// ════════════════ actions ════════════════
// run() ของ Übersicht คืน Promise (ยืนยันจาก client.js) — เผื่อ callback ไว้ด้วยให้ทน
function doRun(cmd) {
  return new Promise((resolve, reject) => {
    let done = false;
    const fin = (fn, v) => { if (!done) { done = true; fn(v); } };
    try {
      const ret = run(cmd, (err, out) => {
        if (out !== undefined) return err ? fin(reject, err) : fin(resolve, out);
        // out ไม่มี: บาง run() เรียก callback(output) อาร์กเดียว — แต่ถ้าเป็น Error ต้อง reject
        // (เดิม resolve(Error) → JSON.parse(Error) พัง → การ์ดกลายเป็น "ดึงข้อมูลไม่ได้")
        if (err instanceof Error) return fin(reject, err);
        fin(resolve, err);
      });
      if (ret && typeof ret.then === "function") ret.then((o) => fin(resolve, o), (e) => fin(reject, e));
    } catch (e) { fin(reject, e); }
  });
}
function repaintCurrent(data) {
  const root = document.querySelector(".cu-root");
  if (root) paint(root, data !== undefined ? data : root.__cuData);
}
function refreshNow(e) {
  if (e) e.stopPropagation();
  const btn = document.querySelector(".cu-refresh");
  if (btn) { btn.textContent = "⟳ กำลังรีเฟรช"; btn.classList.add("spin"); }
  const restore = () => {
    const b = document.querySelector(".cu-refresh");
    if (b) { b.textContent = "↻ รีเฟรช"; b.classList.remove("spin"); }
  };
  doRun(CMD + " --force") // ข้าม TTL cache ของ script (แต่ script ยังกัน backoff หลัง 429 ให้)
    .then((out) => {
      let d = null; try { d = JSON.parse(out); } catch (_) {}
      // วาดทับเฉพาะตอนได้ JSON จริง — ผลเพี้ยน/ว่าง (เช่น server สะดุด) ให้คงค่าเดิมไว้
      if (d && d._status) repaintCurrent(d);
      else restore();
    })
    .catch(restore);
}
function openLogin(e) {
  if (e) e.stopPropagation();
  doRun(
    'osascript -e \'tell application "Terminal" to activate\' ' +
    '-e \'tell application "Terminal" to do script "claude"\''
  ).catch(() => {});
}
function collapse(e) { if (e) { e.stopPropagation(); } lsSet(COLLAPSE_KEY, "1"); repaintCurrent(); }
function expand(e) { if (e) { e.stopPropagation(); } lsDel(COLLAPSE_KEY); repaintCurrent(); }
function chooseScreen(sig) {
  if (sig === "__all__") lsDel(SCREEN_KEY); else lsSet(SCREEN_KEY, sig);
  applyScreenVisibility();
  repaintCurrent(); // อัปเดตไฮไลต์/ปุ่มในจอนี้ทันที
}

// ── drag ──
function startDrag(e) {
  if (e.button !== 0) return;
  e.preventDefault();
  const card = e.currentTarget.closest(".cu-card");
  if (!card) return;
  const rect = card.getBoundingClientRect();
  const offX = e.clientX - rect.left, offY = e.clientY - rect.top, w = rect.width, h = rect.height;
  card.style.transition = "none";
  const move = (ev) => {
    card.style.left = Math.max(0, Math.min(ev.clientX - offX, window.innerWidth - w)) + "px";
    card.style.top = Math.max(0, Math.min(ev.clientY - offY, window.innerHeight - h)) + "px";
    card.style.right = "auto";
  };
  const up = () => {
    document.removeEventListener("mousemove", move);
    document.removeEventListener("mouseup", up);
    const left = parseInt(card.style.left, 10), top = parseInt(card.style.top, 10);
    if (!isNaN(left) && !isNaN(top)) lsSet(POS_KEY, JSON.stringify({ left, top }));
  };
  document.addEventListener("mousemove", move);
  document.addEventListener("mouseup", up);
}

// ════════════════ CapyBeats — คาปิบาร่าดุ๊กดิ๊กบนหัวการ์ด ════════════════
// spritesheet 8 คอลัมน์ × 9 แถว = 72 เฟรม (เฟรมต้นฉบับ 192×208, ย่อ/ขยายด้วย CAPY_SCALE)
// ไฟล์ claude-usage-capy.png อยู่ในโฟลเดอร์ widgets (Übersicht serve ให้เอง)
// ใช้ <style> ตรงๆ (ไม่ฝังใน className) เพราะ @keyframes ต้องอยู่ top-level
const CAPY_SCALE = 0.75; // ปรับขนาดน้องตรงนี้ (0.5 = เล็ก, 0.75 = ใหญ่, 1 = เท่าต้นฉบับ)
const CAPY_W = Math.round(192 * CAPY_SCALE), CAPY_H = Math.round(208 * CAPY_SCALE);
const CAPY_SHEET_W = CAPY_W * 8, CAPY_SHEET_H = CAPY_H * 9;
const CAPY_OVERHANG = CAPY_H - 10; // โผล่พ้นหัวการ์ด (จมลงในการ์ด 10px เหมือนนั่งบนขอบ)
const CAPY_CSS =
  '<style>' +
  '.cu-capy{position:absolute;top:-' + CAPY_OVERHANG + 'px;left:14px;width:' + CAPY_W + 'px;height:' + CAPY_H + 'px;' +
    'background:url("claude-usage-capy.png") no-repeat 0 0;background-size:' + CAPY_SHEET_W + 'px ' + CAPY_SHEET_H + 'px;' +
    'image-rendering:pixelated;pointer-events:none;' +
    'animation:cuCapX 0.8s steps(8) infinite, cuCapY 7.2s steps(9) infinite;}' +
  '@keyframes cuCapX{from{background-position-x:0}to{background-position-x:-' + CAPY_SHEET_W + 'px}}' +
  '@keyframes cuCapY{from{background-position-y:0}to{background-position-y:-' + CAPY_SHEET_H + 'px}}' +
  '</style>';

// ════════════════ painter (แหล่งวาดเดียว) ════════════════
function rowHTML(r) {
  const b = r.budget;
  // เส้นขีดขาวบน bar = เป้าที่ควรหยุดของวันนี้ + บรรทัดบอกว่าใช้ได้อีกเท่าไหร่
  const markAt = b ? Math.max(0, Math.min(100, b.target)) : 0; // เป้าติดลบได้ตอนโดนแคป → กันหลุดขอบ bar
  const mark = b ? '<div class="cu-mark" style="left:' + markAt.toFixed(2) + '%" title="เป้าวันนี้"></div>' : "";
  let daily = "";
  if (b) {
    const t = Math.max(0, Math.round(b.target)); // เป้าติดลบ (โดนแคป) อ่านว่า 0 = วันนี้ไม่ควรใช้เพิ่ม
    const dTxt = b.days.toFixed(1);
    const why = b.capped ? ' · จำกัดโดยโควตาสัปดาห์รวม' : "";
    daily = b.left >= 0
      ? '<div class="cu-daily">วันนี้ควรหยุดที่ ~' + t + '% · ใช้ได้อีก ' + b.left.toFixed(1) + '% · เหลือ ' + dTxt + ' วัน' + why + '</div>'
      : '<div class="cu-daily over">เกินเป้าวันนี้ +' + (-b.left).toFixed(1) + '% (เป้า ~' + t + '%) · เหลือ ' + dTxt + ' วัน' + why + '</div>';
  }
  return '<div class="cu-row"><div class="cu-row-top"><span class="cu-name">' + esc(r.name) +
    '</span><span class="cu-pct">' + r.pct + '% ใช้ไป</span></div>' +
    '<div class="cu-track"><div class="cu-fill" style="width:' + Math.max(2, r.pct) +
    '%;background:' + barColor(r.pct) + '"></div>' + mark + '</div>' +
    daily +
    (r.reset ? '<div class="cu-reset">' + esc(r.reset) + '</div>' : "") + '</div>';
}

function paint(root, data) {
  if (!root) return;
  root.__cuData = data;
  registerThisScreen();

  // โหมดย่อ → วงกลมเล็ก
  if (lsGet(COLLAPSE_KEY) === "1") {
    const pct = sessionPct(data);
    root.innerHTML =
      '<div class="cu-pill"' + posAttr() + ' title="กางการ์ด Claude Usage">' +
        '<div class="cu-pill-logo">✳</div>' +
        (pct != null ? '<div class="cu-pill-pct">' + pct + '%</div>' : "") +
      '</div>';
    const pill = root.querySelector(".cu-pill");
    if (pill) pill.addEventListener("click", expand);
    finishPaint(root);
    return;
  }

  const status = data ? data._status : "error", err = data ? data._error : null;
  let bodyHTML, footColor, footText, showLogin = false;

  if (!data || status === "error") {
    const info = errInfo(err);
    footColor = "#f0554a"; footText = info.short; showLogin = info.login;
    bodyHTML = '<div class="cu-err">' + esc(info.msg) + "</div>";
  } else {
    bodyHTML = toRows(data).map(rowHTML).join("");
    const fetched = data._fetched_at ? new Date(data._fetched_at) : new Date();
    if (status === "stale") {
      const info = errInfo(err);
      footColor = "#f0a728"; footText = "ค่าล่าสุด " + fmtClock(fetched) + " · " + info.short; showLogin = info.login;
    } else { footColor = "#3fbf68"; footText = "อัปเดต " + fmtClock(fetched) + " · ทุก 10 นาที"; }
  }

  // dropdown เลือกจอ
  const chosen = chosenScreen(), here = thisScreenSig();
  const ddItems = listScreens().map((s) =>
    '<div class="cu-dd-item' + (s.sig === chosen ? " cur" : "") + '" data-sig="' + esc(s.sig) + '">' +
    "🖥️ " + esc(screenLabel(s.w, s.h)) + (s.sig === here ? " · จอนี้" : "") + "</div>"
  ).join("");
  const ddAll = '<div class="cu-dd-item' + (!chosen ? " cur" : "") + '" data-sig="__all__">แสดงทุกจอ</div>';

  root.innerHTML =
    '<div class="cu-card"' + posAttr() + '>' +
      CAPY_CSS + '<div class="cu-capy" title="CapyBeats"></div>' +
      '<div class="cu-head">' +
        '<div class="cu-logo">✳</div><div class="cu-title">Claude Usage</div>' +
        '<div class="cu-badge">' + esc((data && data._plan) || "Max (20×)") + '</div>' +
        '<div class="cu-close" title="ย่อ">✕</div>' +
      '</div>' +
      bodyHTML +
      '<div class="cu-foot">' +
        '<span class="cu-dot" style="background:' + footColor + '"></span>' +
        '<span class="cu-foot-text">' + esc(footText) + '</span>' +
        '<span class="cu-actions">' +
          (showLogin ? '<span class="cu-btn cu-login" title="เปิด Claude เพื่อล็อกอิน/รีเฟรช token">🔑</span>' : "") +
          '<span class="cu-btn cu-refresh">↻ รีเฟรช</span>' +
          '<span class="cu-btn cu-screen" title="เลือกจอ">🖥️</span>' +
          '<div class="cu-dd"><div class="cu-dd-title">ให้ widget อยู่จอไหน</div>' + ddItems + ddAll + "</div>" +
        '</span>' +
      '</div>' +
    '</div>';

  // ผูก event (innerHTML ล้าง handler เดิม → bind ใหม่ทุกครั้ง)
  const q = (sel) => root.querySelector(sel);
  const head = q(".cu-head"); if (head) head.addEventListener("mousedown", startDrag);
  const close = q(".cu-close");
  if (close) { close.addEventListener("mousedown", (e) => e.stopPropagation()); close.addEventListener("click", collapse); }
  const rBtn = q(".cu-refresh"); if (rBtn) rBtn.addEventListener("click", refreshNow);
  const lBtn = q(".cu-login"); if (lBtn) lBtn.addEventListener("click", openLogin);
  const sBtn = q(".cu-screen"), dd = q(".cu-dd");
  if (sBtn && dd) {
    sBtn.addEventListener("click", (e) => { e.stopPropagation(); dd.classList.toggle("open"); });
    dd.querySelectorAll(".cu-dd-item").forEach((it) => {
      it.addEventListener("click", (e) => { e.stopPropagation(); dd.classList.remove("open"); chooseScreen(it.getAttribute("data-sig")); });
    });
  }
  finishPaint(root);
}

// ปิด dropdown เมื่อคลิกที่อื่น (ผูกครั้งเดียว)
if (typeof document !== "undefined" && !window.__cuDocClose) {
  window.__cuDocClose = true;
  document.addEventListener("click", () => {
    const dd = document.querySelector(".cu-dd.open"); if (dd) dd.classList.remove("open");
  });
}

// ════════════════ render (shell + ref → painter) ════════════════
export const render = ({ output }) => {
  let data = null;
  try { data = JSON.parse(output); } catch (e) { data = null; }
  // จำค่าดีล่าสุดไว้ — รอบไหน output เพี้ยน (server สะดุด/stderr ปน) โชว์ค่าเดิมเป็น stale แทน error
  if (data && data._status) window.__cuLastGood = data;
  else if (window.__cuLastGood) data = Object.assign({}, window.__cuLastGood, { _status: "stale", _error: "widget" });
  return <div className="cu-root" ref={(el) => { if (el) paint(el, data); }} />;
};
