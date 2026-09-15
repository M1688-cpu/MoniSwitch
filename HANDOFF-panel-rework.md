# 面板改版交接文档（2026-09-07，未提交，待手动测试反馈）

> 用途：新对话里修复本次改版发现的问题时，先读这份文档（AGENTS.md 已有简版条目，本文是带行号的完整版）。
> 状态：代码已完成并编译通过（swift build + build-app.sh 打包），新版 .app 已在运行；**git 未提交**；**未做人工测试**（自动化视觉验证被用户叫停，改为手动测试，测试表见文末）。

## 一、需求与实现总览（8 项）

| # | 需求 | 实现位置 |
|---|------|---------|
| 1 | 排列卡参数折叠（默认全收起） | PanelView.swift |
| 2 | hover 高光左右加宽 6pt（不挤字） | Components.swift |
| 3 | 位置分段 + 镜像/扩展**未选中**按钮 hover 高光 | Components.swift ActivePill |
| 4 | 底部工具栏（刷新/设置）hover | PanelView.swift |
| 5 | 分辨率/刷新率行旋转 chevron 展开指示 | PanelView.swift SelectionRow |
| 6 | 布局图点击选中 → 联动展开该屏参数组 | PanelView.swift layoutPreviewCard |
| 7 | 预设「当前」角标（与当前布局一致时） | DisplayManager.swift + PanelView.swift + Localization.swift |
| 8 | 菜单栏图标线条调细（semibold → medium） | MoniSwitchApp.swift:61 |

## 二、各文件改动细节（含行号锚点，行号以当前工作区为准）

### Components.swift
- `RowButton` 新增 `highlightExpansion: CGFloat = 6` 参数（:165），透传给 `.hoverRowHighlight(horizontalExpansion:)`（:174）。
- `hoverRowHighlight(horizontalExpansion: CGFloat = 6)`（:188）：`HoverRowHighlightModifier`（:253 附近）在高亮圆角矩形上用 **负 padding** `.padding(.horizontal, -horizontalExpansion)` 向两侧外扩——只扩视觉不占布局，文字位置零偏移。
- **例外传 0 的调用点**：SelectionRow 展开列表 optionRow（自带 h:6 padding，再扩会溢出浅灰圆角容器）、底部工具栏按钮（防越过中间分隔线）。
- `ActivePill` 未选中态 hover（:214 isHovered、:235 填充、:246-247 动画）：`!active && isHovered` → `Capsule().fill(BrandColor.accent.opacity(0.14))`，描边层叠最上。**手写了显式 init（:216 附近）**：加 `@State private` 后默认成员构造器会变 private，不写显式 init 会导致 PanelView.swift 的调用点编译失败。

### PanelView.swift
- 面板级新状态 `@State expandedDisplayID: String?`（:30）：排列卡当前展开参数组的屏 id，单值互斥，nil=全收起（默认）。
- arrangeCard 多屏分支（:179-180）：传 `foldable: true` + `$expandedDisplayID`；单内置屏分支（:199-206）：`foldable: false` + `.constant(nil)` 常展开。
- `ArrangementRow`（:437 起）：
  - 新参数 `foldable`（:450）、`@Binding expandedDisplayID`（:452）；`isExpanded = !foldable || expandedDisplayID == display.id`（:459）。
  - 标题行改为 RowButton 折叠头（:464）：图标 + 屏名 + 概要 + 旋转 chevron（:474-483）；`.onHover(perform: onHoverDisplay)` 保留在 RowButton 外层（布局图联动不变）。
  - 表单三行（位置/分辨率/刷新率）包进 `if isExpanded` + `.transition(.opacity.combined(with: .move(edge: .top)))`（:491 起）。
  - `toggleExpanded()`（:554）：**总是先清空 `expandedRowID = nil`**（任何组折叠/切换都会让组内选项列表不可见，防残留），再在 `withAnimation(.easeInOut(0.15))` 里切换 `expandedDisplayID`。
  - `parameterSummary`（:564）：`位置 · 分辨率 · 刷新率`；位置前缀仅 `showsPosition && state.side(of:) != nil`（镜像/重叠时省略，与 sideSegmented 两段均不亮的判定一致）；不新增 L10n key，复用 sideLeft/sideRight/hertzLabel。
