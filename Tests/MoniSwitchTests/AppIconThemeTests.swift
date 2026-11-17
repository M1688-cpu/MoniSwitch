import AppKit
import Testing
@testable import MoniSwitch

/// App 图标映射（2026-10-23；2026-11-14 面板主题移除后只剩强调色）：系统强调色序号 →
/// Resources/AppIconThemes 里的资源名。资源由 Support/render-theme-icons.sh 从 SVG 渲染；
/// 这里锁映射，并检查资源文件真的齐全。
@Suite("App 图标主题映射")
struct AppIconThemeTests {

    /// 仓库根目录（用 #filePath 定位，不依赖测试进程的工作目录）。
    private var resourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/MoniSwitchTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // 仓库根
            .appendingPathComponent("Resources/AppIconThemes")
    }

    @Test("跟随系统按 AppleAccentColor 序号映射到 8 档强调色")
    func accentMapping() {
        let cases: [(Int?, String)] = [
            (-1, "graphite"), (0, "red"), (1, "orange"), (2, "yellow"),
            (3, "green"), (4, "blue"), (5, "purple"), (6, "pink"),
            (nil, "blue"), (99, "blue"),   // 缺省（多彩）/ 未知值都按蓝
        ]
        for (index, slug) in cases {
            #expect(AppIconTheme.accentSlug(index) == slug, "accentIndex=\(String(describing: index))")
            #expect(AppIconTheme.resourceName(accentIndex: index) == "system-\(slug)")
        }
    }

    @Test("8 档强调色 slug 与渲染脚本的产出同序")
    func accentSlugsCoverSystemOptions() {
        #expect(AppIconTheme.accentSlugs.count == 8)
        #expect(Set(AppIconTheme.accentSlugs).count == 8)
        #expect(AppIconTheme.accentSlugs == ["blue", "purple", "pink", "red",
                                             "orange", "yellow", "green", "graphite"])
    }

    @Test("系统强调色序号可从全局域读出（无键 = 多彩 → nil）")
    func systemAccentIndexReadable() {
        if let index = AppIconTheme.systemAccentIndex() {
            #expect((-1...6).contains(index), "AppleAccentColor=\(index) 超出标准范围")
        }
    }

    @Test("控制器把强调色图标设成 applicationIconImage（关于页/Dock 取的就是它）")
    @MainActor
    func controllerAppliesIcon() throws {
        let ok = AppIconController.shared.apply(accentIndex: 0)
        #expect(ok)
        let image = try #require(AppIconController.shared.currentImage)
        #expect(image.size == NSSize(width: 512, height: 512))
        // AppKit 应用时可能复制一份 NSImage，这里只校验「已设上且尺寸对」。
        #expect(NSApplication.shared.applicationIconImage?.size == NSSize(width: 512, height: 512))
    }

    @Test("资源文件齐全：8 档强调色都是 512×512 PNG")
    func resourceFilesExist() throws {
        let dir = resourcesDir
        try #require(FileManager.default.fileExists(atPath: dir.path),
                     "缺少 Resources/AppIconThemes，请先跑 Support/render-theme-icons.sh")
        let names = AppIconTheme.accentSlugs.map { "system-\($0)" }
        #expect(names.count == 8)
        for name in names {
            let url = dir.appendingPathComponent("\(name).png")
            #expect(FileManager.default.fileExists(atPath: url.path), "缺少 \(name).png")
            let image = try #require(NSImage(contentsOf: url), "\(name).png 读不出来")
            #expect(image.size == NSSize(width: 512, height: 512), "\(name).png 不是 512×512")
        }
    }
}
