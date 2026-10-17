# 改动总结：面板内置主题 + 参数二级气泡 + 镜像/扩展短文案（2026-10-17）

分支 `v2`，未提交 git。本文档总结本轮三次迭代的最终状态与演进过程；
定型细节的单一事实源仍是 AGENTS.md「v2 全面重构」条目（2026-10-17 第三轮小节）。

## 概述

| # | 特性 | 状态 |
|---|------|------|
| 1 | 面板内置主题（7 组低饱和三档色系 + 跟随系统，深色自动派生） | 已实现，待人肉验收 |
| 2 | 参数块改压叠式二级气泡（主题浮面 + 逐帧揭示动画） | 已实现，待人肉验收 |
| 3 | 镜像/扩展按钮短文案（只留图标 + 二字） | 已实现 |
| 4 | 设置页通用页新增「主题色」选择卡（三区圆点） | 已实现 |

构建绿（Xcode 27.0 SDK），24 个测试 5 套件全绿，`Support/MoniSwitch.app` 已重打。

---

## 一、内置主题系统

### 1.1 色源与提取

- 色源 = 用户提供的 Chrome 浏览器主题色卡截图（15 组三档 + 1 自定义按钮）。
- 三档色值经 **Swift + CoreGraphics 像素扫描**逐圆提取（`/tmp` 脚本，非视觉模型描述）。
  实测圆卡几何 = **左上象限最深 / 右上象限中间 / 下半圆最浅**——视觉模型对分区的
  文字描述与像素探针相反，以后取色一律以像素扫描为地面真值。
- **收录 7 组低饱和同色系**：玫瑰红/鼠尾草绿/橙/棕褐/蓝/蓝灰/青灰。
  （初版收录 13 组，2026-10-17 用户二次筛选删掉品红/紫/绿/黄/粉/青六个高饱和色。）
  2 组蓝灰混合卡未收——其中间档是纯灰 `#C7C7C7`，做高亮在浅灰底上不可见。
- 全部 21 个浅色 hex 由 `Tests/PanelThemeTests` 锁定（`lightTiersLocked`）。

### 1.2 三档映射（实现勘误后定稿）

| 角色 | 色源档位 | 应用点 |
|------|----------|--------|
| 卡片底色 `background` | **最浅档** | 亮度卡/枢纽卡/预设卡/底部工具栏/HUD（BubbleBackground 染色） |
| 高亮 `highlight` | **中间档** | 行 hover 高亮、布局图点亮填充与描边、未激活胶囊悬停底 |
| 实心 `solid` | **最深档** | ActivePill 激活、图标圆框、滑条与 HUD 进度条填充、✓、「当前」角标、play 图标、分段选中 |
| 二级气泡浮面 `surface` | **最浅档** | 参数二级气泡（浅色与卡底同色，靠描边+阴影分层；深色=其深色派生 L0.21） |

实现勘误（2026-10-17）：初版实现把 `background` 与 `highlight` 两个角色**接反**了
（卡底染中间档、高亮染最浅档），与设置页圆点/注释描述的方向不一致。已掰正为
上表（与简报最初确认的「背景=最浅 / 高亮=中间」一致）；深色派生同步改为
bg←最浅档、highlight←中间档，测试期望值由 python colorsys 独立重算锁定。

「跟随系统」（默认）时全部不染：卡底=浅纯白/深卡色，高亮/实心=系统强调色，
浮面回退中性白/深卡色——即引入主题前的原观感。

滑条/HUD 进度条归**实心档**（简报曾写进高亮类，依用户「实心元素按最深处理」拍板归实心；
如需翻中间档，改 `BrightnessRow`/`BrightnessHUD` 两处 `.tint/.fill(palette.solid)` 即可）。

### 1.3 深色模式自动派生

- 色卡三档为浅色背景设计，深色下直接用会刺眼/沉底。派生**保留各档色相**、
  重算明度与饱和度（HSL 空间，S = 底数 + 原S × 系数并封顶）：

