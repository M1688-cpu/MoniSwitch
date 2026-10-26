import AppKit
import SwiftUI

/// 悬停补充气泡的独立浮窗宿主（2026-10-17 改版）。
///
/// 旧实现把迷你气泡挂在控件 `.overlay` 上，有两重构造性裁剪：
///   1. 参数二级气泡整块包在 `RevealHeightModifier` 的 `.clipped()` 里——
///      居中的气泡右半截会被气泡边界裁掉（旧版因此给镜像/扩展传
///      `.topTrailing`，也就是用户截图里「气泡偏左」的根因）；
///   2. 面板窗口只有 `hostContentWidth`（404pt）宽——贴右缘的控件居中后
///      越过窗口的部分会被窗口边界裁掉。
/// 用户拍板「气泡居中，即使超出整个菜单栏界面也没有问题」，故改为独立无边框
/// 小窗：水平居中于控件正上方、可越过面板边界；`ignoresMouseEvents` 纯展示，
/// 不挡任何交互。窗口尺寸 = 迷你气泡 + `tooltipShadowPadding`（给阴影留出窗口
/// 内空间，否则阴影被窗口边界裁成直线）。
///
/// 生命周期：HoverDwellTooltip 的 dwell 计时到点 → `show`；移开 / 视图消失 /
/// 主面板收起 → `hide`（收起有 0.16s 过渡，等待 SwiftUI 退场动画结束）。
@MainActor
final class FloatingTooltipPresenter {
    static let shared = FloatingTooltipPresenter()

    private var panel: NSPanel?
    private var model: FloatingTooltipModel?
    private var hideWorkItem: DispatchWorkItem?
    /// show/hide 代际号：show 的「下一轮置 visible」异步块与已过期的 hide
    /// 任务都靠它丢弃——防止「hover 在 1 个 runloop 内进出」时退场任务被
    /// 重新点亮、气泡永久停留。
    private var generation = 0

    private init() {}

    /// 在控件屏幕矩形正上方居中展示气泡。`anchor` 为 AppKit 屏幕坐标
    /// （原点左下、y 向上，由 TooltipAnchorBox 从视图窗口转换得到）。
    func show(text: String, icon: String, anchor: CGRect) {
        guard !text.isEmpty else { return }
        // 面板已收起/正在收起时不再弹（防御「dwell 任务在面板 orderOut 后才落地」：
        // 面板常驻不销毁，SwiftUI 收不到 hover exit，任务可能迟到）。
        guard PanelController.shared.canShowTooltips else { return }
        hideWorkItem?.cancel()
        hideWorkItem = nil
        generation += 1
        let generation = self.generation

        let panel = ensurePanel()
        let model = FloatingTooltipModel(text: text, icon: icon)
        let controller = NSHostingController(rootView: FloatingTooltipBubble(model: model))
        controller.sizingOptions = []
        // 尺寸由 SwiftUI 理想尺寸决定（内容 .fixedSize()，文字不换行）。
        // NSHostingView 无 sizeThatFits（那是 NSHostingController 的 API），
        // 故用 hosting controller 承载浮窗内容；测量不依赖窗口，先算后装。
        let measured = controller.sizeThatFits(in: NSSize(width: 2000, height: 2000))
        let size = NSSize(width: ceil(measured.width), height: ceil(measured.height))
        panel.contentViewController = controller
        self.model = model

        // 水平居中于控件；窗口底边下移一个投影留白——气泡本体底边 = 控件顶边 + 间隙。
        // 水平方向只做屏幕兜底（面板可被推到屏幕边缘；不夹击则文字会被屏幕裁掉）。
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let origin = FloatingTooltipLayout.windowOrigin(
            anchor: anchor,
            windowSize: size,
            screenVisibleFrame: screen?.visibleFrame
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        // 入场动画与旧 overlay 版同一条弹簧：先以隐藏态渲染（尺寸与可见性无关），
        // 下一轮 runloop 再置 visible —— 缩放 0.85→1 + 淡入，锚点为下缘（自按钮
        // 上缘向上生长）。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == generation, self.model === model else { return }
            model.isVisible = true
        }
    }

