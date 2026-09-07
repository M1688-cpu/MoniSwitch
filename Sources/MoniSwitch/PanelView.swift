import SwiftUI
import AppKit

/// 菜单栏下拉面板（宿主为 PanelController 的 NSPopover）：按参考图做成分栏「气泡卡片」。
///
/// 这里是一块可完全自定义的 SwiftUI 视图：
///   - 每个功能分栏是一张圆角气泡卡片（`BubbleCard`，Components.swift）；
///   - 强调色跟随系统（`BrandColor.accent`，Components.swift）；
///   - 所有切换操作复用 `AppState` / `PresetManager` 的现有逻辑，只改触发控件形态；
///   - 箭头/居中对齐/展开动画由 NSPopover 系统 chrome 提供（圆角贴顶同理）。
///
/// 卡片顺序：主显示器 → 排列与镜像 → 布局预设 → 布局预览 → 底部工具栏 → 退出。
/// 交互：操作进行中（isOperating）禁用卡片区并显示顶部流动进度条；
/// 卡片区可滚动（多屏/多预设时封顶 600pt）；排列行 hover 与布局图互相联动。
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

    /// 卡片区内容实测高度（PreferenceKey 上报），驱动 ScrollView 的明确高度。
    ///
    /// 背景（2026-09 实测）：屏幕重配（切主屏/自动排列等触发系统级 relayout）时，
    /// 面板被系统重新求解尺寸，ScrollView 在无确定高度 proposal 的求解轮里
    /// ideal 高度塌为 0——面板瞬间只剩底部工具栏与退出行，且不再自愈。
    /// （当时宿主是 MenuBarExtra(.window)；迁移 NSPopover 后保留同一防御，
    /// 显式高度对 popover 的 preferredContentSize 同样是确定值。）
    /// 改为测内容实高后显式 frame：任何重求解都拿到确定值，不再塌。
    /// 初值取典型四卡高度，防首帧闪变。
    @State private var scrollContentHeight: CGFloat = 480

    /// 是否有操作在后台执行（含预设回放）：禁用卡片区 + 显示进度条。
    private var busy: Bool { state.isOperating || presetManager.isApplying }

    var body: some View {
        VStack(spacing: BubbleMetrics.cardSpacing) {
            if state.displays.isEmpty {
                // 无显示器：只放一张提示卡。
                BubbleCard(title: l10n.t(.displaysSection), systemImage: "display", accent: accent) {
                    Text(l10n.t(.noDisplays))
                        .font(.system(size: BubbleMetrics.fontBody))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                }
            } else {
                // 卡片区可滚动：高度 = min(内容实高, 600)，显式 frame 的原因见
                // scrollContentHeight 注释（屏幕重配时防 ScrollView 塌 0）。
                ScrollView {
                    VStack(spacing: BubbleMetrics.cardSpacing) {
                        primaryCard
                        // 单内置屏时也显示：卡片退化为内置屏的分辨率/刷新率调节。
                        arrangeCard
                        if !presetManager.presets.isEmpty {
                            presetsCard
                        }
                        layoutPreviewCard
                    }
                    .background(
                        // 测内容固有高度（GeometryReader 铺在内容 background 上，
                        // 读到的是内容布局高度，不受滚动视口影响）
                        GeometryReader { geo in
                            Color.clear.preference(key: PanelContentHeightKey.self,
                                                   value: geo.size.height)
                        }
                    )
                }
                .onPreferenceChange(PanelContentHeightKey.self) { scrollContentHeight = $0 }
                .frame(height: min(scrollContentHeight, 600))
                .disabled(busy)
            }
            bottomToolbar
            quitRow
        }
        .padding(14)
        // 只锁宽度，高度按内容自适应。
        .frame(minWidth: 380, idealWidth: 380, maxWidth: 380)
        // 操作进行中：顶部悬浮一条流动进度条（overlay 不占布局空间，内容不下移）。
        .overlay(alignment: .top) {
            if busy {
                IndeterminateBar(accent: accent)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - 主显示器卡片

    /// 主显示器列表：每块屏一行，点击即设为主屏，主屏行带强调色角标。
    /// 行 hover 时布局图对应屏块高亮。
    private var primaryCard: some View {
        BubbleCard(title: l10n.t(.displaysSection), systemImage: "display", accent: accent) {
            VStack(spacing: BubbleMetrics.rowSpacing) {
                ForEach(state.displays) { d in
                    RowButton(action: { state.setPrimary(d) }) {
                        HStack(spacing: 10) {
                            // 主屏用实心强调色圆点，非主屏用空心圆。
                            Image(systemName: d.isMain ? "circle.fill" : "circle")
                                .font(.system(size: BubbleMetrics.fontMini))
                                .foregroundStyle(d.isMain ? accent : Color.secondary.opacity(0.4))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.localizedTypeName(l10n: l10n))
                                    .font(.system(size: BubbleMetrics.fontBody, weight: d.isMain ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Text(subtitle(for: d))
                                    .font(.system(size: BubbleMetrics.fontCaption))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if d.isMain {
                                Text(l10n.t(.panelPrimaryBadge))
                                    .font(.system(size: BubbleMetrics.fontMini, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accent, in: Capsule())
                            }
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
        return BubbleCard(title: hasExternals ? l10n.t(.panelArrange) : l10n.t(.panelDisplayAdjust),
                          systemImage: hasExternals ? "arrow.left.and.right" : "slider.horizontal.3",
                          accent: accent) {
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
                    // 操作对端随主屏身份切换（与原 menu 逻辑一致，避免 mirror(ext==main) 退化）。
                    mirrorExtendRow

                    Divider().padding(.vertical, 4)

                    // 一键自动排列：横向排开、消除重叠（镜像组保持完整）。
                    autoArrangeRow
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

    /// 镜像 / 扩展切换区：目标屏说明行 + 并排胶囊按钮。
    ///
    /// 说明行明确写出镜像操作的对端屏名（多外接时消除"操作哪块屏"的歧义）。
    private var mirrorExtendRow: some View {
        let externals = state.displays.filter { !$0.isBuiltIn }
        let isMirroring = externals.contains { state.isMirroring($0) }

        // 操作对端：外接是主屏 → 内置屏；否则首个外接屏。
        let peer: DisplayInfo? = state.externalIsMain
            ? state.builtInDisplay
            : externals.first

        return VStack(spacing: 6) {
            if let peer {
                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(l10n.t(.mirrorTarget, peer.localizedTypeName(l10n: l10n)))
                        .font(.system(size: BubbleMetrics.fontCaption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 8) {
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
        }
        .padding(.top, 2)
    }

    // MARK: - 布局预设卡片

    /// 一键自动排列行：全行可点的小按钮，横排所有屏并消除重叠。
    private var autoArrangeRow: some View {
        RowButton(action: { state.autoArrange() }) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.rays")
                    .font(.system(size: BubbleMetrics.fontControl))
                    .foregroundStyle(accent)
                    .frame(width: 16)
                Text(l10n.t(.autoArrange))
                    .font(.system(size: BubbleMetrics.fontCaption))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 已保存预设：每条一行（名称 + 快捷键角标 + 应用按钮）。
    private var presetsCard: some View {
        BubbleCard(title: l10n.t(.groupPresets), systemImage: "square.stack", accent: accent) {
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
        BubbleCard(title: l10n.t(.panelLayoutPreview), systemImage: "rectangle.split.2x1", accent: accent) {
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
                    if !same {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            expandedDisplayID = d.id
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .frame(height: 120)
        }
    }

    // MARK: - 底部工具栏

    /// 刷新 / 设置：轻量图标行。退出刻意不放在这里（与"设置"相邻易误触），
    /// 单独挪到下方低视觉权重的小字行。
    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton(l10n.t(.refreshList), systemImage: "arrow.clockwise") {
                state.refresh()
            }
            Divider().frame(height: 18)
            toolbarButton(l10n.t(.settingsTitle), systemImage: "gearshape") {
                // openSettings 会切 activation policy 并激活 App，先收面板防悬空。
                PanelController.shared.close()
                DockPolicyManager.shared.openSettings()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        // 与气泡统一材质（BubbleBackground）+ 阴影，使整列观感一致。
        .modifier(BubbleBackground())
        .bubbleShadow()
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: BubbleMetrics.fontTitle))
                Text(title)
                    .font(.system(size: BubbleMetrics.fontMini))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            // 与全站行控件统一 hover 反馈；外扩传 0——按钮已占满半宽，
            // 再外扩会盖过中间分隔线。
            .hoverRowHighlight(horizontalExpansion: 0)
        }
        .buttonStyle(.plain)
    }

    /// 底部独立的退出小字行：低视觉权重（secondary 色小字）+ 与工具栏拉开距离，
    /// 与"设置"的相邻误触问题由此消除。
    private var quitRow: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Text(l10n.t(.quit))
                .font(.system(size: BubbleMetrics.fontCaption))
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
                .hoverRowHighlight()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 卡片区内容高度上报

/// 面板卡片区内容固有高度上报（GeometryReader 铺在滚动内容 background 上）。
/// PanelView 用它给 ScrollView 显式 frame，避免屏幕重配时高度塌 0。
private struct PanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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

    var body: some View {
        VStack(spacing: 0) {
            // 标题行（可折叠时是折叠头）：图标 + 屏名 + 参数概要 + 旋转 chevron。
            RowButton(action: toggleExpanded) {
                HStack(spacing: 10) {
                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.system(size: BubbleMetrics.fontControl))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(label)
                        .font(.system(size: BubbleMetrics.fontBody))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if foldable {
                        // 概要：收起时也能一眼看到当前档位（位置已知才带前缀）。
                        Text(parameterSummary)
                            .font(.system(size: BubbleMetrics.fontCaption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }
            .onHover(perform: onHoverDisplay)

            // 表单风三行：位置（分段控件）/ 分辨率 / 刷新率，标题靠左、控件靠右对齐。
            // 折叠态下整块隐藏（foldable=false 恒显示）。
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
                    // 却得到小图标」的误解（逻辑分辨率才是观感档位）。
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
                .padding(.leading, 24)   // 与标题行文字对齐：图标 frame 14 + spacing 10
                .padding(.trailing, 4)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 折叠头点击：切换本组展开态。组间互斥（面板级单值）：展开本组自动收起其他组；
    /// 任何组折叠/切换都会让组内的选项列表不可见，统一清空 expandedRowID 防止
    /// 下次展开时残留旧的选项展开态。
    private func toggleExpanded() {
        guard foldable else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            expandedRowID = nil
            expandedDisplayID = isExpanded ? nil : display.id
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

    var body: some View {
        VStack(spacing: BubbleMetrics.rowSpacing) {
            RowButton(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
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

            if expanded {
                // 展开列表：浅灰圆角底呈现「菜单浮层」感；选项多时内部滚动并限高，面板高度可控。
                ScrollView {
                    VStack(spacing: BubbleMetrics.rowSpacing) {
                        ForEach(options.indices, id: \.self) { idx in
                            optionRow(options[idx])
                        }
                    }
                    .padding(3)
                }
                .frame(maxHeight: 216)
                .background(
                    RoundedRectangle(cornerRadius: BubbleMetrics.hoverCornerRadius)
                        .fill(Color.secondary.opacity(0.08))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 单个选项行：当前项前 ✓（固定占位对齐），点击执行操作并收起（连同其他行）。
    private func optionRow(_ option: Option) -> some View {
        RowButton(action: {
            option.action()
            withAnimation(.easeInOut(duration: 0.15)) { expandedRowID = nil }
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
/// 用 ZStack 定位每块屏的圆角矩形。主屏用强调色实心浅底，外接用描边。
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

    /// 单个屏块：填充/描边随 主屏态、选中态、hover 高亮态 变化。
    private func screenBlock(_ item: PlacedRect) -> some View {
        let isMain = item.display.isMain
        let isHighlighted = (item.id == highlightedID)
        let isSelected = (item.id == selectedID)

        // 优先级：选中/高亮 > 主屏 > 普通。
        let stroke: Color = (isSelected || isHighlighted)
            ? accent
            : (isMain ? accent : Color.secondary.opacity(0.4))
        let lineWidth: CGFloat = (isSelected || isHighlighted) ? 2 : (isMain ? 1.5 : 1)
        let fill = isHighlighted
            ? accent.opacity(0.28)
            : (isMain ? accent.opacity(0.18) : Color.gray.opacity(0.08))

        return RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(stroke, lineWidth: lineWidth)
            )
            .overlay(alignment: .topLeading) {
                // 主屏标实心点，副屏标空心点
                Image(systemName: isMain ? "circle.fill" : "circle")
                    .font(.system(size: 7))
                    .foregroundStyle(isMain ? accent : .secondary)
                    .padding(3)
            }
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
