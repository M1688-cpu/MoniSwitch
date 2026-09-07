#!/bin/bash
# 本地预览宣传页：复刻 .github/workflows/website.yml 的组装逻辑到 /tmp，
# 再起 python3 静态服务——与线上 Pages 结构同构，所见即所得。
# 用法: bash Support/preview-site.sh [端口(默认 4173)]

set -euo pipefail
cd "$(dirname "$0")/.."

PORT="${1:-4173}"
SITE_DIR="/tmp/moniswitch-site"

rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR"
cp docs/index.html "$SITE_DIR/index.html"
cp -R screenshots "$SITE_DIR/screenshots"
cp Resources/AppIcon-source.png "$SITE_DIR/icon.png"
touch "$SITE_DIR/.nojekyll"

# 注意：中文标点紧贴 $VAR 会被 bash 并入变量名，必须用 ${} 显式界定
echo "已组装到 ${SITE_DIR}，预览地址: http://localhost:${PORT}/  (Ctrl+C 退出)"
cd "$SITE_DIR"
python3 -m http.server "$PORT"
