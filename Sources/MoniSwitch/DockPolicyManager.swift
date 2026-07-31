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
final class DockPolicyManager: NSObject, NSWindowDelegate, NSToolbarDelegate {

    static let shared = DockPolicyManager()

    private var settingsWindow: NSWindow?

    /// 工具栏居中标题项的标识符（承载"设置"文字）。
    private let titleItemIdentifier = NSToolbarItem.Identifier("SettingsTitleItem")
    /// 工具栏居中标题文案，在 openSettings 时设置。
    private var toolbarTitle: String = ""

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
            // 注意：不设置 window.title，避免 NavigationSplitView 继承窗口标题
            // 并在边栏/内容区重复显示——标题统一由下方 NSToolbar 的居中项承担。
            window.title = ""
            // 固定尺寸窗口（520×720，竖向）；用 fullSizeContentView 让内容延伸到标题栏下方
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .hidden
            // 用 NSToolbar 承载居中标题：principal 项 + centeredItem，
            // 使"设置"相对整窗水平居中（覆盖边栏+内容区），与系统设置/Finder 一致。
            toolbarTitle = l10n.t(.settingsTitle)
            let toolbar = NSToolbar(identifier: "SettingsToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .labelOnly
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            // centeredItemIdentifiers 让该标题项相对整窗水平居中（macOS 13+）。
            toolbar.centeredItemIdentifiers = [titleItemIdentifier]
            window.setContentSize(NSSize(width: 520, height: 720))
            // 锁死尺寸，不可拉伸。三处必须同步：只改 setContentSize 会被 maxSize 钳回。
            window.minSize = NSSize(width: 520, height: 720)
            window.maxSize = NSSize(width: 520, height: 720)
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false   // 复用窗口对象
            window.center()
            window.delegate = self                 // 监听关闭事件
            settingsWindow = window
        }

        // 3) 显示并置前
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 4) 把 NavigationSplitView 自带的分割线设为细线样式，
        //    避免默认粗分割线在边栏处显示异常光标（可拖拽提示）。
        if let splitView = settingsWindow?.contentView?.findFirst(NSSplitView.self) {
            splitView.dividerStyle = .thin
        }
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

// MARK: - NSToolbarDelegate

extension DockPolicyManager {

    /// 工具栏只含一个居中标题项。
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [titleItemIdentifier]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [titleItemIdentifier]
    }

    /// 创建居中标题项：用 NSToolbarItem(groupContaining:) 包一层，
    /// 内部放居中的标题标签——这是让标题在工具栏里水平居中的稳妥写法。
    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == titleItemIdentifier else { return nil }

        let label = NSTextField(labelWithString: toolbarTitle)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.textColor = .labelColor
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false

        let container = NSStackView(views: [label])
        container.orientation = .horizontal
        container.alignment = .centerY
        container.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)

        let group = NSToolbarItem(itemIdentifier: itemIdentifier)
        group.view = container
        // label 留空：displayMode=.labelOnly 时若 label 非空会额外渲染文字，
        // 导致标题重复。居中标题完全由上面的 container 承载。
        group.label = ""
        group.paletteLabel = ""
        group.toolTip = nil
        // 去掉 Sonoma/Sequoia 给自定义 view 项默认渲染的 pill/圆角背景。
        // 自 macOS 13 起可用，正好匹配本项目最低版本。
        group.isBordered = false
        return group
    }
}

// MARK: - NSView 辅助

private extension NSView {
    /// 深度优先递归查找第一个指定类型的子视图。
    func findFirst<T: NSView>(_ type: T.Type) -> T? {
        if let match = self as? T { return match }
        for sub in subviews {
            if let found = sub.findFirst(type) { return found }
        }
        return nil
    }
}
