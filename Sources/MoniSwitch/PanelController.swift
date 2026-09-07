import AppKit
import SwiftUI

/// 菜单栏面板控制器：自持 NSStatusItem + NSPopover 承载 PanelView。
///
/// 背景（2026-09，macOS 26）：原 MenuBarExtra(.window) 方案的系统面板 chrome
/// 在 macOS 26 上渲染退化——面板呈尖角方框、顶部不贴合菜单栏、底部露出系统
/// 窗口底色（浅色模式为白色长条）；且该样式不提供窗口位置/箭头/动画的任何 API。
/// 改为 NSStatusItem + NSPopover 后：
///   - 箭头沿面板顶边指向菜单栏图标，面板在图标上居中（靠屏边时自动平移、
///     箭头继续追踪图标）；
///   - `animates = true` 的系统原生展开动画：从顶部锚点由小放大向下生长；
///   - 圆角/贴顶等 chrome 回归系统标准 popover 行为，根治上述渲染 bug。
final class PanelController: NSObject, NSPopoverDelegate {

    static let shared = PanelController()

    /// 面板 UI 状态（原挂在 SwiftUI App 上的 @StateObject，唯一消费者是 PanelView；
    /// AppState.init 自带首次 refresh 与热键/自动刷新绑定）。
    let state = AppState()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    /// 上次 popover 收起的时刻。经典竞态：面板开着时点菜单栏图标，
    /// transient 行为会**先**关面板，**再**触发 button action——此时 isShown 已是
    /// false，若直接 toggle 会立即重开，表现为「点图标永远关不掉面板」。
    /// 距上次收起 0.25s 内的 toggle 直接忽略，吞掉这次由点击引发的关闭。
    private var lastCloseTime: Date?

    /// 外部点击收起监控器（全局 + 本地各一）。
    private var dismissMonitors: [Any] = []

    private override init() { super.init() }

    /// 创建菜单栏图标与 popover（App 启动完成后调用一次）。
    @MainActor
    func setup() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarIcon
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        statusItem = item

        popover.behavior = .transient   // 点面板外任意处收起（与原 MenuBarExtra .window 行为一致）
        popover.animates = true         // 系统展开动画：从顶部锚点由小放大
        popover.delegate = self
        popover.contentViewController = hostingController

        installDismissMonitors()
    }

    /// 面板内容。`sizingOptions = [.preferredContentSize]`（macOS 13+）让 SwiftUI
    /// 的理想尺寸（380 宽 / 高自适应）驱动 popover 尺寸；接线模式与
    /// DockPolicyManager.openSettings 的设置窗口一致（单例直接注入 environmentObject）。
    /// （environmentObject 修饰会擦掉具体视图类型，存成属性需包一层 AnyView。）
    private lazy var hostingController: NSHostingController<AnyView> = {
        let rootView = AnyView(
            PanelView(state: state)
                .environmentObject(L10n.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(PresetManager.shared)
        )
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = [.preferredContentSize]
        return hosting
    }()

    // MARK: - 开关面板

    /// 点菜单栏图标：toggle 面板（竞态守卫见 lastCloseTime 注释）。
    @objc @MainActor private func togglePanel(_ sender: NSStatusBarButton) {
        if let last = lastCloseTime, Date().timeIntervalSince(last) < 0.25 { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            show(from: sender)
        }
    }

    @MainActor private func show(from button: NSStatusBarButton) {
        // 先强制一轮布局，把 SwiftUI 理想尺寸固化进 preferredContentSize，
        // 避免首开瞬间 popover 从过时尺寸跳变到实际尺寸。
        hostingController.view.layoutSubtreeIfNeeded()
        // preferredEdge 取按钮的 maxY = 菜单栏图标下方（NSStatusBarButton 坐标系不翻转）。
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        // 图标高亮反馈：模板 image 在高亮态自动反色（等价原 MenuBarExtra 行为）。
        // 系统在 show 过程中会重置 cell 状态，异步到下一轮 runloop 再置位才稳。
        DispatchQueue.main.async {
            button.cell?.isHighlighted = true
        }
    }

    /// 主动收起面板（「设置」等切走焦点/激活策略前调用，防面板悬空）。
    @MainActor func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    // MARK: - 外部点击收起（手装事件监控）

    /// 背景（2026-09 macOS 26 实测）：`.transient` 的自动收起依赖「App 激活后失活」
    /// 或 key 窗口变更——纯菜单栏 App（LSUIElement）从不激活，点桌面/其他 App 时
    /// 这些信号不会到达，AppKit 的自动 dismiss 不触发（表现为点面板外毫无反应，
    /// 只有点图标才关）。手装鼠标按下监控补齐：按下点在 popover 窗口外即收起。
    ///
    /// 全局监控收其他 App/桌面/其他菜单栏图标的点击；本地监控收自家其他窗口
    /// （如设置窗口）的点击；popover 内与状态项按钮上的点击放行（后者交给
    /// togglePanel，它自带竞态守卫）。
    @MainActor
    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            // 监控回调在主线程派发（AppKit 约定），assumeIsolated 直接续接主 actor。
            MainActor.assumeIsolated {
                self?.dismissPopoverIfClickedOutside()
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissPopoverIfClickedOutside()
            }
            return event
        }
        dismissMonitors = [global, local].compactMap { $0 }
    }

    /// 鼠标按下点在面板外 → 收起。点在面板窗口内（正常交互）或状态项按钮上
    /// （由 togglePanel 处理，防双重关闭）时放行。
    @MainActor
    private func dismissPopoverIfClickedOutside() {
        guard popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window else { return }
        let location = NSEvent.mouseLocation
        if popoverWindow.frame.contains(location) { return }
        if let button = statusItem?.button, button.window?.frame.contains(location) == true { return }
        close()
    }

    // MARK: - NSPopoverDelegate

    @MainActor func popoverDidClose(_ notification: Notification) {
        lastCloseTime = Date()
        statusItem?.button?.cell?.isHighlighted = false
    }

    // MARK: - 菜单栏图标

    /// 菜单栏图标的模板 NSImage。
    ///
    /// 用 SF Symbol `display`（苹果系统标准显示器图标）—— 为菜单栏这种小尺寸场景
    /// 专门优化，16pt 下粗描边 + 扁宽屏 + 醒目底座，一眼可辨；且与菜单栏其他系统图标
    /// （WiFi/电池/控制中心）视觉语言统一。
    ///
    /// 关键：SF Symbol 返回的 NSImage 天然是模板 image（isTemplate 默认 true），
    /// 系统会在深浅色/高亮态自动反色——NSStatusBarButton 的 cell 高亮（面板打开时）
    /// 同样依赖这一机制保持图标可见。
    static let menuBarIcon: NSImage = {
        // medium weight：semibold 在 16pt 下线条偏粗（2026-09 用户反馈略粗），
        // regular 又偏细，medium 折中——视觉重量与其他菜单栏图标接近且更清爽。
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: "display",
                       accessibilityDescription: "MoniSwitch")?
            .withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "display",
                       accessibilityDescription: "MoniSwitch")
            ?? NSImage()
    }()
}
