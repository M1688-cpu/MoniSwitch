import Foundation
import AppKit
import SwiftUI

/// F1/F2 调外接屏亮度时的迷你 HUD 气泡：浮在菜单栏图标下方，与面板同设计语言
/// （不透明填充圆角气泡 + 悬浮阴影），显示太阳图标 + 进度条 + 百分比，1.2s 无新
/// 事件后淡出；重复按键自动续期。纯展示：`ignoresMouseEvents` 挡全部命中。
@MainActor
final class BrightnessHUD {
    static let shared = BrightnessHUD()

    private var panel: NSPanel?
    private var model = HUDModel()
    private var hideWorkItem: DispatchWorkItem?
    private let size = NSSize(width: 168, height: 44)
    private let autoHideInterval: TimeInterval = 1.2

    /// 显示 HUD 并更新亮度百分比（主线程）。
    func show(percent: Double) {
        assert(Thread.isMainThread)
        let panel = ensurePanel()

        model.percent = min(max(percent, 0), 1)
        positionNearStatusBar(panel: panel)

        hideWorkItem?.cancel()
        panel.alphaValue = panel.isVisible ? 1 : 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

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
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: BrightnessHUDView(model: model))
        self.panel = panel
        return panel
    }

    /// 锚定在菜单栏图标正下方（图标 frame 由面板壳提供；取不到时退到主屏右上角）。
    private func positionNearStatusBar(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let anchor = PanelController.shared.statusItemFrame
        var x: CGFloat
        if let anchor, anchor.minX > 0 {
            x = anchor.midX - size.width / 2
        } else {
            x = screen.frame.maxX - size.width - 16
        }
        // 菜单栏高度约 24~25pt；HUD 悬在图标下方留 8pt 间距
        let y: CGFloat
        if let anchor {
            y = anchor.minY - size.height - 8
        } else {
            y = screen.frame.maxY - 44 - size.height - 8
        }
        x = max(screen.frame.minX + 8, min(x, screen.frame.maxX - size.width - 8))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// HUD 的 SwiftUI 状态（百分比）。
private final class HUDModel: ObservableObject {
    @Published var percent: Double = 0.5
}

/// 气泡内容：太阳图标 + 圆角进度条 + 百分比。
private struct BrightnessHUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 10) {
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}
