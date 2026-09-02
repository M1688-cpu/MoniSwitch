import SwiftUI
import AppKit

/// 设置窗口：HStack 手拼「边栏 + 竖线 + 内容区」布局。
///
/// 不用 NavigationSplitView：它在 macOS 上对 sidebar 列强制施加圆角剪裁 + 独立面板感
///（透明标题栏下尤为明显），靠 modifier 调不掉——那是边栏"像悬浮圆角气泡"的根因。
/// 改用 HStack：边栏(240pt) + 1pt 深灰竖线 + 内容区，三者平铺无圆角，
/// 边栏与内容区同用 `.regularMaterial` 融为一体，仅由中间一条竖线分隔。
///
/// 标题：去掉旧的 NSToolbar 居中"设置"白条（见 DockPolicyManager），
/// 改由右侧内容区顶部的 `DetailHeader`（渐变图标 + 已选功能名）承担标题，
/// 跟随 selectedTab 动态切换。标题经 safeAreaInset 悬浮于滚动内容之上：
/// 静止时无背景（观感与旧固定标题一致）；滚动时内容从标题底下穿过，
/// `HeaderFadeBackdrop` 渐入「顶实底虚」的 thinMaterial 渐变毛玻璃。
///
/// 视觉风格：边栏用 ScrollView+VStack 自绘行（不用原生 List(.sidebar)，那会带白色
/// vibrancy 背景 + 强调色选中胶囊），选中态深灰圆角、未选图标深灰（medium 字重）、
/// 选中图标跟随系统强调色。
/// 各分组用圆角卡片（BubbleBackground：不透明填充——浅色纯白 / 深色卡片色 + 淡描边 + 阴影），
/// 头部图标用无背景纯图标（PlainIcon，深灰自适应），与正文文字层次一致、视觉极简。
/// 圆角刻度统一引用 `BubbleMetrics`，与菜单栏面板同步。
///
/// 边栏宽度锁死 240pt，不可拖拽。
/// 右侧内容区按选中标签直接切换。
struct SettingsView: View {

