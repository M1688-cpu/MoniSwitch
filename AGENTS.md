# MoniSwitch 项目上下文

## 项目简介

macOS 菜单栏显示器快捷切换工具。纯菜单栏 App（LSUIElement=YES），无 Dock 图标无主窗口。
底层调用 displayplacer 完成显示器切换。

## 技术栈

- Swift 6 / SwiftUI / macOS 13+（NSStatusItem + NSPopover 菜单栏面板）
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
  MoniSwitchApp.swift      # @main 入口（AppDelegate 创建菜单栏图标 + ⌘, 命令）+ menuBarIcon
  PanelController.swift    # 菜单栏面板控制器（NSStatusItem + NSPopover + NSHostingController
                           #   承载 PanelView；开关/竞态守卫/图标高亮/AppState 宿主）
  AppState.swift           # UI 状态对象：显示器列表 + 全部切换操作 + isOperating 进行中状态
  PanelView.swift          # 菜单栏气泡卡片面板（主屏/排列/预设/交互式布局预览，宿主 NSPopover）
  Components.swift         # 全站共享视觉组件（BrandColor/BubbleBackground/BubbleCard/
                           #   SettingsCard/RowButton/ActivePill/IndeterminateBar/PlainIcon…）
  BubbleMetrics.swift      # 圆角/字号/间距刻度 + 气泡深色填充色 + bubbleShadow()
  Models.swift             # 显示器数据模型（DisplayInfo/ResolutionOption/HotkeyBinding/Preset）
  ShellRunner.swift        # displayplacer 调用封装
  DisplayManager.swift     # 解析 + 切换算法 + 稳定检测 + 自动排列 + id 漂移重映射
  AppSettings.swift        # 用户偏好单例（自启动/通知/自动刷新）+ 通知发送
  PresetManager.swift      # 预设管理（保存/应用/删除/快捷键绑定，isApplying）
  HotkeyManager.swift      # 全局快捷键（Carbon RegisterEventHotKey，零权限）
  DockPolicyManager.swift  # Dock 策略管理 + 设置窗口宿主（NSWindow）
  SettingsView.swift       # 设置窗口骨架（边栏 + 悬浮标题 + 滚动毛玻璃 + ScrollOffsetReader）
  SettingsTabs.swift       # 设置窗口三个标签页（GeneralTab/PresetsTab/AboutTab/PresetRow）
  Localization.swift       # 中英双语（L10n 类 + TextKey 枚举，t() 支持 %d 与 %@）
Resources/
  AppIcon.icns              # 应用图标（make-app-icon.sh 产物）
  AppIcon-source.png        # 图标源图（make-app-icon-design.swift 自绘产物，1024×1024）
  dmg-background.png        # DMG 安装包背景图（make-dmg-background.swift 产物，1320×800 @2x）
  displayplacer             # 不入库（.gitignore 排除）
Support/
  Info.plist                # App 元信息
  build-app.sh              # 打包脚本（编译 → .app → 签名 → .dmg，DMG 段会写 Finder 视图元数据）
  make-dmg-background.swift # 生成 DMG 背景图（裁波浪源图中部 + 绘箭头）
  make-app-icon.sh          # 重建 AppIcon.icns（默认调自绘脚本；传源图路径走旧外部图流程）
  make-app-icon-design.swift# 纯代码自绘图标（Liquid Glass 风格显示器，6 主题×2 红绿灯摆法，--all 出预览）
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

### 版本线说明（2026-09 v0.1.4 发版时记录，重要）

