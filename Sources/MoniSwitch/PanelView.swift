import SwiftUI
import AppKit

private struct PanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PanelScrollHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 控制中心式面板：没有整体背板，玻璃瓷砖直接浮在壁纸上。
/// 选中显示器只影响参数与动作瓷砖；亮度始终保留每个可控外接屏。
struct PanelView: View {
    @ObservedObject var state: AppState
    var windowHeight: CGFloat = 0
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var presetManager: PresetManager
    @ObservedObject private var presentation = PanelController.shared
    @State private var selectedDisplayID: String?
    @State private var scrollContentHeight: CGFloat = 1
    @State private var brightness = BrightnessManager.shared

    private static let tileSpacing: CGFloat = 10

    private var busy: Bool { state.isOperating || presetManager.isApplying }
    private var selectedID: String? {
        PanelDisplayContext.selectedID(preferred: selectedDisplayID, in: state.displays)
    }
    private var selectedDisplay: DisplayInfo? { state.displays.first { $0.id == selectedID } }
    private var configurationID: String { PanelDisplayContext.configurationID(state.displays) }
    private var menuContextID: String { configurationID + "|\(selectedID ?? "")|\(busy)" }
    private var viewportHeight: CGFloat {
        let hostHeight = windowHeight > 0 ? windowHeight : 600
        // 底栏瓷砖与内外边距预留；仅滚动内容，绝不调整固定窗口尺寸。
        let available = min(hostHeight, presentation.availablePanelHeight) - 112
        return PanelDisplayContext.viewportHeight(content: scrollContentHeight, available: available)
    }

