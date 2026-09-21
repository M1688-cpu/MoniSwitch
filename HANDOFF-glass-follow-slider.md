# HANDOFF：背板玻璃「跟随系统 Liquid Glass 透明度」实验中断交接（2026-09-20）

> **状态：已完结（2026-09-20 晚，同日续跑）**。核心结论：背板**不跟随** Liquid Glass 滑块（滑块两端读数逐位相同，证伪）；27 上 `.clear`/keyed 旋钮全部失效（2×2 矩阵，key 态差异 ≤1.4/255）；定型 = `applyLiquidGlassBackdrop()` 按系统分支（27+ 完全不干预 / 26 保留 clear+makeKey / 13~15 makeKey 无害保留），三组 DEBUG 开关已删，26.5 SDK 重打包并终验完毕。结论与增补已并入 AGENTS.md（「悬浮卡片背景板」条目 27 段 / 构建与打包 SDK 坑 / 自动化条目⑪ 2026-09-20 增补）。本文档其余内容为过程存档，勿删。

> 供新对话直接接手。深层历史结论不在此重复，见 AGENTS.md（项目主文档）与 HANDOFF-floating-panel.md（26 时代玻璃背板完整实验史）。

## 〇、续跑会话完成总结（2026-09-20 晚接手，同日完结）

### 实验数据（新壁纸、1920×1080 单屏、面板 406×550 @ (1342,27)；边距带读数与壁纸相关，仅同轮可比）

| 档 | 滑块位置 | makeKey | style 覆盖 | L | R | T | B |
|---|---|---|---|---|---|---|---|
| A | 最不透端（≈1.0，用户确认现状） | ✓ | 不碰 | 170.5 | 140.6 | 182.1 | 192.4 |
| B | 最透端（≈0.0，用户手动拨） | ✓ | 不碰 | 170.5 | 140.6 | 182.1 | 192.4 |
| M0 | —（滑块位置无关） | ✓ | 强制 .clear | 170.5 | 140.6 | 182.1 | 192.4 |
| M2 | — | ✗ | 不碰 | 171.9 | 141.7 | 182.1 | 192.4 |
| M3 | — | ✗ | 强制 .clear | 171.9 | 141.7 | 182.1 | 192.4 |

管线自证：A/B 两张截图哈希不同（独立抓帧）而玻璃带读数逐位相同 → 判定成立。用户肉眼确认：滑块拨满全程，系统别处（菜单栏/Dock 等）变透了、唯独面板不变。

### 结论（均已并入 AGENTS.md）

1. **「背板跟随滑块」证伪**：滑块作用于系统玻璃，但 NSPopover 背板玻璃不消费它（冷启动新建面板、滑块全量程两端，读数逐位相同）；方案 B（找偏好键）随之无意义。
2. **26 时代旋钮在 27 全部失效**：`.clear` 强制零影响（mode 0≡1、3≡2）；key 态差异仅 ≤1.4/255（26 时代 +50~102）——key 态自适应层实质消失，「点击变白」结构性不存在，观感是 27 系统 popover 玻璃固有渲染（自绘背板方向历史上已否决，勿重试）。
3. **定型实现**：`applyLiquidGlassBackdrop()` 按系统分支——**27+ 完全不干预**（含 makeKey，实测 born-non-key 面板真实点击内部正常不收起）；**26 保留 clear+makeKey**（删除会复发 26 的「点击变白」）；**13~15 makeKey 无害保留**（与 v0.1.6 行为一致）。

### 代码与产物改动

- `PanelController.swift` 五处：删 `[DEBUG-autoshow]` 整块（含内嵌 `[DEBUG-bump]` 探针）；`applyLiquidGlassBackdrop()` 重写为按系统分支并重写定型注释（含矩阵数据）；show()/updateContentHeight 两处调用点注释同步。
- 26.5 SDK 编译零警告（仅 2 条链接器 search-path 环境噪音）；`MONISWITCH_SDKROOT=...26.5.sdk bash Support/build-app.sh` 重打包，`Support/MoniSwitch.app`/`.dmg` 已更新（会话结束时运行的即新包）。
- **新坑（已记 AGENTS.md「构建与打包」）**：本机裸 `swift build` 现默认 27.0 SDK，直接编译失败（`SwiftUIMacros.StateMacro` 宏插件缺失），本机编译须 `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build`。
- 调试 defaults 残键（MoniswitchDebugBackdropMode/AutoShow/BumpHeight）已无代码读取、无害；要清理可 `defaults delete com.moniswitch.app <key>`。

### 终验与新增自动化怪癖（详见 AGENTS.md 自动化条目⑪ 2026-09-20 增补）

