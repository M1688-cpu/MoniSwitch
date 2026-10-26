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

/// 展开块逐帧高度揭示修饰器（2026-10-17 离屏 harness 实证定型）：
/// SwiftUI 内建 `.frame(height:)` 的三元切换与 `.transition` 在 withAnimation 下
/// 都只做**呈现层**动画——父容器布局与 PreferenceKey 高度桥拿到的是一步到位的
/// 终值，窗口经高度桥瞬跳、内容无过渡（「展开直接弹出」的根因）。自定义
/// Animatable 修饰器在插值期间**每帧以中间高度重排 body**，父容器与高度桥
/// 逐帧跟随，窗口顶边锚死逐帧生长/收缩——展开/收起两向对称丝滑。
/// 收起方向内容保持挂载，由 max(height,0)+clipped 压制；调用方必须另挂
/// `.allowsHitTesting(展开态)` 摘除压扁内容的命中区（clip 不摘命中）。
private struct RevealHeightModifier: ViewModifier, Animatable {
    var height: CGFloat

    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }

    func body(content: Content) -> some View {
        content
            .frame(height: max(height, 0), alignment: .top)
            .clipped()
    }
}

/// 菜单栏下拉面板（宿主为 PanelController 的 NSPopover）：按参考图做成分栏「气泡卡片」。
///
/// 这里是一块可完全自定义的 SwiftUI 视图：
///   - 每个功能分栏是一张圆角气泡卡片（`BubbleCard`，Components.swift）；
///   - 配色 = 内置主题三档色板（`PanelPalette` 环境注入，见 PanelTheme.swift；
///     「跟随系统」时高亮/实心取系统强调色、卡底纯白/深卡色）；
///   - 所有切换操作复用 `AppState` / `PresetManager` 的现有逻辑，只改触发控件形态；
///   - 面板无背板（2026-09-21 起）：气泡卡片直接悬浮于壁纸，居中对齐/展开动画
///     由 NSPopover 系统行为提供；指向菜单栏的箭头随玻璃背板隐藏而消失（与参考形态一致）。
///
/// 卡片顺序（2026-10 改版）：显示器枢纽（布局预览+点块展开参数）→ 布局预设 →
/// 底部操作栏。原主屏卡/排列卡已并入枢纽卡（设为主屏/镜像扩展在非主屏参数块底部）。
/// 交互：操作进行中（isOperating）禁用卡片区并显示顶部流动进度条；
/// 面板高度随内容自适应（展开参数/切换语言变长都不出滚动条）；参数块 hover 与布局图互相联动。
struct PanelView: View {

    @ObservedObject var state: AppState
    /// 面板窗口的固定高度（0 = 旧弹性行为）。2026-10-18 终版：窗口高度恒定，
    /// 根部也固定成这个高度，让**内容理想尺寸恒定**——SwiftUI 就没有可改的窗口
    /// 尺寸（它会按内容尺寸自动改窗口，且底部锚定），面板可见期间零窗口写入。
    /// 展开/收起因此退化为窗口内部的纯 SwiftUI 布局动画，顶边天然不动。
    /// 视觉面板高度仍等于内容高度，下方是透明的多余区域（点击判定按内容矩形，
    /// 见 PanelController.dismissIfClickedOutside）。
    var windowHeight: CGFloat = 0
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var presetManager: PresetManager

    @Environment(\.colorScheme) private var colorScheme

    /// 面板主题三档色板（2026-10-17 内置主题）：按设置的主题 id 与当前外观解析，
    /// 根部注入环境——BubbleBackground/ActivePill/行高亮与面板私有视图全部由此
    /// 取色（卡底=最浅档、高亮类=中间档、实心类=最深档；「跟随系统」= 原观感）。
    /// 设置窗口不注入（环境默认 .system），保持原生强调色。
    private var palette: PanelPalette {
        PanelTheme.palette(id: settings.panelThemeID, dark: colorScheme == .dark)
    }

    /// 当前面板内展开的 SelectionRow 标识（互斥：同屏的分辨率/刷新率、
    /// 跨屏的各行同时只展开一个，避免面板高度反复跳动）。nil=全部收起。
    @State private var expandedRowID: String?

    /// 枢纽卡内展开参数组的屏 id（面板级互斥：同时只展开一块屏，默认全收起；
    /// 点布局图屏块 toggle）。nil=全部收起。2026-10 改版后「选中」与「展开」
    /// 同生共死，布局图 ✓ 角标直接由本值驱动（不再单独持有 selectedDisplayID
    /// ——折叠头 chevron 收起时 ✓ 随之消失，两条收起路径天然同步）。
    @State private var expandedDisplayID: String?

    /// 枢纽卡参数块当前挂载的屏 id：展开时与 expandedDisplayID 同步；收起动画
    /// 期间保持不变（RevealHeightModifier 块高动画回 0 的过程内容须留在树上，
    /// 否则收起瞬间就是空白块在收缩）。
    @State private var mountedDisplayID: String?

    /// 参数块实测高度（含折叠头，SelectionRow 列表处于收起态）：内容变化时经
    /// onChange 自动重测；块内列表展开时内层 RevealHeight 每帧重排会驱动这里
    /// 逐帧上报，外层高度目标随之逐帧跟随（嵌套展开无二次跳变）。
    @State private var paramBlockHeight: CGFloat = 0

    /// 当前 hover 的屏（参数块折叠头 hover 时上报，布局图对应块点亮，
    /// 解决"不知道操作的是哪块屏"的歧义）。
    @State private var hoveredDisplayID: String?

    /// 是否有操作在后台执行（含预设回放）：禁用卡片区 + 显示进度条。
    private var busy: Bool { state.isOperating || presetManager.isApplying }

