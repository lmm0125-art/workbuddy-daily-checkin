#!/usr/bin/env bash
# ============================================================================
# buddy-station-checkin —— 一键安装脚本
#
# 作用：把本仓库（标准 WorkBuddy Skill）安装到 ~/.workbuddy/skills/ 下，
#       使其可被 WorkBuddy 客户端识别并调用。
#
# 用法：
#   bash install.sh                        # 安装到默认目录
#   WORKBUDDY_SKILLS_DIR=/path bash install.sh   # 自定义技能目录
# ============================================================================
set -euo pipefail

# 技能名（须与 SKILL.md 的 name 字段一致）
SKILL_NAME="buddy-station-checkin"
# 源目录 = 本脚本所在目录
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 目标目录：优先环境变量，否则 ~/.workbuddy/skills
SKILLS_DIR="${WORKBUDDY_SKILLS_DIR:-$HOME/.workbuddy/skills}"
DEST_DIR="$SKILLS_DIR/$SKILL_NAME"

echo "[..] 安装 $SKILL_NAME"
echo "     源目录: $SRC_DIR"
echo "     目标:   $DEST_DIR"

# 若已存在，先备份，避免覆盖用户改动
if [[ -e "$DEST_DIR" ]]; then
  BACKUP="$DEST_DIR.bak.$(date +%Y%m%d%H%M%S)"
  echo "[..] 目标已存在，备份到 $BACKUP"
  mv "$DEST_DIR" "$BACKUP"
fi

mkdir -p "$SKILLS_DIR"
# 只拷贝技能所需内容，排除仓库级文件（README/LICENSE/install.sh）
mkdir -p "$DEST_DIR"
cp -R "$SRC_DIR/SKILL.md" "$DEST_DIR/"
[[ -d "$SRC_DIR/scripts" ]] && cp -R "$SRC_DIR/scripts" "$DEST_DIR/"
[[ -d "$SRC_DIR/references" ]] && cp -R "$SRC_DIR/references" "$DEST_DIR/"
chmod +x "$DEST_DIR"/scripts/*.sh 2>/dev/null || true

echo "[ok] 已安装到 $DEST_DIR"
cat <<'TIP'

下一步（首次使用需配置一次调试端口）：
  bash "$HOME/.workbuddy/skills/buddy-station-checkin/scripts/setup-debug-port.sh"

然后完全退出并重新打开 WorkBuddy 一次，即可长期生效。
验证：
  bash "$HOME/.workbuddy/skills/buddy-station-checkin/scripts/checkin.sh"
TIP
