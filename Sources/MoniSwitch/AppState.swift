import Foundation
import Combine

/// 持有屏幕列表与所有操作的 UI 状态对象。
/// displayplacer 调用是同步阻塞的，故放在后台线程执行，
/// 完成后再回主线程更新列表。
final class AppState: ObservableObject {

    @Published var displays: [DisplayInfo] = []

    /// 是否有切换操作正在后台执行（面板据此禁用控件 + 显示进度条，
    /// 防止连点重复触发 displayplacer 命令）。
    @Published var isOperating = false

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
        setupPresetAppliedBinding()
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

    /// 订阅 PresetManager 的应用完成广播：面板点击与全局热键两条路径都经
    /// PresetManager.apply，热键路径下 AppState 无从感知，靠广播拿到稳定后的
    /// 屏幕列表刷新面板。
    private func setupPresetAppliedBinding() {
        NotificationCenter.default.publisher(for: .moniswitchPresetApplied)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                if let list = note.userInfo?["displays"] as? [DisplayInfo] {
                    self?.displays = list
                } else {
                    self?.refresh()
                }
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

    /// 切换某屏分辨率（res.hidpi 决定目标屏 scaling，见 DisplayManager.setResolution）。
    func setResolution(_ res: ResolutionOption, for display: DisplayInfo) {
        runOp(kind: .resolution) { [self, displays] in
            manager.setResolution(res, for: display, in: displays)
        }
    }

    /// 一键自动排列：所有屏横向排开、消除重叠（镜像组保持完整）。
    func autoArrange() {
        runOp(kind: .autoArrange) { [self, displays] in
            manager.autoArrange(in: displays)
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
    ///
    /// 高亮不跟随的根因：displayplacer 进程退出 ≠ 系统显示器配置已生效。
    /// CoreGraphics 对 origin/hertz/res 的系统级重配是异步的（AGENTS.md 记录镜像类
    /// 重配耗时约 1.2-1.5s；origin/hertz 变更更短，但仍有数百毫秒窗口）。
    /// 若在 work() 返回后立即 currentDisplays()，会读到重配未完成时的旧值，
    /// 表现为面板高光停在旧选项。修复：waitForStableDisplays 轮询 list 输出
    /// 直到连续两次一致再读终值；通知也在稳定后提交（避开投递被重配中断的窗口）。
    private func runOp(kind: OpKind, work: @escaping () -> Bool) {
        // runOp 由 UI 回调触发（主线程），置位后再进后台队列。
        isOperating = true
        queue.async { [weak self] in
            let ok = work()
            let list = self?.manager.waitForStableDisplays() ?? []
            DispatchQueue.main.async {
                self?.displays = list
                self?.isOperating = false
                if ok {
                    self?.settings.sendSwitchNotification(kind)
                } else {
                    self?.settings.sendFailureNotification()
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
}