- SelectionRow 触发行尾部 chevron（:651）：`chevron.right` 9pt semibold secondary，`.rotationEffect(.degrees(expanded ? 90 : 0))`，随触发行自己的 withAnimation 一起动。
- layoutPreviewCard onSelect（:350-360 附近）：选中某屏时 `withAnimation { expandedDisplayID = d.id }`；取消选中不收起。
- toolbarButton：内容加 `.hoverRowHighlight(horizontalExpansion: 0)`（:396 附近）。
- presetsCard（:320-327）：`DisplayManager.shared.presetMatchesCurrentLayout(preset.screenArgs, displays: state.displays)` 为真时，play 图标前渲染「当前」胶囊角标（样式同主屏「主屏」角标：fontMini medium 白字 accent Capsule）。

### DisplayManager.swift（纯计算，不跑 shell）
- `presetMatchesCurrentLayout(_:displays:)`（:424）：预设侧 `argSignature` 解析每条 arg，当前侧 `currentLayoutSignatures` 按 currentSnapshotArgs 同构归并（镜像组一条、基准屏主屏优先，用 displays + 单例 mirrorGroups 推导），两侧排序后整体比较。
- 签名格式 `layoutSignature`（:477）：`res:WxH|hz:N|depth:N|scaling:on/off|origin:x,y|degree:N|n:屏数`。**忽略 persistent id**（免疫漂移）；镜像 vs 扩展靠 `n`（合并条目屏数）区分。
- `argSignature`（:462）：复用 idTokens/resToken；hz 默认 60、depth 默认 8、degree 默认 0（旧版 mirror() 生成的缺字段 arg 可能误判不匹配——宁缺毋滥）。`token(_:in:)`（:487）是通用 `key:value` 取段工具。

### Localization.swift
- 新 key `currentLayoutBadge`（枚举 :106 / 翻译表 :219）：zh「当前」/ en "Current"。

### MoniSwitchApp.swift
- menuBarIcon 字重 `.semibold` → `.medium`（:61），14pt 不变；注释已同步。

### AGENTS.md
- 「已完成的功能」追加「面板折叠与 hover 交互统一（2026-09）」条目；「注意事项→自动化验证的 2026-09 增补」追加第 ⑤ 条（CUA 点击是窗口路由、点菜单栏图标必须 CGEventPost 全局脚本、图标定位用 killall 前后差分、视觉 MCP 解析不了 CUA CDN）。

## 三、修复问题时最容易踩的点

1. **折叠互斥**：`expandedDisplayID` 是面板级单值（同时只展开一块屏）。若要「多组同时展开」需改成 Set；现设计是防面板高度跳动。
2. **expandedRowID 清空时机**：toggleExpanded 无条件清空（连别的组开的选项列表也会关）。若测试反馈「切换组时不想关掉别组选项列表」，改成仅当前缀匹配 `"\(display.id)-"` 才清——但要处理「A 组开着列表 → 展开 B → A 折叠 → 列表状态悬空」的残留问题。
3. **单内置屏不折叠**：`foldable: false` 分支是刻意设计（内容仅两行）。若测试希望单屏也折叠，把 :205 的 false 改 true 即可（Binding 不能再传 .constant）。
4. **角标误判排查**：presetMatchesCurrentLayout 对不上的常见原因——hz/分辨率真的变了（设计如此）；旧预设 arg 缺 hz/color_depth 字段（默认 60/8 可能对不上实际值）；镜像组基准屏选择差异。**不要**用 currentSnapshotArgs() 跑 shell 对比（面板渲染路径不能起 displayplacer）。
5. **ActivePill 改动**：动它之前记住必须保留显式 init，否则跨文件调用点编译失败。
6. **hover 加宽**：负 padding 只影响 background shape，若某行高亮溢出容器，给该行调用点传 `horizontalExpansion: 0`。