    enum Tab: String, CaseIterable, Identifiable, Hashable {
        case general, presets, about
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .presets: return "square.stack"
            case .about:   return "info.circle"
            }
        }

        /// 右侧内容区顶部标题用的本地化文案 key（跟随选中标签动态切换）。
        var titleKey: TextKey {
            switch self {
            case .general: return .tabGeneral
            case .presets: return .tabPresets
            case .about:   return .tabAbout
            }
        }
    }

    @EnvironmentObject private var l10n: L10n
    @State private var selectedTab: Tab? = .general
    /// 内容区已向上滚出的距离（各 tab 的 ScrollOffsetReader 上报，驱动顶部毛玻璃渐入）。
    @State private var contentScrollOffset: CGFloat = 0

    var body: some View {
        // HStack 手拼「边栏 + 竖线 + 内容区」：放弃 NavigationSplitView——它在 macOS 上对
        // sidebar 列强制施加圆角剪裁 + 独立面板感（透明标题栏下尤为明显），靠 modifier
        // 调不掉，正是边栏"像悬浮圆角气泡"的根因。HStack 三者平铺无圆角，仅由中间竖线分隔。
        HStack(spacing: 0) {
            // —— 左侧边栏 ——
            // 不用 List(.sidebar)：它自带白色 vibrancy 背景与强调色选中胶囊，
            // 会把边栏变成"悬浮白气泡"。改用 ScrollView+VStack 自绘行，背景与内容区同材质，
            // 选中态自绘深灰圆角，整窗融为一体（仅留中间一条深灰竖线）。
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Tab.allCases) { tab in
                        SidebarRow(
                            title: l10n.t(tab.titleKey),
                            systemImage: tab.systemImage,
                            isSelected: selectedTab == tab
                        )
                        .onTapGesture { selectedTab = tab }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            // 与右侧内容区完全相同的 regularMaterial，边栏不再单独发白。锁死宽度 240pt。
            .frame(width: 240)
            .background(.regularMaterial)

            // —— 中间一条从上到下的深灰竖线：边栏与内容区的唯一分界 ——
            // 0.22 比 0.12 明显加深，浅色下呈清晰深灰、深色下自适应变浅灰，两端都不刺眼。
            // 仅竖线 ignore 顶部安全区：让竖线一通到顶（无白色断口），但边栏/内容区保留正常
            // 顶部留白、避开红绿灯按钮（红绿灯 x 范围落在 240pt 边栏内，边栏不顶到标题栏即不挡）。
            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)

            // —— 右侧内容区：标题经 safeAreaInset 悬浮于滚动内容之上 ——
            // 静止时内容从标题下方开始（与旧 VStack「固定标题+下方滚动」布局一致）；
            // 滚动时卡片滑入标题底下，HeaderFadeBackdrop 按滚动距离渐入渐变毛玻璃。
            Group {
                switch selectedTab {
                case .general: GeneralTab(scrollOffset: $contentScrollOffset)
                case .presets: PresetsTab(scrollOffset: $contentScrollOffset)
                case .about:   AboutTab(scrollOffset: $contentScrollOffset)
                case .none:    GeneralTab(scrollOffset: $contentScrollOffset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                DetailHeader(tab: selectedTab ?? .general)
                    .background {
                        // 毛玻璃层：底边尾巴伸进内容区 + 向上贯通标题栏区到窗口顶。
                        HeaderFadeBackdrop(scrollOffset: contentScrollOffset)
                            .padding(.bottom, -BubbleMetrics.headerBlurFadeTail)
                            .ignoresSafeArea(.container, edges: .top)
                    }
            }
            // 内容区变灰：.regularMaterial 浅色淡灰、深色深灰，自动适配。
            .background(.regularMaterial)
        }
        // 不在根视图加 .tint(Color(NSColor.controlAccentColor))：SwiftUI 控件默认就跟随系统
        // 强调色，这条桥接 AppKit 动态色的 tint 是冗余的；且 macOS 15 实机上它会让下拉框箭头
        // 胶囊实况渲染成红色（2026-08 实测，系统强调色并非红；离屏渲染不可复现，属实况合成
        // 路径的桥接动态色解析失败）。删掉后控件依旧跟随系统强调色，显式用 BrandColor.accent
        // 的地方（边栏选中图标/hover 高亮/菜单栏面板）不受影响。
        // 注意：不在根视图加 .ignoresSafeArea(.top)——那会让整个边栏(240pt，覆盖红绿灯 x 范围)
        // 和内容区都顶进标题栏、压住红绿灯。仅竖线 Rectangle 单独 ignore（见上），实现
        // 「竖线一通到顶 + 内容避开红绿灯」。HeaderFadeBackdrop 的 ignore 也只作用于内容列
        // 的背景层（红绿灯在边栏 x 范围内，不受影响）。配合 fullSizeContentView + titlebarAppearsTransparent。
    }
}

// MARK: - 共享视觉组件

/// 右侧内容区顶部标题：纯图标 + 已选功能名（跟随 selectedTab 动态切换）。
/// 取代旧的 NSToolbar 居中"设置"白条——透明标题栏下由右侧内容区承担标题职责。
/// 顶部 padding 避开红绿灯按钮区。
private struct DetailHeader: View {
    @EnvironmentObject private var l10n: L10n
    let tab: SettingsView.Tab

    var body: some View {
        HStack(spacing: 10) {
            PlainIcon(systemImage: tab.systemImage, size: 22)
            Text(l10n.t(tab.titleKey))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
        }
        // 透明标题栏下 safe area 已自然避让红绿灯，顶部无需再手动留大空档；
        // 仅留小呼吸量，让标题紧贴顶部、整页内容上移。
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}

/// 顶部渐变毛玻璃：滚动时从透明渐入实心（thinMaterial），底边在尾巴长度内渐隐到透明，
/// 内容从玻璃底边穿过时无硬切线。静止（scrollOffset=0）时全透明，观感与无背景一致。
/// 由 DetailHeader 的 .background 承载：负 padding 把尾巴伸进内容区、
/// ignoresSafeArea 把玻璃顶到窗口顶（滚动内容滑到最顶时也在玻璃之下）。
private struct HeaderFadeBackdrop: View {
    let scrollOffset: CGFloat