- **真实点击面板内部：不收起、功能正常（用户实测）——新包无产品 bug**；「点击不变白」以矩阵 key 态数据（≤1.4/255）+ 人肉点击定案。
- **合成点击（CGEventPost）边距空白处会把 born-non-key 面板收起**，收起后 popover 窗口停泊屏幕右缘外（实测 (1908,42)，仅 12pt 在屏内）仍被 CGWindowList onScreenOnly 列出——采样脚本会把它误当面板采到钳制窄条垃圾（n 骤降是识别信号）；26 时代「边距空白点击可送达不收起」这个机器验证点在 27 失效。
- **AX 开面板的命中区偏移在 27 复现**（合成点击误触面板内「设置」按钮开出了设置窗口）；凡需对面板做合成交互，开面板走真实点击。
- HITL 实验教训（已入持久记忆 verify-primitives-before-comparison）：用户「报告完成」的动作本身会改变被测状态（点聊天窗回复 → 面板外按下 → 面板收起 → 采样扑空，同晚踩两次）；依赖用户操作后立即取态的验证，须把「探测校验→采样→操控→再采样」预编排成单条命令零间隔执行。
- 工具修复：`shoot.sh` 原把 CGDirectDisplayID 直传 `screencapture -D`（该参数要的是显示器序号），双屏时代两者数值恰好相同、单屏即报 Invalid display——已改为取 wprobe `panelOn=1` DISPLAY 行的 idx。

### 遗留（用户侧）

- 人肉验收：日常用面板（开/关、点卡片、展开参数、设置/退出）；观感接受度；Reduce Transparency 开启时正常退化。
- **Liquid Glass 滑块拨回原值 0.188**（最透端起约 19% 轨道处）。
- 全部改动未提交（PanelController.swift / AGENTS.md / build-app.sh / PanelView.swift 幽灵悬浮修复 / 本文档），是否提交由用户决定。
- `/tmp/moniswitch-matrix/` 工具与截图（含 crop-mode0~3 四档对比图）重启即清，需要留档自行拷贝。

## 一、用户需求（本次会话原话的具体化，最高优先级）

1. **核心功能需求**：菜单栏面板的背景板（NSPopover 底层系统玻璃）的 Liquid Glass 透明度要**完全跟随** 系统设置 > 外观 > Liquid Glass 的透明度滑块（macOS 27 新增的连续滑块）。现状（makeKey + 强制 `.clear`，26 时代定型方案）在 macOS 27 上呈「macOS 15 毛玻璃」观感，用户明确不满。
2. 气泡卡片保持**不透明纯白**（历史否决项：材质实验、悬浮卡片、隐藏玻璃内层均已否决，勿重试）。
3. **任何操控电脑 / 截图采样 / 改系统设置（含调 Liquid Glass 滑块、写 defaults、open/pkill App、AX/CGEvent 自动化）之前，必须逐项向用户说明并获准**（2026-09-16 约定 + 本次会话重申）。
4. **每个新对话开始前先检查 skill 清单并加载有用的**（不全载）：
   - engineering（18 个）：tdd、code-review、diagnosing-bugs、implement、prototype、research、triage、domain-modeling、codebase-design、improve-codebase-architecture、resolving-merge-conflicts、to-spec、to-tickets、grill-with-docs、wayfinder、wizard、ask-matt、setup-matt-pocock-skills
   - productivity（7 个）：grilling、grill-me、handoff、teach、wait-what、to-questionnaire、writing-for-agents
   - （此约定还应写进 AGENTS.md 顶层章节——本会话未完成，见「下一步」第 1 条）
5. **不主动 git commit**（工作区有未提交改动，是否提交由用户决定）。

## 二、已定性的调研结论（新对话无需重查）

- 本机 = macOS 27（darwin 27.0）；CLT 里最新可用编译 SDK = **26.5**（27.0 SDK 编译不了：CLT 没有 27 需要的 SwiftUIMacros 宏插件，SwiftUI `@State` 在 27 SDK 是宏展开）。构建命令：`MONISWITCH_SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk bash Support/build-app.sh`。玻璃跟随是运行时系统 chrome 行为，与编译 SDK 版本无关。
- macOS 27 的外观滑块是**连续透明度滑块**（26.x 只有 Clear/Tinted 二选一）；系统玻璃（含 NSPopover 的 NSGlassView 背板）按系统机制自动跟随该设置。
- **公开 SDK 没有任何读取该滑块的 API**：NSGlassEffectView 全部公开属性 = contentView / cornerRadius / tintColor / style(.regular|.clear) / effectIsInteractive(27+)；SwiftUI Glass = regular / clear / identity / tint / interactive。无透明度数值参数、无偏好读取接口。tintColor 语义是染色不是透明度（历史实验已否）。
- **唯一实现路线 = 不再覆盖 style**（去掉 `.clear` 强制），让系统玻璃自渲染（即现有诊断开关 mode 1 分支）。
- 唯一相关的公开偏好 API 是 Reduce Transparency 二元开关：`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` + `NSWorkspace.shared.notificationCenter` 的 `accessibilityDisplayOptionsDidChangeNotification`（最终方案不覆盖 style 时无需用它）。

