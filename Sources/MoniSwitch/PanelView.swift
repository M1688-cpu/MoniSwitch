import SwiftUI
import AppKit

/// 面板展开/收起动画：平滑弹簧（先加速后减速、末端轻柔收敛不回弹），
/// 配合 .move(edge: .top) 过渡呈现「由上向下拉伸」，popover 高度随内容联动。
private let panelReveal = Animation.spring(response: 0.32, dampingFraction: 0.86)

/// 面板内容理想高度上报（手动尺寸桥：PanelController 在 sizingOptions=[] 下
/// 依赖此值回写 preferredContentSize，窗口高度由此驱动）。
private struct PanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 菜单栏下拉面板（宿主为 PanelController 的 NSPopover）：按参考图做成分栏「气泡卡片」。
///
/// 这里是一块可完全自定义的 SwiftUI 视图：
///   - 每个功能分栏是一张圆角气泡卡片（`BubbleCard`，Components.swift）；
///   - 强调色跟随系统（`BrandColor.accent`，Components.swift）；
///   - 所有切换操作复用 `AppState` / `PresetManager` 的现有逻辑，只改触发控件形态；
///   - 面板无背板（2026-09-21 起）：气泡卡片直接悬浮于壁纸，居中对齐/展开动画
///     由 NSPopover 系统行为提供；指向菜单栏的箭头随玻璃背板隐藏而消失（同 Tutti）。
///
/// 卡片顺序（2026-10 改版）：显示器枢纽（布局预览+点块展开参数）→ 布局预设 →
/// 底部操作栏。原主屏卡/排列卡已并入枢纽卡（设为主屏/镜像扩展在非主屏参数块底部）。
/// 交互：操作进行中（isOperating）禁用卡片区并显示顶部流动进度条；
/// 面板高度随内容自适应（展开参数/切换语言变长都不出滚动条）；参数块 hover 与布局图互相联动。
struct PanelView: View {

    @ObservedObject var state: AppState
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var presetManager: PresetManager

    /// 系统强调色（跟随「系统设置 > 外观 > 强调色」实时变化）。
    private let accent = BrandColor.accent

    /// 当前面板内展开的 SelectionRow 标识（互斥：同屏的分辨率/刷新率、
    /// 跨屏的各行同时只展开一个，避免面板高度反复跳动）。nil=全部收起。
    @State private var expandedRowID: String?

    /// 枢纽卡内展开参数组的屏 id（面板级互斥：同时只展开一块屏，默认全收起；
    /// 点布局图屏块 toggle）。nil=全部收起。2026-10 改版后「选中」与「展开」
    /// 同生共死，布局图 ✓ 角标直接由本值驱动（不再单独持有 selectedDisplayID
    /// ——折叠头 chevron 收起时 ✓ 随之消失，两条收起路径天然同步）。
    @State private var expandedDisplayID: String?

    /// 当前 hover 的屏（参数块折叠头 hover 时上报，布局图对应块点亮，
    /// 解决"不知道操作的是哪块屏"的歧义）。
    @State private var hoveredDisplayID: String?

    /// 是否有操作在后台执行（含预设回放）：禁用卡片区 + 显示进度条。
    private var busy: Bool { state.isOperating || presetManager.isApplying }

