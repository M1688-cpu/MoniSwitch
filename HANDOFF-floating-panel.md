# HANDOFF — 悬浮卡片背景板改版（2026-09-12）

> 交接文档：本文自包含，供新会话直接使用。当前代码**未提交**（工作区里同时还有本次会话之前的 Tutti 改版未提交改动，见「当前代码状态」）。
> 用户对本次结果**不满意**，两个遗留问题见「五、修改后的效果与遗留问题」，**尚未做任何修复**。

---

## 一、用户最初想要的三个效果

1. **背景板（popover 系统玻璃）**：点击面板内任意位置后不再变白（浅色模式）/变黑（深色模式）；且整体比「刚打开时的初始态」更透明一点。
2. **显示器名称前的图标圆框**（DeviceIconBadge）稍微调大一点。
3. **布局预览图（LayoutDiagram）**：去掉主显示器显示蓝色这一功能，只保留「鼠标悬停在对应显示器名称上时的高亮」。

## 二、修改前的状态（基线，含实测数据）

- 背景板 = macOS 26 系统 NSPopover 自带的液态玻璃（私有类 `NSGlassView`）。
  刚打开时较透（用户"可以接受"）；**点击面板内任意处后变白**——像素实测（浅色模式，背板左边距带采样，壁纸参考值 145/248/248）：
  - y=60 处 162,182,199 → 214,230,244（+50）
  - 顶部带 145,166,186 → 208,224,238（+63）
  - 深色模式对称变黑。
- 图标圆框 24pt、图标字号 12pt（复用 `fontControl`）、排列卡展开块缩进 34pt。
- 布局预览：主屏块 `accent.opacity(0.18)` 填充 + accent 描边 1.5pt + 左上角实心圆点标记；副屏块 `gray.opacity(0.08)` 填充 + `secondary.opacity(0.4)` 描边 1pt + 空心圆点。

对比截图（本机 /tmp/msdiag/，重启后丢失，仅本次会话有效）：
`off-before.png`（改前·刚打开）、`off-after.png`（改前·点击后变白）。

## 三、根因诊断结论（已实锤，勿重复排查）

### 3.1 层级结构（视图树 dump 实测）

```
_NSPopoverWindow（popover 窗口，406×636）
└── NSPopoverFrame（= window.contentView.superview）
    ├── NSGlassView（406×636，背板玻璃）        ← 兄弟节点！
    │   ├── ContentHolderView
    │   │   └── _NSCoreHostingView<RootView>   ← 系统自带的 SwiftUI 内容层
    │   └── （再无其他子视图）
    └── NSView（contentView，13,13,380×610，13pt chrome 内缩）
        └── NSHostingView<AnyView>（我们的 PanelView 容器链）
```

**关键结论**：
- `NSGlassView` 是 **contentView 的兄弟节点**，从 contentView 子树里找不到它，遍历必须从 `window.contentView.superview`（NSPopoverFrame）开始。
- `NSGlassView` **继承公开类 `NSGlassEffectView`**（SDK 头文件 `NSGlassEffectView.h`，macOS 26+），`as? NSGlassEffectView` 向下转型安全。公开 API：`contentView` / `cornerRadius` / `tintColor` / `style(.regular | .clear)`。
- 变白/变黑的根因：`ContentHolderView → _NSCoreHostingView` 这层**系统自带 SwiftUI 内容随窗口 key 态自适应**——面板初开（LSUIElement App 未激活、窗口非 key）渲染较透变体；点击面板内 → 窗口变 key → 切加白变体。运行时自省证实**两态间 style/tintColor/cornerRadius 均不变**，自适应藏在内层 SwiftUI 里，公开旋钮无法关闭。

### 3.2 实验矩阵（9 条路线全部实测过，数据与否决原因）

背板左边距带采样，壁纸参考 y=60/320/600 = 145/248/248，顶部带 = 108,134,155。

