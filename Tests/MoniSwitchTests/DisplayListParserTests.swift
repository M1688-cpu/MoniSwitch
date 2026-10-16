// displayplacer list 解析回归测试：fixture 取自本机真实输出（2026-10，双屏：
// 27 寸外接主屏 + MacBook 内置屏），模式行保留 HiDPI 变体形态以锁定合并行为。
// v2 重构保留 DisplayManager 引擎，此测试是解析层的回归网。
import Testing
import Foundation
@testable import MoniSwitch

@Suite("displayplacer list 解析")
struct DisplayListParserTests {
    /// 真实输出裁剪版：外接主屏（0,0）+ 内置屏（-1512,0），各带数条模式行。
    static let dualScreenFixture = """
        Persistent screen id: A2FF4D28-2FA9-42BC-9877-46A34EFB5FB4
        Contextual screen id: 3
        Serial screen id: s1620
        Type: 27 inch external screen
        Resolution: 1920x1080
        Hertz: 60
        Color Depth: 8
        Scaling: on
        Origin: (0,0) - main display
        Rotation: 0
        Enabled: true
        Resolutions for rotation 0:
          mode 0: res:800x600 hz:60 color_depth:8
          mode 1: res:800x600 hz:60 color_depth:8 scaling:on
          mode 2: res:960x540 hz:60 color_depth:8 scaling:on
          mode 3: res:1024x576 hz:60 color_depth:8 scaling:on
          mode 4: res:1024x576 hz:60 color_depth:8
          mode 5: res:1920x1080 hz:60 color_depth:8
          mode 6: res:1920x1080 hz:50 color_depth:8

        Persistent screen id: 37D8832A-2D66-02CA-B9F7-8F30A301B230
        Contextual screen id: 2
        Serial screen id: s1619
        Type: MacBook built in screen
        Resolution: 1512x982
        Hertz: 120
        Color Depth: 8
        Scaling: on
        Origin: (-1512,0)
        Rotation: 0
        Enabled: true
        Resolutions for rotation 0:
          mode 0: res:1512x982 hz:120 color_depth:8 scaling:on
          mode 1: res:1504x982 hz:120 color_depth:8 scaling:on
          mode 2: res:1496x964 hz:60 color_depth:8 scaling:on

        """

    @Test("双屏解析：数量/主屏/内置识别/origin")
    func parseDualScreen() {
        let displays = DisplayManager.shared.parseList(Self.dualScreenFixture)
        #expect(displays.count == 2)

        let external = displays.first { $0.typeName.contains("external") }
        #expect(external != nil)
        #expect(external?.isMain == true)
        #expect(external?.isBuiltIn == false)
        #expect(external?.origin.x == 0)
        #expect(external?.origin.y == 0)
        #expect(external?.resolution.width == 1920)

        let builtIn = displays.first { $0.typeName.contains("built in") }
        #expect(builtIn != nil)
        #expect(builtIn?.isMain == false)
        #expect(builtIn?.isBuiltIn == true)
        #expect(builtIn?.origin.x == -1512)
        #expect(builtIn?.hertz == 120)
    }

    @Test("HiDPI 变体合并：同分辨率双变体合并为一条且 hidpi=true")
    func hidpiVariantMerge() {
        let displays = DisplayManager.shared.parseList(Self.dualScreenFixture)
        let external = displays.first { $0.typeName.contains("external") }!
        // 1024x576 在 fixture 里先出现 scaling:on 再出现非 HiDPI 变体，合并后应 hidpi=true
        let option = external.availableResolutions.first { $0.width == 1024 && $0.height == 576 }
        #expect(option?.hidpi == true)
        // 800x600 只有 mode 0（无 scaling:on）与 mode 1（有），同样应合并为 hidpi=true
        let option800 = external.availableResolutions.first { $0.width == 800 && $0.height == 600 }
        #expect(option800?.hidpi == true)
        // 1920x1080 只有非 HiDPI 模式行 → hidpi=false
        let native = external.availableResolutions.first { $0.width == 1920 && $0.height == 1080 }
        #expect(native?.hidpi == false)
        // 去重：1920x1080 只一条
        #expect(external.availableResolutions.filter { $0.width == 1920 && $0.height == 1080 }.count == 1)
    }

    @Test("刷新率解析：当前分辨率下的全部档位去重升序")
    func refreshRatesForCurrentResolution() {
        let displays = DisplayManager.shared.parseList(Self.dualScreenFixture)
        let external = displays.first { $0.typeName.contains("external") }!
        // 1920x1080 有 60 与 50（后者带 scaling:on 也算）
        #expect(external.availableRefreshRates == [50, 60])
        let builtIn = displays.first { $0.typeName.contains("built in") }!
        #expect(builtIn.availableRefreshRates == [120])
    }

    @Test("镜像组检测：同 origin 两屏归一组")
    func mirrorGroupDetection() {
        let mirrored = Self.dualScreenFixture
            .replacingOccurrences(of: "Origin: (-1512,0)", with: "Origin: (0,0)")
        let displays = DisplayManager.shared.parseList(mirrored)
        #expect(displays.count == 2)
        let groups = DisplayManager.shared.mirrorGroups
        #expect(groups.count == 1)
        #expect(groups.first?.count == 2)
    }
}
