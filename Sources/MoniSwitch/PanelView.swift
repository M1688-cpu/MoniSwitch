import SwiftUI
import AppKit

/// 强调色：跟随 macOS 系统强调色（系统设置 > 外观 > 强调色）。
///
/// 不再使用自定义品牌蓝：改读 `NSColor.controlAccentColor`（动态色），
/// 用户在「系统设置 > 外观」切换强调色时本界面实时刷新。
/// 项目约定「纯 SPM、无 xcassets」，故不引入 AccentColor.colorset，直接桥接 AppKit 动态色。
enum BrandColor {
    static var accent: Color { Color(NSColor.controlAccentColor) }
}

/// 菜单栏下拉面板（`.window` 样式）：按参考图做成分栏「气泡卡片」。
///
/// 与原 `.menu` 样式相比，这里是一块可完全自定义的 SwiftUI 视图：
///   - 每个功能分栏是一张圆角气泡卡片（`BubbleCard`）；
///   - 强调色统一品牌蓝（取自 App 图标，见 BrandColor）；
///   - 所有切换操作复用 `AppState` / `PresetManager` 的现有逻辑，只改触发控件形态。
///
/// 卡片顺序：主显示器 → 排列与镜像 → 布局预设 → 布局预览 → 底部工具栏。
struct PanelView: View {

    @ObservedObject var state: AppState
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var presetManager: PresetManager

    /// 品牌强调色（取自 App 图标主色）。
    private let accent = BrandColor.accent

    var body: some View {
        // 不用 ScrollView：所有气泡卡片一次性全部展开，不滚动。
        VStack(spacing: 14) {
            if state.displays.isEmpty {
                // 无显示器：只放一张提示卡。
                BubbleCard(title: l10n.t(.displaysSection), systemImage: "display", accent: accent) {
                    Text(l10n.t(.noDisplays))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
                }
            } else {
                primaryCard
                if !state.displays.filter({ !$0.isBuiltIn }).isEmpty {
                    arrangeCard
                }
                if !presetManager.presets.isEmpty {
                    presetsCard
                }
                layoutPreviewCard
            }
            bottomToolbar
        }
        .padding(14)
        // 只锁宽度，高度按内容自适应（气泡全展开）。
        .frame(minWidth: 380, idealWidth: 380, maxWidth: 380)
        // 不再叠加自定义背景层：气泡（thinMaterial）直接浮在 MenuBarExtra(.window) 原生
        // popover 的毛玻璃上，整体更通透、不再发灰。气泡四周各自带阴影呈现悬浮层次。
    }

    // MARK: - 主显示器卡片

