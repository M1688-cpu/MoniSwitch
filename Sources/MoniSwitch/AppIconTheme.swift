import AppKit

/// 图标主题：设置里选中的面板主题决定 App 图标（2026-10-23）。
///
/// 资源由 `Support/render-theme-icons.sh` 从 `design/icon-web/theme-icons/*.svg`
/// 渲染到 `Resources/AppIconThemes/`（512×512，透明底），打包时整套拷进
/// `Contents/Resources/AppIconThemes`。7 个内置主题各自一张；「跟随系统」按系统的
/// 8 档强调色各备一张（AppleAccentColor 映射），未设置（多彩）用蓝。
///
/// 为什么预渲染而不是运行时画：图标由线性/径向渐变 + 多层阴影组成，用 SVG 渲染
/// 保证与设计稿逐像素一致；运行时只做「主题 → 文件名」的映射，不重画。
enum AppIconTheme {
    /// 资源子目录（bundle 内与源码树同名）。
    static let resourceFolder = "AppIconThemes"

    /// 标准强调色 slug，顺序与系统设置里的强调色一致。
    static let accentSlugs = ["blue", "purple", "pink", "red",
                              "orange", "yellow", "green", "graphite"]

    /// 主题 id + 强调色序号 → 资源名（不含扩展名）。
    /// 主题未知或为「跟随系统」时走 `system-<accent>`。
    static func resourceName(themeID: String, accentIndex: Int?) -> String {
        if themeID != PanelTheme.systemID,
           PanelTheme.all.contains(where: { $0.id == themeID }) {
            return "theme-\(themeID)"
        }
        return "system-\(accentSlug(accentIndex))"
    }

    /// AppleAccentColor 序号 → 强调色 slug。
    /// -1 graphite / 0 red / 1 orange / 2 yellow / 3 green / 4 blue /
    /// 5 purple / 6 pink；缺省（多彩）按蓝——没有自定义强调色的 App 实际取蓝。
    static func accentSlug(_ index: Int?) -> String {
        switch index {
        case -1: return "graphite"
        case 0: return "red"
        case 1: return "orange"
        case 2: return "yellow"
        case 3: return "green"
        case 5: return "purple"
        case 6: return "pink"
        default: return "blue"
        }
    }

    /// 读系统强调色序号（NSGlobalDomain 的 AppleAccentColor）。
    /// 用户从「系统设置 > 外观 > 强调色」切换后才会变；无此键 = 多彩。
    static func systemAccentIndex() -> Int? {
        UserDefaults.standard.object(forKey: "AppleAccentColor") as? Int
    }
}

/// 把「当前主题」应用成 Dock / 关于页看到的图标。
///
/// 触发点：启动、设置里换主题（AppSettings 发 `.moniswitchPanelThemeChanged`）、
/// App 激活（用户可能在系统设置里换了强调色）、系统强调色变化的分布式通知。
/// 同一张图重复应用会被 `appliedKey` 去重。
///
/// 注意：通知横幅等系统 UI 取的是 bundle 里的 AppIcon.icns（静态 = 跟随系统蓝），
/// 这里的 applicationIconImage 只影响运行中的 Dock 图标与关于页。
@MainActor
final class AppIconController: NSObject {
    static let shared = AppIconController()

    /// 当前生效的主题图标（关于页直接取它，避免再读静态 icns）。
    private(set) var currentImage: NSImage?

    /// 上一次成功应用的资源名：只换主题/强调色时才重设 applicationIconImage。
    private var appliedKey: String?

    private override init() { super.init() }

    /// AppDelegate 启动时调用一次。
    func start() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(themeChanged),
                           name: .moniswitchPanelThemeChanged, object: nil)
        center.addObserver(self, selector: #selector(refresh),
                           name: NSApplication.didBecomeActiveNotification, object: nil)
        // 强调色是全局域设置，「跟随系统」时要跟着换图。分布式通知在注册线程
        // （主线程）的 runloop 上派发，与 selector 观察者配合无需额外切换队列。
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh),
            name: NSNotification.Name("AppleColorPreferencesChangedNotification"),
            object: nil, suspensionBehavior: .deliverImmediately)
        apply(force: true)
    }

    @objc private func themeChanged() { apply(force: true) }

    @objc private func refresh() { apply() }

    /// 按当前设置解析并应用图标；资源缺失时保持现状（打包漏拷时降级，不崩）。
    func apply(force: Bool = false) {
        let key = AppIconTheme.resourceName(themeID: AppSettings.shared.panelThemeID,
                                            accentIndex: AppIconTheme.systemAccentIndex())
        guard force || key != appliedKey else { return }
        apply(themeID: AppSettings.shared.panelThemeID,
              accentIndex: AppIconTheme.systemAccentIndex())
    }

    /// 显式指定主题/强调色应用图标（测试友好，不读 AppSettings）。
    /// 返回是否成功加载并应用；资源缺失返回 false。
    @discardableResult
    func apply(themeID: String, accentIndex: Int?) -> Bool {
        let key = AppIconTheme.resourceName(themeID: themeID, accentIndex: accentIndex)
        guard let image = loadImage(named: key) else { return false }
        NSApplication.shared.applicationIconImage = image
        currentImage = image
        appliedKey = key
        return true
    }

    private func loadImage(named key: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: key, withExtension: "png",
                                     subdirectory: AppIconTheme.resourceFolder),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            return image
        }
        // dev（swift run，没有打包资源）：回退源码树，便于本地调试
        let devPath = "Resources/\(AppIconTheme.resourceFolder)/\(key).png"
        return NSImage(contentsOfFile: devPath)
    }
}