    var body: some View {
        VStack(spacing: BubbleMetrics.cardSpacing) {
            if state.displays.isEmpty {
                // 无显示器：只放一张提示卡。
                BubbleCard(title: l10n.t(.displaysSection)) {
                    Text(l10n.t(.noDisplays))
                        .font(.system(size: BubbleMetrics.fontBody))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                }
            } else {
                // 卡片区直接排列：面板高度随内容自适应，无 ScrollView 封顶——
                // 展开参数组、切换语言文本变长都不会出滚动条。不包 ScrollView
                // 也顺带消除两处历史问题（详见 AGENTS.md）：它对子视图 bounds 的
                // 裁切会把卡片阴影切出直线边界；屏幕重配时理想高度会塌 0。
                VStack(spacing: BubbleMetrics.cardSpacing) {
                    // 枢纽卡（2026-10 改版）：主屏卡/排列卡并入布局预览——
                    // 多屏=布局图+点块展开参数；单屏=常展开参数（原显示器调节卡）。
                    displayHubCard
                    if !presetManager.presets.isEmpty {
                        presetsCard
                    }
                }
                .disabled(busy)
            }
            bottomToolbar
        }
        // 顶部 padding 开发期可调（MoniswitchDebugTopPadding，默认 16）：无背板后
        // 卡片与菜单栏的空隙偏大，用户扫值定档后写死；其余三边保持 16
        // （底部给悬浮阴影留衰减空间，勿跟顶部一起缩）。
        .padding(EdgeInsets(top: BubbleMetrics.panelTopPadding, leading: 16, bottom: 16, trailing: 16))
        // 只锁卡片列宽度，高度按内容自适应。
        .frame(minWidth: BubbleMetrics.panelColumnWidth,
               idealWidth: BubbleMetrics.panelColumnWidth,
               maxWidth: BubbleMetrics.panelColumnWidth)
        // 无背板呼吸边距（透明）：窗口比卡片列大一圈，悬浮阴影（基座 r8 + hover r10）
        // 在窗口内淡尽，不被窗口边界裁出「背景板框」直线（2026-09-21 用户报告的
        // hover 框线）。顶部**不加**——保持用户定档的卡顶-菜单栏间距不变。
        .padding(.horizontal, BubbleMetrics.shadowBreathingSide)
        .padding(.bottom, BubbleMetrics.shadowBreathingBottom)
        // 内容理想高度上报（手动尺寸桥的 SwiftUI 侧）：sizingOptions=[] 后
        // popover 不再自动跟随内容尺寸，由这里实测高度 → PanelController 回写
        // preferredContentSize。挂 background 不占布局；宽度恒 380，只需上报高度。
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: PanelContentHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(PanelContentHeightKey.self) { height in
            PanelController.shared.updateContentHeight(height)
        }
        // 操作进行中：顶部悬浮一条流动进度条（overlay 不占布局空间，内容不下移）。
        .overlay(alignment: .top) {
            if busy {
                IndeterminateBar(accent: accent)
                    // 呼吸边距计入：进度条保持压在卡片列上（与卡同宽），不越到透明带。
                    .padding(.horizontal, BubbleMetrics.shadowBreathingSide + 16)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        // 顶端钉死（配合 PanelController 的 sizingOptions=[] 手动尺寸桥，修「展开
        // 参数时所有气泡先上跳再下拉」）：根视图按宿主视图边界布局时，此弹性 frame
        // 让内容恒钉顶部——内容与窗口高度瞬态不一致（窗口跟随滞后 1-2 帧）时，
        // 误差只落在底缘的微小裁切，整列内容不会垂直居中漂移。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 显示器枢纽卡

    /// 布局预览为中心的枢纽卡（2026-10 改版：主屏卡与排列卡并入本卡）。
    ///
    /// - 多屏：等比布局图 + 图下方展开**当前选中屏**的参数块；点屏块是完整
    ///   toggle（选中+展开同生共死，再点已展开的块即收起），未展开时图下无
    ///   内容、首屏清爽。「设为主屏」「镜像/扩展」在非主屏参数块底部。
    /// - 单屏：无布局图（孤块无信息量），直接常展开参数行——原「显示器调节」
    ///   卡并入（单外接屏的极端场景同样走这里）。
    private var displayHubCard: some View {
        let hasMultiple = state.displays.count > 1
        // 无标题卡（2026-10 拍板）：图即内容，标题字样删除（含单屏的「显示器调节」，
        // panelLayoutPreview/panelDisplayAdjust 两 L10n 键随之废弃）。
        return BubbleCard(title: nil) {
            VStack(spacing: BubbleMetrics.rowSpacing) {
                if hasMultiple {
                    LayoutDiagram(
                        displays: state.displays,
                        accent: accent,
                        selectedID: expandedDisplayID,
                        highlightedID: hoveredDisplayID,
                        onSelect: { d in toggleExpansion(for: d) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: BubbleMetrics.diagramHeight)

                    // 当前展开屏的参数块：只渲染展开中的那一块（互斥由
                    // expandedDisplayID 单值天然保证）。插入不带动画（二值跳变，
                    // 视觉平滑由块内 mask 揭示承担）；移除（收起）随 toggleExpansion
                    // 的 withAnimation 走淡出+上滑过渡。
                    if let expanded = state.displays.first(where: { $0.id == expandedDisplayID }) {
                        ArrangementRow(display: expanded,
                                       state: state,
                                       accent: accent,
                                       label: expanded.localizedTypeName(l10n: l10n),
                                       showsPosition: !expanded.isMain,
                                       foldable: true,
                                       expandedDisplayID: $expandedDisplayID,
                                       expandedRowID: $expandedRowID,
                                       onHoverDisplay: { hovering in
                                           hoveredDisplayID = hovering ? expanded.id : nil
                                       })
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } else if let sole = state.displays.first {
                    // 单屏：无位置可排、无镜像对象，参数常展开（内容仅两三行，
                    // 折叠反而多一次点击）。
                    ArrangementRow(display: sole,
                                   state: state,
                                   accent: accent,
                                   label: sole.localizedTypeName(l10n: l10n),
                                   showsPosition: false,
                                   foldable: false,
                                   expandedDisplayID: .constant(nil),
                                   expandedRowID: $expandedRowID,
                                   onHoverDisplay: { hovering in
                                       hoveredDisplayID = hovering ? sole.id : nil
                                   })
                }
            }
        }
    }

    /// 布局图点块 toggle：展开/收起（✓ 角标由 expandedDisplayID 驱动，一处状态）。
    ///
    /// 方向拆分与折叠头一致：展开方向二值跳变（不带 withAnimation，高度一步
    /// 到位，配合 PanelController 容器闸门+同步高度桥构造性零漂移，视觉平滑
    /// 由参数块内 mask 揭示承担）；收起方向保留弹簧。切换屏时统一清空
    /// expandedRowID——旧块已卸载，残留展开态会让下次挂载走「兜底」直接全揭示。
    private func toggleExpansion(for d: DisplayInfo) {
        if expandedDisplayID == d.id {
            withAnimation(panelReveal) {
                expandedRowID = nil
                expandedDisplayID = nil
            }
        } else {
            expandedRowID = nil
            expandedDisplayID = d.id
        }
    }

    // MARK: - 布局预设卡片

    /// 已保存预设：每条一行（名称 + 快捷键角标 + 应用按钮）。
    private var presetsCard: some View {
        BubbleCard(title: l10n.t(.groupPresets)) {
            VStack(spacing: BubbleMetrics.rowSpacing) {
                ForEach(presetManager.presets) { preset in
                    RowButton(action: { presetManager.apply(preset) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack")
                                .font(.system(size: BubbleMetrics.fontControl))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(preset.name)
                                .font(.system(size: BubbleMetrics.fontBody))
                                .foregroundStyle(.primary)
                            Spacer()
                            // 快捷键角标（已绑定才显示）。
                            if let hk = preset.hotkey, !hk.isEmpty {
                                Text(HotkeyManager.shared.displayString(for: hk))
                                    .font(.system(size: BubbleMetrics.fontCaption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: BubbleMetrics.keycapCornerRadius))
                            }
                            // 与当前布局一致的预设给「当前」角标（忽略 id 的签名对比，
                            // 免疫 persistent id 漂移；纯计算不跑 shell）。
                            if DisplayManager.shared.presetMatchesCurrentLayout(preset.screenArgs,
                                                                               displays: state.displays) {
                                Text(l10n.t(.currentLayoutBadge))
                                    .font(.system(size: BubbleMetrics.fontMini, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accent, in: Capsule())
                            }
                            Image(systemName: "play.fill")
                                .font(.system(size: BubbleMetrics.fontMini))
                                .foregroundStyle(accent)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 底部操作栏

    /// 底部一排两气泡：左气泡「自动排列 | 刷新 | 设置」拉满剩余宽度（三按钮等宽均分，
    /// Divider 分隔），右气泡「退出」内容自适应、刚好包住按钮——左宽右紧。
    /// 自动排列从排列卡移入（单屏时无意义，禁用置灰防死点击）。
    /// 悬浮反馈为按钮级：图标微放大 + 圆角底色高亮（见 ToolbarIconButton），
    /// 两气泡不再挂整泡 bubbleHoverLift（用户要求单按钮反馈而非整体放大）；
    /// 卡片级 hover 浮起不受影响。纯图标 + 原生 tooltip（.help 悬停停留后显示，
    /// 文案走 L10n 随语言切换）。
    private var bottomToolbar: some View {
        HStack(spacing: BubbleMetrics.cardSpacing) {
            HStack(spacing: 2) {
                ToolbarIconButton(tooltip: l10n.t(.autoArrange), systemImage: "wand.and.rays",
                                  fullWidth: true, disabled: state.displays.count < 2) {
                    state.autoArrange()
                }
                Divider().frame(height: 18)
                ToolbarIconButton(tooltip: l10n.t(.refreshList), systemImage: "arrow.clockwise",
                                  fullWidth: true) {
                    state.refresh()
                }
                Divider().frame(height: 18)
                ToolbarIconButton(tooltip: l10n.t(.settingsTitle), systemImage: "gearshape",
                                  fullWidth: true) {
                    // openSettings 会切 activation policy 并激活 App，先收面板防悬空。
                    PanelController.shared.close()
                    DockPolicyManager.shared.openSettings()
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            // 与气泡统一材质（BubbleBackground 不透明纯白）+ 壁纸承接悬浮阴影；拉满剩余宽度。
            .modifier(BubbleBackground())
            .bubbleFloatingShadow()
            .frame(maxWidth: .infinity)

            // 退出：内容自适应小气泡，刚好适配按钮触区。
            ToolbarIconButton(tooltip: l10n.t(.quit), systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .modifier(BubbleBackground())
            .bubbleFloatingShadow()
        }
    }
}

// MARK: - 面板私有小组件

/// 显示器类型图标圆框：圆形填充底 + 类型图标（内置屏 laptopcomputer / 外接屏 display）。
///
/// `active` 决定底框状态：主屏卡传 `d.isMain`（主屏主题色、其余深灰暗态，用图标
/// 颜色表达主从层级）；排列卡恒 true（统一主题色，仅作类型标识）。
private struct DeviceIconBadge: View {
    let isBuiltIn: Bool
    let active: Bool
    let accent: Color

    var body: some View {
        Circle()
            .fill(active ? accent : Color.primary.opacity(BubbleMetrics.deviceIconInactiveFillOpacity))
            .frame(width: BubbleMetrics.deviceIconDiameter, height: BubbleMetrics.deviceIconDiameter)
            .overlay(
                Image(systemName: isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: BubbleMetrics.deviceIconFontSize, weight: .semibold))
                    .foregroundStyle(active ? Color.white : Color.secondary)
            )
    }
}

/// 底部纯图标按钮：固定触区 34×26（fullWidth 时等宽均分、图标居中）；
/// 功能名称由 .help 原生 tooltip 呈现。
///
/// 悬浮反馈为按钮级（区别于卡片整泡浮起）：图标 scaleEffect 微放大（仅图标本体，
/// 2D 仿射不栅格化、触区与布局不动，无边缘振荡问题）+ 圆角底色高亮；
/// reduceMotion 时仅保留底色高亮。
private struct ToolbarIconButton: View {
    let tooltip: String
    let systemImage: String
    var fullWidth: Bool = false
    var disabled = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: BubbleMetrics.fontTitle))
                .foregroundStyle(.primary)
                .scaleEffect(isHovered && !reduceMotion ? BubbleMetrics.toolbarIconHoverScale : 1)
                .frame(width: fullWidth ? nil : 34, height: 26)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isHovered && !disabled
                                                    ? BubbleMetrics.toolbarHoverFillOpacity : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(tooltip)
        .onHover { isHovered = $0 }
        .animation(BubbleMetrics.buttonHoverSpring, value: isHovered)
    }
}

/// 镜像对端屏补充气泡：hover 挂载目标并停留 `tooltipDwell` 后，在目标上方弹出
/// 迷你气泡（缩小→放大的弹跳入场，近似系统 tooltip 的 dwell 手感 + Tutti 设置页
/// 感叹号提示的弹性缓动）；移开立即快退收起。纯展示层：不参与布局、不挡交互。
/// mini 气泡外壳（MirrorTargetTooltip 专用；2026-10 曾与布局图悬停名称标签
/// 共用，名称改常驻居中后布局图不再引用）：
/// 与卡片同源的不透明填充 + 细描边 + 浅阴影，浅/深模式分别取白 / 深卡色。
private struct MiniBubble: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .light ? Color.white : BubbleMetrics.bubbleDarkFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(colorScheme == .light ? 0.10 : 0.18), lineWidth: 1)
            )
            .bubbleShadow(opacity: 0.7)
    }
}

private struct MirrorTargetTooltip: ViewModifier {
    let text: String

    @State private var isShown = false
    @State private var dwellTask: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard !text.isEmpty else { return }
                if hovering {
                    let task = DispatchWorkItem { isShown = true }
                    dwellTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + BubbleMetrics.tooltipDwell, execute: task)
                } else {
                    dwellTask?.cancel()
                    dwellTask = nil
                    isShown = false
                }
            }
            .overlay(alignment: .top) {
                // 迷你气泡：与卡片同源的不透明填充 + 细描边 + 浅阴影。
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.system(size: BubbleMetrics.fontCaption))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .modifier(MiniBubble())
                .fixedSize()
                // 纯展示层不参与命中：透明态（opacity 0）的气泡悬在按钮上方 36pt 处
                // 仍可命中的话，会拦截其覆盖区域内行的 hover（opacity 不摘除命中区）。
                .allowsHitTesting(false)
                // 上移到按钮上方（overlay .top 贴按钮顶边，再抬一个按钮高 + 间隙）；
                // 缩放锚点 .bottom：从按钮上缘向上「生长」。
                .offset(y: -36)
                .scaleEffect(isShown || reduceMotion ? 1 : BubbleMetrics.tooltipPopScale, anchor: .bottom)
                .opacity(isShown ? 1 : 0)
                .animation(isShown ? BubbleMetrics.tooltipSpring : .easeOut(duration: 0.12), value: isShown)
            }
    }
}

// MARK: - 排列行（常驻左/右移 + 刷新率 + 分辨率）

/// 单个屏的排列行：可折叠标题行 + 位置分段控件、刷新率与分辨率「当前值 + 点击展开」选择。
/// `showsPosition` 为 false 时隐藏位置行（单内置屏无左右可排）；
/// `foldable` 为 true（多屏）时点击标题行展开/收起参数组（默认收起），
/// false（单内置屏）常展开。
/// `expandedDisplayID` / `expandedRowID` 均由 PanelView 持有：组间互斥 + 选项行互斥。
private struct ArrangementRow: View {
    let display: DisplayInfo
    @ObservedObject var state: AppState
    let accent: Color
    let label: String
    var showsPosition: Bool = true
    /// 是否可折叠（多屏 true：标题行是折叠头；单内置屏 false：参数常展开）。
    var foldable: Bool = true
    /// 当前面板内展开参数组的屏 id（面板级互斥，等于本屏 id 时展开）。
    @Binding var expandedDisplayID: String?
    /// 当前面板内展开的 SelectionRow 标识（互斥收起其他）。
    @Binding var expandedRowID: String?
    /// 标题行 hover 上报（布局图联动高亮该屏）。
    var onHoverDisplay: (Bool) -> Void = { _ in }

    /// 本屏参数组是否展开（不可折叠时恒 true）。
    private var isExpanded: Bool { !foldable || expandedDisplayID == display.id }

    /// 展开块实测高度（onAppear 时量一次，驱动 mask 揭示）。
    @State private var blockHeight: CGFloat = 0
    /// 展开块 mask 揭示高度（纯呈现层：布局已二值到终值，揭示高度从 0 弹簧拉满）。
    @State private var revealHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            // 折叠头（两行式）：图标 + [名称行 / 参数概要副行] + 旋转 chevron。
            // 名称与概要各占一行——挤一行时长名称 + 长参数会换行/截断（可读性差）；
            // 展开后副行淡出（详情行已展示同信息，不重复），高度随 toggleExpanded 的弹簧一起动。
            RowButton(action: toggleExpanded) {
                HStack(spacing: 10) {
                    // 显示器类型图标统一套主题色圆形底框（与主屏卡同一组件）。
                    DeviceIconBadge(isBuiltIn: display.isBuiltIn, active: true, accent: accent)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 8) {
                            Text(label)
                                .font(.system(size: BubbleMetrics.fontBody))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if foldable {
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            }
                        }
                        // 概要副行：收起时也能一眼看到当前档位（位置已知才带前缀）。
                        if foldable && !isExpanded {
                            Text(parameterSummary)
                                .font(.system(size: BubbleMetrics.fontCaption))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .transition(.opacity)
                        }
                    }
                }
                // 撑满行宽：整行可点 + 副行截断基准与卡片一致。
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onHover(perform: onHoverDisplay)

            // 表单风三行：位置（分段控件）/ 分辨率 / 刷新率，标题靠左、控件靠右对齐。
            // 折叠态下整块隐藏（foldable=false 恒显示）。
            // 外包顶部对齐的 ZStack + clipped：揭示期间内容不会越过折叠头「凭空出现」，
            // 裁切边界即折叠头下边缘，视觉呈从标题行下方「抽拉」出来。
            //
            // 动画机制（2026-09 定型）：**展开方向布局二值跳变**（toggleExpanded 不带
            // withAnimation，高度一步到位）——配合 PanelController 的容器闸门 +
            // 同步高度桥，窗口/容器/布局同帧到终值，构造性零漂移（根治「所有气泡
            // 先上跳再下拉」）；视觉平滑由 mask 揭示承担（revealHeight 从 0 弹簧
            // 拉到实高，纯呈现层不参与布局）。**收起方向**布局随 withAnimation 弹簧
            // 收短，块移除走 .move+.opacity 过渡（实测该方向无居中漂移）。
            ZStack(alignment: .top) {
                if isExpanded {
                    VStack(spacing: BubbleMetrics.rowSpacing) {
                        if showsPosition {
                            HStack {
                                Text(state.localized(.positionLabel))
                                    .font(.system(size: BubbleMetrics.fontCaption))
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 12)
                                sideSegmented
                            }
                            .padding(.vertical, 3)
                        }
                        // 分辨率选择：多于一个可选分辨率时才显示。
                        // 数字是逻辑分辨率（HiDPI 条目由 2 倍物理像素渲染，更锐利），
                        // 条目尾部标注变体、当前值带 HiDPI 后缀——避免「4K 屏选 4K 数字
                        // 却得小图标」的误解（逻辑分辨率才是观感档位）。
                        if display.availableResolutions.count > 1 {
                            SelectionRow(
                                rowID: "\(display.id)-resolution",
                                title: state.localized(.resolutionMenu),
                                currentValue: "\(display.resolution.width)×\(display.resolution.height)"
                                    + (display.scalingOn ? " · \(state.localized(.hidpiTag))" : ""),
                                accent: accent,
                                expandedRowID: $expandedRowID,
                                options: display.availableResolutions.map { res in
                                    .init(text: "\(res.width)×\(res.height) "
                                          + state.localized(res.hidpi ? .hidpiTag : .lowResolutionTag),
                                          isActive: (res.width == display.resolution.width
                                                         && res.height == display.resolution.height)) {
                                        state.setResolution(res, for: display)
                                    }
                                }
                            )
                        }
                        // 刷新率选择：当前分辨率下多于一个可选刷新率时才显示。
                        if display.availableRefreshRates.count > 1 {
                            SelectionRow(
                                rowID: "\(display.id)-refresh",
                                title: state.localized(.refreshRateMenu),
                                currentValue: "\(display.hertz) \(state.localized(.hertzLabel))",
                                accent: accent,
                                expandedRowID: $expandedRowID,
                                options: display.availableRefreshRates.map { hz in
                                    .init(text: "\(hz) \(state.localized(.hertzLabel))",
                                          isActive: hz == display.hertz) {
                                        state.setRefreshRate(hz, for: display)
                                    }
                                }
                            )
                        }
                        // 底部操作行（2026-10 改版：主屏卡与排列卡的镜像区并入）——
                        // 仅非主屏显示：主屏无「设为主屏」可言；镜像/扩展的操作
                        // 主体就是非主屏（目标=当前主屏，见 mirrorExtendPills）。
                        if !display.isMain {
                            Divider().padding(.vertical, 2)
                            HStack(spacing: 8) {
                                setPrimaryPill
                                mirrorExtendPills
                            }
                        }
                    }
                    .padding(.leading, 38)   // 与标题行文字对齐：圆框 28 + spacing 10
                    .padding(.trailing, 4)
                    .padding(.bottom, 6)
                    // 展开方向的视觉揭示：mask 高度弹簧拉开（自折叠头下缘向下「抽拉」）；
                    // 收起方向不重置 mask（保持全开），让 .move+.opacity 移除过渡可见。
                    .mask(alignment: .top) {
                        Color.white.frame(height: revealHeight)
                    }
                    // 收起方向的移除过渡（展开是二值插入 + mask 揭示，不走此过渡）。
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .background {
                        // 量展开块实高，驱动 mask 揭示终点。onAppear 量首帧 +
                        // onChange 跟踪后续变化（双通道，与 SelectionRow 的列表
                        // 测量同构）：块内 SelectionRow 展开/收起会让块高变化，
                        // mask 若停在旧高度，会把新增区域全部遮住（2026-10
                        // 「二级菜单只露一条缝」bug 的根因）。
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    blockHeight = geo.size.height
                                    revealHeight = 0
                                    withAnimation(panelReveal) { revealHeight = blockHeight }
                                }
                                .onChange(of: geo.size.height) { newHeight in
                                    // 首帧量到 0（masked 祖先下新插入子树的零
                                    // proposal）时，这里补走带动画的初始揭示。
                                    let isInitialReveal = (blockHeight == 0 && newHeight > 0)
                                    blockHeight = newHeight
                                    guard newHeight > revealHeight else { return }
                                    // 只跟涨不跟缩：增长直接跳到新高不加独立动画
                                    // （视觉动画由内层列表自己的 mask 揭示承担，
                                    // 外层只负责不裁切）；收缩保持不动（mask 高于
                                    // 内容无副作用，块收起走整体弹簧路径）。
                                    if isInitialReveal {
                                        withAnimation(panelReveal) { revealHeight = newHeight }
                                    } else {
                                        revealHeight = newHeight
                                    }
                                }
                        }
                    }
                }
            }
            .clipped()
        }
    }

    /// 折叠头点击：切换本组展开态。组间互斥（面板级单值）：展开本组自动收起其他组；
    /// 任何组折叠/切换都会让组内的选项列表不可见，统一清空 expandedRowID 防止
    /// 下次展开时残留旧的选项展开态。
    /// 折叠头点击：切换本组展开态。组间互斥（面板级单值）：展开本组自动收起其他组；
    /// 任何组折叠/切换都会让组内的选项列表不可见，统一清空 expandedRowID 防止
    /// 下次展开时残留旧的选项展开态。
    ///
    /// 动画方向拆分（2026-09 实测定型）：
    /// - **展开方向二值跳变**（无 withAnimation）：高度一步到位，配合 PanelController
    ///   的容器闸门 + 同步高度桥，窗口/容器/布局同帧到终值，构造性零漂移；
    ///   视觉平滑由展开块的 mask 揭示承担（onAppear 里弹簧拉起，纯呈现层）。
    /// - **收起方向保留弹簧**：实测该方向无居中漂移（窗口收短时容器不超前）。
    private func toggleExpanded() {
        guard foldable else { return }
        if isExpanded {
            withAnimation(panelReveal) {
                expandedRowID = nil
                expandedDisplayID = nil
            }
        } else {
            expandedRowID = nil
            expandedDisplayID = display.id
        }
    }

    /// 折叠头右侧的参数概要：位置（可排且已知时）· 分辨率 · 刷新率。
    /// 位置未知（镜像中/重叠布局）时省略前缀，与 sideSegmented 两段均不高亮的判定一致。
    private var parameterSummary: String {
        var parts: [String] = []
        if showsPosition, let side = state.side(of: display) {
            parts.append(side == .left ? state.localized(.sideLeft) : state.localized(.sideRight))
        }
        parts.append("\(display.resolution.width)×\(display.resolution.height)")
        parts.append("\(display.hertz) \(state.localized(.hertzLabel))")
        return parts.joined(separator: " · ")
    }

    /// 位置分段控件：「◀ 左侧 | 右侧 ▶」，玻璃槽 + 染色玻璃激活段。
    /// 当前侧未知（镜像中/重叠布局）时两段均不高亮。
    private var sideSegmented: some View {
        let current = state.side(of: display)
        return HStack(spacing: 2) {
            sideSegment(.left, active: current == .left)
            sideSegment(.right, active: current == .right)
        }
        .padding(2)
        .background(
            Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    /// 分段控件的单段：箭头指向移动方向，激活段强调色实心。
    private func sideSegment(_ side: HorizontalSide, active: Bool) -> some View {
        ActivePill(active: active) {
            HStack(spacing: 3) {
                if side == .left {
                    Image(systemName: "arrow.left").font(.system(size: 9))
                }
                Text(side == .left ? state.localized(.sideLeft) : state.localized(.sideRight))
                    .font(.system(size: BubbleMetrics.fontCaption))
                if side == .right {
                    Image(systemName: "arrow.right").font(.system(size: 9))
                }
            }
            .frame(minWidth: 58)
        }
        .asButton {
            state.moveArrangement(display, side: side)
        }
    }

    // MARK: 底部操作行（2026-10 改版：主屏卡/排列卡镜像区并入本行）

    /// 「设为主屏」：中性描边胶囊（动作型按钮，非状态型，不用强调色实心）。
    private var setPrimaryPill: some View {
        ActivePill(active: false, verticalPadding: 6, strokeWhenInactive: true) {
            Text(state.localized(.setAsPrimary))
                .font(.system(size: BubbleMetrics.fontControl))
                .frame(maxWidth: .infinity)
        }
        .asButton {
            state.setPrimary(display)
        }
    }

    /// 镜像/扩展胶囊对：主体=本屏（非主屏），目标=当前主屏——与旧排列卡的
    /// peer 推导等价（AppState.mirror 的操作主体本就是非主屏，外接为主屏时
    /// 主体即内置屏）。镜像按钮保留目标屏名 hover 补充气泡。
    private var mirrorExtendPills: some View {
        let isMirroring = state.isMirroring(display)
        let mainName = state.displays.first(where: { $0.isMain })?
            .localizedTypeName(l10n: L10n.shared) ?? ""

        return HStack(spacing: 8) {
            ActivePill(active: isMirroring, verticalPadding: 6, strokeWhenInactive: true) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: BubbleMetrics.fontCaption))
                    Text(state.localized(.mirrorMain))
                        .font(.system(size: BubbleMetrics.fontControl, weight: isMirroring ? .semibold : .regular))
                }
                .frame(maxWidth: .infinity)
            }
            .asButton { state.mirror(display) }
            // 目标屏名补充气泡：hover 停留触发（扩展按钮不需要——它不涉及对端选择）。
            .modifier(MirrorTargetTooltip(text: L10n.shared.t(.mirrorTarget, mainName)))

            ActivePill(active: !isMirroring, verticalPadding: 6, strokeWhenInactive: true) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.dashed").font(.system(size: BubbleMetrics.fontCaption))
                    Text(state.localized(.extendDisplay))
                        .font(.system(size: BubbleMetrics.fontControl, weight: !isMirroring ? .semibold : .regular))
                }
                .frame(maxWidth: .infinity)
            }
            .asButton { state.unmirror(display) }
        }
    }
}