| 方案 | 点击前后恒定？ | 数据 | 否决/采纳原因 |
|---|---|---|---|
| 现状不动 | ✗ | 162→214（y=60），顶部 145→208 | 用户投诉的问题本身 |
| `style = .clear` | 深色区基本✓ | y=60: 158→153（稳）；y=320: 234→250（+16）；顶部 151→130（稳） | 浅色壁纸区点击后仍 +16 提亮；不完美 |
| `alphaValue` 0.85~0.75 | ✗ | ≈基线，几乎无效果 | 玻璃渲染不理会视图 alpha |
| `clear` + `alphaValue` 组合 | 同 clear | ≈clear 单独 | 同上 |
| `tintColor = NSColor.clear` | ✗ | y=320: 224→250（+26 更糟），点击前更透 | tint 关不掉自适应，漂移更乱 |
| `tintColor = 黑20%` | ✗ | 各点位漂移方向混乱 | 不可用 |
| **隐藏玻璃内层（hideinner）** | **✓ 像素级零漂移** | 143/243/247/108 ≈ 壁纸（Δ≤5） | **采纳（方案 A）**；代价：blur/边框/箭头全无 |
| hideinner + 自建 NSVisualEffectView 垫底（.popover / .underWindowBackground, state=.active） | ✓ | 191~226 雾白 | macOS 26 上老式振动材质=雾白，比现状还白 |
| hideinner + 自建 NSGlassEffectView 垫底（.regular/.clear） | ✗ | 点击后自建玻璃被系统压制消失（两态不一致） | key 切换时非系统位置的玻璃不渲染 |

当时给用户的三选一：A 悬浮卡片（采纳）/ B clear 玻璃风格 / C 维持现状。**用户拍板 A**。

## 四、实际进行的修改（文件级清单）

全部未提交，在工作区。

### 4.1 `Sources/MoniSwitch/PanelController.swift`（核心改动）

- 新增 `hideSystemGlassBackdrop()`（幂等）：从 `window.contentView.superview` 遍历找 `NSGlassEffectView`（含私有子类 NSGlassView），`glass.subviews.forEach { $0.isHidden = true }`——只隐藏玻璃的**内层内容**，玻璃视图本体仍在。macOS 13~15 无 NSGlassView，静默返回（旧系统行为不变）。
- 辅助：`static glassEffectViews(under:)`（`@available(macOS 26.0, *)`，递归收集）。
- 补挂时机四处：`show(from:)` 同步 + async 各一次（让展开动画期间玻璃也不出现）、`popoverDidShow`、popover 窗口 `didBecomeKey`、App `didBecomeActive`（后两个是 **selector 式**观察者 `popoverWindowDidBecomeKey(_:)` / `appDidBecomeActive(_:)`，注册在 `setup()`——**不能用 block 式**：SDK 26 下闭包标 @Sendable，捕获 self 告警，项目基线零警告）。
- 已实测：窗口 resize（展开参数 636→685）不会复活玻璃。

### 4.2 `Sources/MoniSwitch/BubbleMetrics.swift`

- `deviceIconDiameter` 24 → **28**；新增 `deviceIconFontSize` = **14**（不能改 `fontControl=12`，它被镜像/扩展按钮、预设卡、设置页十几处共用）。

### 4.3 `Sources/MoniSwitch/PanelView.swift`

- `DeviceIconBadge` 图标字号改用 `deviceIconFontSize`；排列卡展开块缩进 34 → **38**（=28+10）。
- `LayoutDiagram.screenBlock`：删 `isMain` 特判——所有屏块统一 `fill = gray.opacity(0.08)`、`stroke = secondary.opacity(0.4)` 宽 1；**删左上角主屏圆点标记**；保留 hover 联动高亮（accent 0.28 填充 + 2 宽描边）与点击选中 ✓ 角标 + 展开联动。`LayoutDiagram` doc 注释同步。

### 4.4 `Support/build-app.sh`

- 加 `set -o pipefail`：原 `swift build -c release 2>&1 | tail -5` 会拿 tail 退出码 0 掩盖编译失败，脚本带旧二进制打包出「假新版」（本次实测踩坑，实验矩阵整轮跑空）。

### 4.5 `AGENTS.md`

- 已更新：新条目「悬浮卡片背景板 + 视觉微调（2026-09-12）」、修正旧结论「公 API 无从调其透明度」、build 脚本 pipefail 说明、badge 常量变更注记。

## 五、修改后的效果与遗留问题（用户实测反馈：非常不理想）

