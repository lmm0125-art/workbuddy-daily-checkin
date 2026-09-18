#!/usr/bin/env bash
# ============================================================================
# 让 WorkBuddy 每次启动都自带调试端口（CDP），从而支持自动签到。
#
# 做法：写入一个 macOS 登录项(LaunchAgent)，登录时以
#       `--remote-debugging-port=<PORT>` 拉起 WorkBuddy。
#
# 用法：
#   bash scripts/setup-debug-port.sh            # 生成并尝试加载
#   WORKBUDDY_APP=/Applications/WorkBuddy.app PORT=9222 bash scripts/setup-debug-port.sh
#
# 说明：调试端口只绑定 127.0.0.1（本机回环），外部网络无法访问；
#       但它允许本机进程驱动 WorkBuddy，请知悉后再启用。
# ============================================================================
set -uo pipefail

APP="${WORKBUDDY_APP:-/Applications/WorkBuddy.app}"
PORT="${PORT:-9222}"
LABEL="com.workbuddy.checkin-port"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -d "$APP" ]]; then
  echo "[!] 未找到应用：$APP"
  echo "    如安装在其他位置，请用 WORKBUDDY_APP=/path/to/WorkBuddy.app 重跑。"
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-a</string>
    <string>$APP</string>
    <string>--args</string>
    <string>--remote-debugging-port=$PORT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
</dict>
</plist>
EOF

echo "[ok] 已写入登录项：$PLIST"

UID_NUM="$(id -u)"
echo "[..] 尝试加载…"
if launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null; then :; fi
if launchctl bootstrap "gui/$UID_NUM" "$PLIST" 2>/dev/null; then
  echo "[ok] 登录项已加载。下次登录 WorkBuddy 将自动带调试端口启动。"
else
  echo "[!] 自动加载失败（常见于权限受限环境）。请在【自己的终端】执行一次："
  echo "    launchctl bootstrap gui/$UID_NUM \"$PLIST\""
fi

cat <<'TIP'

生效方式（重要）：
  1) 上面加载成功后，【完全退出 WorkBuddy 再重新打开】一次，调试端口即生效；
  2) 之后每次登录都会自动带端口，签到脚本即可长期稳定运行。

验证：
  bash scripts/checkin.sh
  看到「✅ 签到成功」或「✅ 今日已签到」即表示已打通。
TIP
