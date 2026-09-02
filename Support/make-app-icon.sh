#!/usr/bin/env bash
#
# make-app-icon.sh
# 重建 macOS AppIcon.icns
#
# 两种模式：
#   自绘（默认，无参数或 --theme/--traffic）：
#     调 Support/make-app-icon-design.swift 纯代码渲染 1024×1024 源图
#     （Liquid Glass 风格显示器，多主题可选），再 sips → iconutil。
#       bash Support/make-app-icon.sh                      # 靛蓝 + 屏内红绿灯
#       bash Support/make-app-icon.sh --theme violet       # 其他主题
#       bash Support/make-app-icon.sh --traffic bezel      # 红绿灯在边框下巴
#
#   外部源图（传入图片路径）：
#     先经 make-app-icon-square.swift 规整为 1024×1024（近正方形时
#     以边缘色合成补边，避免黑边），再 sips → iconutil。
#       bash Support/make-app-icon.sh /path/to/image.png
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$PROJECT_DIR/Resources"

DESIGN_SWIFT="$SCRIPT_DIR/make-app-icon-design.swift"
SQUARE_SWIFT="$SCRIPT_DIR/make-app-icon-square.swift"
SOURCE_1024="$RESOURCES_DIR/AppIcon-source.png"
ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
ICNS_OUT="$RESOURCES_DIR/AppIcon.icns"

# 默认主题/红绿灯摆法（v0.2.0 起的正式图标）
THEME="blue"
TRAFFIC="screen"
EXTERNAL_SOURCE=""

# 解析参数：--theme/--traffic 走自绘；非选项参数视为外部源图路径
while [ $# -gt 0 ]; do
    case "$1" in
        --theme)   THEME="${2:?--theme 需要值}"; shift 2 ;;
        --traffic) TRAFFIC="${2:?--traffic 需要值}"; shift 2 ;;
        -h|--help)
            sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)         EXTERNAL_SOURCE="$1"; shift ;;
    esac
done

echo "▶ 重建 AppIcon"

if [ -n "$EXTERNAL_SOURCE" ]; then
    # ---------- 模式 B：外部源图（旧流程） ----------
    if [ ! -f "$EXTERNAL_SOURCE" ]; then
        echo "  ✗ 源图不存在: $EXTERNAL_SOURCE" >&2
        exit 1
    fi
    echo "  源图(外部): $EXTERNAL_SOURCE"
    echo "  [1/3] 规整源图 → 1024×1024 ..."
    swift "$SQUARE_SWIFT" \
        --source "$EXTERNAL_SOURCE" \
        --output "$SOURCE_1024"
else
    # ---------- 模式 A：纯代码自绘（默认） ----------
    echo "  源图(自绘): theme=$THEME traffic=$TRAFFIC"
    echo "  [1/3] 渲染自绘图标 → 1024×1024 ..."
    swift "$DESIGN_SWIFT" \
        --theme "$THEME" \
        --traffic "$TRAFFIC" \
        --output "$SOURCE_1024"
fi

# ---------- 2. 生成 10 个标准尺寸 iconset ----------
echo "  [2/3] 生成 iconset ..."
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z   16   16 "$SOURCE_1024" --out "$ICONSET_DIR/icon_16x16.png"        >/dev/null
sips -z   32   32 "$SOURCE_1024" --out "$ICONSET_DIR/icon_16x16@2x.png"     >/dev/null
sips -z   32   32 "$SOURCE_1024" --out "$ICONSET_DIR/icon_32x32.png"        >/dev/null
sips -z   64   64 "$SOURCE_1024" --out "$ICONSET_DIR/icon_32x32@2x.png"     >/dev/null
sips -z  128  128 "$SOURCE_1024" --out "$ICONSET_DIR/icon_128x128.png"      >/dev/null
sips -z  256  256 "$SOURCE_1024" --out "$ICONSET_DIR/icon_128x128@2x.png"   >/dev/null
sips -z  256  256 "$SOURCE_1024" --out "$ICONSET_DIR/icon_256x256.png"      >/dev/null
sips -z  512  512 "$SOURCE_1024" --out "$ICONSET_DIR/icon_256x256@2x.png"   >/dev/null
sips -z  512  512 "$SOURCE_1024" --out "$ICONSET_DIR/icon_512x512.png"      >/dev/null
cp "$SOURCE_1024"                                "$ICONSET_DIR/icon_512x512@2x.png"

# ---------- 3. 编译 icns ----------
echo "  [3/3] iconutil → AppIcon.icns ..."
rm -f "$ICNS_OUT"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUT"
rm -rf "$ICONSET_DIR"

if [ -f "$ICNS_OUT" ]; then
    echo "  ✓ 完成: $ICNS_OUT"
else
    echo "  ✗ iconutil 失败" >&2
    exit 1
fi
