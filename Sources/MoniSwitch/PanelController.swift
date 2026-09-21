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

        // [DEBUG-autoshow]（临时调试，定型后删除）：启动后自动弹出面板，供像素采样验证
        // 背板/阴影。macOS 27 上合成点击对面板不可靠、AX 开面板有命中区偏移，自动弹出
        // 是唯一无副作用的机器验证入口。
        if UserDefaults.standard.bool(forKey: "MoniswitchDebugAutoShow"),
           let button = item.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.show(from: button)
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
        // 窗口 resize 会触发系统重设玻璃配置（历史实测 26：.clear 被打回 .regular；隐藏层
        // 也可能被系统复活），高度变化是面板全部 resize 路径的必经点，在此幂等补挂；
        // 系统重配可能落在本轮布局之后，再补一跳 async。
        applyFloatingBackdrop()
        DispatchQueue.main.async { [weak self] in self?.applyFloatingBackdrop() }
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
        // 无背板悬浮处理（26+：隐藏玻璃层 + 关窗口投影；13~15：makeKey 保持系统背板），
        // 详见 applyFloatingBackdrop；窗口 resize 后的补挂在 updateContentHeight。
        applyFloatingBackdrop()
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
        applyFloatingBackdrop()
        // [DEBUG-dump]（临时调试，定型后删除）：dump 窗口视图树到 /tmp，用于定位
        // macOS 27 上背板视图的真实类名（玻璃隐藏是否命中）。
        if UserDefaults.standard.bool(forKey: "MoniswitchDebugDumpTree"),
           let window = popover.contentViewController?.view.window {
            Self.dumpViewTree(window)
        }
        // [DEBUG-bump]（临时调试，定型后删除，每进程一次）：一次性抬升内容高度模拟
        // 「展开参数」触发的窗口 resize，供验证 resize 后玻璃不复活（外缘仍全透）。
        let bump = UserDefaults.standard.integer(forKey: "MoniswitchDebugBumpHeight")
        if bump > 0, !didDebugBump {
            didDebugBump = true
            let h = panelContainerController.preferredContentSize.height
            updateContentHeight(h + CGFloat(bump))
        }
    }

    /// [DEBUG-dump] 的视图树 dump（含兄弟节点，从 contentView.superview 起走）；
    /// 同时 dump layer 树（玻璃可能是 CALayer 而非子视图）与关键类的运行时属性名。
    private static func dumpViewTree(_ window: NSWindow) {
        var lines: [String] = []
        lines.append("window=\(type(of: window)) hasShadow=\(window.hasShadow) isOpaque=\(window.isOpaque) frame=\(window.frame)")
        func walk(_ v: NSView, depth: Int) {
            lines.append(String(repeating: "  ", count: depth)
                + "\(type(of: v)) frame=\(NSStringFromRect(v.frame)) hidden=\(v.isHidden) alpha=\(v.alphaValue)")
            for s in v.subviews { walk(s, depth: depth + 1) }
        }
        if let content = window.contentView {
            walk(content.superview ?? content, depth: 0)
        }
        // layer 树：根取 NSPopoverFrame（contentView 的 superview，窗口真正的 chrome 视图）
        lines.append("--- layers ---")
        func walkLayer(_ l: CALayer, depth: Int) {
            lines.append(String(repeating: "  ", count: depth)
                + "\(type(of: l)) frame=\(l.frame) hidden=\(l.isHidden) name=\(l.name ?? "-")")
            for s in l.sublayers ?? [] { walkLayer(s, depth: depth + 1) }
        }
        if let popoverFrame = window.contentView?.superview {
            lines.append("popoverFrameClass=\(type(of: popoverFrame)) wantsLayer=\(popoverFrame.wantsLayer)")
            if let layer = popoverFrame.layer { walkLayer(layer, depth: 0) }
        }
        // 私有属性现值（找玻璃相关旋钮）
        lines.append("--- private prop values ---")
        for p in ["_glassWindowBackingGlassView", "cn_isSkyglowEnabled",
                  "_hostWindowIsOpaque", "_hostWindowBackgroundColor", "allowsInteriorShadow"] {
            let v = window.value(forKey: p)
            if let view = v as? NSView {
                lines.append("\(p) = \(type(of: view)) frame=\(NSStringFromRect(view.frame)) hidden=\(view.isHidden) alpha=\(view.alphaValue) desc=\(view)")
            } else {
                lines.append("\(p) = \(String(describing: v))")
            }
        }
        // 全应用窗口清单（排查与面板无关的幽灵窗口，如 900x450 的 Settings 占位窗）
        lines.append("--- app windows ---")
        for w in NSApp.windows {
            lines.append("\(type(of: w)) frame=\(NSStringFromRect(w.frame)) title='\(w.title)' visible=\(w.isVisible) identifier=\(w.identifier?.rawValue ?? "-")")
        }
        // 运行时属性名（_NSPopoverWindow 与 NSPopoverFrame，找玻璃相关私有旋钮）
        lines.append("--- runtime properties ---")
        func dumpProps(_ cls: AnyClass, label: String) {
            lines.append("[\(label)] \(cls)")
            var c: AnyClass? = cls
            while let cur = c {
                var count: UInt32 = 0
                if let props = class_copyPropertyList(cur, &count) {
                    let names = (0..<count).map { String(cString: property_getName(props[Int($0)])) }
                    if !names.isEmpty { lines.append("  \(cur): \(names.joined(separator: ", "))") }
                }
                c = class_getSuperclass(cur)
            }
        }
        dumpProps(type(of: window), label: "window")
        if let frame = window.contentView?.subviews.first { dumpProps(type(of: frame), label: "popoverFrame") }
        let text = lines.joined(separator: "\n")
        try? text.write(toFile: "/tmp/moniswitch-viewtree.txt", atomically: true, encoding: .utf8)
    }

    /// [DEBUG-bump] 的每进程一次性标记。
    private var didDebugBump = false

    // MARK: - 背板处理（无背板悬浮，2026-09-21 重启「悬浮卡片」路线）

    /// 无背板悬浮（用户拍板：本轮根治 2026-09-14 回退时的两条死因后正式启用）：
    ///
    /// - **macOS 26+：** 2026-09-21 视图树 dump 实测（27）：popover 层级为
    ///   `_NSPopoverWindow → NSPopoverFrame → NSView(13,13) → NSHostingView`，
    ///   **27 上已不存在 NSGlassView/NSGlassEffectView 视图**（26 时代的隐藏技法
    ///   与 .clear 旋钮在 27 空转的共同根因）；玻璃背板由窗口/NSPopoverFrame
    ///   自身渲染。当前杠杆：`window.hasShadow = false`（已验证可写入）+
    ///   窗口透明化（isOpaque=false + backgroundColor=.clear）+ 26 及以下仍走
    ///   玻璃视图隐藏（26 上该视图存在且技法已验证）。开发期由
    ///   MoniswitchDebugBackdropMode 跑策略矩阵定位 27 的最终杀招，定型后固化。
    /// - **macOS 13~15：保留系统玻璃背板（makeKey 无害保留，与 v0.1.6 行为一致）。**
    ///
    /// 卡片阴影直接落在壁纸上的观感由 BubbleMetrics 的悬浮阴影参数承担
    /// （bubbleFloatingShadow，壁纸承接语境重调）；完整实验矩阵与历史结论见
    /// AGENTS.md「悬浮卡片背景板」条目与 HANDOFF 系列文档。
    @MainActor
    private func applyFloatingBackdrop() {
        guard let window = popover.contentViewController?.view.window else { return }
        guard #available(macOS 26.0, *) else {
            window.makeKey()   // 13~15：保留系统背板行为
            return
        }
        // [DEBUG-backdrop-mode]（临时策略矩阵，定型后删除；消融阶梯 1<2<3<0）：
        // 0/未写=全量策略（关投影+窗口透明化+隐藏玻璃视图[26-]+隐藏材质 layer[27]）；
        // 1=完全不干预（对照组）；2=仅关投影+窗口透明化；3=0 减 layer 级（视图级 only）。
        let mode = UserDefaults.standard.integer(forKey: "MoniswitchDebugBackdropMode")
        if mode == 1 { return }
        window.hasShadow = false
        if mode == 0 || mode == 2 {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        if mode == 0 || mode == 3 {
            // 视图级（macOS 26 及以下：玻璃以 NSGlassEffectView 子类视图存在）
            if let root = window.contentView?.superview ?? window.contentView {
                for glass in Self.glassEffectViews(under: root) {
                    glass.isHidden = true
                }
            }
            // layer 级（macOS 27：玻璃以纯 CALayer 存在——NSPopoverFrame.layer 下名为
            // kCUIVariantPopoverMaterial 的材质组，含 backdrop 磨砂/fill/tone/Chameleon
            // 自适应四层；视图级手段在 27 全部够不着，2026-09-21 dump 定位）
            if let frameLayer = window.contentView?.superview?.layer {
                Self.hideNamedLayers(under: frameLayer, name: "kCUIVariantPopoverMaterial")
            }
        }
        // [DEBUG-makekey]（临时调试，定型后删除）：验证 key 态（点击面板内部后的状态）
        // 材质层不复活——26 时代 key 态是加白触发器，27 需单独确认。
        if UserDefaults.standard.bool(forKey: "MoniswitchDebugMakeKey") {
            window.makeKey()
        }
    }

    /// 递归隐藏指定名称的 CALayer（不进入已命中层的内部——其子层属于同一材质组）。
    private static func hideNamedLayers(under layer: CALayer, name: String) {
        for sub in layer.sublayers ?? [] {
            if sub.name == name {
                sub.isHidden = true
            } else {
                hideNamedLayers(under: sub, name: name)
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