    /// 外接屏亮度中枢（v2）：@Observable 单例经 @State 桥接，body 内读 entries
    /// 自动追踪；写经 setPercent（本地乐观更新 + DDC 异步合并写）。
    @State private var brightness = BrightnessManager.shared

    var body: some View {
        VStack(spacing: BubbleMetrics.cardSpacing) {
            if state.displays.isEmpty {
                // 无显示器：只放一张提示卡。
                BubbleCard(title: l10n.t(.panelSectionDisplays)) {
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
                    // 亮度卡（v2 控制中心式，2026-10）：外接屏各一行滑条，常驻顶部
                    // ——亮度是合并 MonitorControl 后的最高频操作，零点击可达。
                    // 无外接 DDC 屏（单内置屏等）整卡不出现。
                    if !brightness.entries.isEmpty {
                        brightnessCard
                    }
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
        // 主题色板注入：面板全树取色来源（见 palette 注释）。
        .environment(\.panelPalette, palette)
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
        // 内容实测高度上报（窗口尺寸已钉死，这里只供 PanelController 计算
        // 外部点击的命中矩形）。挂 background 不占布局；宽度恒 380，只需高度。
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
                IndeterminateBar(accent: palette.solid)
                    // 呼吸边距计入：进度条保持压在卡片列上（与卡同宽），不越到透明带。
                    .padding(.horizontal, BubbleMetrics.shadowBreathingSide + 16)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        // 根视图尺寸：传入固定窗口高度时，把内容理想尺寸也钉死成「面板宽 ×
        // 窗口高」并以顶端对齐排布（这正是阻止 SwiftUI 自动改窗口的关键）；
        // 未传时保留旧的弹性顶端对齐行为（预览/测试场景）。
        .frame(width: windowHeight > 0 ? BubbleMetrics.hostContentWidth : nil,
               height: windowHeight > 0 ? windowHeight : nil,
               alignment: .top)
        .frame(maxWidth: windowHeight > 0 ? nil : .infinity,
               maxHeight: windowHeight > 0 ? nil : .infinity,
               alignment: .top)
    }

    // MARK: - 显示器枢纽卡

    /// 布局预览为中心的枢纽单元（2026-10 改版：主屏卡与排列卡并入）。
    ///
    /// - 多屏：背板气泡（等比布局图）+ 其下的**参数二级气泡**（2026-10-17 末版：
    ///   与一级气泡同宽（取消左右缩进）、同圆角 20、不再压叠——用常规卡片间距接在
    ///   枢纽卡下方，交互与观感都与一级气泡一致：hover 整泡放大、右上光源布光、
    ///   壁纸承接悬浮阴影）。点屏块是完整 toggle（选中+展开同生共死，再点已展开的
    ///   块即收起），未展开时无二级气泡、首屏清爽。「设为主屏」「镜像/扩展」在
    ///   非主屏参数块底部。
    /// - 单屏：无布局图（孤块无信息量）、也无背板层级可叠，参数常展开直接作为
    ///   枢纽卡主体——原「显示器调节」卡并入（单外接屏的极端场景同样走这里）。
    @ViewBuilder
    private var displayHubCard: some View {
        if state.displays.count > 1 {
            // spacing 0：参数二级气泡自带「上缘间隙 + 揭示高度」的完整占位
            // （见 secondaryParamBubble），收起态高度归零时这里不残留空档。
            VStack(spacing: 0) {
                // 分区标题（2026-10-17 用户要求）：与预设卡同款小型大写标签。
                BubbleCard(title: l10n.t(.panelSectionDisplays)) {
                    LayoutDiagram(
                        displays: state.displays,
                        selectedID: expandedDisplayID,
                        highlightedID: hoveredDisplayID,
                        onSelect: { d in toggleExpansion(for: d) }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: BubbleMetrics.diagramHeight)
                }
                // 参数二级气泡：常驻挂载（互斥由 expandedDisplayID 单值天然保证；
                // 收起动画期间内容保持挂载、块高动画回 0，见 secondaryParamBubble）。
                if let mounted = state.displays.first(where: { $0.id == mountedDisplayID }) {
                    secondaryParamBubble(mounted)
                }
            }
        } else if let sole = state.displays.first {
            // 单屏：无位置可排、无镜像对象，参数常展开（内容仅两三行，
            // 折叠反而多一次点击）。
            BubbleCard(title: l10n.t(.panelSectionDisplays)) {
                ArrangementRow(display: sole,
                               state: state,
                               label: sole.localizedTypeName(l10n: l10n),
                               showsPosition: false,
                               foldable: false,
                               isExpanded: true,
                               onToggle: {},
                               expandedRowID: $expandedRowID,
                               onHoverDisplay: { hovering in
                                   hoveredDisplayID = hovering ? sole.id : nil
                               })
            }
        }
    }

    /// 参数二级气泡本体（2026-10-17 末版，用户拍板「跟前面两个一级气泡一样」）：
    /// 主题浮面（浅色=最浅档、深色=其深色派生 L0.21）+ 同款圆角 20 / 描边 /
    /// 右上光源布光 / 壁纸承接悬浮阴影 / hover 整泡放大（底锚 1.02，与一级气泡
    /// 共用 BubbleHoverLiftModifier）；宽度不再缩进、取消上缘压叠——与枢纽卡之间
    /// 用常规卡片间距（间隙计入揭示高度，收起态不占位。
    /// 揭示/收起 = RevealHeightModifier（逐帧重排，范式见其注释）；折叠态高度 0 +
    /// allowsHitTesting(false) 构造性摘除整块命中区（frame(0)/clipped 只裁绘制
    /// 不裁命中测试）。
    /// 块高测量挂在气泡内容（含内边距）上：内容/内部列表变化自动重测，onChange
    /// 须裹动画——切屏/刷新的实高变化发生在点击事务后的独立更新轮，不裹则揭示
    /// 高度一步跳变（「切屏时面板长度瞬变」，普通展开走 onAppear 天然有动画）。
    private func secondaryParamBubble(_ mounted: DisplayInfo) -> some View {
        let gap = BubbleMetrics.secondaryBubbleGap
        return VStack(alignment: .leading, spacing: 10) {
            // 分区标题（2026-10-17 用户要求「每张气泡顶部都加像 presets 的标题」）：
            // 与一级气泡共用 BubbleSectionLabel，字号/字距/主题色完全一致。
            // leading 4 + 气泡 12 = 16，与 ArrangementRow 的行内容左缘对齐；
            // 垂直沿用二级气泡自己的 12pt 内边距（比一级气泡的 16 紧凑一档）。
            BubbleSectionLabel(text: l10n.t(.panelSectionParameters))
                .padding(.leading, 4)
            ArrangementRow(display: mounted,
                           state: state,
                           label: mounted.localizedTypeName(l10n: l10n),
                           showsPosition: !mounted.isMain,
                           foldable: true,
                           isExpanded: expandedDisplayID == mounted.id,
                           onToggle: { toggleExpansion(for: mounted) },
                           expandedRowID: $expandedRowID,
                           onHoverDisplay: { hovering in
                               hoveredDisplayID = hovering ? mounted.id : nil
                           })
        }
            .padding(BubbleMetrics.secondaryBubblePadding)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { paramBlockHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, newHeight in
                            withAnimation(panelReveal) { paramBlockHeight = newHeight }
                        }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: BubbleMetrics.cardCornerRadius, style: .continuous)
                    .fill(palette.surface ?? BubbleMetrics.surfaceFill(dark: colorScheme == .dark))
            )
            .overlay(
                // 纯装饰描边不摘命中区（全站范式；描边环在气泡内缩 12pt 的交互内容之外）。
                RoundedRectangle(cornerRadius: BubbleMetrics.cardCornerRadius, style: .continuous)
                    .stroke(palette.cardBorder
                                ?? Color.primary.opacity(BubbleMetrics.surfaceStrokeOpacity(dark: colorScheme == .dark)),
                            lineWidth: 1)
                    .allowsHitTesting(false)
            )
            // 与一级气泡同款的右上光源布光（圆角 20）。
            .bubbleLighting()
            // 上缘间隙也计入揭示帧：展开时先露出间距、气泡逐帧向下「抽出」；
            // 收起时连同间隙一起压回 0，枢纽卡与下一张卡之间不残留空档。
            .padding(.top, gap)
            .modifier(RevealHeightModifier(height: expandedDisplayID != nil ? paramBlockHeight + gap : 0))
            .allowsHitTesting(expandedDisplayID != nil)
            // 壁纸承接的统一悬浮阴影 + hover 浮起（与一级气泡同款，底锚缩放不振荡；
            // 阴影必须挂在揭示裁切之外，否则被 clipped 切出直线边界）。
            .bubbleFloatingShadow()
            .bubbleHoverLift()
    }

    /// 布局图点块/折叠头 toggle：展开/收起（✓ 角标由 expandedDisplayID 驱动，一处状态）。
    ///
    /// 两方向均经 RevealHeightModifier 逐帧高度揭示（2026-10-17 harness 实证定型；
    /// 旧「withAnimation + transition 插入/移除」是呈现层动画，高度桥拿不到逐帧值，
    /// 表现为窗口与布局一步跳变）。收起只清 expandedDisplayID——mountedDisplayID
    /// 保持挂载，块高动画回 0 的过程内容留在树上。切换屏时统一清空 expandedRowID
    /// ——旧块残留展开态会让下次挂载直接全展开。
    private func toggleExpansion(for d: DisplayInfo) {
        withAnimation(panelReveal) {
            expandedRowID = nil
            if expandedDisplayID == d.id {
                expandedDisplayID = nil
            } else {
                mountedDisplayID = d.id
                expandedDisplayID = d.id
            }
        }
    }

    // MARK: - 亮度卡（v2 控制中心式，2026-10）

    /// 外接屏亮度卡：每屏一行「图标圆框 + 名称 / ☀ 滑条 + 百分比」，常驻面板顶部
    /// （亮度是合并 MonitorControl 后的最高频操作，零点击可达）。
    /// 名称取注册表 ProductName（如 "DELL U2723QE"，比 displayplacer 的
    /// "27 inch external screen" 更可辨），缺失退本地化「外接显示器」。
    private var brightnessCard: some View {
        BubbleCard(title: l10n.t(.panelSectionBrightness)) {
            VStack(spacing: BubbleMetrics.rowSpacing) {
                ForEach(brightness.entries) { entry in
                    BrightnessRow(
                        name: entry.name.isEmpty ? l10n.t(.externalDisplay) : entry.name,
                        percent: entry.percent
                    ) { newValue in
                        brightness.setPercent(newValue, for: entry.id)
                    }
                }
            }
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
                                    .foregroundStyle(palette.solidText)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.solid, in: Capsule())
                            }
                            Image(systemName: "play.fill")
                                .font(.system(size: BubbleMetrics.fontMini))
                                .foregroundStyle(palette.solid)
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
    /// 悬浮反馈（2026-10-17 用户拍板「高光改放大」）：左气泡 = hover 按钮处轮廓局部
    /// 隆起（BulgingBubbleShape，与未隆起区 cos² 钟形平滑衔接）+ 图标微放大；
    /// 右气泡 = 整泡中心锚放大（QuitBubble）。两气泡不挂 bubbleHoverLift；
    /// 纯图标 + 原生 tooltip（.help 悬停停留后显示，文案走 L10n 随语言切换）。
    private var bottomToolbar: some View {
        HStack(spacing: BubbleMetrics.cardSpacing) {
            ToolsBubble(autoArrangeDisabled: state.displays.count < 2,
                        onAutoArrange: { state.autoArrange() },
                        onRefresh: { state.refresh() },
                        onSettings: {
                            // openSettings 会切 activation policy 并激活 App，先收面板防悬空。
                            PanelController.shared.close()
                            DockPolicyManager.shared.openSettings()
                        })
            QuitBubble {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

// MARK: - 面板私有小组件

/// 亮度卡单行：图标圆框 + 名称一行，☀ 滑条 + 百分比一行。
/// 滑条值直连 BrightnessManager（乐观本地更新 + DDC 异步合并写），拖动即时回显。
/// 主题分档：图标圆框与滑条填充 = 实心档（环境色板）。
private struct BrightnessRow: View {
    let name: String
    let percent: Double
    let onChange: (Double) -> Void

    @Environment(\.panelPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                DeviceIconBadge(isBuiltIn: false, active: true)
                Text(name)
                    .font(.system(size: BubbleMetrics.fontBody, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.system(size: BubbleMetrics.fontControl))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: Binding(
                    get: { percent },
                    set: { onChange($0) }
                ), in: 0...1)
                .tint(palette.solid)
                Text("\(Int((percent * 100).rounded()))%")
                    .font(.system(size: BubbleMetrics.fontCaption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 显示器类型图标圆框：圆形填充底 + 类型图标（内置屏 laptopcomputer / 外接屏 display）。
///
/// `active` 决定底框状态：active = 实心档填充 + 对比色图标（主题色板；青/绿/黄系
/// 深色模式实心档偏亮时自动换黑图标），非 active = 半透明主色暗态；图标颜色表达
/// 主从层级（亮度行/排列卡恒 active，仅作类型标识）。
private struct DeviceIconBadge: View {
    let isBuiltIn: Bool
    let active: Bool

    @Environment(\.panelPalette) private var palette

    var body: some View {
        Circle()
            .fill(active ? palette.solid : Color.primary.opacity(BubbleMetrics.deviceIconInactiveFillOpacity))
            .frame(width: BubbleMetrics.deviceIconDiameter, height: BubbleMetrics.deviceIconDiameter)
            .overlay(
                Image(systemName: isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: BubbleMetrics.deviceIconFontSize, weight: .semibold))
                    .foregroundStyle(active ? palette.solidText : Color.secondary)
            )
    }
}

/// 底部纯图标按钮：固定触区 34×26（fullWidth 时等宽均分、图标居中）；
/// 功能名称由与镜像/扩展同款的 HoverDwellTooltip 停留气泡呈现
/// （2026-10-17 由 .help 原生 tooltip 换成面板统一的自绘迷你气泡）。
///
/// 悬浮反馈为按钮级（区别于卡片整泡浮起）：图标 scaleEffect 微放大（仅图标本体，
/// 2D 仿射不栅格化、触区与布局不动，无边缘振荡问题）；reduceMotion 时无放大。
/// 2026-10-17 用户拍板：hover 的圆角底色高亮删除（「高光改放大」）——三连气泡的
/// 放大感由宿主 ToolsBubble 的局部隆起轮廓承担，退出气泡由 QuitBubble 整泡放大
/// 承担（两者 contentMagnifies=false，避免双重放大）。
/// `onHoverChange`：hover 进出上报宿主（驱动气泡隆起；禁用态不上报）。
private struct ToolbarIconButton: View {
    let tooltip: String
    let systemImage: String
    var fullWidth: Bool = false
    var disabled = false
    /// 图标本体是否随 hover 放大（退出气泡整泡放大时传 false）。
    var contentMagnifies = true
    /// hover 进出上报（宿主驱动气泡级放大；禁用态不触发）。
    var onHoverChange: (Bool) -> Void = { _ in }
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: BubbleMetrics.fontTitle))
                .foregroundStyle(.primary)
                .scaleEffect(isHovered && !reduceMotion && contentMagnifies
                             ? BubbleMetrics.toolbarIconHoverScale : 1)
                .frame(width: fullWidth ? nil : 34, height: 26)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        // 2026-10-17 用户要求：底部四个按钮也改用与镜像/扩展同款的停留解释气泡
        // （原 .help 原生 tooltip 文案不变，展示换成统一的自绘迷你气泡）。
        .modifier(HoverDwellTooltip(text: tooltip, icon: systemImage))
        .onHover { hovering in
            isHovered = hovering
            if !disabled { onHoverChange(hovering) }
        }
        .animation(BubbleMetrics.buttonHoverSpring, value: isHovered)
    }
}

/// 三连工具气泡的「局部隆起」轮廓（2026-10-17 用户拍板：hover 丝滑衔接）：
/// 以圆角矩形为基础，在归一化位置 `bulgeX` 处让顶/底边同步向外隆起
/// `bulgeHeight × amount`；隆起包络为 cos² 钟形（中心与边界斜率均为 0，C1 连续，
/// 放大区与未放大区之间无棱）。**整条顶/底边（含四角圆弧段）统一采样成折线**：
/// y = 圆角下坠量 ± 隆起量，隆起直接骑在圆角曲线上连续叠加——曾用「直边采样 +
/// 固定角弧」两段拼合，左右按钮的隆起延伸到角区时拼合点斜率不连续，放大区与
/// 最外侧之间出棱（2026-10-17 用户实测报告后重构，勿退回拼合式）。
/// 纯路径构建器（不带 animatableData）：动画由 BulgingBubbleModifier 每帧重建
/// 实例驱动——AnyShape 类型擦除会丢 Shape 自身的 animatableData 插值，逐帧重排
/// 必须挂在 ViewModifier 层（RevealHeightModifier 同款范式）。
private struct BulgingBubbleShape: Shape {
    var bulgeX: CGFloat
    var bulgeAmount: CGFloat
    var bulgeHeight: CGFloat
    /// 钟形归一化半宽（相对气泡宽度）。侧竖边会随端点处的 bump 同步伸缩，
    /// 无硬性上限；默认 0.17 下左右按钮的钟形在到达侧边前已自然衰减到 ≈0。
    var halfWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = min(BubbleMetrics.cardCornerRadius, w / 2, h / 2)

        // 圆角在顶边产生的下坠量（x<r / x>w-r 的圆弧段，直边段为 0）。
        func cornerDrop(_ x: CGFloat) -> CGFloat {
            if x < r {
                return r - sqrt(r * r - (r - x) * (r - x))
            }
            if x > w - r {
                let d = x - (w - r)
                return r - sqrt(r * r - d * d)
            }
            return 0
        }
        func bump(_ x: CGFloat) -> CGFloat {
            guard bulgeAmount > 0.001, halfWidth > 0 else { return 0 }
            let d = abs(x / w - bulgeX) / halfWidth
            guard d < 1 else { return 0 }
            let c = cos(.pi / 2 * d)
            return bulgeHeight * bulgeAmount * c * c
        }

        // 顶边 左→右（y = 圆角下坠 - 隆起，向上顶出为负方向）、底边 右→左
        // （y = h - 圆角下坠 + 隆起）。120 段折线在 20pt 圆角上的弦高 <0.04pt，
        // 与真圆弧不可分辨；无隆起时与普通圆角矩形逐点一致。
        let samples = 120
        var p = Path()
        p.move(to: CGPoint(x: 0, y: cornerDrop(0) - bump(0)))
        for i in 1...samples {
            let x = w * CGFloat(i) / CGFloat(samples)
            p.addLine(to: CGPoint(x: x, y: cornerDrop(x) - bump(x)))
        }
        // 右侧竖边（随端点处的 bump 伸缩，默认参数下 bump(w)≈0 即普通竖边）。
        p.addLine(to: CGPoint(x: w, y: h - r + bump(w)))
        for i in stride(from: samples - 1, through: 0, by: -1) {
            let x = w * CGFloat(i) / CGFloat(samples)
            p.addLine(to: CGPoint(x: x, y: h - cornerDrop(x) + bump(x)))
        }
        // 左侧竖边，回到顶边起点。
        p.addLine(to: CGPoint(x: 0, y: r - bump(0)))
        p.closeSubpath()
        return p
    }
}

/// 隆起气泡的背景/描边/布光/阴影驱动器：`bulgeX`/`bulgeAmount` 为 animatableData，
/// 插值期间每帧以中间值重建轮廓实例——填充、描边、布光、阴影随轮廓逐帧一致变形；
/// 光标滑到相邻按钮时山丘平滑滑过去（衔接在动画中也连续），进出则山丘起落。
private struct BulgingBubbleModifier: ViewModifier, Animatable {
    var bulgeX: CGFloat
    var bulgeAmount: CGFloat
    var bulgeHeight: CGFloat
    var halfWidth: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bulgeX, bulgeAmount) }
        set { bulgeX = newValue.first; bulgeAmount = newValue.second }
    }

    func body(content: Content) -> some View {
        let shape = BulgingBubbleShape(bulgeX: bulgeX, bulgeAmount: bulgeAmount,
                                       bulgeHeight: bulgeHeight, halfWidth: halfWidth)
        content
            // 与气泡统一材质（填充/描边随轮廓）+ 右上光源布光（随轮廓）+
            // 壁纸承接悬浮阴影（shadow 跟随合成轮廓，含隆起区）。
            .modifier(BubbleBackground(shape: AnyShape(shape)))
            .bubbleLighting(shape: shape)
            .bubbleFloatingShadow()
    }
}

/// 底部三连工具气泡（自动排列 | 刷新 | 设置）：hover 到某个按钮时气泡轮廓在该按钮
/// 中心处局部隆起（顶/底边同步外扩），与未隆起区经 cos² 钟形平滑衔接（2026-10-17
/// 用户拍板「只放大那一部分，衔接要丝滑、动画中也要体现」）。
/// 触区不随隆起变化（纯轮廓变形 + 图标 scaleEffect，均不参与布局/命中），
/// 构造性无 hover 振荡；reduceMotion 时不隆起。
private struct ToolsBubble: View {
    let autoArrangeDisabled: Bool
    let onAutoArrange: () -> Void
    let onRefresh: () -> Void
    let onSettings: () -> Void

