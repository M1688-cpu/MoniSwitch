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
  AppIcon.icns              # 应用图标（make-app-icon.sh 产物）
  AppIcon-source.png        # 图标源图（make-app-icon-square.swift 产物，1024×1024）
  dmg-background.png        # DMG 安装包背景图（make-dmg-background.swift 产物，1320×800 @2x）
  displayplacer             # 不入库（.gitignore 排除）
Support/
  Info.plist                # App 元信息
  build-app.sh              # 打包脚本（编译 → .app → 签名 → .dmg，DMG 段会写 Finder 视图元数据）
  make-dmg-background.swift # 生成 DMG 背景图（裁波浪源图中部 + 绘箭头）
  make-app-icon.sh          # 从源图重建 AppIcon.icns（调用 make-app-icon-square.swift + sips + iconutil）
  make-app-icon-square.swift# 把任意尺寸图标源规整为 1024×1024 正方形（采样背景色填充，避免黑边）
  make-dmg-preview.swift    # 合成 README 用的 DMG 安装窗口预览图（背景 + app 图标 + Applications 图标）
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
- 全局快捷键（每个预设绑定一个快捷键，Carbon RegisterEventHotKey，无需辅助功能权限）
- 菜单栏面板气泡化：每个功能分栏是一张独立圆角气泡卡片，四周带悬浮阴影，垂直悬浮于原生 popover 上。背景历经迭代：ultraThinMaterial+thinMaterial 双层叠加（发灰发平，已弃）→ thinMaterial+浅色叠白提亮（通透但关于页能看到底色）→ **现版：不透明填充**（浅色纯白 / 深色 `BubbleMetrics.bubbleDarkFill` 接近系统卡片色），由 `BubbleBackground` modifier 统一控制（设置卡片 + 菜单栏 BubbleCard/bottomToolbar 共用）
- 强调色跟随 macOS 系统强调色：`BrandColor.accent` 改为 `Color(NSColor.controlAccentColor)`（动态色），用户在「系统设置 > 外观 > 强调色」切换时面板/设置窗口实时刷新。**不再有自定义品牌蓝**；项目约定「纯 SPM、无 xcassets」，故不引入 `AccentColor.colorset`，直接桥接 AppKit 动态色（`import AppKit` 已在用）
- 列表行 hover 高亮（显示器选择行 / 预设行）：`hoverRowHighlight()` 修饰器，悬停时叠半透明强调色背景，类原生菜单反馈
- 设置窗口顶部滚动毛玻璃：内容区标题（DetailHeader）改经 `.safeAreaInset(edge: .top)` 悬浮于滚动内容之上——静止时无背景（与旧固定标题观感一致），滚动时内容从标题底下穿过，`HeaderFadeBackdrop` 按「已滚出距离 / `BubbleMetrics.headerBlurRamp`(24pt)」把 thinMaterial 从透明渐入实心，底边留 `headerBlurFadeTail`(18pt) 渐隐尾巴（LinearGradient mask），无硬切线；玻璃层 `ignoresSafeArea(.top)` 顶到窗口顶（红绿灯在边栏 x 范围内不受影响）。滚动偏移由 `ScrollOffsetReader`（NSViewRepresentable，沿 superview 链找 NSClipView、监听 bounds 变更通知）从各 tab 滚动内容的 background 回写 SettingsView 的 `@State contentScrollOffset`——**不能用 GeometryReader+PreferenceKey**：静止时读到的偏移 = 标题栏+悬浮头的安全区 inset，还得找参照物归零；NSClipView bounds 原点与 inset 无关，静止恒 0。探针必须挂在滚动内容上（挂 ScrollView 外壳的 background 走不到 NSClipView）；挂载即上报当前值，切 tab 自动复位。AboutTab 也为此包进了 ScrollView（内容不满屏不可滚，观感不变）。注意当前 SDK 属性名是复数 `postsBoundsChangedNotifications`（旧 SDK 单数）
- 排列卡片表单化（v0.1.4）：排列行改为「系统设置表单风」——位置行（`位置` 标题 + 左/右分段控件 `sideSegmented`，当前侧强调色实心，替代原两个小胶囊按钮）+ 分辨率行 + 刷新率行，标题靠左、控件靠右统一对齐；标题行右侧 ◀/▶ 小指示因与分段控件状态重复已删
- 分辨率/刷新率行内展开（v0.1.4）：`SelectionRow` 弃用原生 `Menu`，改自绘「点击整行 → 面板内向下展开选项列表」（当前项 ✓、行 hover 高亮、选项多时 ScrollView 限高 216pt、浅灰圆角底）。**根因：SwiftUI `Menu` 在 `MenuBarExtra(.window)` 的 borderless 弹出面板内会弹成分离的空白窗口（macOS 系统级渲染 bug，实测必现，非特定屏才触发）**，行内展开结构性绕开该 bug；右侧 chevron 双箭头图标也一并移除
- 单内置屏可调节分辨率/刷新率（v0.1.4）：无外接屏时「排列与镜像」卡不再整体隐藏，退化为「显示器调节」卡（`panelDisplayAdjust` 键 + slider.horizontal.3 图标）：只保留内置屏的分辨率/刷新率行（`ArrangementRow.showsPosition=false` 隐藏位置行），镜像/扩展行与分隔线一并隐藏
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

