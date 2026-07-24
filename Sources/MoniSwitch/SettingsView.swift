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
        case general, about
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
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
                Label(l10n.t(.tabAbout), systemImage: "info.circle").tag(Tab.about)
            }
            .listStyle(.sidebar)
            // 锁死边栏宽度：min=ideal=max，无法拖拽调整
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        } detail: {
            // —— 右侧内容区：按选中标签直接切换 ——
            switch selectedTab {
            case .general:  GeneralTab()
            case .about:    AboutTab()
            case .none:     GeneralTab()
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.top, 32)

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

            // 测试版本徽标：胶囊样式，提示当前非正式发布版
            Text(l10n.t(.testBuildLabel))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    Capsule().strokeBorder(.orange.opacity(0.5), lineWidth: 1)
                )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
