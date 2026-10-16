#!/bin/bash
# 运行单元测试。
# 注：CLT 新构建系统在测试目标「增量」重编译时偶发加载不了 Swift Testing 宏插件
# （TestingMacros not found），全量构建正常——本脚本先定向清测试目标中间产物规避。
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf .build/out/Intermediates.noindex/MoniSwitch.build/Debug/MoniSwitchTests* 2>/dev/null || true
rm -rf .build/out/Products/Debug/MoniSwitchTests* 2>/dev/null || true
exec env SDKROOT="${MONISWITCH_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}" swift test "$@"