- **公开版本线**：v0.1.1 → v0.1.2 → v0.1.3 → **v0.1.4**（发版前远端 main/tag 一直停在 v0.1.3，v0.1.4 是其后第一个公开版本）
- **本地 `v0.2.0` / `v0.2.0-checkpoint` tag 从未推送，也不要推送**：那是本地开发线的一次「v0.2.0 改版」（commit 2d3cd6e），最终随 v0.1.4 一起公开发布；推这两个 tag 会在 GitHub 上出现比 0.1.4 大的幻影版本号，把版本线搞乱。推送只用 `git push origin main v0.1.4`，**永远不要 `git push --tags`**
- v0.1.4 公开增量 = v0.1.3 以来的全部本地提交（通知根治/面板交互升级/自动排列/防漂移/自绘图标/HiDPI 根治/排列卡全屏可调/液态玻璃加入又回退（净零）/面板折叠与 hover/NSPopover 迁移/面板塌缩修复），release notes 按「从 v0.1.3 升级」视角撰写（dist/RELEASE_NOTES-v0.1.4.md）

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
- 分辨率/刷新率行内展开（v0.1.4）：`SelectionRow` 弃用原生 `Menu`，改自绘「点击整行 → 面板内向下展开选项列表」（当前项 ✓、行 hover 高亮、选项多时 ScrollView 限高 216pt、浅灰圆角底）。**根因：SwiftUI `Menu` 在 `MenuBarExtra(.window)` 的 borderless 弹出面板内会弹成分离的空白窗口（macOS 系统级渲染 bug，实测必现，非特定屏才触发）**，行内展开结构性绕开该 bug（面板宿主已换 NSPopover，但 SelectionRow 自绘方案保留——观感与交互已定型）；右侧 chevron 双箭头图标也一并移除
- 单内置屏可调节分辨率/刷新率（v0.1.4）：无外接屏时「排列与镜像」卡不再整体隐藏，退化为「显示器调节」卡（`panelDisplayAdjust` 键 + slider.horizontal.3 图标）：只保留内置屏的分辨率/刷新率行（`ArrangementRow.showsPosition=false` 隐藏位置行），镜像/扩展行与分隔线一并隐藏
- **通知 bug 根治（v0.2.0）**：`DisplayManager.waitForStableDisplays()` 轮询 `displayplacer list`（0.25s 间隔，最多 3s），连续两次输出签名一致（id/res/origin/hz/isMain）判定系统重配完成，替代「按 OpKind 分类盲等 2s 提交通知 + runOp 盲等 0.4s 重读列表」的旧写法。一个检测同时解决「读列表太早读到旧值（面板高亮不跟随）」和「通知提交被重配窗口中断丢弃」两个问题。**时序契约：sendSwitchNotification 的调用方必须已在稳定后调用**（runOp 与 PresetManager.apply 都先 waitForStableDisplays）
- 面板交互升级（v0.2.0）：操作进行中 `AppState.isOperating`/`PresetManager.isApplying` 禁用卡片区 + 顶部 overlay 流动进度条 `IndeterminateBar`（防连点重复触发）；runOp 失败发系统通知（不再静默 fputs）；SelectionRow 展开态提升为面板级 `expandedRowID` 互斥（同屏/跨屏同时只展开一个）；卡片区包 ScrollView（超 600pt 封顶滚动）；布局图交互化（点击屏块选中 ✓、主显示器行/排列行 hover 时对应块高亮）；镜像/扩展区显示目标屏名（`mirrorTarget` + t() %@ 替换）；退出按钮从工具栏移到底部低视觉权重小字行（防与「设置」相邻误触）
- 一键自动排列（v0.2.0）：`DisplayManager.autoArrange`——所有屏横向排开消除重叠，主屏所在单元归 (0,0)，其余按原 origin.x 排右侧。**镜像组感知**：组内保持 `id:基准+副` 合并 arg（与 currentSnapshotArgs 同理），不会意外拆散镜像
- 预设 id 漂移兜底（v0.2.0）：`DisplayManager.remappedArgsIfDrifted`——旧 persistent id 全部有效则原样应用；屏数一致且能按分辨率 1:1 映射时改写 id 段（镜像合并条目逐段替换）；无法完整映射回退旧行为（宁缺毋滥）。PresetManager.apply 在后台队列里先做此检测
- 自绘应用图标（v0.2.0）：`make-app-icon.sh` 默认调 `make-app-icon-design.swift` 纯代码渲染（选定 blue 主题 + screen 红绿灯摆法），不再依赖外部参考图；传源图路径仍走旧规整流程
- 架构清理（v0.2.0）：AppState 拆出独立文件；Components.swift 集中共享组件（RowButton/ActivePill/BubbleBackground/BubbleCard/SettingsCard…）；SettingsTabs.swift 拆三个标签页；BubbleMetrics 扩充字号/间距刻度 + bubbleShadow()；死代码清理（DisplayInfo 的 enabled/menuLabel/aspectRatio/mirroredPeerID、ScreenCaptureProvider 整文件、3 个死 L10n key）
- PresetManager.apply 完成后广播 `Notification.Name.moniswitchPresetApplied`（userInfo 携带稳定后的屏幕列表），AppState 订阅刷新面板——修复热键应用预设后面板停留旧布局的隐患
- **HiDPI 解析与切换根治（2026-09，修复「重选 4K 图标变小」事故）**：displayplacer 模式行的 `res:` 是**逻辑分辨率**（HiDPI 模式物理像素为 2 倍，已用内置屏实证：当前模式标在 `res:1512x982 scaling:on` 而非 3024x1964）。事故根因两层：① `parseResolutions` 忽略模式行 `scaling:on` 后缀且按 "WxH" 去重，HiDPI/非 HiDPI 变体合并成一条菜单项；② `setResolution` 把屏**当前模式**的 `scalingOn` 照抄进新参数——屏一旦落入 `scaling:off`，之后选任何分辨率都带非 HiDPI 发出，UI 无法自愈（4K 屏落到原生 3840x2160 1x = 图标变小）。修法：`DisplayInfo.availableResolutions` 改为 `[ResolutionOption]`（w/h/hidpi），解析正则捕获 ` scaling:on` 后缀、同分辨率去重时 HiDPI 变体优先（与系统设置默认一致）；`setResolution` 目标屏 scaling 用 `res.hidpi`（其余屏保持各自现状）。面板分辨率选项尾部标注变体（HiDPI / 低分辨率，`hidpiTag`/`lowResolutionTag` key），当前值在 `scalingOn` 时带 "· HiDPI" 后缀——菜单数字是"看起来像"的档位，不是物理像素，防止「4K 屏选 4K 数字得小图标」误解
- 排列卡全屏可调（2026-09）：`arrangeCard` 多屏分支改为 `ForEach(state.displays)` 给**每块屏（含主屏）**渲染 `ArrangementRow`，`showsPosition: !d.isMain`（主屏无左右可排、只保留分辨率/刷新率行）——主屏参数不必先切主屏身份即可调。旧逻辑「外接是主屏只渲染内置屏行 / 否则只渲染外接屏行」结构性排除主屏，已废；镜像/扩展行与自动排列行不变
- 液态玻璃已回退（2026-09，撤销 199bb4d）：手工玻璃的顶部白高光（0.42）+ 白亮描边 + 落影在胶囊上呈"果冻按钮"复古拟物感，用户反馈弃用。ActivePill 恢复强调色实心/`strokeWhenInactive` 细描边，位置分段外壳恢复细描边胶囊，设置页 Toggle 恢复 `.toggleStyle(.switch)`，`LiquidGlass.swift` 已删除。macOS 26 上系统原生控件本身就是真·液态玻璃观感，13~15 上也是干净原生样式——**控件视觉一律用系统原生，不做手工玻璃模拟**
- 面板折叠与 hover 交互统一（2026-09）：① **排列卡参数折叠**——每块屏的 位置/分辨率/刷新率 三行折叠进屏名行下，默认全收起；折叠头 = RowButton（图标+屏名+参数概要「位置 · 分辨率 · 刷新率」+ 旋转 chevron），面板级 `expandedDisplayID` 单值互斥（同时只展开一块屏，高度不跳）；任何组折叠/切换统一清空 `expandedRowID`（防止再展开残留旧的选项列表展开态）；`foldable` 参数区分单内置屏（false 常展开，内容仅两行折叠无收益）；布局图点击选中某屏时联动 `expandedDisplayID = d.id`（选中即定位）。② **hover 高光加宽**——`hoverRowHighlight(horizontalExpansion: 6)`：高亮圆角矩形在 background 里用**负 padding** 向两侧外扩（只扩视觉不占布局、文字零偏移），`RowButton` 经 `highlightExpansion` 透传；例外传 0：SelectionRow 展开列表 optionRow（防溢出浅灰圆角容器）、底部工具栏按钮（防越过中间分隔线）。③ **ActivePill 未选中态 hover**——内部 `@State isHovered`，未选中且悬停时 14% 强调色 Capsule 底（描边层叠最上），位置分段与镜像/扩展按钮一处改动两处生效；**注意加 @State 后默认成员构造器变 private，已手写显式 init 保持调用签名**。④ SelectionRow 触发行尾部加旋转 chevron 状态指示（旧双箭头是为弃用 Menu 删的，此为展开状态指示，不冲突）。⑤ **预设「当前」角标**——`DisplayManager.presetMatchesCurrentLayout(presetArgs:displays:)`：两侧归一成忽略 persistent id 的条目签名（`res|hz|depth|scaling|origin|degree|屏数`，镜像合并条目按屏数区分镜像/扩展态）排序比较，纯计算不跑 shell、免疫 id 漂移；当前侧由 displays + mirrorGroups 按 currentSnapshotArgs 同构推导；新 L10n key `currentLayoutBadge`（当前/Current）。⑥ 菜单栏图标字重 semibold → medium（semibold 反馈偏粗、regular 偏细）
- **面板迁移 NSPopover（2026-09，替代 MenuBarExtra）**：macOS 26 上 MenuBarExtra `.window` 的系统面板 chrome 渲染退化——尖角方框、顶部不贴合菜单栏、底部露系统窗口底色（浅色模式白色长条）；且该样式无 箭头/居中对齐/展开动画 API（用户按 WhatCable 观感要求三件套）。现由 `PanelController`（新文件）自持 NSStatusItem + NSPopover 承载 PanelView：箭头沿顶边指向图标、面板在图标上居中（CGWindowList 实测中心偏差 0）、`animates` 系统展开动画（从顶部锚点由小放大）、圆角/贴顶回归标准 popover。**关键点**：① `NSHostingController.sizingOptions = [.preferredContentSize]` 让 SwiftUI 理想尺寸驱动 popover（environmentObject 修饰擦类型，需包 AnyView 存属性）；② **transient 关-点竞态**：面板开着点图标，transient 先关、action 后到（isShown 已 false 直接 toggle 会立即重开=永远关不掉）——`lastCloseTime` 0.25s 内的 toggle 忽略；②′ **transient 对「App 从未激活」的 LSUIElement App 不会自动收起**（点桌面/其他 App/其他菜单栏图标均无反应，只有点图标才关，2026-09-07 macOS 26 实测）——AppKit 的自动 dismiss 依赖「激活后失活」或 key 窗口变更，纯菜单栏 App 从不激活，这些信号不会到达；修法：`PanelController.installDismissMonitors()` 手装 全局+本地 鼠标按下监控（`.leftMouseDown/.rightMouseDown/.otherMouseDown`），按下点在 popover 窗口 frame 与状态项按钮 frame 之外即收起（按钮上的点击放行给 toggle 防双重处理），已用 CGEventPost 真实全局事件实测收起生效；③ 图标高亮：show 后主线程异步 `button.cell?.isHighlighted = true`，`popoverDidClose` 复位；④ MoniSwitchApp 瘦身为 `Settings { EmptyView() }` 占位 scene + `.commands` ⌘,（真身仍是 DockPolicyManager 的 NSWindow），AppDelegate 在 didFinishLaunching 调 `PanelController.shared.setup()`；⑤ AppState 从 App 的 @StateObject 移到 PanelController 持有（唯一消费者是 PanelView）；⑥ 面板内「设置」按钮先 `PanelController.shared.close()` 再 openSettings（切 activation policy 防面板悬空）
- Release 产物在 dist/（v0.1.4：MoniSwitch.dmg + MoniSwitch-0.1.4-source.* + RELEASE_NOTES-v0.1.4.md + SHA256SUMS.txt；历史版本 notes 一并留存）