    @State private var hoveredIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            toolButton(0, tooltip: L10n.shared.t(.autoArrange), systemImage: "wand.and.rays",
                       disabled: autoArrangeDisabled, action: onAutoArrange)
            Divider().frame(height: 18)
            toolButton(1, tooltip: L10n.shared.t(.refreshList), systemImage: "arrow.clockwise",
                       disabled: false, action: onRefresh)
            Divider().frame(height: 18)
            toolButton(2, tooltip: L10n.shared.t(.settingsTitle), systemImage: "gearshape",
                       disabled: false, action: onSettings)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .modifier(BulgingBubbleModifier(
            bulgeX: hoveredIndex.map { (CGFloat($0) + 0.5) / 3 } ?? 0.5,
            bulgeAmount: hoveredIndex != nil && !reduceMotion ? 1 : 0,
            bulgeHeight: BubbleMetrics.toolbarBulgeHeight,
            halfWidth: BubbleMetrics.toolbarBulgeHalfWidth))
        // 拉满剩余宽度。
        .frame(maxWidth: .infinity)
    }

    private func toolButton(_ index: Int, tooltip: String, systemImage: String,
                            disabled: Bool, action: @escaping () -> Void) -> some View {
        ToolbarIconButton(
            tooltip: tooltip,
            systemImage: systemImage,
            fullWidth: true,
            disabled: disabled,
            onHoverChange: { hovering in
                // 只认「本按钮退出」：滑向相邻按钮时旧 exit 可能晚于新 enter 到达，
                // 无条件清 nil 会把新按钮刚抬起的山丘抹掉（ScreenBlock 同款范式）。
                if hovering {
                    withAnimation(BubbleMetrics.buttonHoverSpring) { hoveredIndex = index }
                } else if hoveredIndex == index {
                    withAnimation(BubbleMetrics.buttonHoverSpring) { hoveredIndex = nil }
                }
            },
            action: action)
    }
}

