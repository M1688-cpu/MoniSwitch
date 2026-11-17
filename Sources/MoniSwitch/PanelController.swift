import AppKit
import SwiftUI

/// 面板跟随打开它的桌面；不把 isVisible 误当成「当前桌面可见」。
final class PanelWindow: NSPanel {
    // 原生菜单/键盘导航需要 key window；nonactivatingPanel 仍保证不激活主 App。
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Liquid Glass 直接读取 AppKit 的窗口活动外观，不遵从 SwiftUI.appearsActive。
    // 仅对此菜单面板覆写私有外观钩子；不伪造 isKeyWindow、不激活 App，
    // 原生菜单跟踪/背景点击引起的焦点变化仍照常，只让玻璃始终保持活动外观。
    @objc(_hasActiveAppearance)
    func hasActivePanelAppearance() -> Bool { true }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
    }

    nonisolated static func shouldCloseOnToggle(isVisible: Bool, isOnActiveSpace: Bool) -> Bool {
        isVisible && isOnActiveSpace
    }
}

/// 常驻、固定尺寸的 NSPanel。显隐即时完成，内容高度只用于外部点击命中。
/// 窗口和根视图理想尺寸必须始终相同：可见期间禁止 setFrame/setContentSize，
/// 避免与 NSHostingView 的自动窗口布局形成双写者（2026-10-18 崩溃教训）。
@MainActor
final class PanelController: NSObject, ObservableObject {
    static let shared = PanelController()
    let state = AppState()
    private var statusItem: NSStatusItem?
    private var panel: PanelWindow?
    private var contentHeight: CGFloat = 600
    private var dismissMonitors: [Any] = []
    private var spaceObserver: NSObjectProtocol?
    private var activeMenu: NSMenu?
    @Published private(set) var availablePanelHeight: CGFloat = 600

    var statusItemFrame: CGRect? { statusItem?.button?.window?.frame }
    var isShown: Bool { panel?.isVisible == true && panel?.isOnActiveSpace == true }

    private override init() { super.init() }

    func setup() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarIcon
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        statusItem = item
        makePanel()
        installDismissMonitors()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    static let menuBarIcon: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: "display", accessibilityDescription: "MoniSwitch")?
            .withSymbolConfiguration(config) ?? NSImage()
    }()

    private func makePanel() {
        let height = max(600, (NSScreen.main?.frame.height ?? 900) - 40)
        let rect = NSRect(x: 0, y: 0, width: BubbleMetrics.hostContentWidth, height: height)
        let root = PanelView(state: state, windowHeight: height)
            .environmentObject(L10n.shared)
            .environmentObject(AppSettings.shared)
            .environmentObject(PresetManager.shared)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = rect
        let panel = PanelWindow(contentRect: rect)
        panel.contentView = hosting
        self.panel = panel
        hosting.layoutSubtreeIfNeeded()
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        guard let panel else { return }
        if PanelWindow.shouldCloseOnToggle(isVisible: panel.isVisible,
                                           isOnActiveSpace: panel.isOnActiveSpace) {
            close()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        // 异桌面窗口也可能 isVisible=true，先隐藏再定位；可见期间零窗口写入。
        panel.orderOut(nil)
        positionPanel()
        state.refresh()
        BrightnessManager.shared.refresh()
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown else { return }
            self.statusItem?.button?.cell?.isHighlighted = true
        }
    }

    func close() {
        activeMenu?.cancelTracking()
        panel?.orderOut(nil)
        statusItem?.button?.cell?.isHighlighted = false
    }

    /// 原生菜单可超出主面板，跟踪期间由 AppKit 自己处理选择和外部点击。
    func trackMenu(_ menu: NSMenu, body: () -> Void) {
        activeMenu = menu
        defer { activeMenu = nil }
        body()
    }

    private func positionPanel() {
        guard let panel else { return }
        let anchor = statusItemFrame
        let screen = anchor.flatMap { frame in
            NSScreen.screens.first { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) }
        } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.frame.size
        let desiredX = anchor.map { $0.midX - size.width / 2 }
            ?? (screen.frame.maxX - size.width - 16)
        let top = anchor.map { $0.minY - 6 } ?? (screen.visibleFrame.maxY - 6)
        availablePanelHeight = max(1, top - screen.visibleFrame.minY - 8)
        let x = max(screen.frame.minX + 8, min(desiredX, screen.frame.maxX - size.width - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: top - size.height))
    }

    func updateContentHeight(_ height: CGFloat) { contentHeight = height }

    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfClickedOutside() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.dismissIfClickedOutside() }
            return event
        }
        dismissMonitors = [global, local].compactMap { $0 }
    }

    private func dismissIfClickedOutside() {
        guard let panel, panel.isVisible, activeMenu == nil else { return }
        let location = NSEvent.mouseLocation
        let rect = NSRect(x: panel.frame.minX, y: panel.frame.maxY - contentHeight,
                          width: panel.frame.width, height: contentHeight)
        if rect.contains(location) { return }
        if statusItemFrame?.contains(location) == true { return }
        close()
    }
}