    var body: some View {
        PanelGlassGroup {
            VStack(spacing: Self.tileSpacing) {
                ScrollView(.vertical) {
                    panelContent
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, BubbleMetrics.shadowBreathingSide)
                        .padding(.vertical, 4)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: PanelScrollHeightKey.self, value: geo.size.height)
                            }
                        }
                }
                .frame(height: viewportHeight)
                .onPreferenceChange(PanelScrollHeightKey.self) { height in
                    if abs(scrollContentHeight - height) > 0.5 { scrollContentHeight = height }
                }
                bottomToolbar.padding(.horizontal, BubbleMetrics.shadowBreathingSide)
            }
            .font(.system(size: BubbleMetrics.fontBody))
            .frame(width: BubbleMetrics.hostContentWidth)
        }
        .padding(.top, BubbleMetrics.panelTopPadding)
        .padding(.bottom, BubbleMetrics.shadowBreathingBottom)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: PanelContentHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(PanelContentHeightKey.self) { PanelController.shared.updateContentHeight($0) }
        // 根视图理想尺寸恒定；内容高度仅供点击命中，不能写入窗口 frame。
        .frame(width: windowHeight > 0 ? BubbleMetrics.hostContentWidth : nil,
               height: windowHeight > 0 ? windowHeight : nil, alignment: .top)
        .frame(maxWidth: windowHeight > 0 ? nil : .infinity,
               maxHeight: windowHeight > 0 ? nil : .infinity, alignment: .top)
        .onAppear { selectedDisplayID = selectedID }
        .onChange(of: state.displays.map(\.id)) { _, _ in selectedDisplayID = selectedID }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: Self.tileSpacing) {
            if !brightness.entries.isEmpty { brightnessTile }
            if state.displays.isEmpty {
                Text(l10n.t(.noDisplays)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .modifier(PanelGlassSurface())
            } else {
                displayTiles
            }
            if let display = selectedDisplay {
                parameterTile(display)
                if state.displays.count > 1 { actionTile(display) }
            }
            // 没有预设时整块不出现；新建入口在设置 → 预设。
            if !presetManager.presets.isEmpty { presetTile }
        }
        .disabled(busy)
    }

    // MARK: 瓷砖

    private func sectionLabel(_ key: TextKey) -> some View {
        Text(l10n.t(key))
            .font(.system(size: BubbleMetrics.fontCaption, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var brightnessTile: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(.panelSectionBrightness)
            ForEach(brightness.entries) { entry in
                let name = entry.name.isEmpty ? l10n.t(.externalDisplay) : entry.name
                VStack(alignment: .leading, spacing: 5) {
                    if brightness.entries.count > 1 {
                        Text(name).font(.system(size: BubbleMetrics.fontControl)).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "display")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        // 原生滑杆：以 27 SDK 链接时（build-app.sh），按住拖动有系统 Liquid Glass 拇指。
                        Slider(value: Binding(get: { entry.percent },
                                              set: { brightness.setPercent($0, for: entry.id) }),
                               in: 0...1)
                            .accessibilityLabel(name)
                            .accessibilityValue("\(Int((entry.percent * 100).rounded()))%")
                        Text("\(Int((entry.percent * 100).rounded()))%")
                            .font(.system(size: BubbleMetrics.fontControl).monospacedDigit())
                            .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                }
                .help(name)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PanelGlassSurface())
    }

    /// 每块显示器一张瓷砖，两列排布；单屏时独占整行。
    private var displayTiles: some View {
        let rows = stride(from: 0, to: state.displays.count, by: 2).map {
            Array(state.displays[$0..<min($0 + 2, state.displays.count)])
        }
        return VStack(spacing: Self.tileSpacing) {
            ForEach(rows, id: \.first?.id) { row in
                HStack(spacing: Self.tileSpacing) {
                    ForEach(row) { display in displayTile(display) }
                    if row.count == 1 && state.displays.count > 1 {
                        Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                    }
                }
            }
        }
    }

    private func displayTile(_ display: DisplayInfo) -> some View {
        let name = displayTitle(display)
        let isSelected = display.id == selectedID
        var detail = "\(display.resolution.width) × \(display.resolution.height)"
        if settings.detailedMenuInfo { detail += " · \(display.hertz) \(l10n.t(.hertzLabel))" }
        return Button {
            selectedDisplayID = display.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(isSelected && state.displays.count > 1 ? BrandColor.accent : Color.primary)
                        .frame(height: 34, alignment: .bottomLeading)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    if display.isMain {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColor.accent)
                            .accessibilityLabel(l10n.t(.mainDisplay))
                    }
                }
                .padding(.bottom, 6)
                Text(name).fontWeight(.semibold).lineLimit(1)
                Text(detail).font(.system(size: BubbleMetrics.fontCaption))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(PanelGlassSurface(isSelected: isSelected && state.displays.count > 1))
        .help(display.isMain ? "\(name) · \(l10n.t(.mainDisplay))" : name)
        .accessibilityLabel(display.isMain ? "\(name), \(l10n.t(.mainDisplay))" : name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func parameterTile(_ display: DisplayInfo) -> some View {
        let scaleTag = l10n.t(display.scalingOn ? .hidpiTag : .lowResolutionTag)
        let mirrored = state.isMirroring(display)
        let side = state.side(of: display)
        return VStack(alignment: .leading, spacing: 8) {
            NativeParameterRow(title: l10n.t(.resolutionMenu),
                               value: "\(display.resolution.width) × \(display.resolution.height) · \(scaleTag)",
                               options: display.availableResolutions.map { res in
                .init(title: "\(res.width) × \(res.height) · \(l10n.t(res.hidpi ? .hidpiTag : .lowResolutionTag))",
                      isSelected: res.width == display.resolution.width && res.height == display.resolution.height
                        && res.hidpi == display.scalingOn) { state.setResolution(res, for: display) }
            }, contextID: menuContextID)
            NativeParameterRow(title: l10n.t(.refreshRateMenu),
                               value: "\(display.hertz) \(l10n.t(.hertzLabel))",
                               options: display.availableRefreshRates.map { hz in
                .init(title: "\(hz) \(l10n.t(.hertzLabel))", isSelected: hz == display.hertz) {
                    state.setRefreshRate(hz, for: display)
                }
            }, contextID: menuContextID)
            if state.displays.count > 1 && !display.isMain {
                NativeParameterRow(title: l10n.t(.positionLabel),
                                   value: side.map { l10n.t($0 == .left ? .sideLeft : .sideRight) } ?? "—",
                                   options: [
                    .init(title: l10n.t(.sideLeft), isSelected: side == .left) {
                        state.moveArrangement(display, side: .left)
                    },
                    .init(title: l10n.t(.sideRight), isSelected: side == .right) {
                        state.moveArrangement(display, side: .right)
                    }
                ], contextID: menuContextID)
                    .disabled(mirrored)
            }
        }
        .padding(14)
        .modifier(PanelGlassSurface())
    }

    /// 镜像/扩展的主体是非主屏；选中主屏且只有两块屏时，作用于另一块。
    private func actionTile(_ display: DisplayInfo) -> some View {
        let others = state.displays.filter { $0.id != display.id }
        let subject: DisplayInfo? = display.isMain ? (others.count == 1 ? others.first : nil) : display
        let mirrored = subject.map { state.isMirroring($0) } ?? false
        let mainName = state.displays.first(where: \.isMain).map(displayTitle) ?? ""
        return HStack(alignment: .top, spacing: 6) {
            GlassRoundAction(symbol: "star", title: l10n.t(.setAsPrimary), isOn: display.isMain) {
                state.setPrimary(display)
            }
            .disabled(display.isMain)
            GlassRoundAction(symbol: "rectangle.on.rectangle", title: l10n.t(.mirrorShort), isOn: mirrored) {
                if let subject, !mirrored { state.mirror(subject) }
            }
            .disabled(subject == nil)
            .help(l10n.t(.mirrorActionHint, mainName))
            GlassRoundAction(symbol: "rectangle.split.2x1", title: l10n.t(.extendShort),
                             isOn: subject != nil && !mirrored) {
                if let subject, mirrored { state.unmirror(subject) }
            }
            .disabled(subject == nil)
            .help(l10n.t(.extendActionHint))
        }
        .padding(.vertical, 12).padding(.horizontal, 10)
        .modifier(PanelGlassSurface())
    }

    private var presetTile: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(.layoutPresets)
            ForEach(presetManager.presets) { preset in
                let shortcut = preset.hotkey.flatMap { $0.isEmpty ? nil : HotkeyManager.shared.displayString(for: $0) }
                let isCurrent = DisplayManager.shared.presetMatchesCurrentLayout(preset.screenArgs,
                                                                                displays: state.displays)
                Button { presetManager.apply(preset) } label: {
                    HStack(spacing: 8) {
                        Text(preset.name).lineLimit(1)
                        Spacer(minLength: 0)
                        if let shortcut {
                            Text(shortcut).font(.system(size: BubbleMetrics.fontCaption))
                                .foregroundStyle(.secondary)
                        }
                        if isCurrent {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BrandColor.accent)
                                .accessibilityLabel(l10n.t(.currentLayoutBadge))
                        }
                    }
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button(l10n.t(.managePresets)) { openSettings(tab: .presets) }
                .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PanelGlassSurface())
    }

    private func displayTitle(_ display: DisplayInfo) -> String {
        let name = PanelDisplayContext.name(for: display, in: state.displays,
                                           baseName: display.localizedTypeName(l10n: l10n))
        return name
    }

    /// 底栏：原「设置」与「更多」菜单里的每一项拆成独立玻璃图标键。
    /// 操作进行中，刷新键换成小转圈并禁用（原底栏进度指示并入这里）。
    private var bottomToolbar: some View {
        HStack(spacing: Self.tileSpacing) {
            PanelIconButton(symbol: "gearshape", title: l10n.t(.settingsTitle)) { openSettings() }
            PanelIconButton(symbol: "rectangle.3.group", title: l10n.t(.autoArrange)) { state.autoArrange() }
                .disabled(busy || state.displays.count < 2)
            PanelIconButton(symbol: "arrow.clockwise", title: l10n.t(.refreshList),
                            showsProgress: busy) { state.refresh() }
                .disabled(busy)
            PanelIconButton(symbol: "power", title: l10n.t(.quit)) { NSApplication.shared.terminate(nil) }
        }
    }

    private func openSettings(tab: SettingsView.Tab? = nil) {
        PanelController.shared.close()
        DockPolicyManager.shared.openSettings(tab: tab)
    }
}

private struct NativeParameterRow: View {
    let title: String
    let value: String
    let options: [ParameterMenuOption]
    var presentation: ParameterMenuTrigger.Presentation = .selection
    var contextID = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            if options.count > 1 || presentation == .command {
                ParameterMenuTrigger(title: title, currentValue: value, options: options,
                                     presentation: presentation, contextID: contextID)
                    .frame(maxWidth: .infinity).frame(height: 26)
            } else {
                Text(value).lineLimit(1).help(value)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(title): \(value)")
            }
        }
        .frame(minHeight: 26)
    }
}