/// 退出气泡：hover 整泡中心锚放大（2026-10-17 用户拍板「正常放大就行」）。
/// 中心锚只向外扩——hover 命中区随之外扩，进出两方向单调，无边缘振荡；
/// 按钮内图标级放大关闭（contentMagnifies=false，避免双重放大）。
private struct QuitBubble: View {
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToolbarIconButton(tooltip: L10n.shared.t(.quit), systemImage: "power",
                          contentMagnifies: false, action: action)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .modifier(BubbleBackground())
            .bubbleLighting()
            .bubbleFloatingShadow()
            .scaleEffect(isHovered && !reduceMotion ? BubbleMetrics.toolbarQuitHoverScale : 1,
                         anchor: .center)
            .onHover { isHovered = $0 }
            .animation(BubbleMetrics.buttonHoverSpring, value: isHovered)
    }
}

/// 控件侧的悬停计时者：停留 `tooltipDwell` 后把气泡交给独立浮窗
/// （FloatingTooltipPresenter）展示；移开/消失立即收起。
///
/// 2026-10-17 改版（用户拍板「气泡居中，即使超出整个菜单栏界面也没问题」）：
/// 气泡从控件 `overlay` 迁到独立无边框浮窗，构造性绕开两重裁剪——
/// ① 参数二级气泡整块包在 RevealHeightModifier 的 `.clipped()` 里，居中的
/// 气泡右半截会被气泡边界裁掉（旧版因此给镜像/扩展传 `.topTrailing`，也就是
/// 用户截图里「气泡偏左」的根因）；② 面板窗口只有 404pt 宽，贴右缘的控件居中后
/// 越过窗口的部分会被窗口边界裁掉。浮窗居中于控件正上方、可越过面板边界；
/// `ignoresMouseEvents` 纯展示，不挡任何交互。
/// 控件自身只做 dwell 计时与屏幕锚点上报（TooltipAnchorReader 背景探针）。
private struct HoverDwellTooltip: ViewModifier {
    let text: String
    /// 气泡前缀图标（通常复用按钮自身的 SF Symbol）。
    var icon: String = "info.circle"

