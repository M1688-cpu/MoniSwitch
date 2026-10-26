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
#
# 环境变量 MONISWITCH_SDKROOT 可跳过自动探测、强制指定 SDK（2026-09-19 加）：
# 本机装了 MacOSX27.0.sdk 但 CLT 工具链没有它需要的 SwiftUIMacros 宏插件
# （SwiftUI 的 @State 在 27 SDK 改为宏展开），「最新获胜」会选到编译不了的
# 27.0。用法：MONISWITCH_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk bash Support/build-app.sh
if [ -n "$MONISWITCH_SDKROOT" ] && [ -d "$MONISWITCH_SDKROOT" ]; then
    export SDKROOT="$MONISWITCH_SDKROOT"
    echo "  SDK: $SDKROOT (MONISWITCH_SDKROOT 指定)"
else
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
    # 回退 xcrun 默认 SDK，也显式导出（下面要读它的版本号写进 LC_BUILD_VERSION）
    export SDKROOT="$(xcrun --show-sdk-path 2>/dev/null || true)"
    echo "  SDK: ${SDKROOT:-xcrun 默认}"
fi
fi

# ---- 设计语言门控：把真实 SDK 版本写进 LC_BUILD_VERSION ----
# SwiftPM 的链接命令只带 -target arm64-apple-macos14.0 + -sdk <27 SDK>，
# 驱动会按「部署目标」给链接器记 sdk = 14.0（不是编译用的 27.0）。AppKit 以
# LC_BUILD_VERSION.sdk 判断设计语言：sdk < 26 时 NSPopUpButton/NSSwitch 等
# 原生控件走旧外观（白底黑字下拉框、扁平开关），macOS 27 的液态玻璃、按住
# 开关左右拖动的液态拉伸都不会出现。编译期 SDK 选对也没用——必须让最终
# 二进制的 sdk 字段等于真实 SDK 版本（2026-10-17 实测：同源码只改这个字段，
# 控件立刻变原生玻璃）。裸 swift build 不带这些参数，属预期。
MIN_MACOS="14.0"   # 与 Package.swift 的 .macOS(.v14) 保持一致
SDK_VERSION="$(basename "${SDKROOT:-}" | sed -E 's/^MacOSX([0-9]+(\.[0-9]+)*)\.sdk$/\1/')"
case "$SDK_VERSION" in
    ""|*[!0-9.]*)
        # 自定义路径可能是指向真实 SDK 的符号链接：回退读 SDKSettings.plist
        SDK_VERSION="$(plutil -extract Version raw -o - "${SDKROOT:-}/SDKSettings.plist" 2>/dev/null || true)"
        ;;
esac
if [ -z "$SDK_VERSION" ]; then
    SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || true)"
fi
if [ -z "$SDK_VERSION" ]; then
    echo "✗ 无法确定 SDK 版本，拒绝打包（会导致控件退回旧设计语言）"
    exit 1
fi
echo "  SDK 版本: ${SDK_VERSION}（写入 LC_BUILD_VERSION 用于设计语言门控）"

cd "$PROJECT_DIR"
swift build -c release \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION" \
    2>&1 | tail -5

# 找到编译产物路径
BIN_PATH="$BUILD_DIR/release/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "✗ 找不到编译产物: $BIN_PATH"
    exit 1
fi
# 校验门控字段真的落进二进制（增量构建/参数被吞时这里会失败，避免又打出
# 一个「编译用 27 SDK、运行时按 14 SDK 画旧控件」的假新版）
RECORDED_SDK="$(otool -l "$BIN_PATH" | awk '/LC_BUILD_VERSION/{found=1} found && $1=="sdk"{print $2; exit}')"
if [ "$RECORDED_SDK" != "$SDK_VERSION" ]; then
    echo "✗ LC_BUILD_VERSION sdk=$RECORDED_SDK，与所选 SDK $SDK_VERSION 不一致"
    echo "  设置页控件会退回旧外观（无液态玻璃）。请检查 -Xlinker 参数。"
    exit 1
fi
if [ "$(printf '%s\n26.0\n' "$RECORDED_SDK" | sort -V | head -1)" != "26.0" ]; then
    echo "  ⚠ 记录的 SDK $RECORDED_SDK < 26：当前系统上仍是传统控件外观"
fi
echo "  ✓ 设计语言门控: LC_BUILD_VERSION sdk=$RECORDED_SDK"
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

# 主题图标（Dock 图标跟随面板主题；bundle 默认图仍是上面的静态 icns）
if [ -d "$PROJECT_DIR/Resources/AppIconThemes" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Resources/AppIconThemes"
    cp "$PROJECT_DIR/Resources/AppIconThemes/"*.png "$APP_BUNDLE/Contents/Resources/AppIconThemes/"
    echo "  ✓ 已打包主题图标 $(find "$PROJECT_DIR/Resources/AppIconThemes" -name '*.png' | wc -l | tr -d ' ') 张"
else
    echo "  ⚠ 警告: 未找到 Resources/AppIconThemes，App 图标不会随主题切换。"
    echo "    先运行: bash Support/render-theme-icons.sh"
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
#
# 签名身份（2026-10-17）：优先用本地自签名证书 "MoniSwitch Dev"（由
# Support/setup-dev-signing.sh 一次性创建）。ad-hoc 签名（-）的 code requirement
# 只含 cdhash，每次重新打包必变，TCC（输入监控/辅助功能）授权随之失效——这正是
# 「系统设置里开关亮着、App 里却显示未授权」的根因。自签名证书的 requirement 是
# identifier + 证书指纹，重新打包授权不丢。
# 可用环境变量 CODESIGN_IDENTITY 强制指定其它身份（如 Apple Development）；
# 找不到自签名身份时回退 ad-hoc（并明确警告）。
echo "▶ [4/6] 清除隔离标记并签名..."

# 先清掉所有扩展属性（quarantine 等）
xattr -cr "$APP_BUNDLE"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"MoniSwitch Dev"'; then
        SIGN_IDENTITY="MoniSwitch Dev"
    else
        SIGN_IDENTITY="-"
        echo "  ⚠ 未找到「MoniSwitch Dev」自签名身份，回退 ad-hoc；"
        echo "    重新打包后 TCC 授权会失效。先运行: bash Support/setup-dev-signing.sh"
    fi
fi
echo "  签名身份: $SIGN_IDENTITY"

# 给 displayplacer 单独签名（它是可执行二进制；主 App 不再 --deep，嵌套项须先签）
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE/Contents/Resources/displayplacer" 2>&1 | tail -2 || true

# 给整个 App 签名（displayplacer 已单独签过，这里不 --deep，避免重复签嵌套项）
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>&1 | tail -2 || true

# 验证签名
echo "  签名校验:"
codesign --verify --verbose=1 "$APP_BUNDLE" 2>&1 | sed 's/^/    /' || true
# 打印 code requirement：含 cdhash = ad-hoc，重新打包后必须重新授权
SIGN_REQUIREMENT="$(codesign -d -r- "$APP_BUNDLE" 2>&1 | tail -1)"
echo "  code requirement: $SIGN_REQUIREMENT"
case "$SIGN_REQUIREMENT" in
    *cdhash*)
        echo "  ⚠ requirement 含 cdhash（ad-hoc）：重新打包后 TCC 授权会失效"
        ;;
esac
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
