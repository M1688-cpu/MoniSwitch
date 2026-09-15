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

- **build-app.sh 自动探测最新 SDK（2026-09）**：脚本在 CLT（`/Library/Developer/CommandLineTools/SDKs`）与 Xcode（`/Applications/Xcode*.app/.../SDKs`）两处找版本号最大的 `MacOSX*.sdk`（`sort -V` 全版本比较）设为本次构建的 `SDKROOT`，不动 xcode-select 系统默认。动机：NSPopover 背景板、NSSwitch 开关等系统 chrome 的 **Liquid Glass 新观感只有用 macOS 26 SDK 编译才被系统采用**（运行时 macOS 26，本机 CLT 曾只有 15.5 SDK）；已约定安装「Command Line Tools for Xcode 26」后由本脚本自动用上 26 SDK。直接 `swift build`（不经脚本）不受影响，仍走默认 SDK。另（2026-09-12）：脚本已加 `set -o pipefail`——此前 `swift build -c release 2>&1 | tail -5` 的管道会拿 tail 的退出码 0 掩盖编译失败，`set -e` 拦不住，脚本会带着**旧二进制**继续打包出「假新版」（实测踩坑：实验矩阵整轮跑空毫无察觉）。

## 项目结构

```
Sources/MoniSwitch/
  MoniSwitchApp.swift      # @main 入口（AppDelegate 创建菜单栏图标 + ⌘, 命令）+ menuBarIcon
  PanelController.swift    # 菜单栏面板控制器（NSStatusItem + NSPopover，容器闸门/手动尺寸桥
                           #   承载 PanelView；开关/竞态守卫/图标高亮/AppState 宿主/背景板透明化）
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
  displayplacer             # 不入库（.gitignore 排除）
Support/
  Info.plist                # App 元信息
  build-app.sh              # 打包脚本（编译 → .app → 签名 → .dmg，DMG 段调 create-dmg）
  make-app-icon.sh          # 重建 AppIcon.icns（默认调自绘脚本；传源图路径走旧外部图流程）
  make-app-icon-design.swift# 纯代码自绘图标（Liquid Glass 风格显示器，6 主题×2 红绿灯摆法，--all 出预览）
  make-app-icon-square.swift# 把任意尺寸图标源规整为 1024×1024 正方形（采样背景色填充，避免黑边）
  preview-site.sh           # 本地预览宣传页（复刻 Pages 组装到 /tmp + python3 http.server）
docs/
  index.html                # 项目宣传页（单文件站点，见「项目宣传页」章节）
.github/workflows/
  website.yml               # GitHub Pages 自动部署（docs/index.html + screenshots/ + 图标 → 站点根）
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

- **公开版本线**：v0.1.1 → v0.1.2 → v0.1.3 → v0.1.4 → **v0.1.5**（v0.1.4 发版前远端 main/tag 一直停在 v0.1.3，v0.1.4 是其后第一个公开版本；v0.1.5 = 面板观感与动画打磨 + SDK 自动探测构建，增量视角见 dist/RELEASE_NOTES-v0.1.5.md）
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
- 面板交互升级（v0.2.0）：操作进行中 `AppState.isOperating`/`PresetManager.isApplying` 禁用卡片区 + 顶部 overlay 流动进度条 `IndeterminateBar`（防连点重复触发）；runOp 失败发系统通知（不再静默 fputs）；SelectionRow 展开态提升为面板级 `expandedRowID` 互斥（同屏/跨屏同时只展开一个）；卡片区当时包 ScrollView 超 600pt 封顶滚动（2026-09 已移除，见「面板去滚动条自适应」条目）；布局图交互化（点击屏块选中 ✓、主显示器行/排列行 hover 时对应块高亮）；镜像/扩展区显示目标屏名（`mirrorTarget` + t() %@ 替换）；退出按钮当时移到底部小字行（现已改为底部独立气泡图标，见同前条目）
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
- README 双语拆分（v0.1.4）：`README.md` 默认英文，`README.zh-CN.md` 简体中文，顶部互链（英文页的链接文案就是「简体中文」）。截图区只保留单语言——英文页引用 `screenshots/en/`、中文页引用 `screenshots/zh/`，两套文件名一一对应，`dmg-install.png` 放 `screenshots/` 根目录两页共用；UI 有视觉改动时两套截图都要重截
- Release 产物在 dist/（v0.1.4：MoniSwitch.dmg + MoniSwitch-0.1.4-source.* + RELEASE_NOTES-v0.1.4.md + SHA256SUMS.txt；历史版本 notes 一并留存）
- **面板去滚动条自适应 + 双层阴影 + 底部双气泡（2026-09）**：① **移除卡片区 ScrollView 与 600pt 封顶**——用户反馈「展开参数/英文长文本就出滚动条」，要求窗口高度随内容自适应。PanelView 卡片区改裸 VStack（宽度仍锁 380），`scrollContentHeight`/`PanelContentHeightKey` 已删；popover 经 `sizingOptions = [.preferredContentSize]` 直接取内容实高（实测英文全收起态 720pt，超出旧封顶理论最大值 ~696，窗口高度==内容高度即无滚动视口）。SelectionRow 内部 216pt 限高 ScrollView 保留（仅选项极多时内部滚动，与面板级滚动无关）。② **展开动画统一平滑弹簧**——文件级 `panelReveal = .spring(response: 0.32, dampingFraction: 0.86)`（用户三选一拍板），替换 4 处 `.easeInOut(0.15)`（ArrangementRow.toggleExpanded / SelectionRow 触发 / optionRow 收起 / LayoutDiagram 选中联动）；`.move(edge:.top)+opacity` 过渡保留呈现「由上向下拉伸」；popover 对 contentSize 变化自带系统动画与内部弹簧大体同步。③ **阴影直线边界根治**——根因是 ScrollView 对子视图 bounds 的**裁切**（阴影在卡片左右被切出竖直线，去 ScrollView 即根治），次要因素是单层阴影硬；`bubbleShadow()` 改双层弥散（ambient radius 11/黑 0.06/y5 + key radius 3.5/黑 0.09/y1.5），参数语义从「透明度」改为「强度系数」（默认 1，SettingsCard 0.85），面板根 padding 14→16 给弥散留衰减空间（勿随意缩小）。④ **底部操作栏重构**——一排两气泡：左宽气泡「刷新|设置」纯图标（arrow.clockwise / gearshape，中间 Divider）+ 右方形气泡「退出」（power，中性色，用户拍板）；`toolbarIconButton` 固定触区 34×26 + hover 高亮（外扩 0）+ `.help(t(...))` 原生 tooltip（悬停停留显示，文案走 L10n 中英自动切换，key 复用 refreshList/settingsTitle/quit）；`quitRow` 小字行已删（④的左宽右方比例已被下一条取代，tooltip/进度条等其余描述仍有效）。验证注记：tooltip/hover/展开动画无法合成事件触发（见注意事项自动化条目⑨），需人肉验证；阴影平滑度与底部结构已像素扫描确认
- **展开动画根治 + 折叠头两行式 + 气泡悬浮浮起（2026-09）**：五项联动改版（BubbleMetrics/Components/PanelView，全部在未提交的工作区改动之上）：① **展开内容越过折叠头的裁切修复**——ArrangementRow 展开块外包 `ZStack(alignment: .top) + .clipped()`：`.move(edge:.top)` 过渡期间内容从上方滑入，链路上原本无任何裁切容器、会飘到折叠头文字上方「凭空出现」；裁切边界即折叠头下边缘，视觉呈从标题行下方「抽拉」出来、收起对称滑回。transition 与 panelReveal 弹簧不动（手感已获认可），只加视觉遮罩；代价是行 hover 高亮负外扩 6pt 在 trailing 方向被裁 ~2pt（padding 4<6，不可感知）。② **SelectionRow 展开无动画的不对称根治**——原「选项展开瞬时拉长、收起有动画」的根因：选项列表是**条件插入的贪婪 ScrollView + `.frame(maxHeight:216)`**，插入瞬间占满全部高度、高度跳变不参与 withAnimation 插值，收起走移除过渡才有动画。现版（经三轮迭代，机制见 ⑤ 的窗口跳变结论）：**常驻挂载 + 布局二值跳变 + mask 视觉揭示**——ScrollView 不再条件插入；`@State listHeight` 由内容 background 内 GeometryReader 实测，`.frame(height: expanded ? min(listHeight, selectionListMaxHeight) : 0)` 显式驱动；**展开方向用 `.transaction { if expanded { $0.animation = nil } }` 剥离动画让布局高度二值跳变**（注意 `.animation(nil, value:)` 挡不住显式 withAnimation 事务，必须用 transaction 改写——SwiftUI 已知行为），视觉揭示由 `@State revealHeight`（0→实高，随 panelReveal 弹簧）驱动 `.mask(alignment:.top)` 呈现「从触发行下拉出」（纯呈现层不参与布局）；**收起方向保留弹簧插值**（frame 回抽 + clipped，窗口收起自带系统动画无下沉问题）。中间帧像素验证：展开时选项渐进揭示（目标 367..577pt 渐次出现）、收起平滑回抽。216 收进 `BubbleMetrics.selectionListMaxHeight`。③ **折叠头两行式解耦**——原图标+屏名+Spacer+参数概要+chevron 挤一行，长名称（DELL U2723QE）+长参数（位置 · 3840×2160 · 60Hz）会换行/截断；改为第一行【名称（lineLimit(1) 尾截断）+ chevron】+ 第二行【参数概要小字副行】，展开时副行 `.transition(.opacity)` 淡出（详情行已展示同信息）；外层 `.frame(maxWidth:.infinity, alignment:.leading)` 保整行点击区；参数移入布局图块的备选方案已否（屏块按物理比例缩放后过小、单内置屏无布局图）。④ **底部操作栏比例重构**——旧「左 maxWidth 撑满 + 右内容自适应方形」两端失衡（用户截图反馈）；改左气泡内容自适应（HStack(spacing:2) + padding h12，双图标天然居中）+ 右退出气泡 `.frame(maxWidth:.infinity)` 占满剩余（`toolbarIconButton` 加 `fullWidth` 参数：Image `frame(width:nil/maxWidth:.infinity, height:26)` + contentShape，触区横贯整泡）；**三按钮 hover 高亮已删**（悬浮反馈让位给整泡 hover 浮起，tooltip 保留）。⑤ **bubbleHoverLift() 悬浮浮起（hover 模糊事故后定型）**——初版曾按 Atoll 观感做 `BubbleTiltModifier`（onContinuousHover 归一化坐标 + `rotation3DEffect` 双轴 3D 倾斜 + 放大 1.02），用户实测反馈**悬停时整卡文字明显变糊**；根因：`rotation3DEffect` 的 3D 透视变换会把视图**栅格化重采样**（HiDPI 下有效分辨率减半），而 2D 仿射变换（scaleEffect/offset/rotationEffect）走 CALayer 路径不栅格化、保持原生锐度（本项目 chevron 旋转从未模糊即是佐证）。定型版 `BubbleHoverLiftModifier`（Components.swift）：**全部仿射**——`scaleEffect(liftScale 1.02)` + `offset(y:-2)` 上浮 + 叠加 hover 增强阴影（black 0.10/radius 16/y8，与 bubbleShadow 双层弥散叠加出「浮起」层次），`@State isHovered + onHover`（回归全站 hover 范式，onContinuousHover/GeometryReader/pointer 归一化全部移除），`liftSpring(.spring(0.3/0.7))`，`accessibilityReduceMotion` 全禁用；应用点：BubbleCard 链尾（主屏/排列/预设/布局预览/空态五卡自动获得）+ 底部两气泡手动挂载；常量在 BubbleMetrics（liftScale/liftOffset/liftShadow*/liftSpring）。静止态像素差分验证与旧版一致（卡片内部零变化，差异仅为底板材质对桌面采样的环境噪声 + 窗口边缘下的桌面变化）。hover 手感只能人肉验证（自动化条目⑨）。⑥ **NSPopover 窗口增涨无动画（本轮实测的重要结论）**——紧密轮询 CGWindowList（无 sleep 死循环采样）证实：面板内容增高的窗口 resize **一步跳到目标**（收起方向才有系统动画），曾以为的「popover 自带 contentSize 动画与内部弹簧同步」不成立；后果是增涨瞬间窗口高于内容，内容在窗口内被短暂居中→整块下沉 ~20-40pt 再弹回（组展开也一直存在，量级小用户未抱怨）。对策：SelectionRow 展开方向布局二值跳变（见②）把理想尺寸瞬间拉到目标消掉大半下沉；余留 ~20pt 瞬态下沉属 AppKit 托管视图行为（SwiftUI 侧 maxHeight top-pin / transaction 均无法完全消除，已试）。（**2026-09 后续：已由「面板 Tutti 风格改版」条目 ⑤ 的容器闸门 + 手动尺寸桥 + 二值布局三件套彻底根治，勿再走 NSAnimationContext 驱动窗口 frame 的路线**。）中间帧验证法：预编译 swiftc 点击工具 + `screencapture` 定时连拍 + 行位置像素扫描（text band 与目标态比对可量化位移/揭示进度）。

- **hover 浮起边缘振荡修复 + 面板卡片材质实验回退（2026-09，v0.1.5 后）**：① **排列卡在面板底部附近「奇怪跳动」的根因**——`BubbleHoverLiftModifier` 的 onHover 命中区跟随几何变换：旧版 `scaleEffect(1.02) + offset(y:-2)` 里 offset 把卡片**底边向内拉 2pt**（短卡必内拉；~240pt 的排列卡仅外扩 0.4pt，`liftSpring` damping 0.7 的过冲相位也会瞬间内拉），指针沿面板下扫、停在卡片边缘死区带时「hover 进入→底边越过指针→退出→落回→再进入」持续振荡。修法：删 offset，改 `scaleEffect(liftScale, anchor: .bottom)` 纯缩放——底边钉死不动（恰是指针巡扫的边界）、顶边/左右只向外扩，进出两方向都单调，**任何卡高、任何过冲相位构造性不可能振荡**；上浮感由「底锚向上生长」+ 阴影下沉保留。`BubbleMetrics.liftOffset` 已删；hover 行为无法合成事件验证（自动化条目⑨），此修法靠构造性保证。② **面板卡片材质实验被用户否决（勿重试）**——曾把 BubbleCard/底部气泡从纯白不透明改为 thinMaterial（后试 ultraThinMaterial）追求「背景板更透明、与系统原生一致」，用户高对比壁纸实测：**气泡变灰不再是白色、整板观感退化为「类 macOS 15 毛玻璃」**，明确否决（「我没说要这么改」）；已回退 BubbleBackground 不透明纯白。教训：**用户口中「背景板」= popover 底层系统玻璃，不是气泡卡片**；卡片必须保持纯白。③ **背景板透光实测**（高对比壁纸 + 关面板差分采样）：NSPopover 自身玻璃对壁纸亮度近乎全透（上半 diff=0、下半 -5~-13），本就是系统原生液态玻璃；公 API 无从调其透明度，想更透只能弃 NSPopover 换自绘 NSPanel + NSVisualEffectView（丢箭头/居中/系统展开动画——NSPopover 迁移的初衷，勿轻动）。**（2026-09-12 修正：前半句仍成立，后半句「公 API 无从调」已被推翻——背板 NSGlassView 继承公开类 NSGlassEffectView；但「点击变白」的 key 态自适应层确实无法用任何公开旋钮关闭，当时改为隐藏玻璃内层=完全透明悬浮卡片，见「悬浮卡片背景板」条目。2026-09-14 再修正：悬浮卡片方案已整体回退，恢复系统玻璃背板；同日下午二次定型「clear + 常驻 key」根治变白，见「悬浮卡片背景板」条目）**
- **面板 Tutti 风格改版 + 展开动画气泡上跳根治（2026-09，v0.1.5 后，视觉参考 github.com/BarryBarrywu/tutti，源码已闭源仅按参考图实现）**：① **标题重构**——BubbleCard 删 22×22 图标徽章（`systemImage`/`accent` 参数已删，签名简化为 `BubbleCard(title:)`），标题改**全大写浅灰小型标签**：fontCaption(11) semibold + `.tracking(1)` + `textCase(.uppercase)` + `BubbleMetrics.sectionLabelColor`（#94A3B8，浅深模式通用；中文无大小写不受影响、字距同样加宽）；五处调用点同步。② **显示器图标圆框 `DeviceIconBadge`**（PanelView 私有组件）——24pt 圆形底框 + 类型图标（isBuiltIn ? laptopcomputer : display，12pt semibold）；**主屏卡**传 `active: d.isMain`（主屏主题色底+白图标、非主屏 `Color.primary.opacity(0.12)` 底+`.secondary` 图标=深灰暗态），删行首 circle/circle.fill 圆点与右侧 "Main" 胶囊角标（**主从关系改由图标圆框颜色表达**，名称 semibold 为第二线索；`panelPrimaryBadge` L10n key 已删）；**排列卡**折叠头恒 active（全主题色）；展开块缩进 24→34 对齐新文字起点（圆框 24 + spacing 10）。（2026-09-12 调大：圆框 24→28、图标 12→14、缩进 34→38，见「悬浮卡片背景板 + 视觉微调」条目。）③ **底部工具栏三键合并**——autoArrangeRow 从排列卡删除，自动排列移入底部左气泡：`[wand.and.rays | arrow.clockwise | gearshape]` 三按钮 fullWidth 等宽均分 + Divider 分隔，气泡 `.frame(maxWidth:.infinity)` 拉满剩余宽度；单屏（displays.count<2）禁用置灰防死点击；**退出气泡改内容自适应**（去 fullWidth，padding h12 v6 刚好包住 34×26 触区）；两气泡**移除 bubbleHoverLift**（用户要求单按钮反馈而非整泡放大），反馈改**按钮级**：`ToolbarIconButton`（原 toolbarIconButton 函数改结构体以持有 @State）图标 `scaleEffect(1.15)`（仅图标本体，2D 仿射不栅格化、触区布局不动）+ `primary 7%` 圆角底色高亮，`buttonHoverSpring`，reduceMotion 只留底色；.help 原生 tooltip 保留；卡片级 hover 浮起不受影响。④ **Mirror Target 动态气泡**——删 mirrorExtendRow 顶部静态说明行；新 `MirrorTargetTooltip` 修饰器挂**镜像** ActivePill（扩展按钮不需要）：hover 停留 0.45s（DispatchWorkItem 可取消）后弹出、移开立即收起；入场 `tooltipSpring(.spring(0.3/0.65))` 弹跳感（≈参考 CSS cubic-bezier(0.175,0.885,0.32,1.275)）驱动 `scaleEffect(0.85→1, anchor:.bottom)` + opacity（自按钮上缘向上生长），退场 easeOut(0.12)，reduceMotion 禁用缩放；迷你气泡样式（圆角 10、不透明填充+bubbleShadow(0.7)、link 小图标+复用 mirrorTarget 文案）经 `.overlay(alignment:.top)+offset(y:-36)` 挂按钮上方，`allowsHitTesting(false)` 不挡交互。⑤ **展开「气泡先上跳再下拉」根治（重要机制结论，替代上条目 ⑥ 的遗留方案）**——症状：点展开参数后所有气泡先上跳/下沉 ±11~16pt 再回位。**根因链（像素级实测）**：SwiftUI 布局弹簧 → NSHostingView **即时**取新高度 → popover 窗口 frame **滞后 1-2 帧**；瞬态里内容视图与窗口高度不一致时，popover 把内容视图**垂直居中**显示（双向都居中：内容高=上跳、内容矮=下沉）。逐项排除的无效解：animates 开关、NSAnimationContext duration=0 剥隐式动画、preferredContentSize 同步/异步写法、SwiftUI 侧 maxHeight 顶端对齐 frame（**在 `[.preferredContentSize]` 下根本不生效**——该模式 NSHostingView 按**理想尺寸**而非视图边界布局根视图；`sizingOptions=[]` 下才按边界，760pt 固定高窗口对照实验证实）、直接在 popover 私有内部容器加约束（与其布局冲突，首开即错位）。**定型解法三件套**：(a) **容器闸门**——PanelController 插入自有容器 VC（`panelContainerController`，普通 NSViewController）：popover → 容器 → NSHostingController.view 四边+等高钉死在容器上（宿主视图恒等于窗口内容区，瞬态裁切只落底缘 1-2 帧）；(b) **手动尺寸桥**——`sizingOptions=[]` + PanelView 根链 `.frame(maxWidth/maxHeight:.infinity, alignment:.top)`（根按边界布局恒钉顶部）+ `PanelContentHeightKey` PreferenceKey 上报内容理想高度（挂内容 background 的 GeometryReader）→ `PanelController.updateContentHeight` **同步直写**容器 VC 的 preferredContentSize 驱动窗口（async 跳一帧会把漂移窗口拉长到 ~0.15s，实测）；setup() 里提前 layoutSubtreeIfNeeded 一轮让首开前 preferredContentSize 就位；(c) **展开方向布局二值跳变**——`toggleExpanded` 展开分支与布局图 onSelect 联动**不带 withAnimation**（高度一步到终值，窗口/容器/布局同帧到齐，构造性零漂移）；视觉平滑由展开块 **mask 揭示**承担：`revealHeight` @State 0→块实测高（blockHeight 由块 background GeometryReader onAppear 量取），panelReveal 弹簧驱动 `.mask(alignment:.top)`，纯呈现层不参与布局；**收起方向保留 withAnimation 弹簧**（实测该方向容器不超前、无漂移），块移除走原 .move+.opacity 过渡（展开是二值插入不走过渡；收起时 mask 不重置保持全开，让移除过渡可见）。验证：标题带像素扫描展开/收起两向全程恒 58px 零漂移；连拍中间帧确认 mask 渐进揭示（Rate 行半显态）；关/开循环尺寸保持；浅/深两模式截图核对。⑥ **范式约定**：日后新增「会改变面板高度」的动画一律走「**二值布局 + 纯呈现层动画**」（mask/offset/scaleEffect），勿直接 withAnimation 高度相关状态（会重启居中漂移）；hover 类交互（按钮放大/tooltip/浮起）无法合成事件验证（自动化条目⑨），需人工过。
- **悬浮卡片背景板 + 视觉微调（2026-09-12，v0.1.5 后）**：① **「点击面板任意处后背景板变白/变黑」根因（诊断结论仍有效）+ 悬浮卡片方案已回退**——popover 背景是 macOS 26 私有类 `NSGlassView`（**继承公开类 NSGlassEffectView，`as? NSGlassEffectView` 向下转型安全**；其公开 API：contentView/cornerRadius/tintColor/style(.regular/.clear)，SDK 头文件 NSGlassEffectView.h）。**层级关键：NSGlassView 是 contentView 的兄弟节点**（`NSPopoverFrame → [NSGlassView → ContentHolderView → _NSCoreHostingView<RootView>, contentView]`），从 contentView 子树里找不到它，必须从 `window.contentView.superview` 起遍历。它内部的系统自带 SwiftUI 内容层随窗口 key 态自适应：面板初开（LSUIElement App 未激活、窗口非 key）渲染较透变体，用户觉得可接受；点击面板内任意处 → 窗口变 key → 切到加白变体（浅色实测 +50~63/255，深色对称加黑）——即用户反馈的问题。运行时自省证实两态间 style/tintColor/cornerRadius **均不变**（自适应藏在内层 SwiftUI 里，外部无法关闭）。实测矩阵全部否决的路线：`style=.clear`（浅色壁纸区点击后仍 +16 提亮）、`alphaValue`（对玻璃渲染无效）、`tintColor` clear/黑20%（漂移更乱）、自建 NSGlassEffectView 垫底（key 切换时被系统压制消失、两态不一致）、自建 NSVisualEffectView 垫底（26 上该材质是雾白 191~226，比现状还白）。**悬浮卡片方案曾于 2026-09-12 实施**（用户三选一拍板 A）：`hideSystemGlassBackdrop()` 隐藏玻璃内层 → 背板完全透明（边距带采样≈壁纸 Δ≤5）、点击前后像素级零漂移（浅/深两模式实测）、气泡卡片靠双层弥散阴影悬浮于壁纸；幂等补挂四时机（`show()` 同步+async、`popoverDidShow`、popover 窗口 `didBecomeKey`、App `didBecomeActive`，后两个用 selector 式观察者——block 式闭包在 SDK 26 下标 @Sendable 捕获非 Sendable 的 self 告警，项目基线零警告）；窗口 resize（展开参数 636→685 实测）不会复活玻璃。**2026-09-14 整体回退（勿重试该方向）**：用户实测两个无法接受的遗留问题——悬浮卡片之外仍见一圈「背景阴影」残留（疑窗口级投影/玻璃 chrome 残留）；卡片弥散软阴影直接投在壁纸上、收缩成一条 1px 像素线的观感（原先投在磨砂玻璃上几乎无感）。回退 = 删 `hideSystemGlassBackdrop()`/`glassEffectViews(under:)` 方法及全部调用点（show 同步/async、popoverDidShow、didBecomeKey/didBecomeActive 两 selector 观察者及其 setup() 注册），恢复系统液态玻璃背板；「点击后变白/变黑」key 态自适应随之回归（已知、接受）。**2026-09-14 下午二次定型（现行方案）= clear 玻璃 + 常驻 key**：`PanelController.applyLiquidGlassBackdrop()`（show() 同步 + popoverDidShow 幂等调用）——`window.makeKey()` + 遍历设 `NSGlassEffectView.style = .clear`。本轮实验矩阵实锤三条机制：① 变白的驱动信号 = **窗口变 key**（`makeKey()` 单独即可完整复现 +78~+102 加白，与 NSApp.activate 无关——继承链实测 `_NSPopoverWindow <- NSPanel`，窗口 styleMask 自带 .nonactivatingPanel，点击本就只变 key 不激活 App）；② **clear+key 是全部状态里最薄的玻璃**（对壁纸雾度约为 regular 初始态一半，模糊/边框/箭头 chrome 保留），regular+key = 最厚白奶（原 bug 观感），clear 非 key ≈ regular 非 key（初始透明度无差别，.clear 不改初始态）；③ `tintColor = .clear` 是彻底 no-op（逐点采样与不设完全同值）。方案本质：面板一出生即 keyed 并处于最薄变体，点击时已无状态可切换，变白构造性不存在——生产构建终验：真实合成点击面板内任意处像素级零漂移、面板不收起。macOS 13~15 无 NSGlassView 跳过样式设置，makeKey 无害保留。**（2026-09-14 晚增补：resize 重置玻璃的补挂）**首版只在 show/didShow 打点，用户实测「点击展开显示器参数的箭头后背板变白」复发——**窗口 resize 会触发系统重设玻璃配置**（.clear 被打回 .regular 按 keyed 态渲染白奶变体，持久不恢复）；expand 是用户可触发的唯一改高度交互，故只有它复发。复现法：纯高度直写 `updateContentHeight(base+49)` 即可（无需点按钮，合成点击驱动不了 SwiftUI 按钮）；无补挂时采样点 +124 持久变白，补挂后全程 Δ≤2。定型：`updateContentHeight` 在写 preferredContentSize 后**幂等补挂** `applyLiquidGlassBackdrop()`（同步 + 一跳 async——系统重配可能落在本轮布局之后），高度变化是面板全部 resize 路径的必经点，一处覆盖展开/收起/选项列表/屏数变化全部场景。另：多屏环境下状态项可能位于副屏，**验证脚本必须按 CGWindowList 实测 bounds 判断面板所在屏**（x≥1920 即副屏）再 `screencapture -D 2` + 本地坐标采样，固定坐标/固定主屏截屏会采到无关内容（本轮两次踩坑）。完整诊断过程/实验矩阵/验证方法论存档于 `HANDOFF-floating-panel.md`（历史记录，勿删）。**背板边距带采样的通用注意**：距卡缘 ~20pt 内有卡片弥散阴影衰减（ambient radius 11 + hover 增强阴影 radius 16），采样点「变白/变灰」先排除阴影污染再怀疑玻璃行为。② **DeviceIconBadge 调大（用户要求）**——`deviceIconDiameter` 24→28、新增 `deviceIconFontSize`=14（**不能改 fontControl=12**：被镜像/扩展按钮、预设卡、设置页十几处共用）、展开块缩进 34→38（=28+10）；主屏卡与排列卡折叠头两个调用点自动生效。③ **布局预览去主屏蓝（用户要求）**——`LayoutDiagram.screenBlock` 删 `isMain` 特判：所有屏块统一中性样式（fill `gray.opacity(0.08)`、stroke `secondary.opacity(0.4)` 宽 1），块左上角主屏小圆点标记（circle.fill/circle）一并删除（其唯一作用是标主屏）；**保留** hover 联动高亮（accent 0.28 填充 + 2 宽描边）与点击选中 ✓ 角标 + 展开联动；主从关系仍由主屏卡图标圆框颜色表达。**诊断方法论沉淀**：视图树 dump（类名+frame+目标类属性）+ ObjC 运行时自省（class_getSuperclass 继承链 / responds(to:) / valueForKey 现值）定位私有层行为；UserDefaults 调试开关（`defaults write com.moniswitch.app <key>`）免重编跑实验矩阵；每轮冷启动重置 CGEventPost 点击预算（自动化条目⑪）。

## 项目宣传页（GitHub Pages）

- 站点地址：https://m1688-cpu.github.io/MoniSwitch/ ；源码 `docs/index.html` 单文件（内嵌 CSS/JS，零外部依赖），布局参考 deckclip.app（粘性导航/居中 hero/双 CTA/卡片网格），排版参考 mole.fit（衬线字体栈 `Charter, Georgia, "Source Han Serif SC", "Songti SC", serif` 全系统字体零字体文件、编号小节标签「00 ·」、容器 1120px），底色 `#f3f2ea`（用户指定），accent 用 Apple 系统蓝 `#0066cc` 呼应 App「跟随系统强调色」
- 双语：右上 EN/中 切换（deckclip 同款），默认英文；文案字典内嵌 JS `I18N`，截图用 `img[data-shot]` 按 `src` 里的 `en|zh` 段正则替换；偏好存 localStorage `moniswitch-site-lang`
- 部署链路：`.github/workflows/website.yml` 在 push main（paths 过滤 docs/index.html、screenshots/**、AppIcon-source.png、workflow 自身）时组装 `_site/`（index.html + screenshots/ 整目录 + 图标 → icon.png + .nojekyll）→ upload-pages-artifact → deploy-pages。**仓库 Pages 设置已切到 Source: GitHub Actions（一次性，勿改回 branch 模式——branch 模式只见 docs/ 会缺图）**。截图/图标更新后 push 即自动上线，无需手动同步
- 本地预览：`bash Support/preview-site.sh [端口]`（复刻组装逻辑到 /tmp/moniswitch-site 再起 http.server，与线上同构）
- **版本号硬编码两处**：docs/index.html 的 `.pill`（hero 与下载区各一行 `v0.1.4`）——发新版本时记得同步 bump（I18N 字典里没有版本号，直接改 HTML 静态文本）
- 宣传页不随 App 的 L10n/TextKey 走：文案是站点独立的（面向访客的海报语，非 UI 字符串）；改宣传页文案直接改 index.html 内嵌字典

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
- **DMG 由 create-dmg（npm: sindresorhus/create-dmg）生成（2026-09 起替代手写 hdiutil+osascript 流程）**：`build-app.sh` 第 5 步直接调 `create-dmg --overwrite --no-version-in-filename --no-code-sign "$APP_BUNDLE" "$STAGING_DIR"`，产物仍为 `Support/MoniSwitch.dmg`。工具默认布局（源码确认）：660×400 窗口、app 图标 (180,170)、Applications 拖放链接 (480,170)、icon 160pt、内置默认背景（`.background/dmg-background.tiff`，视觉为淡紫灰近纯色 660×400 @1x）+ 自动写入 `.VolumeIcon.icns` 卷图标；底层走 appdmg 纯 Node 直接写 `.DS_Store`（不经 Finder AppleScript，下方两个 osascript 坑天然免疫）。产物格式从 UDZO 变 ULFO（lzfse，macOS 10.11+）。两个关键 flag 的原因：`--no-version-in-filename` 保持产物命名 `MoniSwitch.dmg`（不带版本号后缀，发布流程按此命名）；`--no-code-sign` 本机无 Developer ID 证书，默认签名路径找不到证书时以退出码 2 失败（DMG 已生成但 `set -e` 会中断收尾步骤）。依赖（本机一次性安装，新机器需重装）：`brew install node && npm install --global create-dmg`。**注意 sindresorhus 版刻意极简无布局参数**（无 --background/--icon，官方拒绝加选项；带这些参数的是 brew 版 create-dmg 即 andreyvit/create-dmg，勿混淆）。README 预览图 `screenshots/dmg-install.png` 的更新方式：挂载真实 DMG → `open /Volumes/MoniSwitch` → `screencapture -l<windowID> -o`（windowID 由 CGWindowList 按 owner=访达/Finder + layer=0 找，本机系统中文 owner 名是「访达」不是 "Finder"）。
- **DMG osascript 写 .DS_Store 的两个坑（历史存档，2026-09 起 osascript 段已删、由 create-dmg/appdmg 接管，仅在手写 Finder 视图元数据时适用）**：① **不能用 `-mountpoint` 自定义挂载点**，Finder 只往默认 `/Volumes/<卷名>` 写 `.DS_Store`；② **背景别名必须在 `tell disk` 块外解析**（`set bgFile to POSIX file ".../dmg-background.png"`），块内直接 `file ".background:..."` 会因 HFS 冒号路径被 Finder 误解报 -17006/-1700，且 `as alias` 转换也会失败。验证是否写入成功：挂载后 `python3` 原始解析 `.DS_Store` 找 `Iloc`（图标位置）+ `icvp`（背景引用）记录；二进制层确认最可靠（注意：简单 `find(b'Iloc')` 字节匹配会误中 icvp 的 bplist 内容，坐标解析需按 [nameLen+name+type+dataSize] 结构走，2026-09 实测简单解析得到伪值，以窗口截图 + 像素采样为地面真值：窗口背景采样 RGB 与背景源图完全一致即生效）。
- 远程仓库: https://github.com/M1688-cpu/MoniSwitch.git
- **displayplacer persistent id 会漂移**：外接屏唤醒/重新插拔/换屏后 persistent id 可能变化，导致预设失效。当前无 ID 重映射兜底，漂移时需重新保存预设
- **displayplacer 镜像用 `id:A+B` 语法**：镜像组的屏合并成一条 arg（共用基准屏的 res/scaling/origin），不能拆成多条 origin 相同的独立 arg（会让 displayplacer 误判，把后执行的屏设为主屏）
- **`Support/MoniSwitch.app` / `Support/MoniSwitch.dmg` 是 `build-app.sh` 的产物，不是源码镜像**：改完代码必须重新 `bash Support/build-app.sh` 才会更新；光 `swift build` 只更新 `.build/debug|release/MoniSwitch` 裸二进制，不会进 .app。本地验证最新 UI 的两种方式：①直接跑 `Support/MoniSwitch.app`（双击或 `open Support/MoniSwitch.app`，能验证完整 .app 包结构含 displayplacer）；②跑 `.build/debug/MoniSwitch`（最快迭代，但无 .app 包结构、无 displayplacer 依赖）。注意 `build-app.sh` 用的是 release 构建产物。
- **同 bundle id 的多份 .app 会污染 LaunchServices 缓存**：`open -a MoniSwitch` / Spotlight / Launchpad 都按 bundle id 查 LaunchServices 数据库，会解析到任意一份已登记的 .app（包括挂载中的 DMG、废纸篓、`dmg-staging/` 临时目录里的），导致「启动的是旧版」。曾出现的真实场景：开发期间双击挂载过 `Support/MoniSwitch.dmg` 且没卸载，LaunchServices 就一直登记着 DMG 里那份旧 app，`open -a` 永远启动旧版。排查：`lsregister -dump | grep -i moniswitch` 看所有登记路径；登记指定那份：`lsregister -f <path>`；注销过时那份：`lsregister -u <path>`（仅动数据库，不删文件，对废纸篓里的也安全）。发布/验证前确保只剩目标那一份登记。
- **自动化验证面板 UI 的可行路径与坑**（2026-08 实测，macOS 15）：菜单栏图标坐标可由 `CGWindowListCopyWindowInfo` 取（owner=MoniSwitch、layer=25、name=Item-0 的小窗口）；面板窗口是 layer=101 的 380 宽窗口。CGEvent 合成点击**能点开/点关菜单栏图标**，但**对面板内容的控件无效**（Button 不触发，原因未深究）——面板内交互只能人肉验证。另注意：其他菜单栏 App 的面板开着时会吞掉第一次图标点击，先点一下桌面收起它；视觉分析截图必须用**唯一文件名**，CDN 按文件名缓存、重名图会拿到旧内容。
- **自动化验证的 2026-09 增补（macOS 26 实测）**：① 菜单栏图标窗口（MenuBarExtra 时代）**不再出现在 CGWindowList 里**（owner/layer 都查不到，但图标实际显示）；**迁移 NSPopover 后面板窗口可见**：layer=25 的 borderless 窗口，bounds 可直接读（实测用于验证居中/贴顶）；② CGEvent 合成点击对**普通 NSWindow 里的 SwiftUI `onTapGesture` 同样无效**（设置窗口边栏行点不切 tab），不只限面板；③ ~~合成 ⌘, 打开设置~~ **已随 MenuBarExtra 移除失效**（2026-09 面板迁移 NSPopover：App 非 active 时无菜单加速键）——自动打开设置改走 AX 或放弃；④ **裸二进制 `.build/debug/MoniSwitch` 从终端后台启动不创建任何窗口**（进程活着但无菜单栏图标），验证 UI 必须走 `.app`（build-app.sh 产物 + lsregister 登记 + open）；⑤ computer-use（CUA）的 left_click 是窗口路由分发，点自家菜单栏图标会被路由到相邻 App 的图标（其 strategy="event" 的路由定向事件同样**不可被 NSEvent 全局监控观测**，测不了「外部点击收起」这类逻辑）；⑥ **点自家菜单栏图标的最可靠路径是 AppleScript AX**：`tell application "System Events" to tell process "MoniSwitch" to click UI element 1 of menu bar 2`（读该元素 position/size 可定位图标；**状态项 x 会随菜单栏其他图标增减漂移**，点击前必须现查，两次实测从 800 漂到 876）；⑦ **CGEventPost 全局事件在此终端有效，但点不动 NSStatusBarButton**：点 Apple 菜单 (15,10) 可点开、点桌面可被自家 NSEvent 全局监控收到（外部点击收起即以此验证），唯独状态项按钮对合成点击免疫（`.cghidEventTap` 与 `.cgSessionEventTap`+combinedSessionState 源均无效，疑似 macOS 26 对状态项窗口的合成事件屏蔽，与其在 CGWindowList 不可见同源）——自动化开关面板只能走 ⑥ 的 AX；⑧ 视觉像素验证用「打开/关闭两态截图差分」提取面板剪影（壁纸渐变会污染绝对颜色分析）；另 analyze_image 类视觉 MCP 解析不了 CUA 截图 CDN 的签名 URL，纯视觉读图在该链路不可用；⑨ **合成事件触发不了 popover 内的 hover/tooltip**（2026-09-07 macOS 26 实测）：CGEventPost `.mouseMoved` 与 CUA `mouse_move` 都能把系统光标移到位（`cursor_position` 可证），但面板内 SwiftUI `onHover`/`hoverRowHighlight` 的 tint 与 `.help()` tooltip 均不出现——hover 类交互只能人肉验证；⑩ **Read 工具读本地图片会转存 CDN 并返回签名 URL，该 URL 能被 analyze_image 解析**（推翻 ⑧ 后半句对「签名 URL 一律不可解析」的理解——CUA 链路的 URL 不可解析、Read 管道的可以）；但 analyze_image 会被提问里的负面词汇诱导误报（实测在描述里预埋「切线/滚动条」字样，它就报出不存在的滚动条与切线）——**视觉结论以像素扫描（Swift + CoreGraphics 逐行亮度/色相分析）为地面真值**，且注意 NSPopover 窗口自带 chrome 描边（可见边界内缩约 13 逻辑点、全高暗线），别误判为裁切；⑪ **CGEventPost 点面板内容在 macOS 26 上「部分有效后失活」（2026-09-07 实测，修正 ② 的 macOS 15 结论）**：冷启动后面板内的 SwiftUI 按钮（RowButton 折叠头/SelectionRow 触发行/选项行）**能被 CGEventPost 触发**（本轮以此完成了展开/收起/选档的机器验证），但**累计若干次（~5-10 次不等）后整体失活**（再点任何行无响应，面板仍显示），且 System Events 的 AX 树同步劣化（`menu bar 2` 变无效索引、`count of menu bars` 归 0、popover 窗口 AX 不可枚举——panel 是 borderless NSPopover 窗口，AX 本来也读不到内容元素）；`set frontmost to true` 会打乱菜单栏索引。失活后唯一恢复法：pkill 重启 .app + AX 重开面板。验证策略：冷启动后头几次点击是可信窗口期，把最关键的交互放最前；其余用「终态截图 + 行位置像素扫描」验证（text band 对比目标态可量化动画中间帧位移）。另注意 swift 解释执行脚本每次 ~1-2s 编译延迟，定时抓动画中间帧必须 `swiftc -O` 预编译点击/采样工具。**（2026-09-14 增补）**当日构建上面板内按钮（齿轮/退出，坐标经底部工具栏像素扫描校准）对 CGEventPost **始终不响应**（冷启动仅 2-3 次点击、远未到预算，⑪ 的「前几次有效」未复现），与 ② 一致——合成点击驱动 SwiftUI 按钮的能力跨构建不稳定，交互验证以人肉为准；背板边距带空白处的点击则可送达（面板不收起、外部点击监控逻辑正常评估，可作「点击不变白」的机器验证点）。另：swiftc 点击工具若参数索引越界会以 SIGTRAP(133) 静默崩溃且无输出，极易误判为「系统拦截合成事件」——先查工具自身（本轮实测教训）。
- **通知时序契约（v0.2.0 起）**：`AppSettings.sendSwitchNotification` 要求调用方已在显示器配置稳定后调用（先经 `DisplayManager.waitForStableDisplays`）。新增发通知的代码路径若绕过此契约，镜像/扩展类操作会复现「通知不弹出」bug。
- **PanelView 的展开互斥/联动状态都是面板级 @State**：`expandedRowID`（SelectionRow 互斥）、`selectedDisplayID`/`hoveredDisplayID`（布局图联动）挂在 PanelView 上经参数传入 ArrangementRow/SelectionRow——新增联动屏相关的行时记得挂 onHover 上报 hoveredDisplayID，否则布局图不联动。
- **控件视觉用系统原生，不做手工玻璃模拟**（2026-09 实测回退）：199bb4d 曾手工绘制液态玻璃（染色基底+上缘镜面高光+边缘亮线+内阴影+落影），但小尺寸胶囊上 0.42 白高光 + 白亮描边叠加出 Aqua 时代"果冻按钮"复古感，已整体回退删除（`LiquidGlass.swift` 不复存在，ActivePill 恢复实心/描边、Toggle 恢复 `.switch`）。本机工具链 SDK 15.5 也无 `glassEffect` API（需 macOS 26 SDK），而 macOS 26 上系统原生控件自动获得真·液态玻璃观感——原生即最优解。若日后 SDK ≥ 26 且想上玻璃，用系统 `glassEffect`，不要再手绘
- **不要给面板卡片区重新引入 ScrollView**（2026-09 面板已去 ScrollView，此条为历史教训存档）：v0.2.0 曾因「屏幕重配时 ScrollView 理想高度塌 0（面板只剩底部栏不自愈）」加过「GeometryReader+PreferenceKey 测内容实高 + `frame(height: min(实高, 600))` 封顶」防御；2026-09 按用户要求去掉封顶滚动（窗口高度自适应内容）时整体移除——裸 VStack 高度恒为子项之和（确定值，无塌缩问题），且 ScrollView 还曾把卡片阴影**裁切出直线边界**（bounds 裁子视图）并造成 600pt 超限出滚动条，三个问题同源于它。若日后确需面板内滚动（如超多屏极端场景），必须同步处理：显式高度（防塌 0）+ 阴影裁切（`scrollClipDisabled` 或内缩 padding）+ 封顶策略。另：PreferenceKey 测内容高度本身可用（挂内容 background），与设置页滚动偏移改用 NSClipView 的禁忌不冲突
- **ShellRunner 必须并发读管道**（2026-09 防御修复）：原实现「先 waitUntilExit 再顺序 readDataToEndOfFile」有经典死锁隐患——管道缓冲区约 64KB，子进程输出超缓冲时 write() 阻塞、进程退不出，与等待线程互锁，调用方串行队列（AppState.queue/PresetManager.queue）整体卡死、isOperating 永久 true。现改为两个并发块各读一根管道、信号量汇合后再 waitUntilExit。displayplacer list 输出随屏的模式数增长（27 寸 1080p 双屏实测约 21KB，4K/多模式屏更大），开发时要记住这条底线。

## 风格约定

- Release notes 不使用 emoji
- 注释用中文
- 代码风格跟随现有文件的缩进和命名
- **含文字的视图禁用 `rotation3DEffect`（3D 透视变换）**：它会把视图栅格化重采样，HiDPI 下有效分辨率减半（2026-09 hover 倾斜实测：悬停时整卡文字明显变糊，用户反馈后整体移除）。需要动效一律用 2D 仿射组合（`scaleEffect`/`offset`/`rotationEffect`/`shadow`，走 CALayer 路径保持原生锐度）；hover 浮起范式见 `BubbleHoverLiftModifier`。若日后 SDK ≥ 26 想做真 3D，优先找系统级方案并先小范围验证文字锐度
