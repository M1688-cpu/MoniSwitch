import Foundation
import AppKit
import SwiftUI

/// F1/F2 调外接屏亮度时的迷你 HUD 气泡：浮在菜单栏图标下方，与面板瓷砖同为
/// Liquid Glass 胶囊（macOS 26+；14/15 回退系统材质），显示太阳图标 + 进度条 +
/// 百分比，1.2s 无新事件后淡出；重复按键自动续期。纯展示：`ignoresMouseEvents`
/// 挡全部命中。窗口四周留 `shadowPadding` 透明区，玻璃自带的边缘阴影不被裁成方框。
@MainActor
final class BrightnessHUD {
    static let shared = BrightnessHUD()

    private var panel: NSPanel?
    private var model = HUDModel()
    private var hideWorkItem: DispatchWorkItem?
    /// 气泡内容尺寸（不含阴影留白）。
    private let contentSize = NSSize(width: 168, height: 44)
    /// 阴影留白：悬浮阴影必须落在窗口内，否则被窗口边界裁成方框（2026-10-17
    /// 用户实测；与悬停气泡浮窗 tooltipShadowPadding 同源问题、同款解法）。
    private let shadowPadding: CGFloat = 16
    private var windowSize: NSSize {
        NSSize(width: contentSize.width + shadowPadding * 2,
               height: contentSize.height + shadowPadding * 2)
    }
    private let autoHideInterval: TimeInterval = 1.2

    /// 显示 HUD 并更新亮度百分比（主线程）。
    func show(percent: Double) {
        assert(Thread.isMainThread)
        let panel = ensurePanel()

        model.percent = min(max(percent, 0), 1)
        positionNearStatusBar(panel: panel)

        hideWorkItem?.cancel()
        // 直接置 1 再上屏：菜单栏 agent 在后台时窗口淡入动画不可靠（曾导致
        // alpha 停在 0、气泡永远不可见）。淡出仍保留。
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            self?.fadeOut()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideInterval, execute: work)
    }

    // MARK: - 内部

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            if panel.alphaValue == 0 {
                panel.orderOut(nil)
            }
        })
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // NSPanel 默认在 App 失活时自动隐藏；本 App 是菜单栏 agent，按键时通常
        // 不是 frontmost，必须关掉，否则气泡刚 show 就被 AppKit 收走（2026-10-17）。
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // 气泡本体居窗口中央，四周留出阴影呼吸区（窗口透明，不会露出方框）。
        panel.contentView = NSHostingView(rootView: BrightnessHUDView(model: model).padding(shadowPadding))
        self.panel = panel
        return panel
    }

    /// 锚定在菜单栏图标正下方；屏幕取图标所在屏（多屏下 NSScreen.main 会锚错屏，
    /// 2026-10 code-review 指出），图标 frame 取不到时退主屏右上角。
    /// 窗口比气泡大一圈阴影留白：按**内容**定位后外扩 padding，视觉位置与旧版一致。
    private func positionNearStatusBar(panel: NSPanel) {
        let anchor = PanelController.shared.statusItemFrame
        let screen = anchor.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        guard let screen else { return }
        var contentX: CGFloat
        var contentTopY: CGFloat
        if let anchor {
            contentX = anchor.midX - contentSize.width / 2
            contentTopY = anchor.minY - 8
        } else {
            contentX = screen.frame.maxX - contentSize.width - 16
            contentTopY = screen.frame.maxY - 44 - 8
        }
        let windowX = max(screen.frame.minX + 8,
                          min(contentX - shadowPadding,
                              screen.frame.maxX - windowSize.width - 8))
        let windowY = contentTopY - contentSize.height - shadowPadding
        panel.setFrameOrigin(NSPoint(x: windowX, y: windowY))
    }
}

/// HUD 的 SwiftUI 状态（百分比）。
private final class HUDModel: ObservableObject {
    @Published var percent: Double = 0.5
}

/// 气泡内容：太阳图标 + 圆角进度条 + 百分比，整体是一枚玻璃胶囊。
private struct BrightnessHUDView: View {
    @ObservedObject var model: HUDModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let content = HStack(spacing: 10) {
            Image(systemName: "sun.max")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(BrandColor.accent)
                        .frame(width: max(proxy.size.width * model.percent, 4))
                }
            }
            .frame(width: 74, height: 6)
            Text("\(Int((model.percent * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(width: 168, height: 44)

        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: Capsule())
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
