# 排障与原理（WorkBuddy 每日签到）

## 一、为什么用 CDP，而不是复制 cookie

「Buddy加油站」是 WorkBuddy **客户端内置**功能，签到请求由客户端**自身登录会话**鉴权。
接口虽挂在 `www.workbuddy.cn` 域名下，但：

- 网页侧的 session cookie **会过期**，且从客户端外部**无法可靠刷新**：
  - Chrome 127+ 的 App-Bound Encryption 让离线解密 Cookie 数据库只得到密文；
  - 客户端本地库 `~/.workbuddy/app/session/Cookies` 里可能只剩失效 token；
  - 客户端 CDP 的 `Network.getAllCookies` 在部分版本返回 0 条。
- 结论：与其"复制一份会死的凭据"，不如**借客户端自己的会话**——通过调试端口(CDP)
  在客户端渲染进程内发起同源请求，鉴权自动携带，随登录态长期有效。

## 二、接口事实

| 用途 | 方法 | 路径 |
|---|---|---|
| 查状态 | POST | `https://www.workbuddy.cn/billing/meter/checkin-activity-status` |
| 领取 | POST | `https://www.workbuddy.cn/billing/meter/daily-checkin` |

- 在客户端渲染进程内请求时：`fetch(url, { method:'POST', headers:{'Content-Type':'application/json'}, body:'{}', credentials:'include' })`
  即可，**无需手动加任何鉴权头**（实测 200）。
- 返回字段（`data`）：`today_checked_in / streak_days / daily_credit / total_credits / theme_name / activity_name / start_time / end_time`。

## 三、常见故障

### 1) `[!] 未检测到客户端调试端口` / 退出码 3
- 确认客户端在运行：`pgrep -f "WorkBuddy.app/Contents/MacOS/Electron"`。
- 确认端口文件：`cat ~/.workbuddy/app/session/DevToolsActivePort`（首行即端口）。
- 若客户端在跑但没有端口文件：说明它**不是带 `--remote-debugging-port` 启动的**。
  执行 `scripts/setup-debug-port.sh`，在终端跑它给出的 `launchctl bootstrap ...`，然后**完全退出并重开 WorkBuddy**。

### 2) `鉴权失败` / 退出码 2
- 客户端登录态失效。在 WorkBuddy 客户端内重新登录后重试。

### 3) `✅ 今日已签到`
- 正常，当天已领过，无需重复。

### 4) CDP 连得上但求值失败
- 目标窗口可能不在前台或渲染进程忙。重试一次；仍失败可完全重启客户端。

## 四、手动排查（可选）

先确认调试端口可枚举目标窗口（能看到含 `"type"` 的 JSON 即正常）：

```bash
curl -s http://127.0.0.1:9222/json/list | head
```

若只想确认接口连通性，直接在客户端渲染进程里执行一次：

```bash
# 伪代码：在任意页面 DevTools 控制台运行
fetch('https://www.workbuddy.cn/billing/meter/checkin-activity-status', {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: '{}', credentials: 'include'
}).then(r => r.json()).then(console.log)
```

正常情况下 `checkin.sh` 的输出已足够定位问题，无需额外脚本。

## 五、安全说明

- 调试端口**仅绑定 127.0.0.1**，外网不可达。
- 但它允许**本机任意进程**通过 CDP 驱动 WorkBuddy（含读取页面、执行 JS），
  因此仅在可信机器上启用；不需要时可卸载登录项：

  ```bash
  launchctl bootout gui/$(id -u)/com.workbuddy.checkin-port
  rm ~/Library/LaunchAgents/com.workbuddy.checkin-port.plist
  ```

## 六、客户端实现参考（反解 app.asar，供理解）

- `/main/tar.js`：`checkin()` → `postCheckin(\`${billingPrefix}/billing/meter/daily-checkin\`)`。
- `billingPrefix`：Web 端为 `""`；**桌面端为 `/v2`**（走 IDE 网关 Bearer）。
- 桌面端 `getCheckinRequestHeaders()` 会注入 `X-Device-Token`（Turing 设备令牌）。
- 渲染进程 `HttpService`（axios）：`withCredentials: true`，可选 `Authorization: Bearer`。
- **要点**：客户端自己会带鉴权，因此从渲染进程发请求即可，无需复刻 token/签名。