（当前无）

## 已恢复功能

### 全局快捷键（v0.1.2 曾实现移除，现已重新实现）
- 0.1.2 开发期间曾实现，因 Carbon 事件分发与 SwiftUI 集成问题（GetEventDispatcherTarget 修复后仍不稳定）暂缓。
- 现重新实现（`HotkeyManager.swift`）：每个预设可绑定一个全局快捷键，按下即应用该布局。无辅助功能权限依赖（`RegisterEventHotKey` 是标准 API）。
- 修复之前不稳定的根因：
  - **必须用 `GetEventDispatcherTarget()`**（非 `GetApplicationEventTarget`）：SwiftUI/MenuBarExtra App 不跑传统 Carbon 事件循环，只有 dispatcher target 能投递。事件处理器装一次,永久存活。
  - **录键强制"修饰键+主键"组合**：用 `NSEvent.addLocalMonitorForEvents(.keyDown)`，单独按修饰键/单按字母键都忽略，Esc 取消。
  - **全量原子重注册**：presets 变化时先 `unregisterAll()` 再逐个 `RegisterEventHotKey`，消除"删旧 ref 与加新 ref 之间的窗口"竞态。由 `AppState.setupHotkeyBinding()` 订阅 `PresetManager.$presets` 触发（启动时也会跑一次，恢复持久化的绑定）。
  - **主线程回调**：Carbon 事件命中 → 查 hotKeyId→presetId → `DispatchQueue.main.async { PresetManager.shared.applyById(id) }`，所有 PresetManager/AppSettings 访问统一主线程。
- **keyCode → 显示字符的方案变更**（重要，推翻了上一版的结论）：
  - 上一版记录"用 UCKeyTranslate 动态转换，比静态表准确"。
  - 实测发现 macOS 13+ SDK **不再把 TIS 系列 C 函数**（`TISGetCurrentInputSource` 等）**导出到 Swift 的 Carbon 模块**，纯 Swift 拿不到当前键盘布局的 `UCKeyboardLayout*` 数据（需 C bridging target，与本项目"纯 SPM、无子目录"结构冲突）。`UCKeyTranslate` 本身可见，但没有布局数据喂不进去。
  - 现改用 **`kVK_*` 静态映射表**（`HotkeyManager.keyCodeNames`）：QWERTY 布局下显示完全正确；非 QWERTY 布局下显示的是"该键位在 QWERTY 上的对应字符"，仍可读，且**不影响功能**（Carbon 用 keyCode 注册，与显示解耦）。
- 热键绑定数据仍由保留的脚手架承载：`HotkeyBinding`（Models.swift）、`Preset.hotkey`、`PresetManager.setHotkey` + 自动持久化（`presets.didSet → persist()`）。
- **命中回调读 hotKeyId 的陷阱（重要，曾导致快捷键"注册成功但按下无反应"）**：`GetEventParameter` 用 `typeEventHotKeyID` 取回的是完整的 `EventHotKeyID` 结构体（8 字节 = signature + id），必须读进 `EventHotKeyID` 变量再取 `.id`。早期版本误把它写进单个 `UInt32`（4 字节）缓冲区：既栈溢出，又在小端序下把 signature（`'MSSW'`=0x4D535357）当成 id，导致 `bindings[hotKeyId]` 恒为 nil、`applyById` 永不触发。


