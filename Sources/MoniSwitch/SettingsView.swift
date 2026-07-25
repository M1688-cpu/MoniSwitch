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
                Label(l10n.t(.tabGeneral), systemImage: "gearshape").tag(Tab.general)
                Label(l10n.t(.tabPresets), systemImage: "square.stack").tag(Tab.presets)
                Label(l10n.t(.tabAbout), systemImage: "info.circle").tag(Tab.about)
            }
            .listStyle(.sidebar)
            // 锁死边栏宽度：min=ideal=max，无法拖拽调整
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        } detail: {
            // —— 右侧内容区：按选中标签直接切换 ——
            switch selectedTab {
            case .general: GeneralTab()
            case .presets: PresetsTab()
            case .about:   AboutTab()
            case .none:    GeneralTab()
            }
        }
        // 显式置空导航标题，避免 NavigationSplitView 继承窗口标题
        // 并在边栏/内容区重复显示"设置"（标题统一由窗口工具栏的居中项承担）。
        .navigationTitle("")
    }
}

// MARK: - 通用标签

struct GeneralTab: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // —— 语言 ——
                Text(l10n.t(.groupLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    icon("globe")
                    Text(l10n.t(.languageLabel))
                        .font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $l10n.lang) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160)
                }
                .padding(.vertical, 4)

                Divider()

                // —— 启动 ——
                Text(l10n.t(.groupStartup))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    icon("power")
                    Text(l10n.t(.launchAtLogin))
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 4)

                Divider()

                // —— 显示器 ——
                Text(l10n.t(.groupDisplays))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    icon("arrow.triangle.2.circlepath")
                    Text(l10n.t(.autoRefresh))
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $settings.autoRefreshEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 4)

                // 刷新间隔：仅当自动刷新开启时显示
                if settings.autoRefreshEnabled {
                    HStack(spacing: 12) {
                        icon("clock")
                        Text(l10n.t(.refreshInterval))
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $settings.autoRefreshInterval) {
                            ForEach(AppSettings.refreshIntervalOptions, id: \.self) { sec in
                                Text(l10n.t(.intervalSeconds, sec)).tag(sec)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 12) {
                    icon("rectangle.on.rectangle.angled")
                    Text(l10n.t(.detailedMenuInfo))
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $settings.detailedMenuInfo)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 4)

                Divider()

                // —— 通知 ——
                Text(l10n.t(.groupNotifications))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    icon("bell")
                    Text(l10n.t(.notifyOnSwitch))
                        .font(.system(size: 13))
                    Spacer()
                    Toggle("", isOn: $settings.notificationsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.vertical, 4)

                Spacer()
            }
            .padding(24)
        }
    }

    /// 统一的对齐图标列（与"语言"行保持一致的尺寸与配色）。
    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 20)
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
            // 关于页图标：优先用真实 App 图标（打包后从 Bundle 取），
            // dev 模式下 Bundle.main 取不到则回退到 SF Symbol 占位。
            if let appIcon = loadAppIcon() {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .padding(.top, 32)
            } else {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
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
            VStack(alignment: .leading, spacing: 20) {
                // —— 保存当前布局 ——
                Text(l10n.t(.groupPresets))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(l10n.t(.presetCaptureHint))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField(l10n.t(.presetNamePlaceholder), text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(capture)

                    Button(l10n.t(.presetCaptureButton), action: capture)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Divider()

                // —— 已保存的预设列表 ——
                if presetManager.presets.isEmpty {
                    Text(l10n.t(.presetEmptyHint))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(presetManager.presets) { preset in
                        PresetRow(preset: preset)
                    }
                }

                Spacer()
            }
            .padding(24)
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

/// 单个预设行：名称 + 应用按钮 + 删除按钮。
struct PresetRow: View {

    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var presetManager: PresetManager
    let preset: Preset

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)

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
        .padding(.vertical, 4)
    }
}

