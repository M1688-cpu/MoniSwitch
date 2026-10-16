import AppKit
import SwiftUI

/// 菜单栏悬浮面板壳（v2）：NSStatusItem + 自有无边框 NSPanel。
///
/// v2 弃用 NSPopover 的原因：旧实现约半数篇幅在与 popover 系统行为搏斗——
/// 背板材质层隐藏（26/27 两套）、尺寸闸门防内容居中漂移、常驻隐形防材质层
/// 重建闪烁、transient 关点竞态。自有 NSPanel 后这些 hack 整体消亡：
/// - 无系统背板材质层 → 无需隐藏/补挂/脉冲，悬浮卡片 = 透明窗口 + 自绘阴影；
/// - 窗口 frame 由我们直写（顶边锚死）→ 垂直漂移构造性不可能；
/// - 无 transient 行为 → 关点竞态不存在，外部点击收起由手装监控承担；
/// - 常驻窗口 + alpha/orderFront 显隐 → 无重建闪烁，入场动画（淡入 + 顶部
///   锚缩放 0.92→1，模拟系统 popover「自菜单栏图标下方生长」）完全自绘。
///
/// 保留的既有工程结论：
/// - `sizingOptions = []` + PanelView 根部顶端对齐弹性 frame：SwiftUI 按宿主
///   边界（而非理想尺寸）布局，内容高于窗口的瞬态只在底缘被裁，不居中漂移；
/// - 高度经 PanelContentHeightKey 上报 → `updateContentHeight` 同步直写窗口
///   frame（多一跳 async 会把尺寸变化拖到下一轮 runloop，实测）；
/// - 图标必须模板 NSImage（cell 高亮反色机制）；
/// - 外部点击收起用全局+本地鼠标监控（LSUIElement App 不激活，系统自动
///   dismiss 信号不会到达）。
@MainActor
final class PanelController: NSObject {
    static let shared = PanelController()

    /// 面板 UI 状态（唯一消费者是 PanelView；AppState.init 自带首次 refresh
    /// 与热键/自动刷新绑定）。
    let state = AppState()

    private var statusItem: NSStatusItem?

    /// 菜单栏图标的屏幕全局 frame（亮度 HUD 锚定用）；图标未创建时 nil。
    var statusItemFrame: CGRect? {
        statusItem?.button?.window?.frame
    }

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    /// PanelContentHeightKey 上报的最新内容高度（首开前 layout 固化用）。
    private var contentHeight: CGFloat = 600
    /// 外部点击收起监控器（全局 + 本地各一）。
    private var dismissMonitors: [Any] = []

    var isShown: Bool { panel?.isVisible ?? false }

    private override init() { super.init() }

    // MARK: - 装配

    /// 创建菜单栏图标与悬浮面板（App 启动完成后调用一次）。
    func setup() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarIcon
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        statusItem = item

