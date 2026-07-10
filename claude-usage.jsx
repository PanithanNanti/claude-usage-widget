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

// installer จะแก้บรรทัด command นี้ให้ชี้ path จริงในเครื่อง
export const command =
  "bash /Users/user/Developer/dev/claudelimit/claude-usage.sh --json";

const CMD = command;
export const refreshFrequency = 300000; // 5 นาที

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
  .cu-track { height: 7px; border-radius: 999px; background: rgba(255,255,255,0.08); overflow: hidden; }
  .cu-fill { height: 100%; border-radius: 999px; transition: width 0.4s ease; }
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
function toRows(data) {
  const rows = [], limits = (data && data.limits) || [];
  if (limits.length) {
    for (const lim of limits) {
      const pct = Math.round(lim.percent || 0);
      if (lim.kind === "session") rows.push({ name: "เซสชันปัจจุบัน", pct, reset: resetRelative(lim.resets_at) });
      else if (lim.kind === "weekly_all") rows.push({ name: "สัปดาห์นี้ (ทุกโมเดล)", pct, reset: resetAbsolute(lim.resets_at) });
      else if (lim.kind === "weekly_scoped" && pct > 0) {
        const nm = ((lim.scope || {}).model || {}).display_name || "โมเดล";
        rows.push({ name: "สัปดาห์ · " + nm, pct, reset: resetAbsolute(lim.resets_at) });
      }
    }
  } else if (data) {
    const fh = data.five_hour || {}, sd = data.seven_day || {};
    rows.push({ name: "เซสชันปัจจุบัน", pct: Math.round(fh.utilization || 0), reset: resetRelative(fh.resets_at) });
    rows.push({ name: "สัปดาห์นี้ (ทุกโมเดล)", pct: Math.round(sd.utilization || 0), reset: resetAbsolute(sd.resets_at) });
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
    case "rate_limit": return { msg: "โดน rate limit ชั่วคราว (429) — เดี๋ยวลองใหม่เอง", short: "rate limit (429)", login: false };
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
  const wantHidden = !!chosen && chosen !== sig;
  const isHidden = el.style.display === "none";
  if (wantHidden !== isHidden) el.style.display = wantHidden ? "none" : "";
}
// กันการ์ดตกนอกขอบจอ (เช่น ตำแหน่งที่บันทึกจากจอกว้าง แล้วย้ายมาจอเล็ก/แนวตั้ง)
// เขียน style เฉพาะตอนหลุดจอจริง → ไม่แฟลช
function ensureOnScreen(el) {
  if (!el || el.style.display === "none") return;
  const rect = el.getBoundingClientRect();
  if (!rect.width) return;
  const maxLeft = window.innerWidth - rect.width - 8, maxTop = window.innerHeight - rect.height - 8;
  let left = rect.left, top = rect.top, changed = false;
  if (left > maxLeft) { left = Math.max(8, maxLeft); changed = true; }
  if (top > maxTop) { top = Math.max(8, maxTop); changed = true; }
  if (left < 8) { left = 8; changed = true; }
  if (top < 8) { top = 8; changed = true; }
  if (changed) { el.style.left = left + "px"; el.style.top = top + "px"; el.style.right = "auto"; }
}
// เรียกท้าย paint + ในลูป sync
function finishPaint(root) {
  applyScreenVisibility();
  const el = root && root.firstElementChild;
  if (el) ensureOnScreen(el);
}
if (typeof window !== "undefined" && !window.__cuVisTimer) {
  window.__cuVisTimer = setInterval(function () {
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
  doRun(CMD)
    .then((out) => { let d = null; try { d = JSON.parse(out); } catch (_) {} repaintCurrent(d); })
    .catch(() => { if (btn) { btn.textContent = "↻ รีเฟรช"; btn.classList.remove("spin"); } });
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

// ════════════════ painter (แหล่งวาดเดียว) ════════════════
function rowHTML(r) {
  return '<div class="cu-row"><div class="cu-row-top"><span class="cu-name">' + esc(r.name) +
    '</span><span class="cu-pct">' + r.pct + '% ใช้ไป</span></div>' +
    '<div class="cu-track"><div class="cu-fill" style="width:' + Math.max(2, r.pct) +
    '%;background:' + barColor(r.pct) + '"></div></div>' +
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
    } else { footColor = "#3fbf68"; footText = "อัปเดต " + fmtClock(fetched) + " · ทุก 5 นาที"; }
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
  return <div className="cu-root" ref={(el) => { if (el) paint(el, data); }} />;
};
