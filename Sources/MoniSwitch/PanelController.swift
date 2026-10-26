import AppKit
import SwiftUI

/// 菜单栏悬浮面板壳（v2）：NSStatusItem + 自有无边框 NSPanel。
///
/// v2 弃用 NSPopover 的原因：旧实现约半数篇幅在与 popover 系统行为搏斗——
/// 背板材质层隐藏（26/27 两套）、尺寸闸门防内容居中漂移、常驻隐形防材质层
/// 重建闪烁、transient 关点竞态。自有 NSPanel 后这些 hack 整体消亡：
/// - 无系统背板材质层 → 无需隐藏/补挂/脉冲，悬浮卡片 = 透明窗口 + 自绘阴影；
/// - 窗口尺寸**恒定**（fixedWindowHeight，内容理想尺寸也钉死）→ 面板可见期间
///   无人改写窗口 frame，顶边天然不动；SwiftUI 的「自动跟随内容尺寸」是底部
///   锚定的，手动写与它并存即双写者，会触发约束自激闪退（2026-10-18 终版）；
/// - 无 transient 行为 → 关点竞态不存在，外部点击收起由手装监控承担；
/// - 常驻窗口 + alpha/orderFront 显隐 → 无重建闪烁，入场动画（淡入 + 顶部
///   锚缩放 0.96→1，模拟系统 popover「自菜单栏图标下方生长」）完全自绘。
///
/// 保留的既有工程结论：
/// - sizingOptions = [] + PanelView 根部固定为窗口尺寸、内容顶端对齐：内容
///   在窗口内部做布局动画，不会居中漂移，也不会反向驱动窗口尺寸；
/// - 高度经 PanelContentHeightKey 上报，仅用于外部点击命中判定；
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
    /// 面板顶边（屏幕坐标，y 向上）：只在隐藏状态定位时重算，供点击命中判定。
    private var panelTop: CGFloat = 0

    /// 收起动画进行中（panel.isVisible 在 orderOut 前仍为 true）。
    private var isHiding = false
    /// 每次显隐递增，避免旧收起动画的 completion 关闭重新打开的面板。
    private var presentationGeneration = 0

    var isShown: Bool { panel?.isVisible ?? false }

    /// 是否允许弹悬停补充气泡：可见且不在收起动画中。收起淡出期间（0.16s）
    /// 迟到的 dwell 任务不得再弹浮窗，否则面板消失后气泡会留在壁纸上。
    var canShowTooltips: Bool { isShown && !isHiding }

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

    /// 菜单栏图标：SF Symbol display，medium 字重（semibold 偏粗、regular 偏细）。
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
        // 2026-10-18 终版架构：**窗口高度恒定**（屏幕高度 − 40），面板可见期间
        // 任何一方都不再改窗口 frame。SwiftUI 的 windowDidLayout →
        // updateAnimatedWindowSize 是「按内容理想尺寸自动改窗口」的写者（且是
        // **底部锚定**：实测 minY 不变、maxY 向上越出屏幕），与高度桥的手动写
        // 形成双写者 → 同 display cycle 内 update-constraints 自激 → 闪退；
        // 唯一稳妥的解法是让「内容尺寸变化」不再引起窗口尺寸变化：
        // PanelView 根部固定为这个高度（理想尺寸恒定），窗口自身也建造成这个
        // 高度——展开/收起只在窗口内部做 SwiftUI 布局动画，顶边与窗口天然不动，
        // 面板视觉高度 = 内容高度（下方是透明的多余区域，点击判定按内容矩形算，
        // 见 dismissIfClickedOutside）。
        let winHeight = Self.fixedWindowHeight
        // environmentObject 修饰会擦掉具体视图类型，存属性需包一层 AnyView
        let rootView = AnyView(
            PanelView(state: state, windowHeight: winHeight)
                .environmentObject(L10n.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(PresetManager.shared)
        )
        let hosting = NSHostingView(rootView: rootView)
        // 按宿主边界布局；PanelView 根部固定为窗口尺寸并顶端对齐内容。
        hosting.sizingOptions = []
        // 2026-10-18 闪退第二根因（与高度桥配套的机制性护栏）：窗口尺寸一变，
        // NSHostingView 会经 didChangeValue(frame) → invalidateSafeAreaInsets →
        // requestUpdate(after: 0) 立刻在**同一个 display cycle** 里再要一轮
        // Update Constraints。面板内容完全不需要窗口安全区（无标题栏、自带
        // padding），置空后该失效级联短路——「resize → setNeedsUpdate → 再布局
        // → 再 resize」的自激循环从机制上被掐断（invalidateSafeAreaInsets 里
        // 对 regions 求交为空即直接返回，反汇编实证）。
        hosting.safeAreaRegions = []
        hosting.wantsLayer = true
        hosting.frame = NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.fixedWindowHeight)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.fixedWindowHeight),
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
        panel.animationBehavior = .none       // 显隐由下方统一控制，避免系统窗口动画叠加
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting
        self.panel = panel
        self.hostingView = hosting

        // 首开前固化一轮布局，让内容高度（外部点击命中矩形）先上报一次。
        hosting.layoutSubtreeIfNeeded()
        Self.configurePresentationAnchor(for: hosting)
    }

    private static var panelWidth: CGFloat { BubbleMetrics.hostContentWidth }

    /// 设置顶部缩放锚点，并补偿修改锚点造成的位移（仅在单位变换、隐藏时调用）。
    static func configurePresentationAnchor(for hosting: NSView) {
        // NSHostingView 的坐标向下，y=1 是底部；旧实现使首帧下移再向上恢复。
        hosting.layer?.anchorPoint = CGPoint(x: 0.5, y: hosting.isFlipped ? 0 : 1)
        hosting.layer?.frame = hosting.bounds
    }

    /// 面板窗口的固定高度（屏幕高度 − 40，至少 600）。
    ///
    /// 窗口尺寸恒定是 2026-10-18 闪退终版修复的支点：SwiftUI 会在内容尺寸动画
    /// 期间按「动画中的内容尺寸」自动改写窗口 frame（NSHostingView.windowDidLayout
    /// → updateAnimatedWindowSize，底部锚定），只要窗口尺寸会变，它与任何手动
    /// 高度桥就是双写者，必然在同一 display cycle 里反复触发 Update Constraints
    /// 直至 AppKit 抛异常。把窗口与内容理想尺寸都钉死，就没有窗口尺寸变化，
    /// 展开/收起退化为窗口内部的纯 SwiftUI 布局动画。下方多出来的区域完全透明。
    private static var fixedWindowHeight: CGFloat {
        max(600, (NSScreen.main?.frame.height ?? 900) - 40)
    }

    // MARK: - 开关面板

    /// 点菜单栏图标 toggle；其余入口（外部点击/切设置）走 close()。
    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if isShown && !isHiding {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panel, let hosting = hostingView else { return }
        // 防御性收掉残留的悬停气泡（正常路径在 hidePanel 已收）。
        FloatingTooltipPresenter.shared.hide()
        presentationGeneration += 1
        isHiding = false
        // 面板打开 = 刷新显示器列表（AppState 定时器之外的开面板触发）+ 亮度值
        BrightnessManager.shared.refresh()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !panel.isVisible {
            positionPanel()
            // 宿主附着与布局结束后再校准顶部锚点；可见期间不改窗口或 layer frame。
            hosting.layer?.setAffineTransform(.identity)
            Self.configurePresentationAnchor(for: hosting)
            hosting.layer?.setAffineTransform(reduceMotion ? .identity :
                CGAffineTransform(scaleX: 0.96, y: 0.96))
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()

        // 淡入（panel 层）+ 生长（内容 layer 层）并行；NSView layer-backed 的
        // 隐式动画必须经 NSAnimationContext.allowsImplicitAnimation 打开（2026-10
        // 实测：裸 CATransaction 对 layer.transform 无动画）。
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.15 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = !reduceMotion
            panel.animator().alphaValue = 1
            hosting.layer?.setAffineTransform(.identity)
        })

        // 图标高亮反馈：模板 image 在高亮态自动反色；异步到下一轮 runloop 置位才稳
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown, !self.isHiding else { return }
            self.statusItem?.button?.cell?.isHighlighted = true
        }
    }

    /// 主动收起（外部点击收起 /「设置」切走焦点前调用）。淡出 + 收缩后 orderOut。
    func close() {
        hidePanel()
    }

    private func hidePanel() {
        guard let panel, let hosting = hostingView, panel.isVisible, !isHiding else { return }
        isHiding = true
        presentationGeneration += 1
        let generation = presentationGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // 悬停气泡是独立浮窗：面板 orderOut 不会自动带走它，必须显式收起
        // （鼠标停在气泡上时点外部收面板，SwiftUI 收不到 hover exit）。
        FloatingTooltipPresenter.shared.hide()
        statusItem?.button?.cell?.isHighlighted = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            context.allowsImplicitAnimation = !reduceMotion
            hosting.layer?.setAffineTransform(reduceMotion ? .identity :
                CGAffineTransform(scaleX: 0.96, y: 0.96))
        }, completionHandler: { [weak self] in
            // 快速关—开—关时，每个 completion 只能结束自己那一轮收起。
            guard let self, self.presentationGeneration == generation,
                  self.isHiding, panel.alphaValue < 0.05 else { return }
            panel.orderOut(nil)
            self.isHiding = false
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
        panelTop = topY
    }

    // MARK: - 高度桥（PanelView 的 PanelContentHeightKey → onPreferenceChange 调用）

    /// 内容高度上报：**只做记录**（供外部点击的命中矩形用），不写任何窗口 frame。
    ///
    /// 2026-10-18 终版（两次失败的教训都在这里）：
    /// - 旧版逐帧 setFrame：SwiftUI 的 updateAnimatedWindowSize 也按「动画中的
    ///   内容尺寸」自动改窗口（**底部锚定**），两个写者逐帧拉锯；每次窗口变化经
    ///   didChangeValue(frame) → invalidateSafeAreaInsets → requestUpdate(after: 0)
    ///   在同一个 display cycle 里再排一轮 Update Constraints，超过窗口视图数即
    ///   抛 NSGenericException（崩溃窗口 {{1937,552},{404,850}} 的高度 850 正是
    ///   手动「贴合精确高度」那次写入后的值——「先缩上去再向下探出」）；
    /// - 上一版改成 72pt 步进 + 延迟贴合，写入仍在 SwiftUI 事务内，第二个写者
    ///   没消失，照崩；
    /// - 只让 SwiftUI 自己跟也不行：它底部锚定，面板顶边被一帧帧推高、越出屏幕。
    /// 终版把窗口高度与内容理想尺寸都钉死（见 fixedWindowHeight / PanelView
    /// 的 windowHeight），SwiftUI 没有可写的尺寸变化：顶边恒在 panelTop，
    /// 展开/收起退化为窗口内部的纯 SwiftUI 布局动画。
    func updateContentHeight(_ height: CGFloat) {
        contentHeight = height
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
        // 命中区按**内容矩形**算：窗口可能比内容高（透明多余区，见高度桥注释），
        // 点面板下方的透明带应视为「外部点击」。
        let contentBottom = panelTop - contentHeight
        let inPanel = location.x >= panel.frame.minX && location.x <= panel.frame.maxX
            && location.y >= contentBottom && location.y <= panel.frame.maxY
        if inPanel { return }
        if let button = statusItem?.button, button.window?.frame.contains(location) == true { return }
        hidePanel()
    }
}
