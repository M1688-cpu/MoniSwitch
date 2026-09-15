# 面板展开动画交接文档（2026-09-07，未提交）

> 用途：新对话里调整面板「展开/收起」动画手感时，先读这份文档。只覆盖动画相关改动；本次三项改版（去滚动条/阴影/底部栏）的完整记录见 AGENTS.md「面板去滚动条自适应 + 双层阴影 + 底部双气泡（2026-09）」条目。
> 状态：代码完成并编译打包，新版 .app 在运行；**git 未提交**；动画手感**未经人工测试**（合成事件触发不了面板内交互，见第四节）。

## 一、需求背景与已拍板的决策

用户要求：点击箭头展开折叠的显示器参数时，窗口高度**自适应拉伸**（不要出滚动条），动画「由上到下拉、先加速后减速」，并给出了三个候选方案。用户已选 **平滑弹簧**。

当时的三选一（后续想换曲线直接改常量即可，见第二节）：

| 方案 | 参数 | 特征 |
|------|------|------|
| **平滑弹簧（已选）** | `.spring(response: 0.32, dampingFraction: 0.86)` | 系统弹出层原生手感，先加速后减速、末端轻柔收敛不回弹 |
| 严格先加速后减速 | `.easeInOut(duration: 0.28)` | 完全按字面曲线，无弹簧成分，观感更「规矩」 |
| 利落快弹簧 | `.spring(response: 0.22, dampingFraction: 0.9)` | 更快更干脆，动画存在感最低 |

配套决策：高度自适应是动画的前提——**卡片区 ScrollView 与 600pt 封顶已整体移除**（PanelView 卡片区改裸 VStack），popover 高度完全由内容驱动，展开时窗口才会跟着长高。恢复封顶/ScrollView 会让本动画失去联动对象。

## 二、实现锚点（行号以 2026-09-07 工作区为准，改前先 grep 校准）

### 动画常量（唯一调参入口）

`Sources/MoniSwitch/PanelView.swift:5`：

```swift
/// 面板展开/收起动画：平滑弹簧（先加速后减速、末端轻柔收敛不回弹），
/// 配合 .move(edge: .top) 过渡呈现「由上向下拉伸」，popover 高度随内容联动。
private let panelReveal = Animation.spring(response: 0.32, dampingFraction: 0.86)
```

文件级 `private let`，全文件 4 个调用点共用；改这一处 = 全部展开/收起动画同步换曲线。

- `response`：动画总时长量级（秒），越大越慢；
- `dampingFraction`：1.0 = 无回弹临界阻尼，<1 会过冲回弹，0.86 = 轻微软着陆、无可见回弹。

### 4 个调用点（`withAnimation(panelReveal)`）

| 位置 | 行号 | 触发场景 |
|------|------|---------|
| `ArrangementRow.toggleExpanded()` | :523 | 点击折叠头展开/收起某屏参数组（主入口） |
| `SelectionRow` 触发行 | :604 | 点击分辨率/刷新率行展开/收起选项列表 |
| `SelectionRow.optionRow` | :649 | 选中某选项后收起列表 |
| `layoutPreviewCard.onSelect` | :341 | 点击布局图屏块 → 联动展开该屏参数组 |

### 2 个过渡（方向感的来源，保留未动）

- `:513` ArrangementRow 参数组：`.transition(.opacity.combined(with: .move(edge: .top)))`
- `:640` SelectionRow 选项列表：同款

`.move(edge: .top)` = 内容从上方滑入 + 高度拉伸，即「由上到下拉」的视觉；chevron 旋转（`rotationEffect`）不需要单独动画，包在同一个 withAnimation 里自动跟随。

### 机制：动画怎么联动到窗口高度

`PanelController.swift:67` 的 `NSHostingController.sizingOptions = [.preferredContentSize]` 让 SwiftUI 内容理想尺寸驱动 popover 尺寸。展开时：SwiftUI 布局目标高度变化（withAnimation 驱动内部过渡）→ hosting controller 的 preferredContentSize 更新 → NSPopover 以自己的系统动画改变窗口 frame。即**两套动画同时跑**：SwiftUI 内部弹簧 + popover 窗口系统动画，两者时长接近（都约 0.3s）所以大体同步。

## 三、调参 / 改方案速查

- **改快慢/软硬**：只改 `panelReveal` 的 response / dampingFraction。
- **换成严格先加速后减速**：`Animation.easeInOut(duration: 0.28)`。
- **出现「动画中底部内容被裁一刀 / 先露一段空白再填上」**：说明两套动画节奏错位（SwiftUI 内部比窗口快或慢）。处理顺序：① 微调 response 靠近系统节奏（0.28~0.35 之间试）；② 仍不行则去掉内部过渡动画（删 `.transition` 或 withAnimation 换 nil），只留 popover 窗口自身的 resize 动画——内容瞬移、窗口平滑，也是一种可接受观感；③ 都不满意再考虑手动驱动窗口尺寸（NSAnimationContext 包 `setContentSize`，注意要绕开 sizingOptions 的自动更新，复杂度高，先别上）。
- **不要动的东西**：hover 高亮动画（Components.swift 里两处 `.easeInOut(duration: 0.12)`，与展开动画无关，是瞬态反馈该快）；IndeterminateBar 的 `.linear(duration: 1.1)` 循环流动；popover 打开/关闭的展开动画（`popover.animates = true`，系统 chrome 提供，用户已确认满意）。
- **其他会改变面板高度的路径没有挂动画**（语言切换、刷新列表、预设应用后的重渲染）——高度会直接跳到新值。若测试觉得语言切换时跳变突兀，可给根 VStack 加 `.animation(panelReveal, value: l10n.lang)` 之类，但注意会让所有子视图重排都进动画，先试再定。

## 四、验证现状与方法

已机器验证：英文全收起态窗口 720pt == 内容完整高度（无滚动视口）；高度自适应机制（内容→preferredContentSize→窗口）工作正常。

**未验证（合成事件触发不了面板内 hover/点击，macOS 26 实测；只能人肉测）**：
1. 展开参数组：窗口高度跟随拉伸、动画平滑无裁切/空隙、弹簧手感是否满意；
2. 收起方向、选项列表（SelectionRow）展开的动画节奏是否与参数组一致；
3. 悬停底部图标 tooltip（本次改版一并加的 `.help()`）。

自动验证路径（新对话照 AGENTS.md 走）：`bash Support/build-app.sh` 打包 → `lsregister -f Support/MoniSwitch.app` + `open` → AppleScript AX 点开面板（`tell process "MoniSwitch" to click UI element 1 of menu bar 2`）→ `swift` + CGWindowList 读 layer=25 窗口 bounds 看高度变化 → `screencapture`（唯一文件名）像素扫描。**面板内交互自动化不可达**，动画观感只能人工看。

## 五、相关文件清单（本次动画改动涉及）

- `Sources/MoniSwitch/PanelView.swift`：panelReveal 常量、4 调用点、2 过渡（动画本体）；卡片区去 ScrollView（高度联动的前提）。
- `Sources/MoniSwitch/PanelController.swift`：未改，但 `sizingOptions = [.preferredContentSize]`（:67）是高度联动的窗口侧机制，调动画出问题时先确认它还在。
- AGENTS.md「面板去滚动条自适应 + 双层阴影 + 底部双气泡（2026-09）」条目：完整改版记录。
