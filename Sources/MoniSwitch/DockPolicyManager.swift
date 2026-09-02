import AppKit
import SwiftUI

/// 管理 App 的"前台/Dock 图标"策略，并负责创建/显示设置窗口。
///
/// MoniSwitch 平时是纯菜单栏 App（`LSUIElement=YES` → `.accessory`），
/// 这样无 Dock 图标、无主窗口。但 `.accessory` 模式无法真正成为前台 App，
/// 导致 SwiftUI 的 Settings 场景窗口无法显示/获得焦点。
///
/// 解法（与 Alcove 等主流菜单栏 App 一致）：
///   - 打开设置时：临时切到 `.regular` → Dock 出现图标、App 成为前台
///   - 用自己管理的 NSWindow 承载设置界面（不依赖脆弱的 Settings 场景）
///   - 设置窗口关闭后：切回 `.accessory` → Dock 图标消失
final class DockPolicyManager: NSObject, NSWindowDelegate {

    static let shared = DockPolicyManager()

    private var settingsWindow: NSWindow?

    private override init() { super.init() }

    /// 打开设置：切到普通模式 → 激活 App → 创建/显示设置窗口。
    @MainActor
    func openSettings() {
        let l10n = L10n.shared
        let settings = AppSettings.shared

        // 打开前同步一次开机自启动的真实状态：用户可能在"系统设置 > 登录项"
        // 里手动改动，开关要与系统真实状态对齐。
        settings.syncLaunchAtLoginStatus()

        // 1) 切到普通模式：Dock 图标出现，App 才能成为前台
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // 2) 创建或复用设置窗口
        if settingsWindow == nil {
            // 用 NSHostingController 把 SwiftUI 视图嵌入 AppKit 窗口
            let rootView = SettingsView()
                .environmentObject(l10n)
                .environmentObject(settings)
                .environmentObject(PresetManager.shared)
            let hosting = NSHostingController(rootView: rootView)

            let window = NSWindow(contentViewController: hosting)
            // 注意：不设置 window.title，避免 NavigationSplitView 继承窗口标题。
            window.title = ""
            // 固定尺寸窗口（680×760，横向更宽）；用 fullSizeContentView 让内容延伸到标题栏下方。
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            // 透明标题栏：去掉顶部"设置"白色条，让 NavigationSplitView 的边栏毛玻璃向上贯通
            // 覆盖整个标题区（红绿灯按钮浮在毛玻璃上），对齐系统设置/图二图三的无标题观感。
            // 标题改由右侧内容区顶部的「图标 + 已选功能名」承担（见 SettingsView.DetailHeader）。
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.setContentSize(NSSize(width: 680, height: 760))
            // 锁死尺寸，不可拉伸。三处必须同步：只改 setContentSize 会被 maxSize 钳回。
            window.minSize = NSSize(width: 680, height: 760)
            window.maxSize = NSSize(width: 680, height: 760)
            // 仅允许在原生标题栏（红绿灯按钮条）拖动窗口，避免边栏/内容区背景任意拖动。
            window.isMovableByWindowBackground = false
            window.isReleasedWhenClosed = false   // 复用窗口对象
            window.center()
            window.delegate = self                 // 监听关闭事件
            settingsWindow = window
        }

        // 3) 显示并置前
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 4) 边栏与内容区的分界由 SettingsView 用 HStack 中间一条自绘深灰竖线承担
        //    （颜色可控）。已弃用 NavigationSplitView，无 NSSplitView 分隔线需要处理。
    }

    // MARK: - NSWindowDelegate

    /// 设置窗口关闭后，切回附件模式（Dock 图标消失）。
    ///
    /// MoniSwitch 平时只有一个设置窗口（纯菜单栏 App 无主窗口），
    /// 所以关闭设置窗口即意味着"已无任何普通窗口需要前台"，直接切回 .accessory。
    /// 用 0.2 秒延迟，留出窗口列表在关闭瞬间状态更新的时间，避免 Dock 图标残留。
    func windowWillClose(_ notification: Notification) {
        // 立即把设置窗口引用清空，防止再次 openSettings 复用已关闭对象
        settingsWindow = nil
        // 无条件延迟 0.2 秒后切回附件模式：Dock 图标消失。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