    /// 计时代际 + 任务（引用盒：由 State 持有，可变但不触发重绘）。
    @State private var hoverState = TooltipHoverState()
    /// 屏幕锚点上报盒（背景 NSView 探针写弱引用）。
    @State private var anchorBox = TooltipAnchorBox()

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchorReader(box: anchorBox))
            .onHover { hovering in
                guard !text.isEmpty else { return }
                if hovering {
                    // 代际递增：迟到的旧任务即使执行，也会因代际不符而丢弃。
                    hoverState.generation += 1
                    let generation = hoverState.generation
                    let box = anchorBox
                    let state = hoverState
                    let task = DispatchWorkItem {
                        MainActor.assumeIsolated {
                            guard state.generation == generation,
                                  let anchor = box.screenRect else { return }
                            FloatingTooltipPresenter.shared.show(text: text, icon: icon, anchor: anchor)
                        }
                    }
                    hoverState.dwellTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + BubbleMetrics.tooltipDwell, execute: task)
                } else {
                    hoverState.generation += 1
                    hoverState.dwellTask?.cancel()
                    hoverState.dwellTask = nil
                    FloatingTooltipPresenter.shared.hide()
                }
            }
            .onDisappear {
                // 面板收起/视图移除时鼠标可能不再产生 exit 事件，主动收掉浮窗。
                hoverState.generation += 1
                hoverState.dwellTask?.cancel()
                hoverState.dwellTask = nil
                FloatingTooltipPresenter.shared.hide()
            }
    }
}