已验证达标的：点击前后背板**像素级零漂移**（浅色 143,167,185→143,167,185；深色 21,21,21→21,21,21）；背板≈壁纸原色（Δ≤5）；卡片内部纯白不变；布局图去蓝生效；badge 放大生效；浅/深模式都测过。

**用户不满意的两个遗留问题（未做任何修复）：**

### 问题 1：背景阴影没去干净
悬浮卡片之外仍能看出一圈"背景阴影"残留。

### 问题 2：卡片周围的阴影成了一条像素点线
原本的弥散软阴影看起来收缩成了一条 1px 的线。

### 成因假设（下个会话按序验证，均未证实）

1. **窗口级系统投影**：`_NSPopoverWindow` 自带 window shadow（`window.hasShadow`），隐藏玻璃内层不影响它——悬浮卡片下会有一圈窗口级大投影，观感即"没去干净"。**可试 `popover.contentViewController?.view.window?.hasShadow = false`**。
2. **NSGlassView 本体的 chrome 残留**：本次只隐藏了它的 `subviews`，玻璃视图**自身**的 layer 可能仍画边框描边/箭头 mask 的 1px 暗线（AGENTS 曾记录"NSPopover 窗口自带 chrome 描边，可见边界内缩约 13 逻辑点、全高暗线"）。**可试整体隐藏：`glass.isHidden = true`（当时没试）**，或对玻璃视图置 `alphaValue = 0`。注意整体隐藏可能连窗口 shape/圆角 mask 一起带走，需实测。
3. **卡片弥散阴影直接投在壁纸上、视觉浓度骤增**：双层 `bubbleShadow()`（ambient radius 11 黑 0.06 y5 + key radius 3.5 黑 0.09 y1.5）原先投在磨砂玻璃上（亮度相近、几乎无感），现在直接投在壁纸上，浅色壁纸处读成灰晕——"没去干净"的感受可能部分来自这里而非系统残留。
4. **阴影被宿主视图边界硬切出直线**（对应"一条像素点线"）：卡片阴影延伸 ~16-27pt，若被 NSHostingView/contentView 边界裁切（layer-backed 视图默认 masksToBounds），切线在透明背板上直接可见——与当年 ScrollView 裁切阴影是同机制，此前被磨砂背板掩盖。验证法：沿卡片右缘向外逐点采样，看阴影衰减是否在固定 x 处**陡然截断**（而非平滑衰减到 0）。
5. **卡片自身 1px 描边显突兀**：`BubbleBackground` 有 `Color.primary.opacity(0.10/0.18)` 描边（Components.swift），投在玻璃上时是柔和边界，直接对壁纸后可能读成硬线。

## 六、可修改的地方（旋钮清单，供下个会话直接用）

### 6.1 背板/残留相关（PanelController.swift）
- `hideSystemGlassBackdrop()`：
  - 改成 `glass.isHidden = true`（整体隐藏，验证假设 2）
  - 追加 `window.hasShadow = false`（验证假设 1）
  - **完全回退** = 删掉四处调用（函数可保留），恢复系统玻璃 = 回到「二、修改前的状态」
- 若想换方案 B（`style = .clear`，保留 chrome、深色区恒定但浅色区点击 +16）：在 `hideSystemGlassBackdrop` 里改为 `glass.style = .clear` 即可（实验代码已删，数据见 3.2 表）。

### 6.2 卡片阴影/描边（Components.swift + BubbleMetrics.swift）
- `bubbleShadow(opacity:)` 扩展：双层参数（radius 11/3.5、黑 0.06/0.09、y 5/1.5）——可减半径/降透明度让悬浮态更干净。
- `BubbleHoverLiftModifier` 的 hover 增强阴影：`liftShadowOpacity 0.10 / liftShadowRadius 16 / liftShadowY 8`。
- `BubbleBackground` 描边：`strokeOpacity` 0.10（浅色）/0.18（深色）——可调弱或删掉。
- 面板根 padding 16（PanelView `.padding(16)`）：加大可给阴影留更多衰减空间（AGENTS 注：勿随意缩小）。
- **注意**：改阴影前先做假设 4 的"陡然截断"采样，确认是裁切还是浓度问题，对症下药。

