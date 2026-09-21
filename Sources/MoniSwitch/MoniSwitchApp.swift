import SwiftUI
import AppKit

/// MoniSwitch 入口：一个纯菜单栏 App（无 Dock 图标、无主窗口，靠 Info.plist 的 LSUIElement=YES 实现）。
/// 菜单栏图标与弹出面板由 PanelController.swift 自持（NSStatusItem + NSPopover），
/// 不再用 MenuBarExtra——macOS 26 上其 .window 面板 chrome 渲染退化（尖角方框/
/// 不贴顶/底部白条），且无箭头/居中对齐/展开动画 API。
/// 设置窗口在 SettingsView.swift（宿主 NSWindow 归 DockPolicyManager），UI 状态层在 AppState.swift。
@main
struct MoniSwitchApp: App {

    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        // SwiftUI App 至少需要一个 Scene；设置真身是 DockPolicyManager 的 NSWindow，
        // 这里只放一个空的 Settings 场景占位（不会展示内容，标准入口已被下方
        // CommandGroup(replacing: .appSettings) 接管为 DockPolicyManager.openSettings）。
        Settings {
            EmptyView()
        }
        .commands {
            // 注册 ⌘, 快捷键，让 App 菜单里的「设置…」也能触发打开
            // （设置窗口打开时 App 已由 DockPolicyManager 切到 regular 模式，菜单栏可见）。
            CommandGroup(replacing: .appSettings) {
                Button(L10n.shared.t(.settings)) {
                    DockPolicyManager.shared.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

/// AppKit 委托：启动完成后创建菜单栏图标与面板（此前由 MenuBarExtra Scene 承担）。
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        PanelController.shared.setup()
        hidePlaceholderSettingsWindow()
        // 占位 Settings scene 的窗口可能在启动后异步实体化（macOS 27 实测会以
        // 900x450 空白窗「MoniSwitch Settings」显示在桌面），用窗口遮挡状态变化
        // 通知（上屏必发）兜底再收，幂等。selector 式观察者（项目约定：block 式
        // 在 SDK 26 下有 @Sendable 捕获告警，基线零警告）。
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowOcclusionStateChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }

    /// 收起 SwiftUI `Settings { EmptyView() }` 占位 scene 实体化的窗口
    /// （identifier=com_apple_SwiftUI_Settings_window）。该窗口从不承载真实 UI
    /// （⌘, 已由 CommandGroup 接管到 DockPolicyManager.openSettings），但 macOS 27
    /// 上会实体化并常驻桌面（2026-09-21 CGWindowList + 截图实测），必须收起。
    private func hidePlaceholderSettingsWindow() {
        for window in NSApp.windows where window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
            window.orderOut(nil)
        }
    }

    @objc private func windowOcclusionStateChanged(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window",
              window.isVisible else { return }
        window.orderOut(nil)
    }
}