    /// 主显示器列表：每块屏一行，点击即设为主屏，主屏行带 Teal 勾选 + 角标。
    private var primaryCard: some View {
        BubbleCard(title: l10n.t(.displaysSection), systemImage: "display", accent: accent) {
            VStack(spacing: 2) {
                ForEach(state.displays) { d in
                    Button {
                        state.setPrimary(d)
                    } label: {
                        HStack(spacing: 10) {
                            // 主屏用实心 Teal 圆点，非主屏用空心圆。
                            Image(systemName: d.isMain ? "circle.fill" : "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(d.isMain ? accent : Color.secondary.opacity(0.4))
                                .frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(d.localizedTypeName(l10n: l10n))
                                    .font(.system(size: 13, weight: d.isMain ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                Text(subtitle(for: d))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if d.isMain {
                                Text(l10n.t(.panelPrimaryBadge))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(accent, in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                        .padding(.horizontal, 4)
                        .hoverRowHighlight()
                    }
                    .buttonStyle(.plain)
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

    /// 外接屏排列（每屏一行，可展开左/右移 + 刷新率）+ 镜像/扩展切换。
    private var arrangeCard: some View {
        BubbleCard(title: l10n.t(.panelArrange), systemImage: "arrow.left.and.right", accent: accent) {
            VStack(spacing: 2) {
                // 排列对象随主屏身份切换（与原 menu 逻辑一致）：
                //   外接是主屏 → 排列内置屏；否则逐个排列外接屏。
                if state.externalIsMain, let builtIn = state.builtInDisplay {
                    ArrangementRow(display: builtIn,
                                   state: state,
                                   accent: accent,
                                   label: builtIn.localizedTypeName(l10n: l10n))
                } else {
                    ForEach(state.displays.filter { !$0.isBuiltIn }) { ext in
                        ArrangementRow(display: ext,
                                       state: state,
                                       accent: accent,
                                       label: ext.localizedTypeName(l10n: l10n))
                    }
                }

                Divider().padding(.vertical, 4)

                // 镜像 / 扩展：两个互斥按钮，当前态 Teal 高亮。
                // 操作对端随主屏身份切换（与原 menu 逻辑一致，避免 mirror(ext==main) 退化）。
                mirrorExtendRow
            }
        }
    }

    /// 镜像 / 扩展并排切换行。
    private var mirrorExtendRow: some View {
        let externals = state.displays.filter { !$0.isBuiltIn }
        let isMirroring = externals.contains { state.isMirroring($0) }

        // 操作对端：外接是主屏 → 内置屏；否则首个外接屏。
        let peer: DisplayInfo? = state.externalIsMain
            ? state.builtInDisplay
            : externals.first

        return HStack(spacing: 8) {
            Button {
                if let peer { state.mirror(peer) }
            } label: {
                pillLabel(l10n.t(.mirrorMain), systemImage: "rectangle.on.rectangle",
                          active: isMirroring)
            }
            .buttonStyle(.plain)
            .disabled(peer == nil)

            Button {
                if let peer { state.unmirror(peer) }
            } label: {
                pillLabel(l10n.t(.extendDisplay), systemImage: "rectangle.dashed",
                          active: !isMirroring)
            }
            .buttonStyle(.plain)
            .disabled(peer == nil)
        }
        .padding(.top, 2)
    }

    /// 镜像/扩展胶囊按钮：激活态 Teal 实心，非激活态描边。
    private func pillLabel(_ text: String, systemImage: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage).font(.system(size: 11))
            Text(text).font(.system(size: 12, weight: active ? .semibold : .regular))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if active {
                Capsule().fill(accent)
            } else {
                Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            }
        }
        .foregroundStyle(active ? .white : .primary)
    }

    // MARK: - 布局预设卡片

    /// 已保存预设：每条一行（名称 + 快捷键角标 + 应用按钮）。
    private var presetsCard: some View {
        BubbleCard(title: l10n.t(.groupPresets), systemImage: "square.stack", accent: accent) {
            VStack(spacing: 2) {
                ForEach(presetManager.presets) { preset in
                    Button {
                        presetManager.apply(preset)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.stack")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(preset.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Spacer()
                            // 快捷键角标（已绑定才显示）。
                            if let hk = preset.hotkey, !hk.isEmpty {
                                Text(HotkeyManager.shared.displayString(for: hk))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            }
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(accent)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 5)
                        .padding(.horizontal, 4)
                        .hoverRowHighlight()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 布局预览卡片（画面预览功能预留位）

    /// 等比布局示意图：按 origin + resolution 画出每块屏的相对位置与比例。
    /// 真实画面截取留待下个版本（ScreenCaptureProvider 已预留接口），这里先用几何示意图。
    private var layoutPreviewCard: some View {
        BubbleCard(title: l10n.t(.panelLayoutPreview), systemImage: "rectangle.split.2x1", accent: accent) {
            VStack(spacing: 8) {
                LayoutDiagram(displays: state.displays, accent: accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)

                // 占位提示：画面预览即将推出。
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(l10n.t(.panelScreenPreview))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 底部工具栏

    /// 刷新 / 设置 / 退出：轻量图标行。
    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            toolbarButton(l10n.t(.refreshList), systemImage: "arrow.clockwise") {
                state.refresh()
            }
            Divider().frame(height: 18)
            toolbarButton(l10n.t(.settingsTitle), systemImage: "gearshape") {
                DockPolicyManager.shared.openSettings()
            }
            Divider().frame(height: 18)
            toolbarButton(l10n.t(.quit), systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        // 与气泡统一材质（thinMaterial）+ 阴影，使整列观感一致。
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        // 自适应淡描边：浅色下清晰勾边，深色下几乎不可见（不破坏深色观感）。
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 排列行（可展开左/右移 + 刷新率）

/// 单个屏的排列行：点击 chevron 展开左移/右移按钮与刷新率选择。
private struct ArrangementRow: View {
    let display: DisplayInfo
    @ObservedObject var state: AppState
    let accent: Color
    let label: String

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题行
            HStack(spacing: 10) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                if let side = state.side(of: display) {
                    Text(side == .left ? "◀" : "▶")
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())

            if expanded {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        sideButton(.left)
                        sideButton(.right)
                        Spacer(minLength: 0)
                    }
                    if display.availableRefreshRates.count > 1 {
                        refreshRateMenu
                    }
                }
                .padding(.leading, 28)   // 与标题行文字对齐
                .padding(.trailing, 4)
                .padding(.bottom, 6)
            }
        }
    }

    /// 左移/右移胶囊按钮，当前生效侧 Teal 高亮。
    private func sideButton(_ side: HorizontalSide) -> some View {
        let current = state.side(of: display)
        let active = (current == side)
        return Button {
            state.moveArrangement(display, side: side)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: side == .left ? "arrow.left" : "arrow.right").font(.system(size: 10))
                Text(side == .left ? state.localized(.moveLeft) : state.localized(.moveRight))
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                if active {
                    Capsule().fill(accent)
                } else {
                    Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
            }
            .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    /// 刷新率选择：胶囊形态的横向选择条。
    private var refreshRateMenu: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            ForEach(display.availableRefreshRates, id: \.self) { hz in
                let active = (hz == display.hertz)
                Button {
                    state.setRefreshRate(hz, for: display)
                } label: {
                    Text("\(hz)")
                        .font(.system(size: 11, weight: active ? .semibold : .regular))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            if active {
                                Capsule().fill(accent)
                            } else {
                                Capsule().fill(Color.secondary.opacity(0.1))
                            }
                        }
                        .foregroundStyle(active ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Text(state.localized(.hertzLabel))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 布局示意图

/// 等比绘制所有屏的相对位置与尺寸。
///
/// 算法：取所有屏 origin + resolution 的包围盒，等比缩放到容器宽度，
/// 用 ZStack 定位每块屏的圆角矩形。主屏用品牌蓝实心浅底，外接用描边。
private struct LayoutDiagram: View {
    let displays: [DisplayInfo]
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            if let layout = computeLayout(into: proxy.size) {
                ZStack {
                    ForEach(layout.rects, id: \.id) { item in
                        let isMain = item.display.isMain
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isMain ? accent.opacity(0.18) : Color.gray.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isMain ? accent : Color.secondary.opacity(0.4),
                                            lineWidth: isMain ? 1.5 : 1)
                            )
                            .overlay(alignment: .topLeading) {
                                // 主屏标实心点，副屏标空心点
                                Image(systemName: isMain ? "circle.fill" : "circle")
                                    .font(.system(size: 7))
                                    .foregroundStyle(isMain ? accent : .secondary)
                                    .padding(3)
                            }
                            .frame(width: item.rect.width, height: item.rect.height)
                            .position(x: item.rect.midX, y: item.rect.midY)
                    }
                }
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

// MARK: - 气泡卡片容器

/// 圆角气泡卡片：顶部标题行（品牌蓝图标方块 + 标题）+ 自定义内容。
///
/// 无边框：不加 stroke 描边（参考图要求气泡后面不要边框），
/// 仅靠柔和的半透明材质填充与圆角呈现气泡形态。
private struct BubbleCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行：品牌蓝圆角方块图标 + 标题
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            content
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        // 自适应淡描边：浅色下清晰勾边，深色下几乎不可见（不破坏深色观感）。
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        // 四周悬浮阴影：气泡与原生毛玻璃背景拉开层次，呈现「浮于桌面之上」的观感。
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
    }
}

private extension View {
    /// 类原生菜单的行 hover 高亮：鼠标悬停时给一层柔和的强调色叠加，
    /// 提升可点性与「鲜活/原生」感。修饰在已带 .contentShape 的行上。
    @ViewBuilder
    func hoverRowHighlight() -> some View {
        modifier(HoverRowHighlightModifier())
    }
}

/// 行 hover 高亮修饰器：用局部 @State 跟踪悬停态，叠加半透明强调色背景。
private struct HoverRowHighlightModifier: ViewModifier {
    @State private var isHovered = false
    @State private var accent: Color = BrandColor.accent

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(isHovered ? 0.14 : 0))
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
            )
            .onHover { hovering in
                isHovered = hovering
                // 进入悬停时刷新一次强调色，确保跟随用户当前系统选择。
                if hovering { accent = BrandColor.accent }
            }
    }
}