## 注意事项

- **设置窗口不要在根视图 `.tint(桥接 AppKit 动态色)`**（2026-08 实测踩坑）：曾加过 `.tint(Color(NSColor.controlAccentColor))`，在 macOS 15 实机上会让 `.menu` 样式 Picker 的箭头指示胶囊**实况渲染成红色**（系统强调色并非红；离屏 `dataWithPDF` 渲染不可复现——属实况合成路径对桥接动态色的解析失败，换 NSColor.systemGray 等其它桥接色同样有风险）。SwiftUI 控件默认就跟随系统强调色，根级 tint 本就冗余，已删。两个下拉框（语言/刷新间隔）改挂 `menuPickerNeutralTint()`（SwiftUI 静态 `Color.gray`，非桥接色）压中性灰指示器；若日后胶囊仍现异常色，兜底是 `.menuIndicator(.hidden)`。
- **边栏未选中图标刻意比 `.secondary` 深一档**：`Color.primary.opacity(0.78)` + `medium` 字重（SidebarRow）。`.secondary` + regular 在 16pt 下笔画太细、与 regularMaterial 背景融合看不清（像素实测对比度 1.8:1 → 加深后 4.5:1）；选中态仍用 `BrandColor.accent`。
- displayplacer 二进制不入 git，打包脚本从 Resources/ 目录拷入 .app
- DockPolicyManager 的 NSToolbar 居中标题：window.title 必须留空，否则 NavigationSplitView 会继承并在边栏重复渲染
- windowWillClose 无条件延迟 0.2s 后 setActivationPolicy(.accessory)，确保 Dock 图标消失
- **设置窗口仅原生标题栏可拖**：`window.isMovableByWindowBackground = false`（DockPolicyManager.openSettings）。配合 `.fullSizeContentView` + 透明标题栏,SwiftUI 边栏/内容区的 `.regularMaterial` 背景会变成"非控件背景",若开 `isMovableByWindowBackground` 则哪都能拖；关掉后只有顶部红绿灯按钮条可拖,对齐系统设置窗口行为
- **MenuBarExtra `.window` 样式的菜单栏图标必须用模板 NSImage**：`.window` 样式下面板打开时系统给图标加深色高亮背景，非模板的 SwiftUI 视图（用 `.foregroundColor(.primary)` 描边）会与高亮背景同色，表现为图标位置一整块黑。正确做法：用 `ImageRenderer` 把自绘视图离屏渲染成 `NSImage`，设 `isTemplate = true`，再由 label 承载（`Image(nsImage:).renderingMode(.template)`）。模板 image 由系统在深浅/高亮态自动反色，稳定可见。代码见 `MoniSwitchApp.menuBarIcon`。
- **AppIcon.icns 重建流程**：现由 `bash Support/make-app-icon.sh <源图>` 一键完成——内部先调 `make-app-icon-square.swift` 把任意尺寸源图规整为 1024×1024（采样中心区域平均色填上下/左右边，避免黑边；源图四周常有透明环，直接取边缘会采到 alpha=0），再 `sips` 缩放 10 个标准尺寸（16/32/128/256/512 各 @1x@2x）→ `iconutil -c icns`。产物 `Resources/AppIcon-source.png` + `Resources/AppIcon.icns`。`build-app.sh` 只做 `cp Resources/AppIcon.icns → .app`，所以重建 icns 后无需改打包脚本。README 顶部内嵌 logo 指向 `Resources/AppIcon-source.png`，换图标后自动跟着变。
- **DMG 安装包背景与图标布局由三个脚本协作**（改背景/箭头/图标位置，不要手改 DMG）：`make-dmg-background.swift` 生成 `Resources/dmg-background.png`（1320×800 @2x = Finder 窗口 660×400 逻辑点；波浪源图居中裁 33:20 中部 + 绘半透明白曲线箭头，箭头 y 与图标中心对齐）；`build-app.sh` 第 5 步把背景打进 `.background/` 隐藏目录，再用 `osascript` 写 Finder 视图元数据（背景 / 窗口 bounds `{0,0,660,400}` / 图标 128pt / 位置 `{140,180}` MoniSwitch.app + `{480,180}` Applications）；`make-dmg-preview.swift` 合成 README 用的 DMG 窗口预览图（沙箱 `screencapture` 不可靠时的替代）。改图标位置：同时改 `make-dmg-background.swift` 的箭头坐标 + `build-app.sh` osascript 段的 `set position`。
- **DMG osascript 写 .DS_Store 的两个坑（曾导致背景与图标位置全部丢失，已踩过）**：① **不能用 `-mountpoint` 自定义挂载点**，Finder 只往默认 `/Volumes/<卷名>` 写 `.DS_Store`；② **背景别名必须在 `tell disk` 块外解析**（`set bgFile to POSIX file ".../dmg-background.png"`），块内直接 `file ".background:..."` 会因 HFS 冒号路径被 Finder 误解报 -17006/-1700，且 `as alias` 转换也会失败。验证是否写入成功：挂载后 `python3` 原始解析 `.DS_Store` 找 `Iloc`（图标位置）+ `icvp`（背景引用 `dmg-background`）记录；二进制层确认最可靠，视觉确认（screencapture）在多屏/无头环境可能失败但不影响真实 DMG 内容。
- 远程仓库: https://github.com/M1688-cpu/MoniSwitch.git
- **displayplacer persistent id 会漂移**：外接屏唤醒/重新插拔/换屏后 persistent id 可能变化，导致预设失效。当前无 ID 重映射兜底，漂移时需重新保存预设
- **displayplacer 镜像用 `id:A+B` 语法**：镜像组的屏合并成一条 arg（共用基准屏的 res/scaling/origin），不能拆成多条 origin 相同的独立 arg（会让 displayplacer 误判，把后执行的屏设为主屏）
- **`Support/MoniSwitch.app` / `Support/MoniSwitch.dmg` 是 `build-app.sh` 的产物，不是源码镜像**：改完代码必须重新 `bash Support/build-app.sh` 才会更新；光 `swift build` 只更新 `.build/debug|release/MoniSwitch` 裸二进制，不会进 .app。本地验证最新 UI 的两种方式：①直接跑 `Support/MoniSwitch.app`（双击或 `open Support/MoniSwitch.app`，能验证完整 .app 包结构含 displayplacer）；②跑 `.build/debug/MoniSwitch`（最快迭代，但无 .app 包结构、无 displayplacer 依赖）。注意 `build-app.sh` 用的是 release 构建产物。
- **同 bundle id 的多份 .app 会污染 LaunchServices 缓存**：`open -a MoniSwitch` / Spotlight / Launchpad 都按 bundle id 查 LaunchServices 数据库，会解析到任意一份已登记的 .app（包括挂载中的 DMG、废纸篓、`dmg-staging/` 临时目录里的），导致「启动的是旧版」。曾出现的真实场景：开发期间双击挂载过 `Support/MoniSwitch.dmg` 且没卸载，LaunchServices 就一直登记着 DMG 里那份旧 app，`open -a` 永远启动旧版。排查：`lsregister -dump | grep -i moniswitch` 看所有登记路径；登记指定那份：`lsregister -f <path>`；注销过时那份：`lsregister -u <path>`（仅动数据库，不删文件，对废纸篓里的也安全）。发布/验证前确保只剩目标那一份登记。
- **自动化验证面板 UI 的可行路径与坑**（2026-08 实测，macOS 15）：菜单栏图标坐标可由 `CGWindowListCopyWindowInfo` 取（owner=MoniSwitch、layer=25、name=Item-0 的小窗口）；面板窗口是 layer=101 的 380 宽窗口。CGEvent 合成点击**能点开/点关菜单栏图标**，但**对面板内容的控件无效**（Button 不触发，原因未深究）——面板内交互只能人肉验证。另注意：其他菜单栏 App 的面板开着时会吞掉第一次图标点击，先点一下桌面收起它；视觉分析截图必须用**唯一文件名**，CDN 按文件名缓存、重名图会拿到旧内容。

## 风格约定

- Release notes 不使用 emoji
- 注释用中文
- 代码风格跟随现有文件的缩进和命名