### 6.3 badge / 布局图（BubbleMetrics.swift + PanelView.swift）
- `deviceIconDiameter`（现 28）/ `deviceIconFontSize`（现 14）/ 展开块缩进（PanelView 中 `.padding(.leading, 38)`，=直径+10）。
- `LayoutDiagram.screenBlock`：`fill = gray.opacity(0.08)`、`stroke = secondary.opacity(0.4)`、宽 1；hover 态 `accent.opacity(0.28)` + 宽 2；选中 ✓ 角标。

## 七、验证方法论（工具与命令，/tmp/msdiag 重启即失，按此重建）

1. **编译打包**：`swift build`（快检）→ `bash Support/build-app.sh`（.app，用 release）。**务必核对二进制 mtime 或 build log 里 `Build complete`**（pipefail 已修，但多一眼无妨）。
2. **启动**（绕过 `open` 以抓 stderr 日志）：
   ```bash
   pkill -x MoniSwitch; sleep 1
   nohup Support/MoniSwitch.app/Contents/MacOS/MoniSwitch > /tmp/msdiag/run.log 2>&1 & disown
   ```
3. **开面板**（AX，menu bar 索引可能漂移，先 `count of menu bars`）：
   ```bash
   osascript -e 'tell application "System Events" to tell process "MoniSwitch" to click UI element 1 of menu bar 2'
   ```
4. **查面板窗口**：CGWindowList 找 owner=MoniSwitch、layer=25 的窗口（406 宽）。bounds 为**主屏左上原点、点单位**，与 CGEventPost 坐标系一致。
5. **合成点击**：CGEventPost（swiftc 预编译 ~15 行：mouseMoved + leftMouseDown/Up，`.cghidEventTap`）。**冷启动后仅前 ~5-10 次对面板内容有效**（macOS 26 实测，之后整体失活，需 pkill 重启重置预算）。点击位置选左边距带（窗口 x+22 左右，纯背板无控件）。
6. **截图/采样**：`screencapture -x -D 1 /tmp/x.png`（主屏）；像素采样用 swiftc 小工具（ImageIO 读 PNG → CGContext RGBA8 缓冲，坐标按 `img.width / CGDisplayBounds(CGMainDisplayID()).width` 换算点→像素）。**壁纸参考值**：点面板外（如 x=700）关面板后同点采样。
7. **深色模式**：`osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true/false'`（测完还原）。
8. **免重编实验矩阵**：`defaults write com.moniswitch.app <调试键> <值>` + 代码读 `UserDefaults.standard.string(forKey:)`（本次已删干净，含 `defaults delete com.moniswitch.app MoniswitchBackdropDebug`）。
9. **坑**：①analyze_image 会被截图里的终端文本/提问措辞诱导误报，**像素扫描是唯一地面真值**；②背板边距带采样点距卡缘 ~20pt 内会被卡片弥散阴影污染（ambient 11 + hover 16 的衰减范围），"变白/变灰"先排除阴影再下结论（本次就把 hover 阴影误判过一次玻璃回归）；③hover/tooltip 无法合成事件，只能人肉。

## 八、当前代码状态与回退

- 工作区未提交改动 = **两层叠加**：本次会话之前已有的 Tutti 改版等未提交改动（Components/Localization/PanelView 大改、DMG 相关文件删除等，见 `git status`）+ 本次四、节的改动。回退本次改动请按 4.1~4.3 的文件逐点逆向，不要 `git checkout` 整文件（会连带丢掉之前的改版）。
- 彻底回退背景板方案：删 `hideSystemGlassBackdrop()` 的四处调用即可（show 同步/async、popoverDidShow、两个 selector 观察；观察者注册也可一并删）。
- 新构建产物 `Support/MoniSwitch.app`（2026-09-12 16:57 打包）含全部改动。

## 九、下个会话建议的排查顺序

1. 先复现两个问题并各拍一张截图（开/关面板差分）。
2. 假设 4 验证（阴影陡然截断采样）→ 决定是裁切问题还是浓度问题。
3. 假设 1/2 快速试：`window.hasShadow = false`、`glass.isHidden = true`（各一次构建即可分辨）。
4. 依据结果从「六、旋钮清单」选对症参数；若整体不满意的根因是"悬浮风格本身"，与用户确认是否切方案 B（.clear）或回退 C。
