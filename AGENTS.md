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
- 设置窗口（NavigationSplitView 边栏 + 通用/预设/关于页）
- 自定义应用图标
- 设置窗口标题整窗居中（NSToolbar centeredItemIdentifiers）
- 开机自启动、自动刷新列表、菜单显示刷新率/HiDPI
- 显示器布局预设（保存/应用/删除，菜单栏联动，感知镜像组）
- 菜单内切换外接屏刷新率
- Release v0.1.1 产物在 dist/

## 已知 bug（待修复）

### 通知 bug：镜像/扩展操作的通知不弹出
- 现象：切主屏/左右移动/改刷新率的通知正常弹出；但镜像、扩展、预设应用这三类操作的通知不弹出。
- 根因（已诊断，非猜测）：这三类操作会让 displayplacer 触发系统级显示器重新配置（display mode 切换），全程约 1.2~1.5 秒。期间 UNUserNotificationCenter 的投递被系统中断/丢弃。代码层面 sendSwitchNotification 已被正确调用（日志证实 enabled=true），问题在 macOS 通知投递时机。
- 已尝试但无效的方案：
  - UNTimeIntervalNotificationTrigger 延迟投递（延迟只决定何时显示，不解决提交时机问题）
  - DispatchQueue.main.asyncAfter 延迟 0.8s 提交（displayplacer 重配要 1.2s，0.8s 时仍在重配窗口内）
- 待尝试的方案：
  - 延迟 2s+ 提交（需验证 2s 是否足够）
  - 改用 NSUserNotification（旧 API，对运行时状态不敏感）
  - 用 Process 完成回调而非固定延迟来判定重配结束

## 暂缓功能（下个版本）

### 全局快捷键（已实现但移除）
- 0.1.2 开发期间曾实现，因 Carbon 事件分发与 SwiftUI 集成问题（GetEventDispatcherTarget 修复后仍不稳定）暂缓。
- 关键经验（下个版本复用）：
  - 全局快捷键必须用 GetEventDispatcherTarget，不能用 GetApplicationEventTarget——后者需传统 Carbon 事件循环
  - 录键必须要求"修饰键+主键"组合，避免单独按键误录
  - keyCode 显示用 UCKeyTranslate 动态转换，比静态表准确
- 保留的脚手架：Models.swift 的 HotkeyBinding 结构体、Preset.hotkey 字段（保数据兼容）

## 注意事项

- displayplacer 二进制不入 git，打包脚本从 Resources/ 目录拷入 .app
- DockPolicyManager 的 NSToolbar 居中标题：window.title 必须留空，否则 NavigationSplitView 会继承并在边栏重复渲染
- windowWillClose 无条件延迟 0.2s 后 setActivationPolicy(.accessory)，确保 Dock 图标消失
- 远程仓库: https://github.com/M1688-cpu/MoniSwitch.git
- **displayplacer persistent id 会漂移**：外接屏唤醒/重新插拔/换屏后 persistent id 可能变化，导致预设失效。当前无 ID 重映射兜底，漂移时需重新保存预设
- **displayplacer 镜像用 `id:A+B` 语法**：镜像组的屏合并成一条 arg（共用基准屏的 res/scaling/origin），不能拆成多条 origin 相同的独立 arg（会让 displayplacer 误判，把后执行的屏设为主屏）

## 风格约定

- Release notes 不使用 emoji
- 注释用中文
- 代码风格跟随现有文件的缩进和命名