## 四、构建 / 运行 / 验证

```bash
swift build                    # 已通过
bash Support/build-app.sh      # 已打包，Support/MoniSwitch.app 即新版
open Support/MoniSwitch.app    # 当前运行中（新 build，lsregister 已登记、陈旧登记已清）
```

- LaunchServices 已清理：注销了 /Volumes/MoniSwitch 和 dmg-staging 的陈旧登记，只剩 Support/MoniSwitch.app 一份。
- **git 全部未提交**。注意工作区还有**本改版之前**的未提交改动（LiquidGlass.swift 删除、AppState/SettingsTabs 等的既有修改），修 bug 时别把旧改动误当本次产物。
- 自动化验证已叫停；新对话如需自动验证，按 AGENTS.md「自动化验证的 2026-09 增补」第 ⑤ 条走 CGEventPost 全局脚本（CUA 的 left_click 点不到自家菜单栏图标）。

## 五、手动测试表（等待用户反馈）

分组：A 折叠（A1-A9）/ B hover 加宽（B1-B4）/ C 未选中按钮 hover（C1-C3）/ D 展开箭头（D1）/ E 布局图联动（E1-E3）/ F 工具栏 hover（F1）/ G 预设角标（G1-G5）/ H 菜单栏图标（H1-H2）/ I 回归（I1-I5）。

重点盯：A6/A7（互斥与不残留）、G2-G5（角标判定，尤其 G5 id 漂移）、I5（面板塌缩老 bug 回归）。完整表格见本次对话交付的测试表（或按上面分组自查）。

## 六、待办

- [ ] 用户手动测试反馈 → 修复问题（用本文档第三节排查）
- [ ] （可选）code-reviewer 过 diff
- [ ] 测试通过后 git commit（Release notes 不用 emoji，注释中文，风格随现有文件）

## 七、第二轮改造：面板迁移 NSPopover（2026-09-07 凌晨，未提交）

### 背景

手动测试反馈第一轮改版后出现回归：面板变成**尖角方框、顶部不贴合菜单栏、底部多出白色长条**（浅色模式）。排查结论：第一轮 diff **完全没碰窗口层**（PanelView 根 body / BubbleBackground / BubbleMetrics 逐字节未变）——这是 macOS 26 上 MenuBarExtra `.window` 系统面板 chrome 的渲染退化，不是卡片层画错。

同时用户提出三个新需求（参考 WhatCable）：面板中线对齐图标、顶部倒三角箭头、从上到下由小到大的展开动画——MenuBarExtra 一个 API 都没有。

### 实现（全部完成）

**放弃 MenuBarExtra，改自持 NSStatusItem + NSPopover**：

- **新增 `Sources/MoniSwitch/PanelController.swift`**（核心，~140 行）：
  - 单例，持有 NSStatusItem（`display` SF Symbol 14pt medium 模板图标，从 MoniSwitchApp 搬来）+ NSPopover（`.transient` + `animates`）+ `NSHostingController<AnyView>`（`sizingOptions = [.preferredContentSize]`，environmentObject 注入 L10n/AppSettings/PresetManager 单例，模式照抄 DockPolicyManager）；
  - AppState 从 App 的 @StateObject 移到这里（唯一消费者是 PanelView）；
  - **transient 关-点竞态守卫**：`lastCloseTime` 0.25s 内的 toggle 忽略（面板开着点图标，系统先关 transient 再发 action，isShown 已 false，直接 toggle 会立即重开=永远关不掉）；
  - show 前强制 `layoutSubtreeIfNeeded()` 固化首开尺寸；show 后主线程异步 `button.cell?.isHighlighted = true`，`popoverDidClose` 复位；
  - `close()` 公开方法：面板内「设置」按钮先收面板再 openSettings。
