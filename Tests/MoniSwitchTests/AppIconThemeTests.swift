import AppKit
import Testing
@testable import MoniSwitch

/// App 图标主题映射（2026-10-23）：主题 id / 系统强调色序号 → Resources/AppIconThemes
/// 里的资源名。资源本身由 Support/render-theme-icons.sh 从 SVG 渲染；这里锁映射，
/// 并检查资源文件真的齐全（防「改了主题列表忘了接图标」）。
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

    @Test("7 个内置主题各自映射到 theme-<id>")
    func themeMapping() {
        #expect(PanelTheme.all.count == 7)
        let names = Set(PanelTheme.all.map {
            AppIconTheme.resourceName(themeID: $0.id, accentIndex: 4)
        })
        #expect(names == Set(PanelTheme.all.map { "theme-\($0.id)" }))
        #expect(names.count == 7)
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
            #expect(AppIconTheme.resourceName(themeID: PanelTheme.systemID, accentIndex: index)
                    == "system-\(slug)")
        }
    }

    @Test("未知主题 id 回落跟随系统")
    func unknownThemeFallsBack() {
        #expect(AppIconTheme.resourceName(themeID: "no-such-theme", accentIndex: 4) == "system-blue")
        #expect(AppIconTheme.resourceName(themeID: "", accentIndex: nil) == "system-blue")
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

    @Test("控制器把主题图设成 applicationIconImage（关于页/Dock 取的就是它）")
    @MainActor
    func controllerAppliesIcon() throws {
        let ok = AppIconController.shared.apply(themeID: "rose", accentIndex: 4)
        #expect(ok)
        let image = try #require(AppIconController.shared.currentImage)
        #expect(image.size == NSSize(width: 512, height: 512))
        // AppKit 应用时可能复制一份 NSImage，这里只校验「已设上且尺寸对」。
        #expect(NSApplication.shared.applicationIconImage?.size == NSSize(width: 512, height: 512))
    }

    @Test("资源文件齐全：7 主题 + 8 强调色都是 512×512 PNG")
    func resourceFilesExist() throws {
        let dir = resourcesDir
        try #require(FileManager.default.fileExists(atPath: dir.path),
                     "缺少 Resources/AppIconThemes，请先跑 Support/render-theme-icons.sh")
        var names = PanelTheme.all.map { "theme-\($0.id)" }
        names += AppIconTheme.accentSlugs.map { "system-\($0)" }
        #expect(names.count == 15)
        for name in names {
            let url = dir.appendingPathComponent("\(name).png")
            #expect(FileManager.default.fileExists(atPath: url.path), "缺少 \(name).png")
            let image = try #require(NSImage(contentsOf: url), "\(name).png 读不出来")
            #expect(image.size == NSSize(width: 512, height: 512), "\(name).png 不是 512×512")
        }
    }
}
