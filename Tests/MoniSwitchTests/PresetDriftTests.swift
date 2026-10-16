// 预设 id 漂移重映射回归测试（v2 计划承诺项）：
// 外接屏唤醒/重插拔后 displayplacer persistent id 变化时，按分辨率 1:1 映射改写
// 预设 args 的 id 段；无法完整映射回退旧行为（nil = 调用方按原样应用）。
import Testing
import Foundation
@testable import MoniSwitch

@Suite("预设 id 漂移重映射")
struct PresetDriftTests {
    /// 最小 DisplayInfo 工厂（其余字段取解析器缺省值即可，重映射只读 id/resolution）。
    static func display(_ id: String, w: Int, h: Int) -> DisplayInfo {
        DisplayInfo(
            id: id, typeName: "test screen",
            resolution: (w, h), origin: (0, 0), isMain: false,
            scalingOn: true, hertz: 60, colorDepth: 8, degree: 0,
            availableRefreshRates: [], availableResolutions: []
        )
    }

    static func arg(id: String, res: String) -> String {
        "id:\(id) res:\(res) hz:60 scaling:on origin:(0,0) degree:0"
    }

    @Test("无漂移：旧 id 全部仍有效 → nil（按原样应用）")
    func noDriftReturnsNil() {
        let args = [Self.arg(id: "AAA", res: "1920x1080"), Self.arg(id: "BBB", res: "1512x982")]
        let current = [Self.display("AAA", w: 1920, h: 1080), Self.display("BBB", w: 1512, h: 982)]
        #expect(DisplayManager.shared.remappedArgsIfDrifted(args, current: current) == nil)
    }

    @Test("漂移：分辨率 1:1 映射 → 改写 id 段、其余字段原样保留")
    func driftRemapsIDs() {
        let args = [Self.arg(id: "OLD1", res: "1920x1080"), Self.arg(id: "OLD2", res: "1512x982")]
        let current = [Self.display("NEW1", w: 1920, h: 1080), Self.display("NEW2", w: 1512, h: 982)]
        let remapped = DisplayManager.shared.remappedArgsIfDrifted(args, current: current)
        #expect(remapped == [
            Self.arg(id: "NEW1", res: "1920x1080"),
            Self.arg(id: "NEW2", res: "1512x982"),
        ])
    }

    @Test("屏数不一致（环境实质变化）→ nil 不猜")
    func countMismatchReturnsNil() {
        let args = [Self.arg(id: "OLD1", res: "1920x1080")]
        let current = [Self.display("NEW1", w: 1920, h: 1080), Self.display("NEW2", w: 1512, h: 982)]
        #expect(DisplayManager.shared.remappedArgsIfDrifted(args, current: current) == nil)
    }

    @Test("镜像合并条目 id:A+B 逐段映射")
    func mirrorMergedEntryRemapsPerSegment() {
        let args = [Self.arg(id: "OLDA+OLDB", res: "1920x1080")]
        let current = [Self.display("NEWA", w: 1920, h: 1080), Self.display("NEWB", w: 1920, h: 1080)]
        let remapped = DisplayManager.shared.remappedArgsIfDrifted(args, current: current)
        #expect(remapped == [Self.arg(id: "NEWA+NEWB", res: "1920x1080")])
    }
}
