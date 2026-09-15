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
set -o pipefail  # 管道中前置命令失败也算失败（否则 `swift build | tail` 编译报错会被
                 # tail 的退出码 0 掩盖，脚本带着旧二进制继续打包出「假新版」，
                 # 2026-09-12 实际踩坑：矩阵实验跑了个寂寞）

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

# ---- SDK 自动探测：挑 CLT 与 Xcode 两处最新的 MacOSX*.sdk 显式指定 ----
# 背景：系统 chrome（NSPopover 背景板、NSSwitch 开关等）的 Liquid Glass
# 新观感只有用 macOS 26 SDK 编译才会被系统采用；xcode-select 默认指向的
# 工具链可能停在旧 SDK。这里不动系统默认，仅给本次 swift build 设 SDKROOT：
# 在 CLT（/Library/Developer/CommandLineTools/SDKs）与 Xcode
# （/Applications/Xcode.app/.../SDKs）两处找版本号最大的 SDK；找不到再回退
# xcrun 默认。直接 `swift build`（不经本脚本）不受影响。
NEWEST_SDK=""
NEWEST_VER=""
for SDK_CAND_DIR in \
    "/Library/Developer/CommandLineTools/SDKs" \
    /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs; do
    for SDK_CAND in "$SDK_CAND_DIR"/MacOSX*.sdk; do
        [ -d "$SDK_CAND" ] || continue
        SDK_VER="$(basename "$SDK_CAND" | sed -E 's/^MacOSX([0-9]+(\.[0-9]+)?)\.sdk$/\1/')"
        case "$SDK_VER" in
            *[!0-9.]*) continue ;;  # 解析不出版本号的（如 MacOSX.sdk）跳过
        esac
        # sort -V 全版本比较（15.5 > 15.2，26 > 15.5），空值时直接当选
        if [ -z "$NEWEST_VER" ] || [ "$(printf '%s\n%s\n' "$SDK_VER" "$NEWEST_VER" | sort -V | tail -1)" = "$SDK_VER" ]; then
            NEWEST_VER="$SDK_VER"
            NEWEST_SDK="$SDK_CAND"
        fi
    done
done
if [ -n "$NEWEST_SDK" ]; then
    export SDKROOT="$NEWEST_SDK"
    echo "  SDK: $SDKROOT (自动探测的最新版)"
else
    echo "  SDK: $(xcrun --show-sdk-path 2>/dev/null || echo 'xcrun 默认')"
fi

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

# 清理旧流程（手写 hdiutil+osascript 时代）的历史残留暂存目录
rm -rf "$PROJECT_DIR/dmg-staging"

# 用 create-dmg（npm: sindresorhus/create-dmg）生成，替代旧的手写
# hdiutil + AppleScript 流程。其默认布局：660×400 窗口、app 图标 (180,170)、
# Applications 拖放链接 (480,170)、icon 160pt、内置默认背景图；底层走
# appdmg 纯 Node 直接写 .DS_Store（不经 Finder AppleScript，旧流程的
# Finder 刷盘坑天然免疫）。
# 依赖（本机一次性安装）：brew install node && npm install --global create-dmg
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "✗ 未安装 create-dmg (npm: sindresorhus/create-dmg)"
    echo "  安装方式: brew install node && npm install --global create-dmg"
    exit 1
fi

rm -f "$DMG_PATH"

# --no-version-in-filename: 产物固定为 MoniSwitch.dmg（不带版本号后缀，
#   与发布流程的既有命名一致）
# --no-code-sign: 本项目无 Developer ID 证书；默认签名路径在找不到证书时
#   以退出码 2 失败（DMG 已生成但 set -e 会中断收尾步骤），显式跳过——
#   旧流程本来也不对 DMG 签名，行为一致
create-dmg \
    --overwrite \
    --no-version-in-filename \
    --no-code-sign \
    "$APP_BUNDLE" \
    "$STAGING_DIR"

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