| 输出 | 色源 | L 目标 | S 公式 |
|------|------|--------|--------|
| bg（卡底） | 最浅档 | 0.15 | 0.24 + 原S×0.35，封顶 0.40 |
| highlight（高亮） | 中间档 | 0.62 | 0.30 + 原S×0.42，封顶 0.60 |
| solid（实心） | 最深档 | 0.52 | 0.30 + 原S×0.50，封顶 0.62 |
| surface（浮面） | 最浅档 | 0.21 | 同 bg |

- 28 个派生 hex 期望值由 **python colorsys 独立实现**算出写进测试
  （`darkDerivationLocked`）——改派生算法必须独立重算期望值，不许由实现反推。

### 1.4 solidText 自动对比文字

- 青/绿/黄系的深色实心派生档偏亮（如 teal `#39D0C5`），白字对比不足。
- `PanelPalette.solidText` 按实心档亮度自动选白/黑（亮度 > 0.55 用黑字），
  应用点：ActivePill 激活文字、图标圆框内图标、预设「当前」角标文字。
  **勿写死 `.white`**；「跟随系统」沿用原行为恒白。

### 1.5 架构：环境注入

- 新文件 `PanelTheme.swift`：`PanelTheme`（7 组定义 + 派生）、`PanelPalette`
  （background/highlight/solid/solidText/surface 五字段）、`\.panelPalette`
  环境键（默认 `.system`）。
- 注入点：PanelView 根部按 `AppSettings.panelThemeID` + colorScheme 解析注入全树；
  **HUD 自行解析**（独立 NSPanel 不继承面板环境，观察 AppSettings 实时刷新）；
  **设置窗口不注入**——保持系统强调色与原生观感（作用范围 = 菜单栏面板 + HUD）。
- 消费点：`BubbleBackground`/`ActivePill`/`HoverRowHighlightModifier`（Components.swift）
  改读环境；面板私有视图（布局图 ScreenBlock、SelectionRow、BrightnessRow、
  DeviceIconBadge）同读环境。**accent 逐层传参的老路已全部删除**。

### 1.6 设置页与持久化

- `AppSettings.panelThemeID`（String，默认 `PanelTheme.systemID`="system"），
  didSet 持久化 UserDefaults（key `panelThemeID`）。
- 通用 tab 新增「主题色」卡（在语言/启动卡与显示器卡之间）：7 组三区圆点 +
  「跟随系统」项，点击立即生效；圆点分区用「矩形 + Circle 裁剪」实现
  （不依赖 addArc 方向语义）；主题名走 `.help` tooltip 与无障碍标签（圆点无文字）；
  行下 footnote 说明三档用途。
- L10n 新键：`groupTheme`/`themeFollowSystem`/`themeFootnote` + 7 个 `theme*` 名称键。

---

## 二、参数二级气泡（压叠式）

- 多屏场景下，参数块（折叠头 + 位置/分辨率/刷新率 + 设为主屏/镜像/扩展）从枢纽卡
  独立成**悬浮气泡**，压叠在背板卡（布局图卡）上：
  - 左右缩进 10pt（`secondaryBubbleInset`）；全展开时上缘压过背板卡下缘 12pt
    （`secondaryBubbleOverlap`）；圆角 14、内容内边距 12、四周弥散阴影
    （黑 0.14 / r6 / y2，挂揭示之后随逐帧可见矩形走）。
  - 浮面 = `palette.surface`（浅色=最浅档，与卡底同色、靠描边 + 四周弥散阴影分层；
    深色=最浅档深色派生 L0.21，比卡底 L0.15 略浅；初版纯白方案被用户否决后改主题浮面）。
