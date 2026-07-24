#!/bin/bash
#
# MoniSwitch 一键打包脚本
# 用途：编译 Swift 源码 → 组装 MoniSwitch.app → 签名 → 生成可分发的 .dmg
# 用法：在项目根目录执行  bash Support/build-app.sh
#
# 产物：
#   Support/MoniSwitch.app   — 打包好的 App
#   Support/MoniSwitch.dmg   — 可分发的安装镜像
#
set -e  # 任何命令失败立即退出

# ---------- 配置 ----------
APP_NAME="MoniSwitch"
BUNDLE_ID="com.moniswitch.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # Support/
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                  # 项目根目录
BUILD_DIR="$PROJECT_DIR/.build"
STAGING_DIR="$SCRIPT_DIR"                                     # .app/.dmg 产出在这里
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
DMG_PATH="$STAGING_DIR/$APP_NAME.dmg"

echo "▶ 项目目录: $PROJECT_DIR"
echo "▶ 产物目录: $STAGING_DIR"
echo ""

# ---------- 1. 编译 ----------
echo "▶ [1/6] 编译 release 版本..."
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -5

# 找到编译产物路径
BIN_PATH="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "✗ 找不到编译产物: $BIN_PATH"
    exit 1
fi
echo "  ✓ 编译完成: $BIN_PATH"
echo ""

# ---------- 2. 清理旧的产物 ----------
echo "▶ [2/6] 清理旧的产物..."
rm -rf "$APP_BUNDLE"
rm -f "$DMG_PATH"
echo "  ✓ 已清理"
echo ""

# ---------- 3. 组装 .app ----------
echo "▶ [3/6] 组装 $APP_NAME.app ..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 主可执行文件
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# 打包 displayplacer 进 Resources
if [ -f "$PROJECT_DIR/Resources/displayplacer" ]; then
    cp "$PROJECT_DIR/Resources/displayplacer" "$APP_BUNDLE/Contents/Resources/displayplacer"
    chmod +x "$APP_BUNDLE/Contents/Resources/displayplacer"
    echo "  ✓ 已打包 displayplacer"
else
    echo "  ⚠ 警告: 未找到 Resources/displayplacer，App 将无法切换显示器！"
    echo "    请按 Resources/README.md 说明放置二进制后重新打包。"
fi

echo "  ✓ .app 组装完成"
echo ""

# ---------- 4. 签名 ----------
# 重要：未签名的 displayplacer 会被 macOS Gatekeeper 杀掉（exit 137）。
# 这里用 ad-hoc 签名（-s -），适合本地/小范围分发。
# 若以后要正式分发，可改成用 Apple Developer ID 签名 + 公证。
echo "▶ [4/6] 清除隔离标记并签名..."

# 先清掉所有扩展属性（quarantine 等）
xattr -cr "$APP_BUNDLE"

# 给 displayplacer 单独签名（它是可执行二进制）
codesign --force --options runtime --sign - \
    "$APP_BUNDLE/Contents/Resources/displayplacer" 2>&1 | tail -2 || true

# 给整个 App 签名（深度）
codesign --force --deep --options runtime --sign - "$APP_BUNDLE" 2>&1 | tail -2 || true

# 验证签名
echo "  签名校验:"
codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1 | sed 's/^/    /' || true
echo "  ✓ 签名完成"
echo ""

# ---------- 5. 生成 DMG ----------
echo "▶ [5/6] 生成 $APP_NAME.dmg ..."

# 准备 DMG 暂存目录：.app + /Applications 拖拽安装软链接
DMG_STAGING="$PROJECT_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# 先建可读写 DMG，再转换为压缩只读 DMG（标准做法）
RW_DMG="$STAGING_DIR/$APP_NAME.tmp.dmg"
hdiutil create -volname "$APP_NAME" -fs HFS+ \
    -srcfolder "$DMG_STAGING" -format UDRW \
    -ov "$RW_DMG" 2>&1 | tail -2

hdiutil convert "$RW_DMG" \
    -format UDZO -imagekey zlib-level=9 \
    -ov -o "$DMG_PATH" 2>&1 | tail -2

rm -f "$RW_DMG"
rm -rf "$DMG_STAGING"

if [ -f "$DMG_PATH" ]; then
    echo "  ✓ DMG 生成完成: $DMG_PATH"
else
    echo "  ✗ DMG 生成失败"
    exit 1
fi
echo ""

# ---------- 6. 完成 ----------
echo "▶ [6/6] 打包完成！"
echo ""
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo ""
echo "  DMG 大小: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "  分发提示：未做 Apple 公证，用户首次打开可能需要在"
echo "  「系统设置 → 隐私与安全性」点击「仍要打开」。"