/// 「当前值 + 点击展开」选择行：左侧标题，右侧当前值，点击整行在面板内展开选项列表。
///
/// 不能用原生 `Menu` 弹下拉：本面板位于 MenuBarExtra(.window) 的 borderless 弹出面板内，
/// 系统菜单在这种窗口里会渲染成分离的空白窗口（macOS 系统级 bug，实测必现）。
/// 故改为自绘行内展开：当前项前 ✓、行 hover 高亮、选项多时列表内滚动，与气泡卡片风格统一。
/// 展开态经外部 `expandedRowID` 持有，与其他行互斥（同时只展开一个）。
private struct SelectionRow: View {
    /// 一个可选项：显示文本 + 是否当前生效 + 选中时执行的操作。
    struct Option {
        let text: String
        let isActive: Bool
        let action: () -> Void
    }

    /// 本行的展开标识（传入 expandedRowID 比对）。
    let rowID: String
    let title: String
    let currentValue: String
    let accent: Color
    /// 面板级展开标识（互斥）：等于 rowID 时本行展开。
    @Binding var expandedRowID: String?
    let options: [Option]

    private var expanded: Bool { expandedRowID == rowID }

    /// 选项列表自然高度（含 padding(3)），由内容 background 内的 GeometryReader 实测，
    /// 选项数变化时自动重测。
    @State private var listHeight: CGFloat = 0