- **动画机制** `SecondaryBubbleReveal`（RevealHeightModifier 的压叠变体）：
  单 Animatable 参数驱动，压叠量随「当前高度 / 全高」线性爬升——展开时气泡上缘
  渐进滑上背板卡、收起时先滑落回卡下缘再压高归零，两向连续；负 bottom padding
  同步收缩布局，后续卡片紧跟真实底缘。离屏 harness 逐帧验证：收起基线 192.0
  与无气泡完全等高、展开 ~20 帧爬坡至 280（= 卡 192 + 块 100 − 压叠 12）、
  两向对称含弹簧过冲。
- 保留既有硬约束：常驻挂载（`mountedDisplayID`）、块高测量挂气泡内容（含 padding）、
  onChange 裹 withAnimation（防切屏高度瞬变）、`allowsHitTesting(expanded)` 摘幽灵命中。
- 单内置屏（`foldable=false`）不套二级气泡——无背板层级可叠，参数直接作枢纽卡主体。

---

## 三、镜像/扩展按钮短文案

- 只留图标 + 「镜像」「扩展」二字（原「镜像主屏/扩展显示」与「设为主屏」三胶囊
  同行时被省略号截断）。
- L10n：`mirrorMain`/`extendDisplay` 删除，新增 `mirrorAction`（镜像/Mirror）、
  `extendAction`（扩展/Extend）。
- 两胶囊改内容自适应宽度，「设为主屏」独占剩余宽度；镜像目标屏名仍走
  MirrorTargetTooltip（hover 停留 0.45s 弹出）。

---

## 四、工程收拢与规范修复（code-review 产出）

- 「浅纯白/深卡底 + 0.10/0.18 描边」色对四处重复 → 收拢为
  `BubbleMetrics.surfaceFill(dark:)` / `surfaceStrokeOpacity(dark:)`
  （BubbleBackground、二级气泡回退面、MiniBubble、布局图点亮块共用）。
- 纯装饰 overlay 补 `.allowsHitTesting(false)`（BubbleLighting 事故范式的存量补漏）：
  二级气泡描边、设置页色卡选中环、布局图 fill/stroke/✓ 角标、MiniBubble 描边。
- `settingRow(title:footnote:control:)` 在 GeneralTab/BrightnessTab 逐字双份
  （存量，本轮未动，待后续清理）。

---

## 五、文件清单

| 文件 | 变更 |
|------|------|
| `Sources/MoniSwitch/PanelTheme.swift` | **新增**：主题定义/派生/色板环境键/颜色数学 |
| `Sources/MoniSwitch/Components.swift` | BubbleBackground/ActivePill/hoverRowHighlight 接环境色板；surface 色对收拢 |
| `Sources/MoniSwitch/PanelView.swift` | 根注入色板；accent 传参全删；枢纽卡拆背板+二级气泡；SecondaryBubbleReveal；短文案；布局图/选行/滑条/徽章分档 |
| `Sources/MoniSwitch/BubbleMetrics.swift` | 二级气泡常量组 + surfaceFill/surfaceStrokeOpacity |
| `Sources/MoniSwitch/AppSettings.swift` | panelThemeID 偏好 + 持久化 |
| `Sources/MoniSwitch/SettingsTabs.swift` | 通用页主题色卡 + ThemeSwatchButton（三区圆点） |
| `Sources/MoniSwitch/BrightnessHUD.swift` | HUD 自解析色板注入 + 进度条取实心档 |
| `Sources/MoniSwitch/Localization.swift` | 新键 12 个（主题 10 + 短文案 2，删旧键 2） |
| `Tests/MoniSwitchTests/PanelThemeTests.swift` | **新增**：6 测试（浅色 21 值锁定/浅色角色映射/深色派生 28 值锁定/回落/名称键对应/solidText） |
| `AGENTS.md` | v2 条目新增第三轮小节（现行架构单一事实源） |

## 六、验证状态

