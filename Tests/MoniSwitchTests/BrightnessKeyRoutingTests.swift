// F1/F2 亮度键「鼠标所在屏」判定纯逻辑测试。
// 坐标系契约：CG 全局显示坐标（主屏左上为原点、y 向下），与 CGEvent.location /
// CGDisplayBounds 一致；矩形按 CGRect.contains 的半开区间语义（含 min 边、不含 max 边）。
import Testing
import CoreGraphics
@testable import MoniSwitch

@Suite("F1/F2 目标屏判定")
struct BrightnessKeyRoutingTests {

    /// 扩展布局：内置屏 x∈[0,100)，外接屏 x∈[100,300)；y 均为 [0,100)。
    static func screens(externalControllable: Bool = true,
                        builtInControllable: Bool = false) -> [BrightnessScreenSnapshot] {
        [
            BrightnessScreenSnapshot(
                displayID: 1,
                bounds: CGRect(x: 0, y: 0, width: 100, height: 100),
                isBuiltIn: true,
                isControllable: builtInControllable
            ),
            BrightnessScreenSnapshot(
                displayID: 2,
                bounds: CGRect(x: 100, y: 0, width: 200, height: 100),
                isBuiltIn: false,
                isControllable: externalControllable
            ),
        ]
    }

    @Test("鼠标在外接可控屏 → 吞事件并接管该屏")
    func externalControllableIsControlled() {
        let target = BrightnessKeyRouting.target(for: CGPoint(x: 150, y: 50), screens: Self.screens())
        #expect(target == .control(2))
    }

    @Test("鼠标在内置屏 → 放行原生事件（系统亮度 + OSD）")
    func builtInPassesThrough() {
        let target = BrightnessKeyRouting.target(for: CGPoint(x: 50, y: 50), screens: Self.screens())
        #expect(target == .passThrough)
    }

    @Test("内置屏即使被误标为可控也放行原生事件")
    func builtInNeverControlled() {
        let target = BrightnessKeyRouting.target(
            for: CGPoint(x: 50, y: 50),
            screens: Self.screens(builtInControllable: true)
        )
        #expect(target == .passThrough)
    }

    @Test("鼠标在外接不可控屏 → 放行原生事件")
    func externalUncontrollablePassesThrough() {
        let target = BrightnessKeyRouting.target(
            for: CGPoint(x: 150, y: 50),
            screens: Self.screens(externalControllable: false)
        )
        #expect(target == .passThrough)
    }

    @Test("鼠标不在任何屏内 → 放行原生事件")
    func outsideAllScreensPassesThrough() {
        #expect(BrightnessKeyRouting.target(for: CGPoint(x: -10, y: 50), screens: Self.screens()) == .passThrough)
        #expect(BrightnessKeyRouting.target(for: CGPoint(x: 150, y: 150), screens: Self.screens()) == .passThrough)
        #expect(BrightnessKeyRouting.target(for: CGPoint(x: 150, y: 50), screens: []) == .passThrough)
    }

    @Test("相邻屏边界点归右侧屏（含 min 边、不含 max 边）")
    func boundaryBelongsToRightScreen() {
        #expect(BrightnessKeyRouting.target(for: CGPoint(x: 100, y: 50), screens: Self.screens()) == .control(2))
        #expect(BrightnessKeyRouting.target(for: CGPoint(x: 0, y: 50), screens: Self.screens()) == .passThrough)
    }

    @Test("坐标原点按 CG 全局空间（主屏左上）而非 NSScreen 左下")
    func cgCoordinateSpace() {
        // y = 0 是 CG 全局空间的顶边：外接屏内的顶点仍命中该屏。
        #expect(BrightnessKeyRouting.target(for: CGPoint(x: 150, y: 0), screens: Self.screens()) == .control(2))
        // y = 100 是底边（半开区间之外）→ 不命中。
        #expect(BrightnessKeyRouting.target(for: CGPoint(x: 150, y: 100), screens: Self.screens()) == .passThrough)
    }
}
