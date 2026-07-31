import SwiftUI
import AppKit
import Combine

/// MoniSwitch 入口：一个纯菜单栏 App（无 Dock 图标、无主窗口，靠 Info.plist 的 LSUIElement=YES 实现）。
@main
struct MoniSwitchApp: App {

    @StateObject private var state = AppState()
    @StateObject private var l10n = L10n.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var presetManager = PresetManager.shared

    var body: some Scene {
        // 顶部菜单栏图标 + 下拉面板（.window 样式：可完全自定义的 SwiftUI 视图，
        // 用于实现「气泡卡片」设计；原 .menu 样式是原生 NSMenu，无法做卡片/配色）。
        MenuBarExtra {
            PanelView(state: state)
                .environmentObject(l10n)
                .environmentObject(settings)
                .environmentObject(presetManager)
        } label: {
            // 菜单栏图标:必须用模板 NSImage(SF Symbol 天然是模板)。
            // .window 样式下面板打开时系统给图标加深色高亮背景,非 template 视图
            // (如用 .primary 描边的自绘视图)会与高亮背景同色,表现为图标位置一整块黑。
            // 模板 image 由系统在高亮/深浅态自动反色,稳定可见(见下方 menuBarIcon)。
            Image(nsImage: Self.menuBarIcon)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        // 设置窗口不再用 SwiftUI 的 Settings 场景——它在菜单栏 App 中不可靠。
        // 改由 DockPolicyManager 用自管理的 NSWindow 承载。
        // 这里只注册 ⌘, 快捷键，让 App 菜单里的「设置…」也能触发打开。
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(l10n.t(.settings)) {
                    DockPolicyManager.shared.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

// MARK: - 菜单栏图标

extension MoniSwitchApp {
    /// 菜单栏图标的模板 NSImage。
    ///
    /// 用 SF Symbol `display`（苹果系统标准显示器图标）—— 为菜单栏这种小尺寸场景
    /// 专门优化，16pt 下粗描边 + 扁宽屏 + 醒目底座，一眼可辨；且与菜单栏其他系统图标
    /// （WiFi/电池/控制中心）视觉语言统一。
    ///
    /// 关键：SF Symbol 返回的 NSImage 天然是模板 image（isTemplate 默认 true），
    /// 系统会在深浅/高亮态自动反色 —— 这是 `.window` 样式 MenuBarExtra 防止图标
    /// 变黑的核心机制（见 AGENTS.md「MenuBarExtra .window 样式…」条目）。
    static let menuBarIcon: NSImage = {
        // semibold weight：默认 regular 在 16pt 下偏细，semibold 让视觉重量
        // 与其他菜单栏图标一致，更醒目但不至于过粗。
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        return NSImage(systemSymbolName: "display",
                       accessibilityDescription: "MoniSwitch")?
            .withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "display",
                       accessibilityDescription: "MoniSwitch")
            ?? NSImage()
    }()
}

// MARK: - UI 状态

/// 持有屏幕列表与所有操作的 UI 状态对象。
/// displayplacer 调用是同步阻塞的，故放在后台线程执行，
/// 完成后再回主线程更新列表。
final class AppState: ObservableObject {

    @Published var displays: [DisplayInfo] = []

    private let manager = DisplayManager.shared
    private let queue = DispatchQueue(label: "moniswitch.ops")
    private let settings = AppSettings.shared

    /// 自动刷新定时器。nil 表示未启用。
    private var autoRefreshTimer: Timer?
    /// Combine 订阅，观察自动刷新设置变化以重建 timer。
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 装一次性 Carbon 事件处理器(整个进程生命周期只装一次)。
        // 必须在任意热键注册之前完成。
        HotkeyManager.shared.installEventHandler()
        refresh()
        setupAutoRefreshBinding()
        setupHotkeyBinding()
    }

    /// 订阅 AppSettings：当自动刷新开关或间隔变化时，重建/销毁 timer。
    private func setupAutoRefreshBinding() {
        // 任一变化都触发一次 timer 重建。
        settings.$autoRefreshEnabled
            .combineLatest(settings.$autoRefreshInterval)
            .sink { [weak self] enabled, interval in
                self?.rebuildAutoRefreshTimer(enabled: enabled, interval: interval)
            }
            .store(in: &cancellables)
    }

    /// 订阅 PresetManager：presets 任意变化(增删/改名/改热键)时全量重注册热键。
    /// 启动时也会触发一次,完成从持久化数据恢复热键。
    private func setupHotkeyBinding() {
        PresetManager.shared.$presets
            .sink { presets in
                HotkeyManager.shared.reregisterAll(from: presets)
            }
            .store(in: &cancellables)
    }

    /// 根据开关与间隔重建自动刷新 timer。
    private func rebuildAutoRefreshTimer(enabled: Bool, interval: Int) {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        guard enabled, interval > 0 else { return }

        // 用 schedule + RunLoop 的 .common 模式，保证菜单打开/拖动时也能触发。
        let timer = Timer(timeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }

    /// 重新读取当前屏幕列表。
    func refresh() {
        queue.async { [weak self] in
            let list = self?.manager.currentDisplays() ?? []
            DispatchQueue.main.async {
                self?.displays = list
            }
        }
    }

    func setPrimary(_ d: DisplayInfo) {
        runOp(kind: .primary) { [self, displays] in
            // 防御：目标已是主屏时直接成功返回，避免无意义调用（也避免点已为主屏的外接时
            // 触发意外平移）。镜像态下点外接名（外接是基准主屏）也命中此分支。
            if displays.first(where: { $0.id == d.id })?.isMain == true { return true }
            return manager.setPrimary(d, in: displays)
        }
    }

    func mirror(_ ext: DisplayInfo) {
        runOp(kind: .mirror) { [self, displays] in
            guard let main = displays.first(where: { $0.isMain }) else { return false }
            // 已在镜像态则视为成功，不再重复发镜像命令
            if manager.isMirroring(ext, main) { return true }
            return manager.mirror(ext, to: main)
        }
    }

    func unmirror(_ ext: DisplayInfo) {
        runOp(kind: .extend) { [self, displays] in
            guard let main = displays.first(where: { $0.isMain }) else { return false }
            return manager.unmirror(main: main, external: ext, in: displays)
        }
    }

    /// 通用排列移动：按 display 是主屏还是非主屏，走对应分支。
    /// - 非主屏（外接或内置）：移动该屏本身
    /// - 主屏（外接为主屏时）：保持自身不动，平移其他屏到对侧
    func moveArrangement(_ display: DisplayInfo, side: HorizontalSide) {
        let kind: OpKind = (side == .left) ? .moveLeft : .moveRight
        runOp(kind: kind) { [self, displays] in manager.moveExternal(display, side: side, in: displays) }
    }

    /// 切换某屏刷新率。
    func setRefreshRate(_ hz: Int, for display: DisplayInfo) {
        runOp(kind: .refreshRate) { [self, displays] in
            manager.setRefreshRate(hz: hz, for: display, in: displays)
        }
    }

    // MARK: - 状态查询（供菜单显示 ✓ 标记用）

    /// 外接屏是否为主屏（决定菜单显示哪个屏的排列项）。
    var externalIsMain: Bool {
        displays.contains { !$0.isBuiltIn && $0.isMain }
    }

    /// 内置屏（若有）。
    var builtInDisplay: DisplayInfo? {
        displays.first(where: { $0.isBuiltIn })
    }

    /// 某外接屏是否正与主屏处于镜像状态。
    func isMirroring(_ ext: DisplayInfo) -> Bool {
        guard let main = displays.first(where: { $0.isMain }) else { return false }
        return manager.isMirroring(ext, main)
    }

    /// 某屏当前在主屏的哪一侧（.left / .right / nil=未知或镜像中）。
    func side(of display: DisplayInfo) -> HorizontalSide? {
        guard let main = displays.first(where: { $0.isMain }),
              main.id != display.id,
              !isMirroring(display) else { return nil }
        if display.origin.x + display.resolution.width <= main.origin.x {
            return .left
        } else if display.origin.x >= main.origin.x + main.resolution.width {
            return .right
        }
        return nil
    }

    /// 在后台执行一个切换操作，完成后刷新列表；成功时发通知。
    /// - Parameter kind: 操作类型，决定切换完成通知的正文文案。
    private func runOp(kind: OpKind, work: @escaping () -> Bool) {
        queue.async { [weak self] in
            let ok = work()
            let list = self?.manager.currentDisplays() ?? []
            DispatchQueue.main.async {
                self?.displays = list
                if ok {
                    self?.settings.sendSwitchNotification(kind)
                }
            }
        }
    }
}

// MARK: - 本地化便捷方法（供 View 层使用）

extension AppState {
    /// 取一条文案。
    func localized(_ key: TextKey) -> String {
        L10n.shared.t(key)
    }

    /// 某个显示器的本地化菜单标签：名称 (宽x高)，按设置可选追加 @Hz 与 HiDPI。
    func localizedLabel(for d: DisplayInfo) -> String {
        let name = d.localizedTypeName(l10n: L10n.shared)
        var label = "\(name) (\(d.resolution.width)x\(d.resolution.height))"
        if AppSettings.shared.detailedMenuInfo {
            label += " @\(d.hertz)Hz"
            if d.scalingOn {
                label += " HiDPI"
            }
        }
        return label
    }
}
