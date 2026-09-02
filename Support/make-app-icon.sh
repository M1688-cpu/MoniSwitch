#!/usr/bin/env bash
#
# make-app-icon.sh
# 从一张正方形（或近正方形）源图重建 macOS AppIcon.icns
#
# 两步：
#   1. 源图规整为 1024×1024（非正方形时，用 AppKit 合成：以源图边缘色填上下/左右边，
#      源图居中合成，避免简单纯色条带感）
#   2. sips 缩放 10 个标准尺寸 → AppIcon.iconset/ → iconutil -c icns → AppIcon.icns
#
# 源图规整用独立的 Swift 片段（Support/make-app-icon-square.swift），保持 macOS 原生工具链。
#
# 用法：bash Support/make-app-icon.sh [源图路径]
#       默认源图 = /tmp/moniswitch-ref/ref2-icon.png
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOURCES_DIR="$PROJECT_DIR/Resources"

SOURCE="${1:-/tmp/moniswitch-ref/ref2-icon.png}"
SQUARE_SWIFT="$SCRIPT_DIR/make-app-icon-square.swift"
SOURCE_1024="$RESOURCES_DIR/AppIcon-source.png"
ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
ICNS_OUT="$RESOURCES_DIR/AppIcon.icns"

echo "▶ 重建 AppIcon"
echo "  源图: $SOURCE"

if [ ! -f "$SOURCE" ]; then
    echo "  ✗ 源图不存在: $SOURCE" >&2
    exit 1
fi

# ---------- 1. 规整源图为 1024×1024 ----------
echo "  [1/3] 规整源图 → 1024×1024 ..."
swift "$SQUARE_SWIFT" \
    --source "$SOURCE" \
    --output "$SOURCE_1024"

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
    sips -g pixelWidth -g pixelHeight "$ICNS_OUT" 2>/dev/null | sed 's/^/    /'
else
    echo "  ✗ iconutil 失败" >&2
    exit 1
fi
