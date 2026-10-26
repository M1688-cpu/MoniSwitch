import Foundation
import AppKit
import SwiftUI

/// F1/F2 调外接屏亮度时的迷你 HUD 气泡：浮在菜单栏图标下方，与面板同设计语言
/// （不透明填充圆角气泡 + 悬浮阴影），显示太阳图标 + 进度条 + 百分比，1.2s 无新
/// 事件后淡出；重复按键自动续期。纯展示：`ignoresMouseEvents` 挡全部命中。
/// 窗口四周留 `shadowPadding` 透明区承接投影（否则阴影被窗口边界裁出方框）。
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

/// 气泡内容：太阳图标 + 圆角进度条 + 百分比。
/// HUD 宿主是独立 NSPanel（不继承面板的环境）：这里自行解析主题色板并注入
/// （BubbleBackground/进度条取色来源与面板一致）；观察 AppSettings 使主题切换
/// 在 HUD 常驻窗口上也实时生效。
private struct BrightnessHUDView: View {
    @ObservedObject var model: HUDModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PanelPalette {
        PanelTheme.palette(id: settings.panelThemeID, dark: colorScheme == .dark)
    }

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
                        .fill(palette.solid)
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
        // 与面板气泡同设计语言：不透明填充（浅色=派生近白淡染 / 深色=派生深底）
        // + 悬浮阴影（壁纸承接）。HUD 是独立小窗、不参与面板的右上光源布光。
        .environment(\.panelPalette, palette)
        .modifier(BubbleBackground())
        .bubbleFloatingShadow(lightDirection: false)
    }
}