/// `HoverDwellTooltip` 的计时盒：代际号用于丢弃「移开后迟到」的 dwell 任务。
final class TooltipHoverState {
    var generation = 0
    var dwellTask: DispatchWorkItem?
}

// MARK: - 排列行（常驻左/右移 + 刷新率 + 分辨率）

/// 单个屏的排列行：可折叠标题行 + 位置分段控件、刷新率与分辨率「当前值 + 点击展开」选择。
/// `showsPosition` 为 false 时隐藏位置行（单内置屏无左右可排）；
/// `foldable` 为 true（多屏）时由外层 RevealHeightModifier 负责揭示/收起，
/// false（单内置屏）常展开。
/// 展开态与 toggle 回调上收到 PanelView（`isExpanded`/`onToggle`）；
/// `expandedRowID` 由 PanelView 持有（选项行互斥）。
private struct ArrangementRow: View {
    let display: DisplayInfo
    @ObservedObject var state: AppState
    let label: String
    var showsPosition: Bool = true
    /// 是否可折叠（多屏 true：标题行是折叠头；单内置屏 false：参数常展开）。
    var foldable: Bool = true
    /// 本屏参数组是否展开（不可折叠时恒 true）。只驱动折叠头视觉（概要副行显隐）；
    /// 揭示/收起动画由外层 RevealHeightModifier 承担。
    var isExpanded: Bool
    /// 折叠头点击回调（多屏 = PanelView.toggleExpansion；单屏空实现）。
    var onToggle: () -> Void
    /// 当前面板内展开的 SelectionRow 标识（互斥收起其他）。
    @Binding var expandedRowID: String?
    /// 标题行 hover 上报（布局图联动高亮该屏）。
    var onHoverDisplay: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            // 折叠头（两行式）：图标 + [名称行 / 参数概要副行]。
            // 名称与概要各占一行——挤一行时长名称 + 长参数会换行/截断（可读性差）；
            // 展开后副行淡出（详情行已展示同信息，不重复）。
            // 2026-10-17 用户拍板：右缘旋转 chevron 删除（展开态由概要副行显隐表达）。
            RowButton(action: onToggle) {
                HStack(spacing: 10) {
                    // 显示器类型图标统一套实心档圆形底框（同一组件，环境取色）。
                    DeviceIconBadge(isBuiltIn: display.isBuiltIn, active: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(.system(size: BubbleMetrics.fontBody))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
            //
            // 常驻渲染（2026-10-17 定型）：多屏的揭示/收起由外层 RevealHeightModifier
            // 逐帧高度动画承担（transition/条件插入是呈现层方案，高度桥拿不到逐帧值，
            // 已退役）；单屏（foldable=false）直接常显。
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
            // 2026-10-17 用户拍板：参数行铺满气泡两缘——标签贴左（与折叠头图标圆框
            // 左缘对齐，RowButton 内容同样有 4pt 内边距）、值与控件贴右，不再按标题
            // 文字缩进 38pt（旧值 = 圆框 28 + spacing 10）。
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .padding(.bottom, 6)
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

    /// 镜像/扩展胶囊对（2026-10-17 末版：**纯图标**）：主体=本屏（非主屏），
    /// 目标=当前主屏——与旧排列卡的 peer 推导等价（AppState.mirror 的操作主体
    /// 本就是非主屏，外接为主屏时主体即内置屏）。用户拍板去掉「镜像/扩展」二字
    /// ——三胶囊同行时两字仍被「设为主屏」挤压截断，图标-only 后两个胶囊变窄、
    /// 「设为主屏」拿到全部剩余宽度；功能说明改由 hover 停留的迷你气泡承担
    /// （镜像顺带给出对端屏名，扩展说明各屏独立排列）。图标-only 后文字消失，
    /// 必须补 accessibilityLabel，否则读屏只剩无标签按钮。
    private var mirrorExtendPills: some View {
        let isMirroring = state.isMirroring(display)
        let mainName = state.displays.first(where: { $0.isMain })?
            .localizedTypeName(l10n: L10n.shared) ?? ""
        let mirrorHint = L10n.shared.t(.mirrorActionHint, mainName)
        let extendHint = L10n.shared.t(.extendActionHint)

        return HStack(spacing: 8) {
            ActivePill(active: isMirroring, verticalPadding: 6, strokeWhenInactive: true) {
                // 固定 26×14 图标框：图标-only 胶囊仍保留足够的点击热区，
                // 两胶囊宽度一致（不随 SF Symbol 内禀宽度抖动）。
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: BubbleMetrics.fontControl))
                    .frame(width: 26, height: 14)
            }
            .asButton { state.mirror(display) }
            .accessibilityLabel(Text(mirrorHint))
            // 悬停停留补充气泡：镜像到对端屏（图标-only 后这是唯一的文字说明）。
            // 居中于按钮正上方（浮窗可越过面板边界，见 HoverDwellTooltip）。
            .modifier(HoverDwellTooltip(text: mirrorHint, icon: "rectangle.on.rectangle"))

            ActivePill(active: !isMirroring, verticalPadding: 6, strokeWhenInactive: true) {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: BubbleMetrics.fontControl))
                    .frame(width: 26, height: 14)
            }
            .asButton { state.unmirror(display) }
            .accessibilityLabel(Text(extendHint))
            .modifier(HoverDwellTooltip(text: extendHint, icon: "rectangle.dashed"))
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
    /// 面板级展开标识（互斥）：等于 rowID 时本行展开。
    @Binding var expandedRowID: String?
    let options: [Option]

    @Environment(\.panelPalette) private var palette

    private var expanded: Bool { expandedRowID == rowID }

    /// 选项列表自然高度（含 padding(3)），由内容 background 内的 GeometryReader 实测，
    /// 选项数变化时自动重测（frame 高度目标直接读它，无需手动同步）。
    @State private var listHeight: CGFloat = 0

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
            // 揭示走 RevealHeightModifier 逐帧高度动画（2026-10-17 harness 实证：
            // 内建 .frame(height:) 三元切换与 transition 一样是呈现层动画，高度桥
            // 拿不到逐帧值）；不加 opacity——收起动画期间内容须可见，clip 已负责
            // 隐藏溢出。
            ScrollView {
                VStack(spacing: BubbleMetrics.rowSpacing) {
                    ForEach(options.indices, id: \.self) { idx in
                        optionRow(options[idx])
                    }
                }
                .padding(3)
                .background(
                    // 测自然高度：挂在内容（含 padding）的 background 上。onChange
                    // 裹动画：选项数变化（刷新后）落在事务外的独立更新轮，不裹则
                    // 揭示高度一步跳变（与参数块切屏同源的机制，见 displayHubCard）。
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { listHeight = geo.size.height }
                            .onChange(of: geo.size.height) { _, newHeight in
                                withAnimation(panelReveal) { listHeight = newHeight }
                            }
                    }
                )
            }
            .modifier(RevealHeightModifier(height: expanded ? listVisibleHeight : 0))
            .background(
                RoundedRectangle(cornerRadius: BubbleMetrics.hoverCornerRadius)
                    .fill(Color.secondary.opacity(0.08))
            )
            // 折叠态摘除整棵列表的命中区（含 hover）：frame(0)/clipped 只裁「绘制」
            // 不裁「命中测试」，折叠列表的选项行曾以自然高度在卡下方形成幽灵命中区，
            // 指针落在面板未遮挡的缝隙（工具栏两气泡之间/上下空带）时命中幽灵行、
            // 沿祖先链触发卡片级 hover 浮起（2026-09「缝隙触发显示器调节卡悬浮」bug）。
            // 状态翻转即恢复命中，与高度动画无时序耦合。
            .allowsHitTesting(expanded)
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
                    .foregroundStyle(palette.solid)
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
/// 交互：悬停块体点亮（不透明卡底 + 高亮档淡色 + 描边 + 轻放大，经 zIndex
/// 置顶覆盖邻块共享边）；点击屏块回调 onSelect（选中态 ✓ 角标[实心档] + 加粗
/// 描边，由宿主 toggle 展开参数块）；highlightedID（二级气泡折叠头 hover 联动）
/// 与块直悬同等点亮。
private struct LayoutDiagram: View {
    let displays: [DisplayInfo]
    var selectedID: String? = nil
    var highlightedID: String? = nil
    var onSelect: ((DisplayInfo) -> Void)? = nil

