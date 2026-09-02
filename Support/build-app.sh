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

# 应用图标
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  ✓ 已打包应用图标 AppIcon.icns"
else
    echo "  ⚠ 警告: 未找到 Resources/AppIcon.icns，App 将使用默认图标。"
fi

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

# 准备 DMG 暂存目录：.app + /Applications 拖拽安装软链接 + 隐藏背景图
DMG_STAGING="$PROJECT_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# 背景图打进 .background/ 隐藏目录（若不存在则跳过，退化为无背景 DMG）
DMG_BG_SOURCE="$PROJECT_DIR/Resources/dmg-background.png"
if [ -f "$DMG_BG_SOURCE" ]; then
    mkdir -p "$DMG_STAGING/.background"
    cp "$DMG_BG_SOURCE" "$DMG_STAGING/.background/dmg-background.png"
    echo "  ✓ 接入背景图: dmg-background.png"
else
    echo "  ⚠ 未找到 Resources/dmg-background.png，将生成无背景 DMG"
fi

# 先建可读写 DMG，再设置 Finder 视图，最后转换为压缩只读 DMG
RW_DMG="$STAGING_DIR/$APP_NAME.tmp.dmg"
hdiutil create -volname "$APP_NAME" -fs HFS+ \
    -srcfolder "$DMG_STAGING" -format UDRW \
    -ov "$RW_DMG" 2>&1 | tail -2

# ---- 用 AppleScript 设置 Finder 视图元数据（背景 / 窗口大小 / 图标位置）----
# 关键经验（曾导致背景与图标位置全部丢失）：
#   1. 不能用 -mountpoint 自定义挂载点 → Finder 不会往自定义路径的卷写 .DS_Store。
#      必须默认挂载到 /Volumes/<卷名>，Finder 才会把视图元数据刷盘。
#   2. 不能在 tell disk 块里把 POSIX file "..." as alias 直接当背景赋值
#      （HFS 路径冒号会被 Finder 误解，报 -1700）。需先在块外解析成变量再传入。
VOLUME="/Volumes/$APP_NAME"
# 若该卷名已被占用（残留挂载），先尝试卸载
hdiutil detach "$VOLUME" -force -quiet 2>/dev/null || true
hdiutil attach "$RW_DMG" -quiet

BG_PATH="$VOLUME/.background/dmg-background.png"

osascript <<APPLESCRIPT
set bgFile to POSIX file "$BG_PATH"
tell application "Finder"
    activate
    tell disk "$APP_NAME"
        open
        delay 2
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {0, 0, 660, 400}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to bgFile
        set position of item "$APP_NAME" of container window to {140, 180}
        set position of item "Applications" of container window to {480, 180}
    end tell
end tell
APPLESCRIPT

# 给 Finder 一点时间把 .DS_Store 刷盘，再卸载
sleep 2
hdiutil detach "$VOLUME" -quiet 2>&1 || hdiutil detach "$VOLUME" -force -quiet 2>&1 || true

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
