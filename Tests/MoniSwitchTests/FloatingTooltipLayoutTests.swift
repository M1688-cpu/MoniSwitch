// 悬停气泡浮窗的定位纯计算测试（2026-10-17）。
// 需求：气泡水平居中于控件正上方，允许越出面板边界（面板不参与夹击）；
// 只对屏幕可见区做兜底，避免文字被屏幕裁掉。
import Testing
import CoreGraphics
@testable import MoniSwitch

@Suite("悬停气泡浮窗定位")
struct FloatingTooltipLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("水平中心 = 控件中心（面板边界不参与）")
    func centersOnAnchor() {
        let anchor = CGRect(x: 940, y: 100, width: 120, height: 26)
        let origin = FloatingTooltipLayout.windowOrigin(
            anchor: anchor,
            windowSize: CGSize(width: 200, height: 56),
            screenVisibleFrame: screen
        )
        // 1000 - 200/2 = 900；即使气泡右缘 1100 越出父容器也不夹击。
        #expect(origin.x == 900)
    }

    @Test("屏幕右缘兜底：只夹到屏幕内，不因面板边界偏移")
    func clampsAtScreenRightEdge() {
        let anchor = CGRect(x: 1400, y: 100, width: 60, height: 26)
        let origin = FloatingTooltipLayout.windowOrigin(
            anchor: anchor,
            windowSize: CGSize(width: 200, height: 56),
            screenVisibleFrame: screen
        )
        // 未夹击 1430-100=1330 → 夹到 1440-200-6=1234。
        #expect(origin.x == 1234)
    }

    @Test("屏幕左缘兜底")
    func clampsAtScreenLeftEdge() {
        let anchor = CGRect(x: 0, y: 100, width: 40, height: 26)
        let origin = FloatingTooltipLayout.windowOrigin(
            anchor: anchor,
            windowSize: CGSize(width: 200, height: 56),
            screenVisibleFrame: screen
        )
        // 未夹击 20-100=-80 → 夹到 0+6=6。
        #expect(origin.x == 6)
    }

    @Test("无屏幕信息时保持严格居中")
    func noScreenKeepsCenter() {
        let anchor = CGRect(x: 940, y: 100, width: 120, height: 26)
        let origin = FloatingTooltipLayout.windowOrigin(
            anchor: anchor,
            windowSize: CGSize(width: 200, height: 56),
            screenVisibleFrame: nil
        )
        #expect(origin.x == 900)
    }

    @Test("垂直：气泡底边 = 控件顶边 + tooltipGap（窗口含投影留白）")
    func verticalPosition() {
        let anchor = CGRect(x: 940, y: 100, width: 120, height: 26)
        let origin = FloatingTooltipLayout.windowOrigin(
            anchor: anchor,
            windowSize: CGSize(width: 200, height: 56),
            screenVisibleFrame: screen
        )
        // 窗口底边 = 126 + 10 - 16（留白）= 120。
        #expect(origin.y == 120)
        // 气泡本体底边 = 窗口底边 + 留白 = 136 = 控件顶边 + 间隙。
        #expect(origin.y + BubbleMetrics.tooltipShadowPadding == 136)
        #expect(BubbleMetrics.tooltipGap == 10)
    }
}
