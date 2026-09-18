#!/usr/bin/env bash
# ============================================================================
# WorkBuddy「Buddy加油站」每日积分领取 —— 入口脚本
#
# 通过 WorkBuddy 客户端的调试端口(CDP)，在客户端内发起同源请求完成签到。
# 鉴权由客户端自己携带，因此不依赖任何会过期的 cookie。
#
# 用法：
#   bash scripts/checkin.sh            # 签到
#   WB_CDP_PORT=9222 bash scripts/checkin.sh
#
# 退出码：0 成功(含今日已签到) / 3 客户端未开调试端口 / 2 需重新登录 / 1 其他失败
# ============================================================================
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${WORKBUDDY_CONFIG_DIR:-$HOME/.workbuddy}"

# 找 node：优先 PATH，其次 WorkBuddy 自带的托管 node
NODE_BIN="$(command -v node 2>/dev/null || true)"
if [[ -z "$NODE_BIN" ]]; then
  shopt -s nullglob
  for c in "$CONFIG_DIR"/binaries/node/versions/*/bin/node; do
    [[ -x "$c" ]] && NODE_BIN="$c"
  done
  shopt -u nullglob
fi
if [[ -z "$NODE_BIN" ]]; then
  echo "[!] 未找到 node 运行时。请安装 Node.js 18+，或确认 WorkBuddy 已正常安装。"
  exit 1
fi

# 解析调试端口
PORT="${WB_CDP_PORT:-}"
if [[ -z "$PORT" ]]; then
  f="$CONFIG_DIR/app/session/DevToolsActivePort"
  if [[ -r "$f" ]]; then
    raw="$(<"$f")"; raw="${raw%%$'\n'*}"; PORT="${raw//[!0-9]/}"
  fi
fi
PORT="${PORT:-9222}"

if ! curl -s --max-time 3 "http://127.0.0.1:$PORT/json/list" 2>/dev/null | grep -q '"type"'; then
  echo "[!] 未检测到客户端调试端口($PORT)。"
  if pgrep -f "WorkBuddy.app/Contents/MacOS/Electron" >/dev/null 2>&1; then
    echo "    客户端正在运行但没开调试端口。请先执行 scripts/setup-debug-port.sh 配置，"
    echo "    然后完全退出并重新打开 WorkBuddy 一次即可长期生效。"
  else
    echo "    请先启动 WorkBuddy 客户端（建议用 scripts/setup-debug-port.sh 配置为带端口启动）。"
  fi
  exit 3
fi

WORKBUDDY_CONFIG_DIR="$CONFIG_DIR" WB_CDP_PORT="$PORT" "$NODE_BIN" "$DIR/checkin_cdp.mjs"
exit $?