    var body: some View {
        GeometryReader { geo in
            // 渐隐起点：扣除尾巴后的位置（0~1 比例），尾巴区间内 black → clear。
            let fadeStart = max(0, 1 - BubbleMetrics.headerBlurFadeTail / max(geo.size.height, 1))
            Rectangle()
                .fill(.thinMaterial)
                .opacity(min(1, scrollOffset / BubbleMetrics.headerBlurRamp))
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: fadeStart),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        // 纯视觉层，不拦截内容区的点击/滚轮。
        .allowsHitTesting(false)
    }
}

// MARK: - 滚动偏移读取

/// 滚动偏移探针：铺在 ScrollView 内容的 background 上，沿 superview 链找到外层
/// NSClipView，通过 bounds 变更通知把「已向上滚出多少 pt」回写 Binding。
///
/// 为什么不用 GeometryReader+PreferenceKey：macOS 13 没有 onScrollGeometryChange，
/// 几何探针读到的静止偏移 = 标题栏+悬浮头的安全区 inset，还得另找参照物归零；
/// NSClipView 的 bounds 原点与内容 inset 无关，静止恒 0，滚多少是多少。
/// 挂载即上报当前值：切换 tab 时新探针自动把偏移复位，无残留。
///
/// 注意必须挂在滚动内容上（如 VStack 的 .background），不能挂 ScrollView 外壳——
/// 外壳的 background 不是 NSClipView 的子孙，superview 链走不到滚动容器。
private struct ScrollOffsetReader: NSViewRepresentable {
    @Binding var offset: CGFloat

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onScroll = { value in offset = value }
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        // binding 可能因视图重建而变化，每次刷新闭包
        view.onScroll = { value in offset = value }
    }

    final class ProbeView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        private var observedClip: NSClipView?
        private var installAttempts = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installAttempts = 0
                // 挂载当帧 superview 链可能尚未接到 NSScrollView，退一个 runloop 再找
                DispatchQueue.main.async { self.install() }
            } else {
                uninstall()
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        private func install() {
            guard observedClip == nil else {
                report()
                return
            }
            guard let clip = sequence(first: self, next: { $0.superview })
                .compactMap({ $0 as? NSClipView })
                .first else {
                // SwiftUI 层级就绪前最多重试 60 帧（约 1s），避免永久空转
                installAttempts += 1
                if installAttempts < 60 {
                    DispatchQueue.main.async { self.install() }
                }
                return
            }
            observedClip = clip
            // 当前 SDK 属性名为复数（旧 SDK 单数），NSClipView 默认即开启，这里显式兜底
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(clipBoundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
            report()   // 挂载即上报：tab 切换后偏移自动复位
        }

        private func uninstall() {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: observedClip
            )
            observedClip = nil
        }

        @objc private func clipBoundsDidChange(_ notification: Notification) {
            report()
        }

        private func report() {
            guard let clip = observedClip else { return }
            // 顶部弹性过冲时 origin.y 可为负，钳到 0（玻璃只随正向滚动渐入）
            onScroll?(max(0, clip.bounds.origin.y))
        }
    }
}

/// 同色系渐变圆角图标方块：跟随系统强调色（亮端 0.85 → 深端 1.0）。
/// 仅关于页 dev 模式图标回退时使用；边栏/卡片头部已改用无背景纯图标（PlainIcon）。
struct GradientIconSquare: View {
    let systemImage: String
    var size: CGFloat = 22
    var cornerRadius: CGFloat = BubbleMetrics.iconBadgeCornerRadius
    /// 自定义渐变色；nil 时用系统强调色蓝渐变。
    var colors: [Color]? = nil

