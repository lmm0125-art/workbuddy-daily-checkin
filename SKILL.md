---
name: workbuddy-daily-checkin
description: 领取 WorkBuddy「Buddy加油站」每日签到积分。当用户要求「签到 / 领积分 / 领取每日积分 / 今天签到了吗 / 查看连续天数和累计积分」，或提到「Buddy加油站」「每日签到」「daily checkin」「buddy station」时应使用本技能。通过 WorkBuddy 客户端调试端口(CDP)在客户端内发起同源请求完成签到，鉴权由客户端自动携带、不会过期；也可用于排查签到失败原因。
metadata:
  agent_created: true
---

# WorkBuddy「Buddy加油站」每日签到

## 概述

领取 WorkBuddy 客户端内置「Buddy加油站」活动的每日积分。签到的接口请求由客户端自身的登录会话鉴权，
因此通过客户端调试端口(CDP)在客户端渲染进程内发起同源请求即可完成签到 —— 无需复制任何 cookie，
也不会因 cookie 过期而失败。

## 何时使用

- 用户说「帮我签到」「领一下积分」「今天签到没有」「看看连续多少天了」。
- 定时/自动化任务需要每日领取积分。
- 签到失败需要定位原因（端口没开 / 未登录 / 已签过）。

## 前置条件

1. 已安装并登录 WorkBuddy 桌面客户端（macOS 路径 `/Applications/WorkBuddy.app`）。
2. 客户端以 `--remote-debugging-port=<PORT>` 运行（默认 9222）。
   首次使用执行一次「配置调试端口」（见下）。

## 执行步骤

1. 运行签到脚本：

   ```bash
   bash scripts/checkin.sh
   ```

   脚本会自动定位端口（`WB_CDP_PORT` → `<配置目录>/app/session/DevToolsActivePort` → 9222），
   然后在客户端内完成「查状态 → 未签则领取 → 复查」。

2. 按输出向用户汇报：
   - `✅ 签到成功！本次 +N 积分，连续 X 天，累计 Y 积分。` → 告知已领取的积分、连续天数、累计。
   - `✅ 今日已签到，无需重复领取。` → 告知今天已签过，无需操作。
   - `[!] 未检测到客户端调试端口` / 退出码 3 → 见「配置调试端口」，配置后重试（最多 1 次）。
   - `鉴权失败 / 需重新登录` / 退出码 2 → 引导用户在客户端内重新登录。
   - 其他失败 → 原样贴出输出并说明可能原因。

3. 详细排障参见 `references/troubleshooting.md`。

## 首次配置：让客户端带调试端口启动（一次性）

```bash
bash scripts/setup-debug-port.sh
```

该脚本写入并尝试加载登录项 `~/Library/LaunchAgents/com.workbuddy.checkin-port.plist`。
若提示自动加载失败（权限受限环境常见），在**自己的终端**执行它给出的 `launchctl bootstrap ...` 命令，
然后**完全退出并重新打开 WorkBuddy 一次**。此后每次登录都会自动带端口。

> 说明：调试端口仅绑定 `127.0.0.1`（本机回环），外网无法访问；但它允许本机进程驱动 WorkBuddy，请知悉后再启用。

## 脚本说明

| 文件 | 作用 |
|---|---|
| `scripts/checkin.sh` | 入口。定位 node 与端口，调用核心脚本，透传退出码。 |
| `scripts/checkin_cdp.mjs` | 核心。连接 CDP → 在客户端渲染进程执行「状态→领取→复查」→ 输出中文结论。 |
| `scripts/setup-debug-port.sh` | 一次性配置：写入/加载登录项，使客户端带调试端口启动。 |

## 退出码

| 码 | 含义 | 处理 |
|---|---|---|
| 0 | 成功（含今日已签到） | 正常汇报 |
| 3 | 客户端未开调试端口 | 引导执行 `setup-debug-port.sh` 并重启客户端 |
| 2 | 需要重新登录 | 引导在客户端内登录 |
| 1 | 其他失败 | 贴出原始输出 |

## 关键约束（避免踩坑）

- **不要在外部拼接/解密 cookie 或 token**：网页 cookie 会过期且无法可靠刷新，是历史上签到失败的主因；
  客户端自带鉴权，走 CDP 即可。
- **不要重启正在运行的 WorkBuddy 客户端**：本技能常由客户端内的 agent 调用，重启会中断自身。
- 本技能依赖 macOS（LaunchAgent）与 WorkBuddy 桌面端；不支持纯 Web 环境。