    /// 当前直悬屏块 id（驱动 zIndex 置顶）：物理相邻的屏块缩放后共享边会压线，
    /// 悬停块抬到最上层绘制，「压线」变「覆盖」，无重合歧义（2026-10-17）。
    @State private var hoveredBlockID: String?

    var body: some View {
        GeometryReader { proxy in
            if let layout = computeLayout(into: proxy.size) {
                ZStack {
                    ForEach(layout.rects, id: \.id) { item in
                        screenBlock(item)
                            // 悬停块置顶。zIndex 施加在 ForEach 包装层、不进 ScreenBlock
                            // 的手势链——其内部 .position 挂链尾的硬约束不受影响。
                            .zIndex(item.id == hoveredBlockID ? 1 : 0)
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
                    isSelected: item.id == selectedID,
                    isHighlighted: item.id == highlightedID,
                    onHoverChange: { hovering in
                        // 只认「本块退出」才清空：指针滑向相邻块时，旧块的 exit 事件
                        // 可能晚于新块的 enter 到达，无条件置 nil 会把新块刚抬起的
                        // 层级抹掉（相邻块恰是本修复的目标场景）。
                        if hovering {
                            hoveredBlockID = item.id
                        } else if hoveredBlockID == item.id {
                            hoveredBlockID = nil
                        }
                    },
                    onSelect: { onSelect?(item.display) })
    }

    /// 单个屏块：屏名常驻居中（fontCaption，超长中截）；悬停点亮（**不透明**
    /// 卡底 + 高亮档淡色 + 2pt 描边 + 轻投影 + 中心锚轻微放大 1.04，经 zIndex
    /// 置顶覆盖邻块共享边——不透明底是覆盖成立的前提，半透明底会让邻块描边透出）；
    /// 静止态主从由描边深浅区分（主屏 secondary 0.75 / 非主屏 0.4）；
    /// 选中态 ✓ 角标（实心档）+ 高亮档描边。
    private struct ScreenBlock: View {
        let item: PlacedRect
        let isSelected: Bool
        let isHighlighted: Bool
        /// hover 上报宿主（zIndex 置顶驱动），与内部 isHovered 视觉态同源。
        var onHoverChange: (Bool) -> Void = { _ in }
        let onSelect: () -> Void

        @State private var isHovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.panelPalette) private var palette

        /// 点亮态：块直悬或二级气泡折叠头 hover 联动（highlightedID）任一成立。
        private var isLit: Bool { isHovered || isHighlighted }

        var body: some View {
            let stroke: Color = (isSelected || isLit) ? palette.highlight
                : Color.secondary.opacity(item.display.isMain ? 0.75 : 0.4)
            let lineWidth: CGFloat = (isSelected || isLit) ? 2 : 1
            // 点亮态底色必须**不透明**：悬停块放大后要覆盖邻块的共享描边，半透明底
            // 盖不住——邻块描边会透出来，zIndex 置顶形同虚设（2026-10-17 用户报告
            // 「覆盖无效」的真因）。不透明底 = 浮层表面色，其上再叠高亮档淡色，
            // 配合 zIndex 让放大块完整遮住压住的邻块边缘。
            // 浅色主题卡的表面 = 派生卡底（近白淡染）；深色维持原卡色（C 方案不动）。
            let cardFill: Color = colorScheme == .light
                ? (palette.surface ?? BubbleMetrics.surfaceFill(dark: false))
                : BubbleMetrics.surfaceFill(dark: true)

            return RoundedRectangle(cornerRadius: 4)
                .fill(isLit ? cardFill : Color.gray.opacity(0.08))
                .overlay(
                    // 以下三个 overlay 都是纯装饰层：摘除命中区（全站范式），手势
                    // 挂在最外层链尾、命中期望 = 块矩形（见下方 contentShape）。
                    RoundedRectangle(cornerRadius: 4)
                        .fill(palette.highlight.opacity(isLit ? palette.litOpacity : 0))
                        .allowsHitTesting(false)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(stroke, lineWidth: lineWidth)
                        .allowsHitTesting(false)
                )
                .overlay(alignment: .topTrailing) {
                    // 选中角标（点击布局图中的屏块后出现，再次点击消失）
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(palette.solid)
                            .padding(2)
                            .allowsHitTesting(false)
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
                // 点亮时轻投影：放大块「压在」邻块之上的深度线索（阴影随 zIndex
                // 一同置顶、落在邻块上；2D 仿射）。
                .shadow(color: .black.opacity(isLit ? 0.16 : 0), radius: 4, x: 0, y: 2)
                // 悬停轻放大：中心锚对称缩放，进出两方向单调，指针不会在块缘
                // 振荡（hover 浮起振荡修复的构造性保证）；2D 仿射不栅格化。
                .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1, anchor: .center)
                .animation(BubbleMetrics.buttonHoverSpring, value: isHovered)
                .onTapGesture { onSelect() }
                .onHover { hovering in
                    isHovered = hovering
                    onHoverChange(hovering)
                }
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
