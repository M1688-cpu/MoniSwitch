// 亮度数值策略的回归测试：锁定「DDC 读失败不得把 maxValue 退化成 1」，
// 以及 F1/F2 的步进/边界。期望值按 DDC 的 0...100 常见范围手算，不由实现反推。
import Testing
@testable import MoniSwitch

@Suite("亮度数值策略")
struct BrightnessValueTests {
    // MARK: max 解析（本次 bug 的核心）

    @Test("读失败时沿用上次成功读取的 max，不退回 1")
    func failedReadUsesCachedMax() {
        #expect(BrightnessValue.resolvedMax(readMax: nil, cachedMax: 100) == 100)
    }

    @Test("首次启动即读失败时用 100 兜底，不产生 0/1 档写入")
    func failedReadWithoutCacheUsesDefault() {
        #expect(BrightnessValue.resolvedMax(readMax: nil, cachedMax: nil) == 100)
    }

    @Test("读回 max=0/1 视为无效，回退缓存")
    func invalidReadMaxFallsBack() {
        #expect(BrightnessValue.resolvedMax(readMax: 0, cachedMax: 100) == 100)
        #expect(BrightnessValue.resolvedMax(readMax: 1, cachedMax: 100) == 100)
    }

    @Test("合法读优先于缓存（显示器/输入源换过时跟随新值）")
    func validReadWinsOverCache() {
        #expect(BrightnessValue.resolvedMax(readMax: 255, cachedMax: 100) == 255)
        #expect(BrightnessValue.resolvedMax(readMax: 100, cachedMax: 255) == 100)
    }

    // MARK: 百分比解析

    @Test("合法读优先于持久化值")
    func validReadPercentWins() {
        #expect(BrightnessValue.resolvedPercent(readCurrent: 50, readMax: 100, savedPercent: 0.1) == 0.5)
    }

    @Test("读失败时百分比回退到持久化值")
    func failedReadUsesSavedPercent() {
        #expect(BrightnessValue.resolvedPercent(readCurrent: nil, readMax: nil, savedPercent: 0.37) == 0.37)
    }

    @Test("max=1 的无效读不参与百分比换算")
    func invalidReadMaxDoesNotDrivePercent() {
        #expect(BrightnessValue.resolvedPercent(readCurrent: 0, readMax: 1, savedPercent: 0.37) == 0.37)
    }

    @Test("首次启动且无持久化值时兜底 50%")
    func noReadNoSavedFallsBackToHalf() {
        #expect(BrightnessValue.resolvedPercent(readCurrent: nil, readMax: nil, savedPercent: nil) == 0.5)
    }

    // MARK: 步进与写入值

    @Test("100 范围的单步 = 6%")
    func stepPercentForHundred() {
        #expect(abs(BrightnessValue.stepPercent(maxValue: 100) - 0.06) < 1e-12)
    }

    @Test("百分比 → 原始值")
    func rawValueMapping() {
        #expect(BrightnessValue.rawValue(percent: 0.37, maxValue: 100) == 37)
        #expect(BrightnessValue.rawValue(percent: 0, maxValue: 100) == 0)
        #expect(BrightnessValue.rawValue(percent: 1, maxValue: 255) == 255)
    }

    @Test("边界钳制：低于 0 与高于 1")
    func adjustedClamps() {
        #expect(BrightnessValue.adjusted(percent: 0.02, up: false, maxValue: 100) == 0)
        #expect(BrightnessValue.adjusted(percent: 0.98, up: true, maxValue: 100) == 1)
    }

    @Test("唤醒后 37% 按 F1/F2 仍是 6% 步进，而不是 0/100 跳变")
    func wakeScenarioKeepsStep() {
        // 模拟：屏睡眠期间 DDC 读失败，但上次成功读到 max=100。
        let max = BrightnessValue.resolvedMax(readMax: nil, cachedMax: 100)
        let down = BrightnessValue.adjusted(percent: 0.37, up: false, maxValue: max)
        let up = BrightnessValue.adjusted(percent: down, up: true, maxValue: max)

        #expect(abs(down - 0.31) < 1e-9)
        #expect(abs(up - 0.37) < 1e-9)
        #expect(BrightnessValue.rawValue(percent: down, maxValue: max) == 31)
        #expect(BrightnessValue.rawValue(percent: up, maxValue: max) == 37)
    }

    @Test("症状说明：max=1 会把 F1 写成 0、F2 写成 1（本次 bug 的机制）")
    func maxOneReproducesSymptom() {
        let down = BrightnessValue.adjusted(percent: 0.37, up: false, maxValue: 1)
        let up = BrightnessValue.adjusted(percent: down, up: true, maxValue: 1)
        #expect(down == 0)
        #expect(up == 1)
    }
}
