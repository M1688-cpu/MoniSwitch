import SwiftUI
import AppKit

// 设置窗口右侧内容区的三个标签页：通用 / 预设 / 关于。
// 窗口骨架（边栏 + 悬浮标题 + 毛玻璃）在 SettingsView.swift；
// 共享卡片/图标组件在 Components.swift。

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
                .font(.system(size: BubbleMetrics.fontBody))
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
                SettingsCard(title: l10n.t(.groupPresets), systemImage: "square.stack") {
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