- **`MoniSwitchApp.swift` 瘦身**：删 MenuBarExtra；Scene 换 `Settings { EmptyView() }` 占位（SwiftUI 至少要一个 Scene）；保留 `.commands` ⌘,（CommandGroup 仍指向 DockPolicyManager.openSettings）；`@NSApplicationDelegateAdaptor AppDelegate` 在 didFinishLaunching 调 `PanelController.shared.setup()`；menuBarIcon 扩展搬走。
- **`PanelView.swift`**：卡片内容零改动；「设置」按钮加 `PanelController.shared.close()`；三处注释更新（头部、scrollContentHeight、SelectionRow 相关历史记录补 NSPopover 语境）。
- 箭头/居中/动画/圆角/贴顶全部由 NSPopover 系统 chrome 原生提供，无自绘。

### 自动化冒烟结论（像素差分 + CGWindowList，2026-09-07 实测）

- 面板窗口 bounds X=616 宽 406 → **中心 x=819 = 图标中心 819，偏差 0**；顶 y=28 紧贴菜单栏底；
- 剪影差分：中心 x≈819 顶部凸起 8pt（箭头尖）、两侧平顶；左上边缘 y41→66 从 635 曲线收到 624（圆角 ~12pt 非尖角）；剪影止于 y=642（窗底 636 + 6pt 阴影，**无底部条带**）；
- AX click（`System Events → process MoniSwitch → click UI element 1 of menu bar 2`）开关两向均生效；**CGEventPost 坐标点击在此终端环境不落地**（AGENTS.md 自动化增补已更新）。

### 已知留观项

- **首开尺寸跳变**：show 前 `layoutSubtreeIfNeeded()` 已做防御，冒烟未见异常；若手动测试仍见开面板瞬间高度跳一下，检查 `scrollContentHeight` 初值 480 与实际内容高的差距。
- **面板状态跨开关保留**：hosting controller 常驻，`expandedDisplayID`/`selectedDisplayID` 等 @State 在关面板后不重置（重开还在）——与 MenuBarExtra 行为大概率一致，若希望重开复位需在 popoverWillShow 里加复位钩子。
- **⌘, 从面板直接打开设置已失效**（App 非 active 无菜单加速键）；设置入口只剩面板底部按钮（不受影响）。
- 动画手感（"从上到下由小到大"）是 NSPopover 系统标准动画——**用户已确认流畅无问题（2026-09-07）**。

### 第二轮补丁：外部点击收起（2026-09-07，用户反馈「点面板外不关」）

**根因**：NSPopover `.transient` 的自动收起依赖「App 激活后失活」或 key 窗口变更。LSUIElement 纯菜单栏 App 从不激活，点桌面/其他 App 时这些信号不会到达——AppKit 的自动 dismiss 不触发（点图标能关是因为走了自家 toggle action）。

**修法**（`PanelController.installDismissMonitors()`）：
- 全局监控（`addGlobalMonitorForEvents`，收其他 App/桌面/其他菜单栏图标的点击）+ 本地监控（`addLocalMonitorForEvents`，收自家其他窗口如设置窗口的点击），事件 mask = 左/右/其他鼠标按下；
- 按下点在 popover 窗口 frame 内（面板正常交互）或状态项按钮 frame 内（交给 togglePanel，防双重关闭）时放行，否则 `close()`；
- 监控回调里用 `MainActor.assumeIsolated` 续接主 actor（AppKit 约定回调在主线程）。

**验证**（CGEventPost 真实全局事件）：面板开着点桌面 (300,400) → 面板收起 ✓；AX click 图标开/关双向正常 ✓；面板开启后稳定不自动关闭 ✓。

**自动化结论更正**（重要，推翻本文件上文「CGEventPost 不落地」的说法）：CGEventPost 在此终端**有效**（Apple 菜单可点开、NSEvent 全局监控收得到），但**点不动 NSStatusBarButton**（hid/session tap 均无效，macOS 26 对状态项的合成事件屏蔽）——自动化开关面板用 AX click（注意状态项 x 会漂移，点击前现查）；测外部点击收起用 CGEventPost 点任意面板外坐标。详见 AGENTS.md「自动化验证的 2026-09 增补」⑥⑦。
