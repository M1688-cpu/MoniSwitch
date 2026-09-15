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
        popover.contentViewController = panelContainerController

        installDismissMonitors()

        // 提前布局一轮：让 PanelView 的 PreferenceKey 高度上报在首次 show 之前就位，
        // preferredContentSize 已是实际值（否则首开会以占位尺寸弹出再跳变）。
        hostingController.view.layoutSubtreeIfNeeded()

        // [DEBUG-autoshow] 临时调试钩子（像素诊断用，收尾时删除）：
        // AX 点击开面板在本机会把面板放到错误位置（内容与窗口框脱节），
        // 自动展示走真实 show(from:) 路径，供 screencapture 差分取样。
        // 必须等首次显示器刷新完成（displays 填充）后再展示——启动中途开面板
        // 会撞上「空态→满态」的内容增高，容器布局卡在错位态（内容掉到屏幕下方）。
        if UserDefaults.standard.bool(forKey: "MoniswitchDebugAutoShow") {
            let state = self.state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                func tryShow(attempt: Int) {
                    guard let self, let button = self.statusItem?.button else { return }
                    if state.displays.isEmpty, attempt < 40 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { tryShow(attempt: attempt + 1) }
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.show(from: button)
                    }
                }
                tryShow(attempt: 0)
            }
        }
    }

    /// 面板宿主层级（2026-09 实测定型，修「展开参数时所有气泡先上跳再下拉」）：
    /// `popover → 自有容器 VC → NSHostingController.view（四边钉死在容器上）`。
    ///
    /// 根因链（像素级实测）：SwiftUI 布局弹簧动画 → NSHostingView **即时**取新高度 →
    /// popover 窗口 frame **滞后 1-2 帧**；滞后瞬态里宿主视图比窗口高，popover 把它
    /// **垂直居中**显示 → 整列内容先上跳再落回（±11~16pt）。animates 开关、隐式动画
    /// 剥离、preferredContentSize 写法均与此无关（逐项实验排除）；直接在 popover 的
    /// 私有内部容器上加约束也会与其布局冲突（实测首开即错位）。
    ///
    /// 解法 = 自有容器做「尺寸闸门」：
    ///   - 宿主视图四边 + 等高钉死在容器上（恒等于窗口内容区），内容高于窗口的瞬态
    ///     只在底缘被裁 1-2 帧（窗口追上后自然揭示），构造性不可能上下漂移；
    ///   - 窗口尺寸由 PanelView 的 PreferenceKey 高度上报 → `updateContentHeight`
    ///     回写容器 VC 的 preferredContentSize 驱动（NSPopover 观察它调整窗口）；
    ///   - `sizingOptions = []` 让 SwiftUI 根视图按容器边界（而非理想尺寸）布局，
    ///     配合 PanelView 根部的顶端对齐弹性 frame，内容恒钉容器顶部。
    private lazy var panelContainerController: NSViewController = {
        let container = NSViewController()
        container.view = NSView()
        let host = hostingController.view
        host.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            host.heightAnchor.constraint(equalTo: container.view.heightAnchor),
        ])
        return container
    }()

    /// SwiftUI 宿主控制器。接线模式与 DockPolicyManager.openSettings 一致
    /// （单例直接注入 environmentObject；environmentObject 修饰会擦掉具体视图类型，
    /// 存成属性需包一层 AnyView）。
    private lazy var hostingController: NSHostingController<AnyView> = {
        let rootView = AnyView(
            PanelView(state: state)
                .environmentObject(L10n.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(PresetManager.shared)
        )
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = []
        return hosting
    }()

    /// 内容高度上报入口（PanelView 的 onPreferenceChange 调用）。
    /// 带 0.5pt 去抖；同步直写容器 VC 的 preferredContentSize（onPreferenceChange
    /// 在布局完成后派发，此时写属性不会重入布局）——多一跳 async 会让窗口滞后
    /// 容器视图一整轮 runloop，居中漂移窗口从 1 帧拉长到 ~0.15s（实测）。
    @MainActor
    func updateContentHeight(_ height: CGFloat) {
        guard abs(panelContainerController.preferredContentSize.height - height) > 0.5 else { return }
        panelContainerController.preferredContentSize = NSSize(width: 380, height: height)
        // 窗口 resize 会触发系统重设玻璃配置（2026-09-14 实测复现+验证：纯高度
        // 变化即可让 .clear 被打回 .regular，按 keyed 态渲染白奶变体且持久不恢复
        // ——即「点击展开显示器参数箭头后背板变白」的根因；expand 是用户可触发的
        // 唯一改高度交互，其余点击均无恙）。高度变化是面板全部 resize 路径的必经
        // 点，在此幂等补挂；系统重配可能落在本轮布局之后，再补一跳 async。
        applyLiquidGlassBackdrop()
        DispatchQueue.main.async { [weak self] in self?.applyLiquidGlassBackdrop() }
    }

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
        // 背板定型（clear 玻璃 + 常驻 key），详见 applyLiquidGlassBackdrop 注释；
        // 窗口 resize 后的补挂在 updateContentHeight。
        applyLiquidGlassBackdrop()
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

    @MainActor func popoverDidShow(_ notification: Notification) {
        applyLiquidGlassBackdrop()
    }

    // MARK: - 背景板（液态玻璃 clear + 常驻 key，2026-09-14 像素实测定型）

    /// 背板定型方案（2026-09-14 实验矩阵，macOS 26）：
    /// NSPopover 的系统玻璃（私有类 NSGlassView，继承公开类 NSGlassEffectView）
    /// 内部有一层随窗口 key 态自适应的渲染：非 key 与 key 是两个观感变体。
    /// 实测结论（边距带像素采样）：
    ///   - 「点击变白」的驱动信号 = **窗口变 key**（makeKey 单独即可完整复现
    ///     +78~+102 的加白；与 App 激活无关——_NSPopoverWindow 继承 NSPanel 且
    ///     自带 .nonactivatingPanel，点击本就只变 key 不激活 App）；
    ///   - `style = .clear` 只改变 key 态观感；**clear+key 是所有状态里最薄的
    ///     玻璃**（对壁纸的雾度约为 regular 初始态的一半），仍保有模糊/边框/
    ///     箭头 chrome；regular+key 则是最厚的白奶态（即原 bug 观感）；
    ///   - `tintColor = .clear` 是彻底 no-op（与不设完全同值）。
    /// 因此定型 = **clear + show 即 makeKey**：面板一出生就处于最薄的 keyed 态，
    /// 点击时已无状态可切换，「点击变白」构造性不存在（真实合成点击实测零漂移、
    /// 面板不收起）。makeKey 在非激活面板上不抢键盘焦点、不激活 App。
    /// macOS 13~15 没有 NSGlassView，样式循环找不到视图即跳过；makeKey 无害保留。
    @MainActor
    private func applyLiquidGlassBackdrop() {
        guard let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
        if #available(macOS 26.0, *) {
            guard let root = window.contentView?.superview ?? window.contentView else { return }
            for glass in Self.glassEffectViews(under: root) {
                glass.style = .clear
            }
        }
    }

    /// 递归收集视图树里的 NSGlassEffectView（含私有子类 NSGlassView）。
    /// NSGlassView 是 contentView 的兄弟节点（NSPopoverFrame → [NSGlassView,
    /// contentView]），必须从 contentView.superview 起遍历才能找到。
    @available(macOS 26.0, *)
    private static func glassEffectViews(under view: NSView) -> [NSGlassEffectView] {
        var result: [NSGlassEffectView] = []
        if let glass = view as? NSGlassEffectView { result.append(glass) }
        for sub in view.subviews { result.append(contentsOf: glassEffectViews(under: sub)) }
        return result
    }

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