    /// 列表视觉揭示高度（0 → 实高随弹簧插值）。只作用于 mask，不参与布局。
    /// 为什么不直接动画布局高度：NSPopover 对内容增高的窗口 resize 不做动画
    /// （一步跳到目标，收起方向才有系统动画），若布局高度中途插值变小，
    /// 内容会在已增高的窗口里被居中→整块下沉再弹回（顶部伪影）。
    /// 故展开方向布局高度二值跳变（理想尺寸瞬间到位），视觉揭示交给 mask。
    @State private var revealHeight: CGFloat = 0

    /// 列表可见高度：自然高度封顶 216（选项极多时 ScrollView 内部滚动）。
    private var listVisibleHeight: CGFloat {
        min(listHeight, BubbleMetrics.selectionListMaxHeight)
    }

    var body: some View {
        VStack(spacing: BubbleMetrics.rowSpacing) {
            RowButton(action: {
                withAnimation(panelReveal) {
                    expandedRowID = expanded ? nil : rowID
                }
            }, verticalPadding: 3, horizontalPadding: 0) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: BubbleMetrics.fontCaption))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(currentValue)
                        .font(.system(size: BubbleMetrics.fontCaption, weight: .medium))
                        .foregroundStyle(.primary)
                    // 展开状态指示：chevron 随展开旋转向下（旋转在触发行的
                    // withAnimation 里一起动），补上「点击可展开」的视觉提示。
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }

            // 选项列表：浅灰圆角底呈现「菜单浮层」感，选项多时内部滚动限高。
            // 常驻挂载（不条件插入）：贪婪 ScrollView 的条件插入高度跳变不参与
            // 动画，是旧版「展开瞬时拉长」的根源；实测高度后显式 frame 驱动。
            // 展开方向用 .animation(nil) 让布局高度二值切换（防居中下沉，见
            // revealHeight 注释），mask 按弹簧从 0 揭示到实高；收起方向保留
            // 弹簧插值（窗口收起自带系统动画，与内容同步缩小无下沉问题），
            // frame 回抽 + clipped 呈现「收回触发行下」的动画。
            ScrollView {
                VStack(spacing: BubbleMetrics.rowSpacing) {
                    ForEach(options.indices, id: \.self) { idx in
                        optionRow(options[idx])
                    }
                }
                .padding(3)
                .background(
                    // 测自然高度：挂在内容（含 padding）的 background 上。
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { listHeight = geo.size.height }
                            .onChange(of: geo.size.height) { listHeight = $0 }
                    }
                )
            }
            .frame(height: expanded ? listVisibleHeight : 0, alignment: .top)
            // 展开方向剥离动画（含显式 withAnimation 事务——.animation(nil) 挡不住
            // 显式事务，必须用 transaction 改写）：布局高度二值跳变，理想尺寸瞬间
            // 到位（防居中下沉，见 revealHeight 注释）；收起方向保留弹簧回抽。
            .transaction { t in
                if expanded { t.animation = nil }
            }
            .opacity(expanded ? 1 : 0)
            .background(
                RoundedRectangle(cornerRadius: BubbleMetrics.hoverCornerRadius)
                    .fill(Color.secondary.opacity(0.08))
            )
            .mask(alignment: .top) {
                Color.white.frame(height: revealHeight)
            }
            .clipped()
            // 折叠态摘除整棵列表的命中区（含 hover）：frame(0)/clipped/mask 只裁「绘制」
            // 不裁「命中测试」，折叠列表的选项行曾以自然高度在卡下方形成幽灵命中区，
            // 指针落在面板未遮挡的缝隙（工具栏两气泡之间/上下空带）时命中幽灵行、
            // 沿祖先链触发卡片级 hover 浮起（2026-09「缝隙触发显示器调节卡悬浮」bug）。
            // 展开方向布局本就二值跳变，展开即恢复命中，无时序问题。
            .allowsHitTesting(expanded)
            .onAppear {
                // 兜底：挂载时已处于展开态（理论上不会发生），直接全揭示。
                if expanded { revealHeight = listVisibleHeight }
            }
            .onChange(of: expanded) { isOn in
                if isOn {
                    // 揭示动画：从 0 弹簧拉到实高（纯视觉，不参与布局）。
                    revealHeight = 0
                    withAnimation(panelReveal) { revealHeight = listVisibleHeight }
                }
                // 收起时不动 revealHeight：frame 弹簧回抽 + clipped 即收起动画。
            }
            .onChange(of: listHeight) { _ in
                // 选项数变化（如刷新后）同步校正揭示高度与布局目标。
                if expanded {
                    withAnimation(panelReveal) { revealHeight = listVisibleHeight }
                }
            }
        }
    }

    /// 单个选项行：当前项前 ✓（固定占位对齐），点击执行操作并收起（连同其他行）。
    private func optionRow(_ option: Option) -> some View {
        RowButton(action: {
            option.action()
            withAnimation(panelReveal) { expandedRowID = nil }
        }, verticalPadding: 3, horizontalPadding: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(accent)
                    .opacity(option.isActive ? 1 : 0)
                    .frame(width: 12)
                Text(option.text)
                    .font(.system(size: BubbleMetrics.fontCaption))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - 布局示意图

/// 等比绘制所有屏的相对位置与尺寸（可交互）。
///
/// 算法：取所有屏 origin + resolution 的包围盒，等比缩放到容器内，用 ZStack
/// 定位每块屏的圆角矩形。屏名常驻显示在块正中央（2026-10 拍板）；主从关系由
/// 静止态描边深浅表达（主屏卡已删，这是图上唯一常驻主从标识）。
/// 交互：悬停块体点亮（accent 浅底+描边+轻放大）；点击屏块回调 onSelect
/// （选中态 ✓ 角标 + 加粗描边，由宿主 toggle 展开参数块）；highlightedID
/// （参数块折叠头 hover 联动）与块直悬同等点亮。
private struct LayoutDiagram: View {
    let displays: [DisplayInfo]
    let accent: Color
    var selectedID: String? = nil
    var highlightedID: String? = nil
    var onSelect: ((DisplayInfo) -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            if let layout = computeLayout(into: proxy.size) {
                ZStack {
                    ForEach(layout.rects, id: \.id) { item in
                        screenBlock(item)
                    }
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 单个屏块（视图包装）：hover 状态与浮层标签收在子视图里（@State 需宿主
    /// 是 View）；样式细节见 ScreenBlock。
    private func screenBlock(_ item: PlacedRect) -> some View {
        ScreenBlock(item: item,
                    accent: accent,
                    isSelected: item.id == selectedID,
                    isHighlighted: item.id == highlightedID,
                    onSelect: { onSelect?(item.display) })
    }

    /// 单个屏块：屏名常驻居中（fontCaption，超长中截）；悬停点亮（accent 浅底 +
    /// 2pt 描边 + 中心锚轻微放大 1.04）；静止态主从由描边深浅区分（主屏
    /// secondary 0.75 / 非主屏 0.4）；选中态 ✓ 角标 + accent 描边。
    private struct ScreenBlock: View {
        let item: PlacedRect
        let accent: Color
        let isSelected: Bool
        let isHighlighted: Bool
        let onSelect: () -> Void

        @State private var isHovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// 点亮态：块直悬或折叠头 hover 联动（highlightedID）任一成立。
        private var isLit: Bool { isHovered || isHighlighted }

        var body: some View {
            let stroke: Color = (isSelected || isLit) ? accent
                : Color.secondary.opacity(item.display.isMain ? 0.75 : 0.4)
            let lineWidth: CGFloat = (isSelected || isLit) ? 2 : 1
            let fill: Color = isLit ? accent.opacity(0.28) : Color.gray.opacity(0.08)

            return RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(stroke, lineWidth: lineWidth)
                )
                .overlay(alignment: .topTrailing) {
                    // 选中角标（点击布局图中的屏块后出现，再次点击消失）
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(accent)
                            .padding(2)
                    }
                }
                // 常驻屏名居中（2026-10 拍板）：不悬停即可识别每块屏；悬停只负责
                // 点亮+轻放大（原浮层标签与顶部标签带一并移除，块群重新居中）。
                // 纯文字层不拦截手势（命中期望落在块矩形，见下方 contentShape）。
                .overlay {
                    Text(item.display.localizedTypeName(l10n: L10n.shared))
                        .font(.system(size: BubbleMetrics.fontCaption, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 3)
                        .allowsHitTesting(false)
                }
                .frame(width: item.rect.width, height: item.rect.height)
                // 命中区显式钉在块矩形（手势默认命中区=视图 frame，此处保险）。
                .contentShape(Rectangle())
                // 悬停轻放大：中心锚对称缩放，进出两方向单调，指针不会在块缘
                // 振荡（hover 浮起振荡修复的构造性保证）；2D 仿射不栅格化。
                .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1, anchor: .center)
                .animation(BubbleMetrics.buttonHoverSpring, value: isHovered)
                .onTapGesture { onSelect() }
                .onHover { hovering in isHovered = hovering }
                // .position 必须挂在此链**末尾**：它会给视图套一层占满父级全部
                // 空间（整个布局图）的弹性 frame，命中区随之变成全图——先挂
                // position 再挂手势，ZStack 最上层的屏块就会吞掉全图的 hover/
                // 点击（2026-10「外接屏块无反应」的根因；该 bug 同时让旧版
                // 点块选中恒选最上层屏，一并修复）。
                .position(x: item.rect.midX, y: item.rect.midY)
        }
    }

    /// 一块屏在画布内的目标矩形。
    private struct PlacedRect {
        let id: String
        let display: DisplayInfo
        let rect: CGRect
    }

    /// 计算所有屏的包围盒并等比缩放到容器内，返回每块屏的放置矩形。
    private struct LayoutResult {
        let rects: [PlacedRect]
    }

    private func computeLayout(into size: CGSize) -> LayoutResult? {
        guard !displays.isEmpty else { return nil }
        // 包围盒：所有屏 origin 的最小/最大 + 各自宽高。
        let minX = displays.map { $0.origin.x }.min() ?? 0
        let maxX = displays.map { $0.origin.x + $0.resolution.width }.max() ?? 1
        let minY = displays.map { $0.origin.y }.min() ?? 0
        let maxY = displays.map { $0.origin.y + $0.resolution.height }.max() ?? 1
        let boundsW = CGFloat(maxX - minX)
        let boundsH = CGFloat(maxY - minY)
        guard boundsW > 0, boundsH > 0 else { return nil }

        // 等比缩放，留 6pt 边距（2026-10：常驻屏名居中后浮层标签带移除，
        // 块群在图内居中、整体更高更宽——见 BubbleMetrics.diagramHeight）。
        let pad: CGFloat = 6
        let avail = CGSize(width: max(size.width - pad * 2, 1),
                           height: max(size.height - pad * 2, 1))
        let scale = min(avail.width / boundsW, avail.height / boundsH)
        // 居中偏移：包围盒缩放后可能不填满容器，居中放置。
        let drawnW = boundsW * scale
        let drawnH = boundsH * scale
        let offsetX = (size.width - drawnW) / 2
        let offsetY = (size.height - drawnH) / 2

        let rects = displays.map { d -> PlacedRect in
            let relX = CGFloat(d.origin.x - minX) * scale
            let relY = CGFloat(d.origin.y - minY) * scale
            // macOS 坐标 y 向上；视图坐标 y 向下，做一次翻转。
            let frame = CGRect(x: offsetX + relX,
                               y: offsetY + (drawnH - relY - CGFloat(d.resolution.height) * scale),
                               width: CGFloat(d.resolution.width) * scale,
                               height: CGFloat(d.resolution.height) * scale)
            return PlacedRect(id: d.id, display: d, rect: frame)
        }
        return LayoutResult(rects: rects)
    }
}