    /// 收起气泡：先播 SwiftUI 退场动画，再 orderOut。
    func hide() {
        guard let panel, panel.isVisible else { return }
        hideWorkItem?.cancel()
        generation += 1
        guard let hiddenModel = model else {
            panel.orderOut(nil)
            return
        }
        hiddenModel.isVisible = false
        let hideGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            // 模型身份 + 代际双重守卫：新一次 show 已经换了内容时，
            // 旧退场任务不得把新气泡 orderOut 掉。
            guard let self,
                  self.generation == hideGeneration,
                  self.model === hiddenModel,
                  hiddenModel.isVisible != true else { return }
            self.panel?.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        // 压在主面板（同为 .statusBar）之上。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

/// 浮窗定位（纯计算，测试锁定）：
/// - 水平方向以控件中心为对称轴（这就是「气泡居中」的定义，面板边界不参与夹击
///   ——用户拍板「即使超出整个菜单栏界面也没有问题」）；
/// - 只在会越出屏幕可见区时向屏幕内夹击，避免文字被屏幕裁掉；
/// - 垂直方向气泡底边 = 控件顶边 + `tooltipGap`；窗口比气泡四周多一圈
///   `tooltipShadowPadding`（阴影画在窗口内），故窗口底边相应下移。
enum FloatingTooltipLayout {
    static func windowOrigin(anchor: CGRect,
                             windowSize: CGSize,
                             screenVisibleFrame: CGRect?) -> CGPoint {
        var x = anchor.midX - windowSize.width / 2
        if let visible = screenVisibleFrame {
            let margin = BubbleMetrics.tooltipScreenMargin
            x = max(visible.minX + margin,
                    min(x, visible.maxX - windowSize.width - margin))
        }
        let y = anchor.maxY + BubbleMetrics.tooltipGap - BubbleMetrics.tooltipShadowPadding
        return CGPoint(x: x, y: y)
    }
}

/// 浮窗里的迷你气泡（与面板同设计语言：不透明浮面 + 细描边 + 浅阴影）。
/// 由 `show` 每次新建（文字/图标烘焙进模型），因此尺寸测量与文本变化同步，
/// 不依赖 SwiftUI 异步刷新。
private struct FloatingTooltipBubble: View {
    @ObservedObject var model: FloatingTooltipModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: model.icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(model.text)
                .font(.system(size: BubbleMetrics.fontCaption))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .modifier(MiniBubble())
        .fixedSize()
        // 阴影留白：气泡本体居中，窗口四周多出一圈透明区域承接阴影。
        .padding(BubbleMetrics.tooltipShadowPadding)
        .scaleEffect(model.isVisible || reduceMotion ? 1 : BubbleMetrics.tooltipPopScale,
                     anchor: .bottom)
        .opacity(model.isVisible ? 1 : 0)
        .animation(model.isVisible ? BubbleMetrics.tooltipSpring : .easeOut(duration: 0.12),
                   value: model.isVisible)
    }
}

/// 浮窗内容模型：文字/图标在构建时固定，仅 `isVisible` 驱动入场/退场动画。
private final class FloatingTooltipModel: ObservableObject {
    let text: String
    let icon: String
    @Published var isVisible = false

    init(text: String, icon: String) {
        self.text = text
        self.icon = icon
    }
}

// MARK: - 屏幕锚点探针

/// 控件屏幕矩形上报盒：背景 NSView 探针写入自身弱引用，hover 时换算成屏幕坐标。
final class TooltipAnchorBox {
    weak var view: NSView?

    /// AppKit 屏幕坐标（原点左下、y 向上）。视图不在窗口里时返回 nil。
    var screenRect: CGRect? {
        guard let view, let window = view.window else { return nil }
        let rectInWindow = view.convert(view.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }
}

/// 挂在控件 `.background` 的零绘制探针：只负责把自身 NSView 交给 AnchorBox。
/// `hitTest` 恒返回 nil——背景探针绝不能拦截控件自身的 hover/点击。
struct TooltipAnchorReader: NSViewRepresentable {
    let box: TooltipAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NonHitTestingView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }

    private final class NonHitTestingView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
