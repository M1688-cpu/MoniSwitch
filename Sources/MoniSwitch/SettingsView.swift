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
    }
}

// MARK: - 通用标签

struct GeneralTab: View {

    @EnvironmentObject private var l10n: L10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.t(.groupLanguage))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
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
                Spacer()
            }
            .padding(24)
        }
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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
