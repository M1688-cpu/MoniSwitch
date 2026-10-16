// 冒烟占位：验证测试目标随包构建通过；Phase 2 起填充真实用例。
// CLT 环境无 XCTest，用 Swift 6 工具链自带的 Swift Testing。
import Testing
@testable import MoniSwitch

@Suite struct SmokeTests {
    @Test func packageBuilds() {
        #expect(Bool(true))
    }
}