## 已知 bug（待修复）

（当前无——原「镜像/扩展操作通知不弹出」已在 v0.2.0 根治，见上「通知 bug 根治」条目）

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
- **菜单栏图标必须用模板 NSImage**：NSStatusBarButton 的 cell 高亮（面板打开时）会给图标加深色高亮背景，非模板的视图（用 `.foregroundColor(.primary)` 描边）会与高亮背景同色，表现为图标位置一整块黑。SF Symbol 返回的 NSImage 天然 `isTemplate = true`，系统在深浅/高亮态自动反色，稳定可见。代码见 `PanelController.menuBarIcon`（原在 MoniSwitchApp，2026-09 随 NSPopover 迁移搬走）。
- **AppIcon.icns 重建流程**：现由 `bash Support/make-app-icon.sh <源图>` 一键完成——内部先调 `make-app-icon-square.swift` 把任意尺寸源图规整为 1024×1024（采样中心区域平均色填上下/左右边，避免黑边；源图四周常有透明环，直接取边缘会采到 alpha=0），再 `sips` 缩放 10 个标准尺寸（16/32/128/256/512 各 @1x@2x）→ `iconutil -c icns`。产物 `Resources/AppIcon-source.png` + `Resources/AppIcon.icns`。`build-app.sh` 只做 `cp Resources/AppIcon.icns → .app`，所以重建 icns 后无需改打包脚本。README 顶部内嵌 logo 指向 `Resources/AppIcon-source.png`，换图标后自动跟着变。
- **DMG 安装包背景与图标布局由三个脚本协作**（改背景/箭头/图标位置，不要手改 DMG）：`make-dmg-background.swift` 生成 `Resources/dmg-background.png`（1320×800 @2x = Finder 窗口 660×400 逻辑点；波浪源图居中裁 33:20 中部 + 绘半透明白曲线箭头，箭头 y 与图标中心对齐）；`build-app.sh` 第 5 步把背景打进 `.background/` 隐藏目录，再用 `osascript` 写 Finder 视图元数据（背景 / 窗口 bounds `{0,0,660,400}` / 图标 128pt / 位置 `{140,180}` MoniSwitch.app + `{480,180}` Applications）；`make-dmg-preview.swift` 合成 README 用的 DMG 窗口预览图（沙箱 `screencapture` 不可靠时的替代）。改图标位置：同时改 `make-dmg-background.swift` 的箭头坐标 + `build-app.sh` osascript 段的 `set position`。
- **DMG osascript 写 .DS_Store 的两个坑（曾导致背景与图标位置全部丢失，已踩过）**：① **不能用 `-mountpoint` 自定义挂载点**，Finder 只往默认 `/Volumes/<卷名>` 写 `.DS_Store`；② **背景别名必须在 `tell disk` 块外解析**（`set bgFile to POSIX file ".../dmg-background.png"`），块内直接 `file ".background:..."` 会因 HFS 冒号路径被 Finder 误解报 -17006/-1700，且 `as alias` 转换也会失败。验证是否写入成功：挂载后 `python3` 原始解析 `.DS_Store` 找 `Iloc`（图标位置）+ `icvp`（背景引用 `dmg-background`）记录；二进制层确认最可靠，视觉确认（screencapture）在多屏/无头环境可能失败但不影响真实 DMG 内容。
- 远程仓库: https://github.com/M1688-cpu/MoniSwitch.git
- **displayplacer persistent id 会漂移**：外接屏唤醒/重新插拔/换屏后 persistent id 可能变化，导致预设失效。当前无 ID 重映射兜底，漂移时需重新保存预设
- **displayplacer 镜像用 `id:A+B` 语法**：镜像组的屏合并成一条 arg（共用基准屏的 res/scaling/origin），不能拆成多条 origin 相同的独立 arg（会让 displayplacer 误判，把后执行的屏设为主屏）
- **`Support/MoniSwitch.app` / `Support/MoniSwitch.dmg` 是 `build-app.sh` 的产物，不是源码镜像**：改完代码必须重新 `bash Support/build-app.sh` 才会更新；光 `swift build` 只更新 `.build/debug|release/MoniSwitch` 裸二进制，不会进 .app。本地验证最新 UI 的两种方式：①直接跑 `Support/MoniSwitch.app`（双击或 `open Support/MoniSwitch.app`，能验证完整 .app 包结构含 displayplacer）；②跑 `.build/debug/MoniSwitch`（最快迭代，但无 .app 包结构、无 displayplacer 依赖）。注意 `build-app.sh` 用的是 release 构建产物。
- **同 bundle id 的多份 .app 会污染 LaunchServices 缓存**：`open -a MoniSwitch` / Spotlight / Launchpad 都按 bundle id 查 LaunchServices 数据库，会解析到任意一份已登记的 .app（包括挂载中的 DMG、废纸篓、`dmg-staging/` 临时目录里的），导致「启动的是旧版」。曾出现的真实场景：开发期间双击挂载过 `Support/MoniSwitch.dmg` 且没卸载，LaunchServices 就一直登记着 DMG 里那份旧 app，`open -a` 永远启动旧版。排查：`lsregister -dump | grep -i moniswitch` 看所有登记路径；登记指定那份：`lsregister -f <path>`；注销过时那份：`lsregister -u <path>`（仅动数据库，不删文件，对废纸篓里的也安全）。发布/验证前确保只剩目标那一份登记。
- **自动化验证面板 UI 的可行路径与坑**（2026-08 实测，macOS 15）：菜单栏图标坐标可由 `CGWindowListCopyWindowInfo` 取（owner=MoniSwitch、layer=25、name=Item-0 的小窗口）；面板窗口是 layer=101 的 380 宽窗口。CGEvent 合成点击**能点开/点关菜单栏图标**，但**对面板内容的控件无效**（Button 不触发，原因未深究）——面板内交互只能人肉验证。另注意：其他菜单栏 App 的面板开着时会吞掉第一次图标点击，先点一下桌面收起它；视觉分析截图必须用**唯一文件名**，CDN 按文件名缓存、重名图会拿到旧内容。
- **自动化验证的 2026-09 增补（macOS 26 实测）**：① 菜单栏图标窗口（MenuBarExtra 时代）**不再出现在 CGWindowList 里**（owner/layer 都查不到，但图标实际显示）；**迁移 NSPopover 后面板窗口可见**：layer=25 的 borderless 窗口，bounds 可直接读（实测用于验证居中/贴顶）；② CGEvent 合成点击对**普通 NSWindow 里的 SwiftUI `onTapGesture` 同样无效**（设置窗口边栏行点不切 tab），不只限面板；③ ~~合成 ⌘, 打开设置~~ **已随 MenuBarExtra 移除失效**（2026-09 面板迁移 NSPopover：App 非 active 时无菜单加速键）——自动打开设置改走 AX 或放弃；④ **裸二进制 `.build/debug/MoniSwitch` 从终端后台启动不创建任何窗口**（进程活着但无菜单栏图标），验证 UI 必须走 `.app`（build-app.sh 产物 + lsregister 登记 + open）；⑤ computer-use（CUA）的 left_click 是窗口路由分发，点自家菜单栏图标会被路由到相邻 App 的图标（其 strategy="event" 的路由定向事件同样**不可被 NSEvent 全局监控观测**，测不了「外部点击收起」这类逻辑）；⑥ **点自家菜单栏图标的最可靠路径是 AppleScript AX**：`tell application "System Events" to tell process "MoniSwitch" to click UI element 1 of menu bar 2`（读该元素 position/size 可定位图标；**状态项 x 会随菜单栏其他图标增减漂移**，点击前必须现查，两次实测从 800 漂到 876）；⑦ **CGEventPost 全局事件在此终端有效，但点不动 NSStatusBarButton**：点 Apple 菜单 (15,10) 可点开、点桌面可被自家 NSEvent 全局监控收到（外部点击收起即以此验证），唯独状态项按钮对合成点击免疫（`.cghidEventTap` 与 `.cgSessionEventTap`+combinedSessionState 源均无效，疑似 macOS 26 对状态项窗口的合成事件屏蔽，与其在 CGWindowList 不可见同源）——自动化开关面板只能走 ⑥ 的 AX；⑧ 视觉像素验证用「打开/关闭两态截图差分」提取面板剪影（壁纸渐变会污染绝对颜色分析）；另 analyze_image 类视觉 MCP 解析不了 CUA 截图 CDN 的签名 URL，纯视觉读图在该链路不可用。
- **通知时序契约（v0.2.0 起）**：`AppSettings.sendSwitchNotification` 要求调用方已在显示器配置稳定后调用（先经 `DisplayManager.waitForStableDisplays`）。新增发通知的代码路径若绕过此契约，镜像/扩展类操作会复现「通知不弹出」bug。
- **PanelView 的展开互斥/联动状态都是面板级 @State**：`expandedRowID`（SelectionRow 互斥）、`selectedDisplayID`/`hoveredDisplayID`（布局图联动）挂在 PanelView 上经参数传入 ArrangementRow/SelectionRow——新增联动屏相关的行时记得挂 onHover 上报 hoveredDisplayID，否则布局图不联动。
- **控件视觉用系统原生，不做手工玻璃模拟**（2026-09 实测回退）：199bb4d 曾手工绘制液态玻璃（染色基底+上缘镜面高光+边缘亮线+内阴影+落影），但小尺寸胶囊上 0.42 白高光 + 白亮描边叠加出 Aqua 时代"果冻按钮"复古感，已整体回退删除（`LiquidGlass.swift` 不复存在，ActivePill 恢复实心/描边、Toggle 恢复 `.switch`）。本机工具链 SDK 15.5 也无 `glassEffect` API（需 macOS 26 SDK），而 macOS 26 上系统原生控件自动获得真·液态玻璃观感——原生即最优解。若日后 SDK ≥ 26 且想上玻璃，用系统 `glassEffect`，不要再手绘
- **屏幕重配时面板的 ScrollView 会塌缩为 0**（2026-09 实测，v0.2.0 曾现严重 bug，当时宿主是 MenuBarExtra(.window)，迁移 NSPopover 后保留同一防御）：面板开着时发生系统级显示器重配（切主屏/自动排列/镜像等），面板被系统重新求解尺寸，ScrollView 在无确定高度 proposal 的求解轮里 ideal 高度塌 0——面板瞬间只剩 ScrollView 外的底部工具栏与退出行，且不自愈（冷启动首开正常，重配才触发）。**修法：GeometryReader+PreferenceKey 测滚动内容固有高度（挂内容 background，与视口无关），`ScrollView.frame(height: min(内容实高, 600))` 显式给高**，任何重求解都拿到确定值；`@State scrollContentHeight` 初值 480 防首帧闪变。不要用 `.frame(maxHeight:)` 依赖 ideal 求解。注意此处 PreferenceKey 测高与设置页滚动偏移的禁忌不冲突（那是因为静止偏移含安全区 inset 才改用 NSClipView；测内容高度不受影响）。
- **ShellRunner 必须并发读管道**（2026-09 防御修复）：原实现「先 waitUntilExit 再顺序 readDataToEndOfFile」有经典死锁隐患——管道缓冲区约 64KB，子进程输出超缓冲时 write() 阻塞、进程退不出，与等待线程互锁，调用方串行队列（AppState.queue/PresetManager.queue）整体卡死、isOperating 永久 true。现改为两个并发块各读一根管道、信号量汇合后再 waitUntilExit。displayplacer list 输出随屏的模式数增长（27 寸 1080p 双屏实测约 21KB，4K/多模式屏更大），开发时要记住这条底线。

## 风格约定

- Release notes 不使用 emoji
- 注释用中文
- 代码风格跟随现有文件的缩进和命名