- `swift build`（Xcode MacOSX27.0.sdk）绿；`bash Support/run-tests.sh` 24/24 全绿。
- 机器可验的都已验：色值/派生锁定、回落行为、二级气泡收起等高与逐帧爬坡（离屏 harness）。
- **待人工验收**（hover/动画/真实观感无法合成事件验证）：
  1. 7 组主题在浅/深两模式真实壁纸下的整体观感（重点：卡底=最浅档是否合适、
     中间档高亮（现 0.14 透明度）可见性是否足够——太淡则调高不透明度）；
  2. 滑条实心档 vs 中间档的取舍（现为实心档）；
  3. 二级气泡压叠观感 + 展开/收起动画 + 块内列表展开；
  4. 镜像/扩展短文案 + 镜像目标 tooltip；
  5. 设置页主题色卡（圆点分区方向、选中环）。

## 七、快速回退/调整点

- 滑条翻中间档：`BrightnessRow` 的 `.tint(palette.solid)`、`BrightnessHUD` 的
  `.fill(palette.solid)` 改 `palette.highlight`。
- 高亮强度：`HoverRowHighlightModifier`/`ActivePill` 悬停底的 `opacity(0.14)`。
- 二级气泡压叠量/缩进/阴影：`BubbleMetrics.secondaryBubble*` 常量组。
- 深色派生参数：`PanelTheme.darkDerived`（改后必须 python 独立重算测试期望值）。

---

## 八、2026-10-17 第四轮：纯图标按钮 + 二级气泡对齐 + 右上光源

> 本节内容**取代**前面第三轮里的「② 参数二级气泡（压叠式）」与「③ 镜像/扩展短文案」两小节；
> 主题系统（①）不变。动机 = 用户截图反馈「镜像/扩展两个按钮挤到了」，并追加两项观感要求。

### 8.1 镜像/扩展：去文字、只留图标

- 两个 `ActivePill` 的内容改成**单个 SF Symbol + 固定 26×26 图标框**（`rectangle.on.rectangle`
  / `rectangle.dashed`），去掉了「镜像/扩展」二字——两字在「设为主屏」同行仍会被省略号截断。
- 激活/未激活样式不变（实心档 / 淡描边 + 14% hover 底）；`设为主屏` 独占剩余宽度。
- 文字消失后补 `.accessibilityLabel`（内容与悬停提示同文案），否则读屏只剩无标签按钮。
- L10n：删 `mirrorAction` / `extendAction` / `mirrorTarget`，新增
  `mirrorActionHint`（镜像到 %@ / Mirror to %@）与
  `extendActionHint`（扩展显示：各屏独立排列 / Extend: independent desktops）。

### 8.2 悬停停留提示（通用化 MirrorTargetTooltip → HoverDwellTooltip）

- 原镜像目标气泡改为通用 `HoverDwellTooltip(text:icon:alignment:)`，两个图标按钮各挂一条：
  停顿 0.45s 后弹白底迷你气泡（圆角 10 + 细描边 + 浅阴影），移开立即收起；入场弹性、
  reduceMotion 关闭缩放，`allowsHitTesting(false)`。
- **贴右缘必须 `alignment: .topTrailing`**：参数二级气泡整块处于 `RevealHeightModifier`
  的 `clipped()` 内，居中气泡的右半截会被气泡边界裁掉——实测「镜像到 27英寸扩展显示器」
  少一个「器」字；改右对齐后完整显示。
- 未知的新发现：AX 树里提示文本的 frame 仍是完整尺寸，只有截图能看出裁切——**裁切问题
  不能靠 AX frame 判断**。

### 8.3 参数二级气泡：与一级气泡同宽同圆角、取消压叠、可 hover 浮起

- 宽度：取消 `secondaryBubbleInset`（左右各 10pt）——与亮度卡/枢纽卡同宽（348pt 卡面）。
- 圆角：`secondaryBubbleCornerRadius` 14 → `cardCornerRadius` 20。
- 压叠：删 `SecondaryBubbleReveal` 与 `secondaryBubbleOverlap`；改为常规卡片间距 14pt
  （`secondaryBubbleGap`），且该间隙**计入揭示高度**——展开时随 RevealHeightModifier 一起
  抽出，收起时归零，不残留空档（收起后窗口高度回到 383pt 基线，实测）。
