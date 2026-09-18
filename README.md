# workbuddy-daily-checkin

> 领取 WorkBuddy「Buddy加油站」每日签到积分 —— 一个可安装、可自动化的 Agent Skill。

[![Platform](https://img.shields.io/badge/platform-macOS-black)]()
[![Skill](https://img.shields.io/badge/WorkBuddy-Skill-blue)]()
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

<!-- 一句话说明：这个仓库是什么、解决什么问题 -->

## 这是什么

WorkBuddy 客户端内置了「Buddy加油站」每日签到活动，签到可获得积分。
本仓库把"每日签到"封装成一个符合 WorkBuddy **Skill 标准格式**的技能，装进 `~/.workbuddy/skills/`
后，即可用一句话（"帮我签到""今天签到没有"）触发，也支持定时/自动化任务每日运行。

## 原理（为什么不复制 Cookie）

「Buddy加油站」是**客户端内置**功能，签到接口由**客户端自身的登录会话**鉴权。
因此本技能**不复制、不解密任何 Cookie/Token**——那些凭据会过期且无法可靠刷新，正是历史上签到失败的主因。

正确做法：通过客户端已开启的**调试端口（CDP）**，在客户端**渲染进程上下文**里发起同源请求，
鉴权由客户端自动携带，随登录态长期有效。

```
┌────────────────────┐   CDP (127.0.0.1:9222)   ┌──────────────────────────┐
│  checkin.sh        │ ───────────────────────► │  WorkBuddy 客户端渲染进程 │
│  (定位端口/node)    │                          │  fetch(同源请求)          │
└────────────────────┘                          │  ↳ 客户端自动带鉴权        │
                                                └────────────┬─────────────┘
                                                             │ POST
                                                             ▼
                                          https://www.workbuddy.cn/billing/meter/daily-checkin
```

## 目录结构

```
workbuddy-daily-checkin/
├── SKILL.md                     # 技能定义（标准 Skill 格式，含 description 触发词与执行步骤）
├── scripts/
│   ├── checkin.sh               # 入口：定位 node/端口 → 调用核心脚本
│   ├── checkin_cdp.mjs          # 核心：连 CDP → 渲染进程「查状态→领取→复查」
│   └── setup-debug-port.sh      # 一次性配置：让客户端带调试端口启动（macOS LaunchAgent）
├── references/
│   └── troubleshooting.md       # 排障与原理详解
├── install.sh                   # 一键安装到 ~/.workbuddy/skills/
├── LICENSE                      # MIT
└── README.md
```

## 安装

### 方式 A：一键安装（推荐）

```bash
git clone https://github.com/lmm0125-art/workbuddy-daily-checkin.git
cd workbuddy-daily-checkin
bash install.sh
```

### 方式 B：手动安装

把整个 `workbuddy-daily-checkin/` 目录放到 `~/.workbuddy/skills/` 下即可：

```bash
git clone https://github.com/lmm0125-art/workbuddy-daily-checkin.git \
  ~/.workbuddy/skills/workbuddy-daily-checkin
```

### 方式 C：通过客户端「上传技能」

下载本仓库的 zip 包 → 解压 → 在 WorkBuddy 技能专栏「添加技能 → 上传技能」选中该文件夹。

## 首次配置（一次性）

客户端需要以 `--remote-debugging-port=<PORT>` 启动（默认 9222）。

```bash
bash ~/.workbuddy/skills/workbuddy-daily-checkin/scripts/setup-debug-port.sh
```

脚本会写入并尝试加载登录项 `~/Library/LaunchAgents/com.workbuddy.checkin-port.plist`。
若提示自动加载失败（权限受限环境常见），在**自己的终端**执行它给出的
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.workbuddy.checkin-port.plist`，
然后**完全退出并重新打开 WorkBuddy 一次**。此后每次登录都会自动带端口。

## 使用

```bash
# 直接运行
bash ~/.workbuddy/skills/workbuddy-daily-checkin/scripts/checkin.sh
```

或在对话框中直接说：

> 帮我签到 / 领一下积分 / 今天签到没有 / 看看连续多少天了

输出示例：

```
✅ 签到成功！本次 +100 积分，连续 3 天，累计 300 积分。
活动：Buddy加油站 / 高校新生攻略  周期：2026-09-16 00:00:00 ~ 2026-09-29 23:59:59
```

### 退出码

| 码 | 含义 | 处理 |
|---|---|---|
| 0 | 成功（含今日已签到） | 正常汇报 |
| 3 | 客户端未开调试端口 | 执行 `setup-debug-port.sh` 并重启客户端 |
| 2 | 需要重新登录 | 在客户端内重新登录 |
| 1 | 其他失败 | 查看原始输出 |

### 使用环境变量

| 变量 | 作用 | 默认 |
|---|---|---|
| `WB_CDP_PORT` | 指定调试端口 | 读 `DevToolsActivePort` → `9222` |
| `WORKBUDDY_CONFIG_DIR` | WorkBuddy 配置目录 | `~/.workbuddy` |
| `WORKBUDDY_APP` | 客户端 .app 路径 | `/Applications/WorkBuddy.app` |

## 接口说明

| 用途 | 方法 | 路径 |
|---|---|---|
| 查状态 | POST | `https://www.workbuddy.cn/billing/meter/checkin-activity-status` |
| 领取 | POST | `https://www.workbuddy.cn/billing/meter/daily-checkin` |

在客户端渲染进程内请求时，只需 `credentials: 'include'`，**无需手动添加任何鉴权头**。

## 安全说明

- 调试端口**仅绑定 `127.0.0.1`（本机回环）**，外网无法访问。
- 但它允许**本机任意进程**通过 CDP 驱动 WorkBuddy（读取页面、执行 JS），
  因此**仅在可信机器上启用**；不需要时可卸载：

  ```bash
  launchctl bootout gui/$(id -u)/com.workbuddy.checkin-port
  rm ~/Library/LaunchAgents/com.workbuddy.checkin-port.plist
  ```

- 本技能不收集、不上传任何个人数据，所有请求均指向 WorkBuddy 官方域名。

## 已知限制

- 仅支持 **macOS**（依赖 LaunchAgent）与 WorkBuddy **桌面客户端**；不支持纯 Web 环境。
- **不要重启正在运行的客户端**：本技能常由客户端内的 agent 调用，重启会中断自身。
- 活动有时间窗口，非活动期接口可能返回异常。

## 许可

[MIT](LICENSE)