## 三、工作区当前状态（全部未提交，`git status` 四个文件）

预先存在（上个会话留下，与本任务关系见标注）：
- `Sources/MoniSwitch/PanelView.swift`（+9 行）：幽灵悬浮修复（`.allowsHitTesting`）——与玻璃正交，保留勿动
- `AGENTS.md`（+3 条目）：幽灵悬浮根治 / 操控电脑许可约定 / 「clipped 不摘命中区」机制结论
- `Sources/MoniSwitch/PanelController.swift`：`[DEBUG-backdrop]` 2×2 诊断开关（`MoniswitchDebugBackdropMode`：0=makeKey+强制clear（旧行为）、**1=makeKey+不碰style（跟随系统，本次目标的雏形）**、2=不makeKey+不碰style、3=不makeKey+强制clear），位于 `applyLiquidGlassBackdrop()`（约 L242-264），注释标注「收尾时删除」

本会话新增：
- `Support/build-app.sh`（+10 行）：`MONISWITCH_SDKROOT` 环境变量覆盖口（绕过 27 SDK 编译问题）——**持久修法，保留**
- `Sources/MoniSwitch/PanelController.swift`：`[DEBUG-bump]` resize 探针（`MoniswitchDebugBumpHeight`，autoshow 展示后 1.2s 纯高度直写 +49 走真实 resize 路径），注释标注「收尾时删除」
- `Support/MoniSwitch.app` / `.dmg` 已用 26.5 SDK 重新打包（含全部调试开关）
- 诊断工具与 15 张截图存档：`/tmp/moniswitch-matrix/`（**/tmp 可能被清**；wprobe/psample/click/drag/shoot.sh 源码同目录，源码内有用法与采样带说明，重建成本低）

运行时状态：
- App 正在运行（Support/MoniSwitch.app，**当前即 mode 1 = 跟随系统滑块**，用户现在点开面板看到的就是候选终态观感，可直接人肉验收）
- 调试 defaults 现值：`MoniswitchDebugBackdropMode=1`、`MoniswitchDebugAutoShow=1`、`MoniswitchDebugBumpHeight=0`
- **⚠ Liquid Glass 滑块可能停在 1.0（最不透端）**：用户原始值为 **0.188449904323**，本会话的自动恢复原语不可靠（见下），接手后第一件事请用户自己看一眼滑块位置、手动拨回原值（0.188 ≈ 轨道左起约 19% 处）
- MoniSwitch 设置窗口曾被本会话关闭一次（采样去污染），后又被用户打开——非 bug

## 四、实验进展与本轮踩坑（省下重复劳动）

### 已完成
- mode 1 基线采样（滑块在用户原值 0.188，面板窗口 1342,27 406×636，主屏 cgid=2 1920×1080）：左带 L=89.0 / 右带 R=70.3 / 顶带 T=55.1 / 底带 B=114.5（玻璃透壁纸的读数，壁纸相关，只可做同轮相对比较）
- 反馈环一条命令化：`bash /tmp/moniswitch-matrix/shoot.sh <标签>` = wprobe 定位面板 → `screencapture -D <屏>` → psample 四条净玻璃边距带（左右 x∈[5,15]/[W-15,W-5]，上下 y∈[17,22]/[H-22,H-17]，避开 chrome 描边与卡片弥散阴影污染带）

