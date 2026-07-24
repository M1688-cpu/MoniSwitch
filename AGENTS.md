# MoniSwitch 项目上下文

## 项目简介

macOS 菜单栏显示器快捷切换工具。纯菜单栏 App（LSUIElement=YES），无 Dock 图标无主窗口。
底层调用 displayplacer 完成显示器切换。

## 技术栈

- Swift 6 / SwiftUI / macOS 13+ (MenuBarExtra)
- 纯 Swift Package Manager 构建，命令行 `swift build` 或 `bash Support/build-app.sh` 打包
- 非 Xcode 项目，无 .xcodeproj

## 构建与打包

```bash
swift build                    # debug 编译
swift build -c release         # release 编译
bash Support/build-app.sh      # 一键打包（编译 → .app → 签名 → .dmg）
```

产物在 `Support/` 下（已被 .gitignore 忽略，不入库）。
发布产物统一放 `dist/`（也被 .gitignore 忽略）。

## 项目结构

```
Sources/MoniSwitch/
  MoniSwitchApp.swift      # 菜单栏 UI 入口
  Models.swift              # 显示器数据模型
  ShellRunner.swift         # displayplacer 调用封装
  DisplayManager.swift     # 解析 + 切换算法
  DockPolicyManager.swift   # Dock 策略管理 + 设置窗口（NSWindow + NSToolbar）
  SettingsView.swift        # 设置窗口 SwiftUI 视图（NavigationSplitView）
  Localization.swift        # 中英双语（L10n 类 + TextKey 枚举）
Resources/
  AppIcon.icns              # 应用图标
  AppIcon-source.png        # 图标源图
  displayplacer             # 不入库（.gitignore 排除）
Support/
  Info.plist                # App 元信息
  build-app.sh              # 打包脚本
```

## Git 历史

- `0d6db61` Initial commit
- `bf0b922` 移除搜索栏、调整窗口 680×460、隐藏标题栏、简化 windowWillClose
- `c28d840` 添加 AppIcon、设置窗口标题整窗居中（NSToolbar + centeredItemIdentifiers）
- `2b37989` 修复"设置"标题重复出现三次（window.title 置空、.navigationTitle("")、toolbar label 清空）
- `25f7657` 版本号 bump 到 0.1.1
- `48e5a1e` gitignore dist/
- Tag: `v0.1.1` — 首个公开 release

## 已完成的功能

- 菜单栏常驻，点击弹出显示器列表
- 一键切换主屏、左右移动外接屏、扩展/镜像切换
- 中英双语界面切换
- 设置窗口（NavigationSplitView 边栏 + 通用/关于页）
- 自定义应用图标
- 设置窗口标题整窗居中（NSToolbar centeredItemIdentifiers）
- Release v0.1.1 产物在 dist/

## 注意事项

- displayplacer 二进制不入 git，打包脚本从 Resources/ 目录拷入 .app
- DockPolicyManager 的 NSToolbar 居中标题：window.title 必须留空，否则 NavigationSplitView 会继承并在边栏重复渲染
- windowWillClose 无条件延迟 0.2s 后 setActivationPolicy(.accessory)，确保 Dock 图标消失
- 远程仓库: https://github.com/M1688-cpu/MoniSwitch.git

## 风格约定

- Release notes 不使用 emoji
- 注释用中文
- 代码风格跟随现有文件的缩进和命名
