#!/usr/bin/env bash
#
# make-app-icon.sh
# 重建 macOS AppIcon.icns
#
# 三种模式：
#   现成源图（默认，现行图标）：
#     直接使用 Resources/AppIcon-source.png（1024×1024，透明留白）生成 iconset/icns。
#     设计源在 design/icon-web/moniswitch-icon.svg；改图后先导出 1024 PNG 覆盖 source。
#       bash Support/make-app-icon.sh
#
#   旧版 Swift 自绘（legacy，仅实验/回归）：
#     调 make-app-icon-design.swift 渲染旧版蓝色显示器图标，会覆盖 source。
#       bash Support/make-app-icon.sh --redraw
#       bash Support/make-app-icon.sh --redraw --theme violet --traffic bezel
#
#   外部源图（会覆盖 source）：
#     先经 make-app-icon-square.swift 规整为 1024×1024，再生成 icns。
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

# 默认：直接使用现成 1024 源图（现行图标）。
# --redraw 才走旧版 Swift 自绘；--theme/--traffic 只对旧版自绘有效。
MODE="prebuilt"
MODE_SET=0
THEME="blue"
TRAFFIC="screen"
EXTERNAL_SOURCE=""

set_mode() {
    local requested="$1"
    if [ "$MODE_SET" -eq 1 ] && [ "$MODE" != "$requested" ]; then
        echo "✗ 模式冲突：已经指定 ${MODE}，不能再指定 ${requested}" >&2
        exit 2
    fi
    MODE="$requested"
    MODE_SET=1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prebuilt)
            set_mode prebuilt
            shift
            ;;
        --redraw)
            set_mode redraw
            shift
            ;;
        --theme)
            if [ $# -lt 2 ]; then
                echo "✗ --theme 需要值" >&2
                exit 2
            fi
            if [ "$MODE_SET" -eq 1 ] && [ "$MODE" != "redraw" ]; then
                echo "✗ --theme 只能和 --redraw 一起用（或省略模式）" >&2
                exit 2
            fi
            THEME="$2"
            MODE="redraw"
            MODE_SET=1
            shift 2
            ;;
        --traffic)
            if [ $# -lt 2 ]; then
                echo "✗ --traffic 需要值" >&2
                exit 2
            fi
            if [ "$MODE_SET" -eq 1 ] && [ "$MODE" != "redraw" ]; then
                echo "✗ --traffic 只能和 --redraw 一起用（或省略模式）" >&2
                exit 2
            fi
            TRAFFIC="$2"
            MODE="redraw"
            MODE_SET=1
            shift 2
            ;;
        -h|--help)
            sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "未知参数: $1" >&2
            exit 2
            ;;
        *)
            if [ -n "$EXTERNAL_SOURCE" ]; then
                echo "✗ 只能提供一个外部源图路径" >&2
                exit 2
            fi
            if [ "$MODE_SET" -eq 1 ] && [ "$MODE" != "external" ]; then
                echo "✗ 外部源图不能和 --prebuilt/--redraw 同时使用" >&2
                exit 2
            fi
            EXTERNAL_SOURCE="$1"
            MODE="external"
            MODE_SET=1
            shift
            ;;
    esac
done

echo "▶ 重建 AppIcon"

case "$MODE" in
    external)
        if [ ! -f "$EXTERNAL_SOURCE" ]; then
            echo "  ✗ 源图不存在: $EXTERNAL_SOURCE" >&2
            exit 1
        fi
        echo "  源图(外部): $EXTERNAL_SOURCE"
        echo "  [1/3] 规整源图 → 1024×1024 ..."
        swift "$SQUARE_SWIFT" \
            --source "$EXTERNAL_SOURCE" \
            --output "$SOURCE_1024"
        ;;
    redraw)
        echo "  源图(旧版 Swift 自绘): theme=$THEME traffic=$TRAFFIC"
        echo "  [1/3] 渲染旧版自绘图标 → 1024×1024 ..."
        swift "$DESIGN_SWIFT" \
            --theme "$THEME" \
            --traffic "$TRAFFIC" \
            --output "$SOURCE_1024"
        ;;
    prebuilt)
        if [ ! -f "$SOURCE_1024" ]; then
            echo "  ✗ 找不到现成源图: $SOURCE_1024" >&2
            echo "    请先把 design/icon-web/moniswitch-icon-1024.png 复制为 Resources/AppIcon-source.png" >&2
            exit 1
        fi
        echo "  源图(现成): $SOURCE_1024"
        echo "  [1/3] 使用现成 1024 源图（不重绘）"
        ;;
esac

SRC_W="$(sips -g pixelWidth "$SOURCE_1024" | awk '/pixelWidth/ {print $2}')"
SRC_H="$(sips -g pixelHeight "$SOURCE_1024" | awk '/pixelHeight/ {print $2}')"
if [ "$SRC_W" != "1024" ] || [ "$SRC_H" != "1024" ]; then
    echo "  ✗ 源图必须是 1024×1024，当前 ${SRC_W}×${SRC_H}" >&2
    exit 1
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
