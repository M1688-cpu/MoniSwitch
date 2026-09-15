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
///   - 箭头/居中对齐/展开动画由 NSPopover 系统 chrome 提供（圆角贴顶同理）。
///
/// 卡片顺序：主显示器 → 排列与镜像 → 布局预设 → 布局预览 → 底部操作栏。
/// 交互：操作进行中（isOperating）禁用卡片区并显示顶部流动进度条；
/// 面板高度随内容自适应（展开参数/切换语言变长都不出滚动条）；排列行 hover 与布局图互相联动。
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

    /// 排列卡内展开参数组的屏 id（面板级互斥：同时只展开一块屏，默认全收起；
    /// 点击布局图选中某屏时联动展开该组）。nil=全部收起。
    @State private var expandedDisplayID: String?

    /// 布局图中点击选中的屏（描边加粗 + ✓ 角标，再次点击取消）。
    @State private var selectedDisplayID: String?

    /// 当前 hover 的屏（主显示器行 / 排列行 hover 时上报，布局图对应块高亮，
    /// 解决"不知道排列/镜像操作的是哪块屏"的歧义）。
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
                    primaryCard
                    // 单内置屏时也显示：卡片退化为内置屏的分辨率/刷新率调节。
                    arrangeCard
                    if !presetManager.presets.isEmpty {
                        presetsCard
                    }
                    layoutPreviewCard
                }
                .disabled(busy)
            }
            bottomToolbar
        }
        .padding(16)
        // 只锁宽度，高度按内容自适应。
        .frame(minWidth: 380, idealWidth: 380, maxWidth: 380)
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
                    .padding(.horizontal, 16)
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

    // MARK: - 主显示器卡片

    /// 主显示器列表：每块屏一行，点击即设为主屏。主从关系由图标圆框状态表达——
    /// 主屏图标圆框填主题色，非主屏为深灰暗态（不再用圆点指示器与 "Main" 角标）。
    /// 行 hover 时布局图对应屏块高亮。
    private var primaryCard: some View {
        BubbleCard(title: l10n.t(.displaysSection)) {
            VStack(spacing: BubbleMetrics.rowSpacing) {
                ForEach(state.displays) { d in
                    RowButton(action: { state.setPrimary(d) }) {
                        HStack(spacing: 10) {
                            // 主从状态由圆框颜色表达；名称字重（主屏 semibold）为第二线索。
                            DeviceIconBadge(isBuiltIn: d.isBuiltIn, active: d.isMain, accent: accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.localizedTypeName(l10n: l10n))
                                    .font(.system(size: BubbleMetrics.fontBody, weight: d.isMain ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Text(subtitle(for: d))
                                    .font(.system(size: BubbleMetrics.fontCaption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onHover { hovering in
                        hoveredDisplayID = hovering ? d.id : nil
                    }
                }
            }
        }
    }

    /// 显示器副标题：分辨率，按设置可选追加 @Hz 与 HiDPI。
    private func subtitle(for d: DisplayInfo) -> String {
        var s = "\(d.resolution.width)×\(d.resolution.height)"
        if settings.detailedMenuInfo {
            s += " @\(d.hertz)Hz"
            if d.scalingOn { s += " HiDPI" }
        }
        return s
    }

    // MARK: - 排列与镜像卡片

    /// 显示器排列与调节（每屏一组行：位置/分辨率/刷新率）+ 镜像/扩展切换。
    ///
    /// 每块屏（含主屏）都有调节行：非主屏多一个位置行（左右移），
    /// 主屏只保留分辨率/刷新率——主屏参数不必先切主屏身份即可调。
    /// 单内置屏（无外接）时卡片退化为「显示器调节」：隐藏位置分段与镜像/扩展
    /// 切换（标题与图标随之切换）。
    private var arrangeCard: some View {
        let externals = state.displays.filter { !$0.isBuiltIn }
        let hasExternals = !externals.isEmpty
        return BubbleCard(title: hasExternals ? l10n.t(.panelArrange) : l10n.t(.panelDisplayAdjust)) {
            VStack(spacing: BubbleMetrics.rowSpacing) {
                if hasExternals {
                    ForEach(state.displays) { d in
                        ArrangementRow(display: d,
                                       state: state,
                                       accent: accent,
                                       label: d.localizedTypeName(l10n: l10n),
                                       showsPosition: !d.isMain,
                                       foldable: true,
                                       expandedDisplayID: $expandedDisplayID,
                                       expandedRowID: $expandedRowID,
                                       onHoverDisplay: { hovering in
                                           hoveredDisplayID = hovering ? d.id : nil
                                       })
                    }

                    Divider().padding(.vertical, 4)

                    // 镜像 / 扩展：两个互斥按钮，当前态强调色高亮。
                    // 操作对端随主屏身份切换（与原 menu 逻辑一致，避免 mirror(ext==main) 退化）；
                    // 对端屏名不再静态占一行，改为 hover 镜像按钮时弹出的补充气泡（见下）。
                    mirrorExtendRow
                } else if let builtIn = state.builtInDisplay {
                    // 单内置屏：无位置可排、无镜像对象，仅分辨率/刷新率。
                    // 内容只有两行，折叠反而多一次点击——foldable=false 常展开。
                    ArrangementRow(display: builtIn,
                                   state: state,
                                   accent: accent,
                                   label: builtIn.localizedTypeName(l10n: l10n),
                                   showsPosition: false,
                                   foldable: false,
                                   expandedDisplayID: .constant(nil),
                                   expandedRowID: $expandedRowID,
                                   onHoverDisplay: { hovering in
                                       hoveredDisplayID = hovering ? builtIn.id : nil
                                   })
                }
            }
        }
    }

    /// 镜像 / 扩展切换区：并排胶囊按钮。
    ///
    /// 镜像操作的对端屏名不静态占行：hover 镜像按钮并停留片刻后，按钮上方弹出
    /// 补充气泡说明对端屏（MirrorTargetTooltip，移开即收）——多外接时消除
    /// "操作哪块屏"的歧义，同时省去常驻占位文字。
    private var mirrorExtendRow: some View {
        let externals = state.displays.filter { !$0.isBuiltIn }
        let isMirroring = externals.contains { state.isMirroring($0) }

        // 操作对端：外接是主屏 → 内置屏；否则首个外接屏。
        let peer: DisplayInfo? = state.externalIsMain
            ? state.builtInDisplay
            : externals.first

        return HStack(spacing: 8) {
            ActivePill(active: isMirroring, verticalPadding: 6, strokeWhenInactive: true) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: BubbleMetrics.fontCaption))
                    Text(l10n.t(.mirrorMain)).font(.system(size: BubbleMetrics.fontControl, weight: isMirroring ? .semibold : .regular))
                }
                .frame(maxWidth: .infinity)
            }
            .asButton {
                if let peer { state.mirror(peer) }
            }
            .disabled(peer == nil)
            // 对端屏名补充气泡：hover 停留触发（扩展按钮不需要——它不涉及对端选择）。
            .modifier(MirrorTargetTooltip(
                text: peer.map { l10n.t(.mirrorTarget, $0.localizedTypeName(l10n: l10n)) } ?? ""
            ))

            ActivePill(active: !isMirroring, verticalPadding: 6, strokeWhenInactive: true) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.dashed").font(.system(size: BubbleMetrics.fontCaption))
                    Text(l10n.t(.extendDisplay)).font(.system(size: BubbleMetrics.fontControl, weight: !isMirroring ? .semibold : .regular))
                }
                .frame(maxWidth: .infinity)
            }
            .asButton {
                if let peer { state.unmirror(peer) }
            }
            .disabled(peer == nil)
        }
        .padding(.top, 2)
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

    // MARK: - 布局预览卡片

    /// 等比布局示意图（可交互）：按 origin + resolution 画出每块屏的相对位置与比例。
    /// 点击屏块选中（✓ 角标）；hover 主显示器行/排列行时对应块高亮。
    private var layoutPreviewCard: some View {
        BubbleCard(title: l10n.t(.panelLayoutPreview)) {
            LayoutDiagram(
                displays: state.displays,
                accent: accent,
                selectedID: selectedDisplayID,
                highlightedID: hoveredDisplayID,
                onSelect: { d in
                    // 点击同一块屏取消选中。
                    let same = selectedDisplayID == d.id
                    selectedDisplayID = same ? nil : d.id
                    // 选中即定位：联动展开排列卡中该屏的参数组（取消选中不收起）。
                    // 展开方向必须二值跳变（不带 withAnimation），与 toggleExpanded
                    // 一致——带动画会让高度弹簧化，重新引入居中漂移（见
                    // PanelController「容器闸门」注释）；视觉揭示由块内 mask 承担。
                    if !same {
                        expandedDisplayID = d.id
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 120)
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
            // 与气泡统一材质（BubbleBackground 不透明纯白）+ 阴影；拉满剩余宽度。
            .modifier(BubbleBackground())
            .bubbleShadow()
            .frame(maxWidth: .infinity)

            // 退出：内容自适应小气泡，刚好适配按钮触区。
            ToolbarIconButton(tooltip: l10n.t(.quit), systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .modifier(BubbleBackground())
            .bubbleShadow()
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
private struct MirrorTargetTooltip: ViewModifier {
    let text: String

    @State private var isShown = false
    @State private var dwellTask: DispatchWorkItem?
    @Environment(\.colorScheme) private var colorScheme
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
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .light ? Color.white : BubbleMetrics.bubbleDarkFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(colorScheme == .light ? 0.10 : 0.18), lineWidth: 1)
                )
                .bubbleShadow(opacity: 0.7)
                .fixedSize()
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
                        // 量一次展开块实高，驱动 mask 揭示终点。
                        GeometryReader { geo in
                            Color.clear.onAppear {
                                blockHeight = geo.size.height
                                revealHeight = 0
                                withAnimation(panelReveal) { revealHeight = blockHeight }
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
/// 算法：取所有屏 origin + resolution 的包围盒，等比缩放到容器宽度，
/// 用 ZStack 定位每块屏的圆角矩形。所有屏块统一中性样式（主屏强调色标示
/// 已于 2026-09-12 移除，主从关系由主屏卡的图标圆框表达）。
/// 交互：点击屏块回调 onSelect（选中态 ✓ 角标 + 加粗描边）；
/// highlightedID（hover 联动）对应块加深高亮。
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

    /// 单个屏块：所有块统一中性样式（2026-09-12 移除主屏强调色标示——主从关系
    /// 已由主屏卡的图标圆框颜色表达）；选中/hover 高亮态用强调色描边+浅底。
    private func screenBlock(_ item: PlacedRect) -> some View {
        let isHighlighted = (item.id == highlightedID)
        let isSelected = (item.id == selectedID)

        let stroke: Color = (isSelected || isHighlighted) ? accent : Color.secondary.opacity(0.4)
        let lineWidth: CGFloat = (isSelected || isHighlighted) ? 2 : 1
        let fill = isHighlighted ? accent.opacity(0.28) : Color.gray.opacity(0.08)

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
            .frame(width: item.rect.width, height: item.rect.height)
            .position(x: item.rect.midX, y: item.rect.midY)
            .onTapGesture { onSelect?(item.display) }
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

        // 等比缩放，留 6pt 边距。
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