- 阴影/浮起：改用面板统一的 `bubbleFloatingShadow()`（壁纸承接 + 右上光源方向性落影）+
  `bubbleHoverLift()`（与一级气泡同源：底锚 scale 1.02、弹簧 0.3/0.7、reduceMotion 关闭）。
  实测悬停时气泡左右边缘各外扩 3.5pt（= 348×2%/2），确认生效。
- 揭示仍走 `RevealHeightModifier`（逐帧重排 + allowsHitTesting 闸门），收起动画内容保持挂载。

### 8.4 右上光源布光（每张气泡各自布光，用户拍板）

- 新增 `BubbleLightingModifier` / `.bubbleLighting()`（Components.swift）；应用点：
  `BubbleCard` 全部卡片 + 参数二级气泡 + 底部两个气泡；**HUD 与设置窗口不参与**。
- 三层纯呈现 overlay（clip 到圆角、`allowsHitTesting(false)`、不占布局）：
  1. 右上→左下暖白泛光 `#FFF6E8`（浅 10% / 深 10%，沿对角逐段衰减到 0）；
  2. 左下极淡冷调压暗 `#0E1729`（浅 3.5% / 深 18%）——纯白卡上白光不可见，
     立体感主要靠背光侧压暗；
  3. 右上→左下 1px 内缘高光（白 0.55 / 0.22）。
- 方向性落影并入 `bubbleFloatingShadow()`（x -2 / y 4，浅 4.5% / 深 14%）：光从右上，
  影子偏左下。**必须挂在揭示裁切之外**，否则二级气泡的 `clipped()` 会把阴影切出直线。
- 静态光效与 reduceMotion 无关（不是动效，不应被关掉）。
- 实测采样（浅色 tealGray 主题）：卡面右上 (213,229,231) → 左下 (205,222,225)，
  对角差 ≈3%；用户此前拍板「接受极轻明暗」。

### 8.5 文件清单（本轮）

| 文件 | 变更 |
|------|------|
| `Sources/MoniSwitch/Components.swift` | **新增** BubbleLightingModifier / `.bubbleLighting()`；BubbleCard 挂布光 |
| `Sources/MoniSwitch/BubbleMetrics.swift` | 删二级气泡缩进/压叠/圆角/私有阴影组；新增 secondaryBubbleGap + 布光常量组；bubbleFloatingShadow 改 ViewModifier（含方向性落影） |
| `Sources/MoniSwitch/PanelView.swift` | 删 SecondaryBubbleReveal；二级气泡重写（同宽/同圆角/间隙/hover 浮起/布光）；镜像扩展纯图标 + 双 tooltip；HoverDwellTooltip 通用化 + alignment 参数；底部两气泡挂布光 |
| `Sources/MoniSwitch/Localization.swift` | 删 mirrorAction/extendAction/mirrorTarget；新增 mirrorActionHint/extendActionHint |
| `AGENTS.md` | 第三轮小节 ②③ 改写为末版；新增 ⑤ 右上光源布光；待办更新第四轮实测结论 |

### 8.6 验证（真实合成事件，非离屏）

- 用 AX 枚举状态项 → `AXPress` 打开面板 → 合成点击布局图屏块展开参数 → 合成 mouseMoved
  悬停按钮/气泡，`screencapture -R` 定点截图 + 像素扫描/比对。
- 已验：二级气泡与一级气泡同宽（左右边缘差 ≤1pt）、展开/收起高度回到 383pt、
  悬停放大（左右各 3.5pt）、两条提示气泡完整无裁切、浅色光效对角差 ≈3%、
  收起后无残留间隙；`swift build` 绿、24/24 测试绿。
- 未验：深色模式光效观感（仅代码审查）、真实壁纸下的整体感（需人肉）。

### 8.7 快速调整点

