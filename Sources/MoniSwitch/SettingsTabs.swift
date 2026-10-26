import SwiftUI
import AppKit

// 设置窗口右侧内容区的三个标签页：通用 / 预设 / 关于。
// 窗口骨架（边栏 + 悬浮标题 + 毛玻璃）在 SettingsView.swift；
// 共享卡片/图标组件在 Components.swift。

// MARK: - 主题色卡圆点（设置页专用）

/// 主题选择圆点（2026-10-17 用户二次拍板「色卡只留一档」）：不再画三区圆，
/// 每个主题只保留最浅一档颜色（原三区圆的右上象限 = 高亮档）做单色圆点；
/// 「跟随系统」直接画系统强调色（不再拼中性色下半圆）。
/// 取当前外观下的生效色板（浅色为 L* 派生、深色为原派生），所见即面板所得。
/// 选中态 = 外圈强调色描边；名称走 .help tooltip 与无障碍标签（与 Chrome 色卡
/// 同为无文字圆点，7 个名称不占卡面空间）。
private struct ThemeSwatchButton: View {
    enum Swatch {
        case theme(PanelTheme)
        case followSystem
    }

    let label: String
    let isSelected: Bool
    let swatch: Swatch
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// 设置窗口的主题色板（2026-10-17）：选中环用实心档；「跟随系统」= 系统强调色。
    @Environment(\.panelPalette) private var palette
    @State private var isHovered = false

    private let diameter: CGFloat = 26