    private var gradientColors: [Color] {
        // 自定义色按原样使用（不叠 0.85 透明，保持指定色准确）；默认蓝渐变保持亮端 0.85。
        colors ?? [BrandColor.accent.opacity(0.85), BrandColor.accent]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// 无背景纯图标：用于内容区标题/卡片头部，对齐 macOS 系统设置的分块标题风格。
/// 与 GradientIconSquare 的区别：去掉彩色方块背景，只渲染 SF Symbol，颜色用 .secondary
/// （深灰、与副标题同色、浅深色自适应）。与正文文字层次一致，视觉极简统一。
struct PlainIcon: View {
    let systemImage: String
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

/// 气泡背景修饰器：不透明填充 + 自适应淡描边。
///
/// 改为不透明后不再涉及 material vibrancy（之前用 thinMaterial 时必须用 shape-style 重载、
/// 且 `.foregroundStyle(.primary)` 依赖 material 上下文，曾导致菜单栏字体变黑的回归）。
/// 现在直接用纯色填充：浅色=纯白，深色=BubbleMetrics.bubbleDarkFill（接近系统卡片色）。
/// `.foregroundStyle(.primary)` 在不透明背景下仍能正常自适应（浅=黑字、深=白字），无需特殊处理。
///
/// 设置卡片、菜单栏 BubbleCard/bottomToolbar 共用。
struct BubbleBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: BubbleMetrics.cardCornerRadius)
        // 浅色纯白、深色用固定卡片色（避免纯白在深色窗口上刺眼）。
        let fill: Color = colorScheme == .light ? .white : BubbleMetrics.bubbleDarkFill
        // 描边：不透明卡片在窗口上需要稍清晰边界，浅色用 0.10，深色用 0.18 提亮边缘。
        let strokeOpacity: Double = colorScheme == .light ? 0.10 : 0.18
        return content
            .background(fill, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1))
    }
}

/// 设置分组卡片：头部（纯图标 + 标题）+ 自定义内容。
/// 视觉与菜单栏 BubbleCard 同源：BubbleBackground（不透明填充）+ 悬浮阴影。
struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                PlainIcon(systemImage: systemImage, size: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            content
        }
        .padding(16)
        .modifier(BubbleBackground())
        // 悬浮阴影略抬升，增强气泡感（与菜单栏 BubbleCard 同款）。
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
    }
}

/// 边栏行：纯 SF Symbol 图标（无方块背景）+ 标题。对齐 macOS 系统设置侧栏风格——
/// 选中页图标用系统强调色、未选用次要灰；选中态再叠半透明深灰圆角底。
private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // 纯 glyph：去掉原彩色方块，保留 24pt 列宽以免文字起点跳动；
            // 选中=强调色（跟随右侧控件），未选=比 .secondary 深一档的灰 + medium 字重
            //（.secondary 在 16pt regular 下笔画太细、与材质背景融合看不清）。
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSelected ? BrandColor.accent : Color.primary.opacity(0.78))
                .frame(width: 24, height: 24)
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        // 选中态：比灰底深一档的半透明黑圆角，深浅色自适应。
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(BubbleMetrics.sidebarSelectionOpacity))
                }
            }
        )
        // 内容形状覆盖整行，点击命中区更大。
        .contentShape(Rectangle())
    }
}

// MARK: - 控件配色

private extension View {
    /// 菜单样式下拉框的中性灰 tint：箭头指示胶囊渲染为灰底白箭头。
    ///
    /// macOS 15 实机上，设置窗口曾在根级传过桥接 AppKit 动态色的 tint
    ///（`Color(NSColor.controlAccentColor)`），下拉框箭头胶囊被实况渲染成红色
    ///（2026-08 实测，15.5 SDK 编译亦出现；离屏渲染不可复现，属实况合成路径的
    /// 桥接动态色解析失败）。此处刻意用 SwiftUI 静态灰 `Color.gray`
    ///（非桥接动态色，深浅外观恒定），避开同类桥接色风险；
    /// 若胶囊不跟随 tint 也无副作用（回落系统默认样式）。
    func menuPickerNeutralTint() -> some View {
        tint(Color.gray)
    }
}

