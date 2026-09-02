import SwiftUI
import AppKit

/// MoniSwitch 入口：一个纯菜单栏 App（无 Dock 图标、无主窗口，靠 Info.plist 的 LSUIElement=YES 实现）。
/// UI 状态层在 AppState.swift，设置窗口在 SettingsView.swift。
@main
struct MoniSwitchApp: App {

    @StateObject private var state = AppState()
    @StateObject private var l10n = L10n.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var presetManager = PresetManager.shared

    var body: some Scene {
        // 顶部菜单栏图标 + 下拉面板（.window 样式：可完全自定义的 SwiftUI 视图，
        // 用于实现「气泡卡片」设计；原 .menu 样式是原生 NSMenu，无法做卡片/配色）。
        MenuBarExtra {
            PanelView(state: state)
                .environmentObject(l10n)
                .environmentObject(settings)
                .environmentObject(presetManager)
        } label: {
            // 菜单栏图标:必须用模板 NSImage(SF Symbol 天然是模板)。
            // .window 样式下面板打开时系统给图标加深色高亮背景,非 template 视图
            // (如用 .primary 描边的自绘视图)会与高亮背景同色,表现为图标位置一整块黑。
            // 模板 image 由系统在高亮/深浅态自动反色,稳定可见(见下方 menuBarIcon)。
            Image(nsImage: Self.menuBarIcon)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口不再用 SwiftUI 的 Settings 场景——它在菜单栏 App 中不可靠。
        // 改由 DockPolicyManager 用自管理的 NSWindow 承载。
        // 这里只注册 ⌘, 快捷键，让 App 菜单里的「设置…」也能触发打开。
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(l10n.t(.settings)) {
                    DockPolicyManager.shared.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - 菜单栏图标

extension MoniSwitchApp {
    /// 菜单栏图标的模板 NSImage。
    ///
    /// 用 SF Symbol `display`（苹果系统标准显示器图标）—— 为菜单栏这种小尺寸场景
    /// 专门优化，16pt 下粗描边 + 扁宽屏 + 醒目底座，一眼可辨；且与菜单栏其他系统图标
    /// （WiFi/电池/控制中心）视觉语言统一。
    ///
    /// 关键：SF Symbol 返回的 NSImage 天然是模板 image（isTemplate 默认 true），
    /// 系统会在深浅/高亮态自动反色 —— 这是 `.window` 样式 MenuBarExtra 防止图标
    /// 变黑的核心机制（见 AGENTS.md「MenuBarExtra .window 样式…」条目）。
    static let menuBarIcon: NSImage = {
        // semibold weight：默认 regular 在 16pt 下偏细，semibold 让视觉重量
        // 与其他菜单栏图标一致，更醒目但不至于过粗。
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        return NSImage(systemSymbolName: "display",
                       accessibilityDescription: "MoniSwitch")?
            .withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "display",
                       accessibilityDescription: "MoniSwitch")
            ?? NSImage()
    }()
}