### 关键机制发现（本会话实测，macOS 27）
1. **AX 直接 `set value` 不提交偏好**——旋钮视觉不动、defaults 无变化，「读回值」只是 AX 缓存假象。System Settings 的滑块只认真实拖动事件。
2. 合成拖动（CGEventPost 12 步插值 drag）**第一次疑似生效**（读回 1.0 且轨道右半变亮），后续拖动是否生效不确定——注意 AGENTS.md 自动化条目⑪的 CGEventPost 预算衰减（~5-10 次后失活）。
3. **调滑块必然收起面板**：`open` 系统设置（App 激活切换）与拖动的外部鼠标按下都会触发 transient/dismiss 监控收起。正确实验时序 = **先定滑块 → pkill + open（autoshow 自动弹面板）→ shoot**。这也与真实用户操作时序一致（先调设置再开面板）。
4. wprobe 陷阱（已修）：MoniSwitch 设置窗口 900×450 是 layer 0，popover 是 layer 25，须取 layer 最高的 >200 宽窗口。
5. `sips --cropOffset` 是**像素**单位而截图是 2x——按逻辑点传必裁错区域（本轮实际踩坑，一度误判窗口消失）。psample/shoot.sh 内部已正确处理 2x 换算。
6. **没找到滑块写入的 defaults 域**（`com.apple.Appearance` 拖动前后 diff 为空）——真实偏好键未定位（可能在别的域或走私有管道）。

### 本轮实验设计的教训（为什么采样「无意义」）
多组对照采样发生在**同一未知滑块状态下**（AX 假赋值、合成拖动是否生效未先验证），基线混乱、全部读数相同。新对话必须先建立**可信的滑块设定原语**（验证旋钮视觉真的动了 + 菜单栏/面板读数随之变化），再跑对照。

## 五、下一步执行清单（建议顺序；本清单已按 2026-09-20 晚续跑会话全部执行或按新结论作废，实际结果见顶部〇节）

1. （零许可成本，先做）AGENTS.md 补三件事：① 顶层新增「会话启动约定」章节（skill 清单见上文第一节第 4 条 + 按需加载指引）；② 许可条目补一句「包括调整系统外观设置（如 Liquid Glass 透明度滑块）」；③ 「悬浮卡片背景板」条目预留 27 段占位（结论出来后填）。改 AGENTS.md 前建议加载 writing-for-agents skill。
2. **建立可信滑块原语**（二选一，都需要用户配合，先请求许可）：
   - 方案 A（推荐）：请用户手动把滑块拨到最透/最不透各一次（每次拨完说一声），agent 只做 `pkill + open + sleep 6 + shoot.sh`——纯观察，稳定可靠；
   - 方案 B：用户拨一次后，agent 对全部 defaults 域做前后 diff 找真实偏好键，之后 `defaults write` + 重启 Dock/WindowServer 类进程实验（成本高，A 失败再试）。
3. 跑矩阵（每步先请求许可）：mode 1 两端跟随（核心验收：边距带读数必须有可测差异）→ 面板边距空白处合成点击前后对比（key 态变白是否还在；mode 1 出生即 keyed 应零漂移）→ `MoniswitchDebugBumpHeight=1` 重启验 resize 是否重置观感 → 视需要 mode 2/3。
4. 定型实现：`applyLiquidGlassBackdrop()` 只保留 `window.makeKey()`（不碰 style，macOS 13~27 全兼容，`#available(macOS 26.0, *)` 分支与 `glassEffectViews(under:)` 一并删）；按 resize 实测决定 `updateContentHeight` 里补挂去留；删 `[DEBUG-backdrop]`/`[DEBUG-bump]` 开关；重写定型注释（记录 27 回归 + 跟随滑块方案 + 矩阵数据）。改代码前建议加载 implement skill。
5. `swift build` 零警告 + 26.5 SDK 重打包 + 终验（合成点击零漂移 / 滑块两端跟随 / resize 零漂移）。
6. AGENTS.md「悬浮卡片背景板」条目正式追加 macOS 27 段（clear+key 失效回归、无公开 API、定型方案、27 的 key 态/resize 行为如有新结论一并记录）。
7. 汇总人肉验收清单交用户：液态折射感、箭头/边框 chrome、与系统原生面板一致性、Reduce Transparency 开启时正常退化。

## 六、suggested skills（新对话接手时按需加载）

- `diagnosing-bugs`：实验矩阵方法论（反馈环先行、一次只变一个变量）——本轮已用，续跑矩阵时继续用
- `writing-for-agents`：改 AGENTS.md / 写交接文档时
- `implement` + `code-review`：定型实现与自查阶段
- `handoff`：再次中断时压缩现场

## 参考

- `AGENTS.md`：项目主文档（历史结论 / 注意事项 / 自动化验证条目⑪CGEventPost 预算 / 许可约定）
- `HANDOFF-floating-panel.md`：26 时代玻璃背板完整实验史（NSGlassView 层级 / key 态变白 / resize 重置）
- `Sources/MoniSwitch/PanelController.swift` L225-275：背板定型注释 + 2×2 诊断开关；L58-78：autoshow 钩子
- `/tmp/moniswitch-matrix/`：本轮全部截图（15 张）与工具源码
