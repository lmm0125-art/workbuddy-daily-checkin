#!/usr/bin/env node
/**
 * WorkBuddy「Buddy加油站」每日签到 —— CDP 核心
 *
 * 原理：Buddy加油站是 WorkBuddy 客户端内置功能，接口请求由客户端自己的会话鉴权。
 * 这里不在外部拼 cookie/token，而是通过客户端已开启的调试端口(CDP)，
 * 在客户端渲染进程里发起同源请求 —— 鉴权由客户端自动携带，随登录态长期有效。
 *
 * 端口解析顺序：环境变量 WB_CDP_PORT → <配置目录>/app/session/DevToolsActivePort → 9222
 * 配置目录：环境变量 WORKBUDDY_CONFIG_DIR → ~/.workbuddy
 *
 * 退出码：0 成功(含今日已签到) / 3 客户端未开调试端口 / 2 需重新登录 / 1 其他失败
 */
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

const CONFIG_DIR = process.env.WORKBUDDY_CONFIG_DIR?.trim() || join(homedir(), '.workbuddy');

function resolvePort() {
  if (process.env.WB_CDP_PORT) return String(process.env.WB_CDP_PORT).replace(/[^0-9]/g, '');
  try {
    const first = readFileSync(join(CONFIG_DIR, 'app', 'session', 'DevToolsActivePort'), 'utf8')
      .trim().split('\n')[0].trim();
    const digits = first.replace(/[^0-9]/g, '');
    if (digits) return digits;
  } catch { /* ignore */ }
  return '9222';
}

const PORT = resolvePort() || '9222';
const BASE = 'https://www.workbuddy.cn';

// 在客户端渲染进程上下文里执行：状态 -> 未签则领取 -> 复查
const EXPR = `(async () => {
  const base = ${JSON.stringify(BASE)};
  const post = async (p) => {
    const r = await fetch(base + p, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{}',
      credentials: 'include'
    });
    const text = await r.text();
    let json = null;
    try { json = JSON.parse(text); } catch (_) {}
    return { http: r.status, json, raw: json ? undefined : text.slice(0, 300) };
  };
  const st = await post('/billing/meter/checkin-activity-status');
  if (st.http !== 200 || !st.json) return JSON.stringify({ ok: false, phase: 'status', http: st.http, raw: st.raw });
  const d = (st.json && st.json.data) || {};
  if (d.today_checked_in) return JSON.stringify({ ok: true, action: 'already', data: d });
  const ck = await post('/billing/meter/daily-checkin');
  const st2 = await post('/billing/meter/checkin-activity-status');
  return JSON.stringify({
    ok: true, action: 'claimed',
    claimHttp: ck.http, claim: ck.json,
    data: (st2.json && st2.json.data) || d
  });
})()`;

async function listTargets() {
  const res = await fetch(`http://127.0.0.1:${PORT}/json/list`, { signal: AbortSignal.timeout(4000) });
  return res.json();
}

async function evalOnTarget(wsUrl, expression) {
  const ws = new WebSocket(wsUrl);
  let id = 0; const pending = new Map();
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  });
  const send = (method, params) => new Promise(res => {
    const i = ++id; pending.set(i, res);
    ws.send(JSON.stringify({ id: i, method, params }));
  });
  try {
    await new Promise((res, rej) => {
      ws.addEventListener('open', res);
      ws.addEventListener('error', () => rej(new Error('ws error')));
      setTimeout(() => rej(new Error('ws timeout')), 8000);
    });
    await send('Runtime.enable', {});
    const r = await send('Runtime.evaluate', {
      expression, returnByValue: true, awaitPromise: true, userGesture: true,
    });
    if (r.result?.exceptionDetails) throw new Error('eval exception');
    return r.result?.result?.value;
  } finally {
    try { ws.close(); } catch { /* ignore */ }
  }
}

async function cdpEval(expression) {
  const list = await listTargets();
  const pages = (list || []).filter(t => t.type === 'page' && t.webSocketDebuggerUrl);
  if (pages.length === 0) throw new Error('no page target');
  // 优先主窗口（app.asar/renderer）
  pages.sort((a, b) => (/app\.asar\/renderer/.test(b.url || '') ? 1 : 0) - (/app\.asar\/renderer/.test(a.url || '') ? 1 : 0));
  let lastErr;
  for (const p of pages) {
    try { return await evalOnTarget(p.webSocketDebuggerUrl, expression); }
    catch (e) { lastErr = e; }
  }
  throw lastErr || new Error('all targets failed');
}

function activityLine(d) {
  return `活动：${d.theme_name || '-'} / ${d.activity_name || '-'}  周期：${d.start_time || '-'} ~ ${d.end_time || '-'}`;
}

let raw;
try {
  raw = await cdpEval(EXPR);
} catch (e) {
  console.log(`[!] 无法连接客户端调试端口(${PORT})：${e.message}`);
  console.log(`    请确保 WorkBuddy 客户端正以 --remote-debugging-port=${PORT} 运行（可用 scripts/setup-debug-port.sh 一键配置）。`);
  process.exit(3);
}

let r;
try { r = JSON.parse(raw); } catch {
  console.log('[!] 返回解析失败：' + String(raw).slice(0, 300));
  process.exit(1);
}

if (!r.ok) {
  console.log(`[!] 状态接口异常 HTTP ${r.http}：${r.raw || ''}`);
  if (r.http === 401 || r.http === 403) {
    console.log('鉴权失败：请在 WorkBuddy 客户端内重新登录后重试。');
    process.exit(2);
  }
  process.exit(1);
}

const d = r.data || {};
if (r.action === 'already') {
  console.log(`✅ 今日已签到，无需重复领取。连续 ${d.streak_days ?? '-'} 天，累计 ${d.total_credits ?? '-'} 积分。`);
  console.log(activityLine(d));
  process.exit(0);
}
const credit = r.claim?.data?.credit ?? d.daily_credit ?? 100;
console.log(`✅ 签到成功！本次 +${credit} 积分，连续 ${d.streak_days ?? '-'} 天，累计 ${d.total_credits ?? '-'} 积分。`);
console.log(activityLine(d));
process.exit(0);