    var body: some View {
        Button(action: action) {
            swatchCircle
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .overlay(
                    // 选中环在外、留 3pt 呼吸；未选中给一圈极淡边界（浅色下淡彩
                    // 圆点在灰卡上几乎无边缘）。纯装饰环摘除命中区（全站范式）。
                    Circle().stroke(isSelected ? palette.solid : Color.primary.opacity(isHovered ? 0.28 : 0.12),
                                    lineWidth: isSelected ? 2 : 1)
                        .padding(-3)
                        .allowsHitTesting(false)
                )
                .scaleEffect(isHovered ? 1.08 : 1)
                .animation(BubbleMetrics.buttonHoverSpring, value: isHovered)
                .help(label)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var swatchCircle: some View {
        switch swatch {
        case .theme(let theme):
            // 单色圆点 = 该主题在当前外观下最浅的一档（原三区圆的右上象限）。
            Circle().fill(theme.palette(dark: colorScheme == .dark).highlight)
        case .followSystem:
            // 默认项直接用系统强调色（用户截图中第一个圆点的蓝色）。
            Circle().fill(BrandColor.accent)
        }
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
                // —— 通用（语言 + 启动合并卡；2026-10-17 分区重排方案 A）——
                SettingsCard(title: l10n.t(.groupGeneral)) {
                    VStack(spacing: 0) {
                        settingRow(l10n.t(.languageLabel)) {
                            SettingsMenuPicker(options: Language.allCases,
                                               title: { $0.displayName },
                                               selection: $l10n.lang)
                                .frame(width: 150)
                        }
                        Divider().padding(.vertical, 6)
                        settingRow(l10n.t(.launchAtLogin),
                                   footnote: l10n.t(.launchAtLoginFootnote)) {
                            Toggle("", isOn: $settings.launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                // —— 主题色（2026-10-17 内置主题：三区圆点选择 + 跟随系统默认项）——
                SettingsCard(title: l10n.t(.groupTheme)) {
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 8)], spacing: 8) {
                            ThemeSwatchButton(
                                label: l10n.t(.themeFollowSystem),
                                isSelected: settings.panelThemeID == PanelTheme.systemID,
                                swatch: .followSystem
                            ) {
                                settings.panelThemeID = PanelTheme.systemID
                            }
                            ForEach(PanelTheme.all) { theme in
                                ThemeSwatchButton(
                                    label: l10n.t(theme.nameKey),
                                    isSelected: settings.panelThemeID == theme.id,
                                    swatch: .theme(theme)
                                ) {
                                    settings.panelThemeID = theme.id
                                }
                            }
                        }
                        Text(l10n.t(.themeFootnote))
                            .font(.system(size: BubbleMetrics.fontCaption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }

                // —— 显示器（三行合并卡，行间 Divider，行下小字说明副文本）——
                SettingsCard(title: l10n.t(.groupDisplays)) {
                    VStack(spacing: 0) {
                        settingRow(l10n.t(.autoRefresh),
                                   footnote: l10n.t(.autoRefreshFootnote)) {
                            Toggle("", isOn: $settings.autoRefreshEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        // 刷新间隔：仅当自动刷新开启时显示
                        if settings.autoRefreshEnabled {
                            Divider().padding(.vertical, 6)
                            settingRow(l10n.t(.refreshInterval)) {
                                SettingsMenuPicker(options: AppSettings.refreshIntervalOptions,
                                                   title: { l10n.t(.intervalSeconds, $0) },
                                                   selection: $settings.autoRefreshInterval)
                                    .frame(width: 150)
                            }
                        }
                        Divider().padding(.vertical, 6)
                        settingRow(l10n.t(.detailedMenuInfo),
                                   footnote: l10n.t(.detailedMenuFootnote)) {
                            Toggle("", isOn: $settings.detailedMenuInfo)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                // —— 通知 ——
                SettingsCard(title: l10n.t(.groupNotifications)) {
                    settingRow(l10n.t(.notifyOnSwitch),
                               footnote: l10n.t(.notifyFootnote)) {
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

    /// 统一的设置行：左侧标签（可带小字说明副文本）+ 右侧控件（原生分组卡行式样）。
    /// 副文本是 2026-10-17 分区重排的可读性核心：短句说明该行的实际效果，
    /// 控件右缘对齐不受副文本影响（HStack 中心对齐）。
    @ViewBuilder
    private func settingRow<Control: View>(_ title: String,
                                           footnote: String? = nil,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: BubbleMetrics.fontBody))
                if let footnote {
                    Text(footnote)
                        .font(.system(size: BubbleMetrics.fontCaption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 亮度与按键标签（v2：F1/F2 调鼠标所在屏亮度）

struct BrightnessTab: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings
    /// 内容滚动偏移，上报给 SettingsView 驱动顶部毛玻璃渐入。
    @Binding var scrollOffset: CGFloat

    /// 辅助功能权限状态。**必须是 @State + 主动刷新**：此前用「body 求值即查」的
    /// 计算属性，SwiftUI 不会因外部 TCC 状态变化重算 body——用户在系统设置里授权
    /// 后回到 App，橙三角不会自动变绿勾（2026-10-17 用户报障）。现在由 App 激活、
    /// 窗口回 key 与 1s 轮询兜底三条路径刷新（见 body 尾部 onReceive）。
    @State private var permissionGranted = BrightnessKeyTap.permissionGranted

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // —— F1/F2 开关（用法说明并入行下副文本；2026-10-17 分区重排方案 A）——
                SettingsCard(title: l10n.t(.groupBrightnessKeys)) {
                    settingRow(l10n.t(.brightnessKeysRow),
                               footnote: l10n.t(.brightnessKeysHint)) {
                        Toggle("", isOn: $settings.brightnessKeysEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                // —— 辅助功能权限（DDC 兼容性说明并入本卡尾部脚注）——
                SettingsCard(title: l10n.t(.groupPermission)) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(permissionGranted ? Color.green : Color.orange)
                            Text(permissionGranted ? l10n.t(.permissionGranted) : l10n.t(.permissionMissing))
                                .font(.system(size: BubbleMetrics.fontBody))
                            Spacer()
                            if !permissionGranted {
                                // 「打开系统设置」已并入本按钮（2026-10-17 用户拍板）：
                                // 点「授权」先弹系统辅助功能请求，未获批再深链到授权页。
                                Button(l10n.t(.grantPermission)) {
                                    requestAccessibility()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        Divider().padding(.vertical, 6)
                        Text(l10n.t(.ddcUnsupportedHint))
                            .font(.system(size: BubbleMetrics.fontCaption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .background(ScrollOffsetReader(offset: $scrollOffset))
        }
        // 授权状态的三条刷新路径：App 重新激活（从系统设置返回）、窗口重新成为 key、
        // 1s 轮询兜底（系统弹窗里直接点「允许」时 App 不会失活，也要及时变绿勾）。
        .onAppear { refreshPermissionState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshPermissionState()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            refreshPermissionState()
        }
    }

    /// 重新读取授权状态并让监听与「开关 + 授权」对齐：授权后自动拉起（无需再手动
    /// 拨开关）、撤销后自动停。状态不变时不写 @State，避免 1s 轮询抖动。
    private func refreshPermissionState() {
        let granted = BrightnessKeyTap.permissionGranted
        if granted != permissionGranted {
            permissionGranted = granted
        }
        BrightnessKeyTap.shared.reconcile()
    }

    /// 「授权」按钮：先走系统辅助功能授权请求（首次使用会把 App 登记进列表），
    /// 未获批则直接深链到「隐私与安全性 > 辅助功能」授权页——原独立「打开系统设置」
    /// 链接已并入本按钮（2026-10-17 用户拍板）。
    private func requestAccessibility() {
        let granted = BrightnessKeyTap.requestPermission()
        if !granted {
            BrightnessKeyTap.openPermissionSettings()
        }
        refreshPermissionState()
    }

    /// 与 GeneralTab 同款的设置行（含可选副文本）。
    @ViewBuilder
    private func settingRow<Control: View>(_ title: String,
                                           footnote: String? = nil,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: BubbleMetrics.fontBody))
                if let footnote {
                    Text(footnote)
                        .font(.system(size: BubbleMetrics.fontCaption))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 关于标签

struct AboutTab: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings
    /// 内容滚动偏移上报（关于页内容不满屏不可滚，探针仅用于切 tab 时把毛玻璃复位）。
    @Binding var scrollOffset: CGFloat

    /// 关于页图标：优先用当前主题的图标（AppIconController 随设置换好），
    /// 取不到再回退 bundle 里的静态 icns（dev 模式下没有打包资源）。
    private var currentIcon: NSImage? {
        _ = settings.panelThemeID   // 建立依赖：换主题后关于页图标同步刷新
        return AppIconController.shared.currentImage ?? loadAppIcon()
    }

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
                if let appIcon = currentIcon {
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
                    .font(.system(size: BubbleMetrics.fontControl))
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
                SettingsCard(title: l10n.t(.groupPresets)) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.t(.presetCaptureHint))
                            .font(.system(size: BubbleMetrics.fontControl))
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
                                .font(.system(size: BubbleMetrics.fontControl))
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
                    .font(.system(size: BubbleMetrics.fontBody))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(preset.name)
                    .font(.system(size: BubbleMetrics.fontBody))

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
                .font(.system(size: BubbleMetrics.fontControl))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(l10n.t(.hotkeyLabel))
                .font(.system(size: BubbleMetrics.fontControl))
                .foregroundStyle(.secondary)

            if isThisRecording {
                // 录制中：提示文案占位,再次点击即取消。
                Button {
                    hotkeyManager.cancelRecording()
                } label: {
                    Text(l10n.t(.hotkeyRecording))
                        .font(.system(size: BubbleMetrics.fontControl))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } else if let binding = preset.hotkey, !binding.isEmpty {
                // 已绑定：显示组合字符串。
                Text(hotkeyManager.displayString(for: binding))
                    .font(.system(size: BubbleMetrics.fontControl, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: BubbleMetrics.keycapCornerRadius))
            } else {
                // 未绑定。
                Text(l10n.t(.hotkeyNone))
                    .font(.system(size: BubbleMetrics.fontControl))
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
