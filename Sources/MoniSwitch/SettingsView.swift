import SwiftUI
import AppKit

/// 设置窗口：基于 SwiftUI 原生 `NavigationSplitView`。
///
/// 用 NavigationSplitView 是关键——它自动处理：
///   - 边栏毛玻璃（vibrancy）材质
///   - 边栏底部圆角
///   - 边栏背景与标题栏的一体化（延伸到顶部）
/// 这些正是 DockDoor / 系统设置的视觉特征，无需手动叠加。
///
/// 视觉风格与菜单栏气泡面板统一：内容区用 .regularMaterial（浅灰/深灰自动适配），
/// 各分组用圆角卡片（thinMaterial + 淡描边 + 阴影），头部图标用同色系渐变方块。
///
/// 边栏宽度用 min=ideal=max 锁死，不可拖拽。
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
    }

    @EnvironmentObject private var l10n: L10n
    @State private var selectedTab: Tab? = .general

    var body: some View {
        // .constant(.all)：边栏永远可见，无法用工具栏按钮折叠。
        // 配合 navigationSplitViewColumnWidth(min:200,ideal:200,max:200) 锁死宽度。
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // —— 左侧边栏 ——
            List(selection: $selectedTab) {
                SidebarRow(title: l10n.t(.tabGeneral), systemImage: Tab.general.systemImage)
                    .tag(Tab.general)
                SidebarRow(title: l10n.t(.tabPresets), systemImage: Tab.presets.systemImage)
                    .tag(Tab.presets)
                SidebarRow(title: l10n.t(.tabAbout), systemImage: Tab.about.systemImage)
                    .tag(Tab.about)
            }
            .listStyle(.sidebar)
            // 锁死边栏宽度：min=ideal=max，无法拖拽调整
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        } detail: {
            // —— 右侧内容区：灰底毛玻璃材质 + 按选中标签切换 ——
            Group {
                switch selectedTab {
                case .general: GeneralTab()
                case .presets: PresetsTab()
                case .about:   AboutTab()
                case .none:    GeneralTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 内容区变灰：.regularMaterial 浅色淡灰、深色深灰，自动适配（图一效果）。
            .background(.regularMaterial)
        }
        // 显式置空导航标题，避免 NavigationSplitView 继承窗口标题
        // 并在边栏/内容区重复显示"设置"（标题统一由窗口工具栏的居中项承担）。
        .navigationTitle("")
        // 设置窗口跟随 macOS 系统强调色，与菜单栏气泡面板保持一致（项目无 xcassets，直接桥接 AppKit 动态色）。
        .tint(Color(NSColor.controlAccentColor))
    }
}

// MARK: - 共享视觉组件

/// 同色系渐变圆角图标方块：跟随系统强调色（亮端 0.85 → 深端 1.0）。
/// 菜单栏气泡头部、设置边栏、设置卡片头部、关于页统一用它。
struct GradientIconSquare: View {
    let systemImage: String
    var size: CGFloat = 22
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [BrandColor.accent.opacity(0.85), BrandColor.accent],
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

/// 设置分组卡片：头部（渐变图标 + 标题）+ 自定义内容。
/// 视觉与菜单栏 BubbleCard 同源：thinMaterial + 淡描边 + 悬浮阴影。
struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                GradientIconSquare(systemImage: systemImage, size: 22)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            content
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        // 自适应淡描边：浅色下清晰、深色下几乎不可见，与菜单栏气泡一致。
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)
    }
}

/// 边栏行：渐变图标方块 + 标题（保留 .listStyle(.sidebar) 的选中高亮）。
private struct SidebarRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            GradientIconSquare(systemImage: systemImage, size: 24)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 通用标签

struct GeneralTab: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings

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

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
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
        VStack(spacing: 16) {
            // 关于页图标：优先用真实 App 图标（打包后从 Bundle 取）；
            // dev 模式下 Bundle.main 取不到则回退到与边栏同款的渐变方块占位。
            if let appIcon = loadAppIcon() {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .padding(.top, 32)
            } else {
                GradientIconSquare(systemImage: "rectangle.on.rectangle", size: 96, cornerRadius: 20)
                    .padding(.top, 32)
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 预设标签

struct PresetsTab: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var presetManager: PresetManager

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
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
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