- 光效强弱：`BubbleMetrics.lightBloom*Opacity` / `lightShade*Opacity` / `lightRim*Opacity`。
- 方向性落影：`lightShadow*`（radius/x/y/opacity）。
- 二级气泡间距：`BubbleMetrics.secondaryBubbleGap`（改这里会同时影响揭示基线）。
- 提示停留时长：`BubbleMetrics.tooltipDwell`；提示文案：Localization 的 *ActionHint 两键。

---

## 九、浅色派生改版（2026-10-17 晚，A 浅 + C 深，用户拍板）

### 9.1 问题（用户浅色模式验收）

- **高亮不可见**：旧浅色直用色卡三档——卡底 L*90、高亮 L*80；行 hover `highlight.opacity(0.14)` 实际只叠出 **ΔL* 1.4**，布局图点亮 0.28 也只有 2.8。
- **配色发脏**：实心档直接用最深档原值，玫瑰 S=0.12 / 鼠尾草 0.09 / 棕褐 0.18 / 蓝灰 0.19 / 青灰 0.12——在粉彩底上像蒙灰；深色派生会把 S 抬到 0.36+，所以深色反而精神。
- **多色相打架**：粉彩底 + 低饱和深档 + slate 标签 + 奶油泛光 + 冷调暗角 + 灰描边同屏。
- **数据问题**：蓝灰浅色卡底 `#D6E3FF` 与蓝主题完全相同，名字叫灰、底是蓝；橙/棕褐也几乎同底。

### 9.2 改法（只动浅色，深色 C 方案逐像素不变）

- `PanelTheme.lightDerived(midHex:deepHex:)`：**取中间档色相为唯一色源**，按 CIELAB L* 目标二分求 HSL 明度——
  - 卡底 L*94，S = clamp(0.04 + 原S×0.22, 0.10...0.26)；
  - 高亮 L*80，S = clamp(原S, 0.42...0.68)；
  - 实心 L*40，S = clamp(最深档原S, 0.42...0.66)；
  - surface = 卡底。
- `PanelPalette` 新增 `hoverOpacity / litOpacity / subtleHoverOpacity` 与 `sectionLabel / cardBorder`：
  - 浅色派生：hover 0.42、点亮 0.50、胶囊悬停 0.22；标签/描边取实心档（标签不透明度 0.90，小字对比 ≈4.7:1）。
  - 深色 / 跟随系统：0.14 / 0.28 / 0.14，标签/描边 nil → 原 slate/primary 中性色。
- 浅色主题卡的右上泛光改**中性白 0.07**（`BubbleMetrics.lightBloomThemedOpacity`），暖白 `#FFF6E8` 会把淡彩叠脏；深色与跟随系统保持原暖白。
- 布局图点亮块：浅色底取派生卡底（`palette.surface`），深色仍取 `bubbleDarkFill`（C 像素不变）；点亮填充透明度走 `palette.litOpacity`。
- 设置页三区圆点改为画**当前外观下的生效色板**（浅色派生 / 深色原派生），不再画色源原值；L10n `themeFootnote` 文案同步。

### 9.3 期望值与测试

- 浅色 21 个派生 hex 由独立 python（sRGB→CIELAB L* + 二分，24 次迭代）计算写入
  `PanelThemeTests.lightDerivationLocked`；深色 `darkPaletteLocked` 断言 C 方案逐值不变
  （色板 = darkDerived、hover 0.14 / 点亮 0.28、标签/描边 nil）。
- `swift build`（Xcode 27 SDK）绿；`bash Support/run-tests.sh` 25/25 绿；`Support/MoniSwitch.app` 已重打。

### 9.4 快速调整点

- 浅色卡底浓度：`lightDerived` 的 `lstar: 94` 与 S 公式；高亮/实心目标同理。
- 交互强弱：`PanelPalette.themedLight` 的 hover 0.42 / lit 0.50 / pill 0.22。
- 标签/描边浓度：`solidColor.opacity(0.90 / 0.22)`。
- 浅色泛光：`BubbleMetrics.lightBloomThemedOpacity`（默认 0.07）。