        makePanel()
        installDismissMonitors()
    }

    /// 菜单栏图标：SF Symbol `display`，medium 字重（semibold 偏粗、regular 偏细）。
    /// 关键：SF Symbol 返回的 NSImage 天然 isTemplate=true，系统在深浅色/高亮态
    /// 自动反色——NSStatusBarButton 的 cell 高亮（面板打开时）依赖这一机制。
    static let menuBarIcon: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        return NSImage(systemSymbolName: "display", accessibilityDescription: "MoniSwitch")?
            .withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "display", accessibilityDescription: "MoniSwitch")
            ?? NSImage()
    }()

    /// 构建常驻悬浮面板（一次构建、永不销毁；显隐 = alpha + orderFront/orderOut）。
    private func makePanel() {
        // environmentObject 修饰会擦掉具体视图类型，存属性需包一层 AnyView
        let rootView = AnyView(
            PanelView(state: state)
                .environmentObject(L10n.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(PresetManager.shared)
        )
        let hosting = NSHostingView(rootView: rootView)
        // 按宿主边界布局（理想尺寸模式会让内容超出窗口瞬态被居中），配合
        // PanelView 根部顶端对齐弹性 frame —— 「尺寸闸门」语义整体保留。
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: contentHeight)
        // 顶部居中缩放锚点（入场动画「自菜单栏图标下方生长」）：只在显示前改
        // 锚点（改锚点会平移 layer 视觉位置），用「改后回写原 frame」配方。
        hosting.layer?.anchorPoint = CGPoint(x: 0.5, y: 1)
        hosting.layer?.frame = hosting.bounds

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: contentHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false              // 阴影由面板卡片自绘（悬浮卡片设计语言）
        panel.isMovable = false
        panel.hidesOnDeactivate = false      // App 不激活，面板不应随失活消失
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting
        self.panel = panel
        self.hostingView = hosting

        // 首开前固化一轮布局，把 SwiftUI 理想高度经 PreferenceKey 桥上报上来
        hosting.layoutSubtreeIfNeeded()
    }

    private static var panelWidth: CGFloat { BubbleMetrics.hostContentWidth }

    // MARK: - 开关面板

    /// 点菜单栏图标 toggle；其余入口（外部点击/切设置）走 close()。
    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if isShown {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let hosting = hostingView else { return }
        // 面板打开 = 刷新显示器列表（AppState 定时器之外的开面板触发）+ 亮度值
        BrightnessManager.shared.refresh()
        positionPanel()
        // 出场起点：瞬时压到 0.92 缩放 + 零透明（中途打断重开也不跳变）
        hosting.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.92, y: 0.92))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        // 淡入（panel 层）+ 生长（内容 layer 层）并行；NSView layer-backed 的
        // 隐式动画必须经 NSAnimationContext.allowsImplicitAnimation 打开（2026-10
        // 实测：裸 CATransaction 对 layer.transform 无动画）。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.26
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            hosting.layer?.setAffineTransform(.identity)
        })

        // 图标高亮反馈：模板 image 在高亮态自动反色；异步到下一轮 runloop 置位才稳
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.button?.cell?.isHighlighted = true
        }
    }

    /// 主动收起（外部点击收起 /「设置」切走焦点前调用）。淡出 + 收缩后 orderOut。
    func close() {
        hidePanel()
    }

    private func hidePanel() {
        guard let panel, let hosting = hostingView, panel.isVisible else { return }
        statusItem?.button?.cell?.isHighlighted = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        })
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            hosting.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.92, y: 0.92))
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// 面板顶边锚定在菜单栏图标正下方（图标 frame 取不到时退主屏右上角）。
    private func positionPanel() {
        guard let panel else { return }
        let anchor = statusItemFrame
        let screen = anchor.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.frame.size
        var x: CGFloat
        var topY: CGFloat
        if let anchor {
            x = anchor.midX - size.width / 2
            topY = anchor.minY - 6
        } else {
            x = screen.frame.maxX - size.width - 16
            topY = screen.frame.maxY - 44 - 6
        }
        x = max(screen.frame.minX + 8, min(x, screen.frame.maxX - size.width - 8))
        let origin = NSPoint(x: x, y: topY - size.height)
        panel.setFrameOrigin(origin)
    }

    // MARK: - 高度桥（PanelView 的 PanelContentHeightKey → onPreferenceChange 调用）

    /// 内容高度变化 → 顶边锚死改写窗口 frame（同步直写；增长方向无动画 =
    /// 「二值布局跳变」防漂移策略的延续，视觉动画由内容自身 mask 揭示承担）。
    func updateContentHeight(_ height: CGFloat) {
        guard let panel, abs(panel.frame.height - height) > 0.5 else { return }
        contentHeight = height
        let size = NSSize(width: Self.panelWidth, height: height)
        if panel.isVisible {
            // 可见时：顶边不动，向下生长/收缩
            var frame = panel.frame
            frame.origin.y = frame.maxY - height
            frame.size = size
            panel.setFrame(frame, display: true)
        } else {
            panel.setContentSize(size)
        }
    }

    // MARK: - 外部点击收起（手装事件监控）

    /// LSUIElement App 从不激活，系统自动 dismiss 信号不会到达——手装鼠标按下
    /// 监控补齐：全局监控收其他 App/桌面/其他菜单栏图标的点击；本地监控收自家
    /// 其他窗口（如设置窗口）的点击；面板内与状态项按钮上的点击放行（后者交给
    /// togglePanel，防双重处理）。
    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismissIfClickedOutside()
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.dismissIfClickedOutside()
            }
            return event
        }
        dismissMonitors = [global, local].compactMap { $0 }
    }

    private func dismissIfClickedOutside() {
        guard let panel, panel.isVisible else { return }
        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) { return }
        if let button = statusItem?.button, button.window?.frame.contains(location) == true { return }
        hidePanel()
    }
}