// MARK: - 通用标签

struct GeneralTab: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings
    /// 内容滚动偏移，上报给 SettingsView 驱动顶部毛玻璃渐入。
    @Binding var scrollOffset: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // —— 语言 ——
                SettingsCard(title: l10n.t(.groupLanguage), systemImage: "globe") {
                    settingRow(l10n.t(.languageLabel)) {
                        Picker("", selection: $l10n.lang) {
                            ForEach(Language.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .menuPickerNeutralTint()
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }

                // —— 启动 ——
                SettingsCard(title: l10n.t(.groupStartup), systemImage: "power") {
                    settingRow(l10n.t(.launchAtLogin)) {
                        Toggle("", isOn: $settings.launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                // —— 显示器 ——
                SettingsCard(title: l10n.t(.groupDisplays), systemImage: "display") {
                    VStack(spacing: 0) {
                        settingRow(l10n.t(.autoRefresh)) {
                            Toggle("", isOn: $settings.autoRefreshEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        // 刷新间隔：仅当自动刷新开启时显示
                        if settings.autoRefreshEnabled {
                            Divider().padding(.vertical, 6)
                            settingRow(l10n.t(.refreshInterval)) {
                                Picker("", selection: $settings.autoRefreshInterval) {
                                    ForEach(AppSettings.refreshIntervalOptions, id: \.self) { sec in
                                        Text(l10n.t(.intervalSeconds, sec)).tag(sec)
                                    }
                                }
                                .pickerStyle(.menu)
                                .menuPickerNeutralTint()
                                .labelsHidden()
                                .frame(width: 150)
                            }
                        }
                        Divider().padding(.vertical, 6)
                        settingRow(l10n.t(.detailedMenuInfo)) {
                            Toggle("", isOn: $settings.detailedMenuInfo)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                // —— 通知 ——
                SettingsCard(title: l10n.t(.groupNotifications), systemImage: "bell") {
                    settingRow(l10n.t(.notifyOnSwitch)) {
                        Toggle("", isOn: $settings.notificationsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            // 探针挂在滚动内容上（ScrollView 外壳的 background 不是 NSClipView 子孙）
            .background(ScrollOffsetReader(offset: $scrollOffset))
        }
    }

    /// 统一的设置行：左侧标签 + 右侧控件，无每行小图标（图标由卡片头部承担）。
    @ViewBuilder
    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
            Spacer()
            control()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 关于标签

struct AboutTab: View {

    @EnvironmentObject private var l10n: L10n
    /// 内容滚动偏移上报（关于页内容不满屏不可滚，探针仅用于切 tab 时把毛玻璃复位）。
    @Binding var scrollOffset: CGFloat

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    /// 加载真实 App 图标用于关于页。
    /// 打包后从 Bundle.main 取 AppIcon.icns；dev 模式下回退到源码目录 Resources/AppIcon.icns。
    private func loadAppIcon() -> NSImage? {
        // 1. 打包后的 App：Bundle.main 里按 Info.plist 的 CFBundleIconFile 取
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        if Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil,
           let icon = NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") {
            return icon
        }
        // 2. dev 模式：从源码目录 Resources/AppIcon.icns 读
        let devPath = "Resources/AppIcon.icns"
        if FileManager.default.fileExists(atPath: devPath) {
            return NSImage(contentsOfFile: devPath)
        }
        return nil
    }

    var body: some View {
        // 包进 ScrollView 与其他两个 tab 结构一致：内容从悬浮标题下方开始；
        // 关于页内容不满一屏不可滚，观感与旧固定布局相同。不包的话顶部图标会顶进标题区。
        ScrollView {
            VStack(spacing: 16) {
                // 关于页图标：优先用真实 App 图标（打包后从 Bundle 取）；
                // dev 模式下 Bundle.main 取不到则回退到与边栏同款的渐变方块占位。
                if let appIcon = loadAppIcon() {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .padding(.top, 16)
                } else {
                    GradientIconSquare(systemImage: "rectangle.on.rectangle", size: 96, cornerRadius: BubbleMetrics.iconBadgeCornerRadius)
                        .padding(.top, 16)
                }

                Text("MoniSwitch")
                    .font(.system(size: 22, weight: .bold))

                Text(l10n.t(.appDescription))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Text("\(l10n.t(.versionLabel)) \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .background(ScrollOffsetReader(offset: $scrollOffset))
        }
    }
}

// MARK: - 预设标签

struct PresetsTab: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var presetManager: PresetManager
    /// 内容滚动偏移，上报给 SettingsView 驱动顶部毛玻璃渐入。
    @Binding var scrollOffset: CGFloat

    /// 新预设名称输入框的文本。
    @State private var newName: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // —— 保存当前布局 / 已保存预设，合并在同一张卡片 ——
                SettingsCard(title: l10n.t(.groupPresets), systemImage: "square.stack") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.t(.presetCaptureHint))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            TextField(l10n.t(.presetNamePlaceholder), text: $newName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(capture)

                            Button(l10n.t(.presetCaptureButton), action: capture)
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !presetManager.presets.isEmpty {
                            Divider().padding(.vertical, 2)
                            ForEach(presetManager.presets) { preset in
                                PresetRow(preset: preset)
                            }
                        } else {
                            Divider().padding(.vertical, 2)
                            Text(l10n.t(.presetEmptyHint))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            // 探针挂在滚动内容上（ScrollView 外壳的 background 不是 NSClipView 子孙）
            .background(ScrollOffsetReader(offset: $scrollOffset))
        }
    }

    /// 保存当前布局：校验名称非空后调 captureCurrent，并清空输入框。
    private func capture() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if presetManager.captureCurrent(name: trimmed) != nil {
            newName = ""
        }
    }
}

/// 单个预设行：名称 + 应用按钮 + 删除按钮，外加一行全局快捷键绑定区。
struct PresetRow: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var presetManager: PresetManager
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    let preset: Preset

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：图标 + 名称 + 应用 + 删除
            HStack(spacing: 10) {
                Image(systemName: "square.stack")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(preset.name)
                    .font(.system(size: 13))

                Spacer()

                Button(l10n.t(.presetApplyButton)) {
                    presetManager.apply(preset)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(l10n.t(.presetDeleteButton), role: .destructive) {
                    presetManager.delete(preset)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // 第二行：全局快捷键绑定区。
            //   - 录制中：按钮文案切为"按下组合键…(Esc 取消)"
            //   - 已绑定：显示当前组合 + [清除]
            //   - 未绑定：显示"未设置" + [录制]
            hotkeyRow
        }
        .padding(.vertical, 6)
    }

    /// 快捷键绑定行。
    @ViewBuilder
    private var hotkeyRow: some View {
        let isThisRecording = hotkeyManager.isRecording && hotkeyManager.recordingFor == preset.id

        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(l10n.t(.hotkeyLabel))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if isThisRecording {
                // 录制中：提示文案占位,再次点击即取消。
                Button {
                    hotkeyManager.cancelRecording()
                } label: {
                    Text(l10n.t(.hotkeyRecording))
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } else if let binding = preset.hotkey, !binding.isEmpty {
                // 已绑定：显示组合字符串。
                Text(hotkeyManager.displayString(for: binding))
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: BubbleMetrics.keycapCornerRadius))
            } else {
                // 未绑定。
                Text(l10n.t(.hotkeyNone))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isThisRecording {
                Button(l10n.t(.hotkeyRecordCancel)) {
                    hotkeyManager.cancelRecording()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if preset.hotkey != nil {
                Button(l10n.t(.hotkeyRecord)) {
                    hotkeyManager.startRecording(for: preset.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(l10n.t(.hotkeyClear), role: .destructive) {
                    presetManager.setHotkey(nil, for: preset)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(l10n.t(.hotkeyRecord)) {
                    hotkeyManager.startRecording(for: preset.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.leading, 28)   // 与第一行名称对齐(图标 18 + spacing 10)
    }
}
