#!/usr/bin/env bash
#
# render-theme-icons.sh
# 从 design/icon-web 的 SVG 渲染「跟随主题」的图标资源（2026-10-23）。
#
# 产物：
#   Resources/AppIconThemes/theme-<id>.png        7 个内置面板主题（512×512，透明底）
#   Resources/AppIconThemes/system-<accent>.png   8 档标准系统强调色（「跟随系统」用）
#   design/icon-web/moniswitch-icon-1024.png      主图标（= 跟随系统/蓝，bundle 默认）
#   design/icon-web/sizes/icon-*.png              尺寸阶梯（512…16）
#   Resources/AppIcon-source.png                  主图标 1024（make-app-icon.sh 的输入）
#
# 末尾自动调用 make-app-icon.sh 重建 Resources/AppIcon.icns。
# 依赖：Google Chrome（headless 截图）；可用 CHROME=/path/to/chrome 覆盖。
#
# 改色/改几何的入口是 design/icon-web/theme-icons/generate.py（色值取自
# PanelTheme.lightDerived，测试锁定），先跑 python3 generate.py 再跑本脚本。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DESIGN_DIR="$PROJECT_DIR/design/icon-web"
THEME_DIR="$DESIGN_DIR/theme-icons"
RESOURCES_DIR="$PROJECT_DIR/Resources"
OUT_DIR="$RESOURCES_DIR/AppIconThemes"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ ! -x "$CHROME" ]; then
    echo "✗ 找不到 Chrome: $CHROME" >&2
    echo "  可用 CHROME=/path/to/chrome bash Support/render-theme-icons.sh 指定" >&2
    exit 1
fi

# Chrome 打开 SVG 文件时按 1024×1024 内在尺寸排版、再按窗口裁切，
# 所以小尺寸不能直接改窗口宽——先按 1024 截全图，再用 sips 缩到目标尺寸。
render() {
    local svg="$1" out="$2" size="$3"
    local dir base url tmp
    dir="$(cd "$(dirname "$svg")" && pwd)"
    base="$(basename "$svg")"
    url="file://$dir/$base"
    tmp="${TMPDIR:-/tmp}/moniswitch-icon-render-$$.png"
    rm -f "$out" "$tmp"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
        --force-device-scale-factor=1 --default-background-color=00000000 \
        --screenshot="$tmp" --window-size=1024,1024 "$url" >/dev/null 2>&1 || true
    if [ ! -s "$tmp" ]; then
        echo "  ✗ 渲染失败: $svg" >&2
        exit 1
    fi
    sips -z "$size" "$size" "$tmp" --out "$out" >/dev/null
    rm -f "$tmp"
    local w
    w="$(sips -g pixelWidth "$out" | awk '/pixelWidth/ {print $2}')"
    if [ "$w" != "$size" ]; then
        echo "  ✗ 尺寸不符（期望 ${size}，实际 ${w}）: $out" >&2
        exit 1
    fi
}

echo "▶ 渲染主题图标资源"
mkdir -p "$OUT_DIR"

themes=0
for svg in "$THEME_DIR"/icon-*.svg; do
    base="$(basename "$svg" .svg)"
    case "$base" in
        icon-system-*) continue ;;
        tier*) continue ;;
    esac
    id="${base#icon-}"
    render "$svg" "$OUT_DIR/theme-$id.png" 512
    themes=$((themes + 1))
done

accents=0
for svg in "$THEME_DIR"/icon-system-*.svg; do
    base="$(basename "$svg" .svg)"
    accent="${base#icon-system-}"
    render "$svg" "$OUT_DIR/system-$accent.png" 512
    accents=$((accents + 1))
done

echo "  ✓ 主题 $themes 张 + 强调色 $accents 张 → Resources/AppIconThemes/"

# ---- 主图标（bundle 默认 = 跟随系统 / 蓝强调色）----
MAIN_SVG="$DESIGN_DIR/moniswitch-icon.svg"
render "$MAIN_SVG" "$DESIGN_DIR/moniswitch-icon-1024.png" 1024
mkdir -p "$DESIGN_DIR/sizes"
for s in 512 256 128 64 32 16; do
    sips -z "$s" "$s" "$DESIGN_DIR/moniswitch-icon-1024.png" \
        --out "$DESIGN_DIR/sizes/icon-$s.png" >/dev/null
done
cp "$DESIGN_DIR/moniswitch-icon-1024.png" "$RESOURCES_DIR/AppIcon-source.png"
echo "  ✓ 主图标 PNG + 尺寸阶梯 + AppIcon-source.png"

# ---- 重建 icns ----
echo "▶ 重建 AppIcon.icns"
bash "$SCRIPT_DIR/make-app-icon.sh"

echo ""
echo "完成。下一步：bash Support/build-app.sh"
