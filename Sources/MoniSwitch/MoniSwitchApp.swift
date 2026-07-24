import SwiftUI
import AppKit

/// MoniSwitch 入口：一个纯菜单栏 App（无 Dock 图标、无主窗口，靠 Info.plist 的 LSUIElement=YES 实现）。
@main
struct MoniSwitchApp: App {

    @StateObject private var state = AppState()
    @StateObject private var l10n = L10n.shared

    var body: some Scene {
        // 顶部菜单栏图标 + 下拉菜单（系统标准 .menu 样式）
        MenuBarExtra {
            menuContent
                .environmentObject(l10n)
        } label: {
            // 菜单栏图标：先用 SF Symbol 占位，后续替换为自定义图标
            Image(systemName: "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.menu)

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

    @ViewBuilder
    private var menuContent: some View {
        // 1) 显示器列表：点击即设为主屏，主屏项打勾
        if state.displays.isEmpty {
            Text(state.localized(.noDisplays))
            Divider()
        } else {
            Section(state.localized(.displaysSection)) {
                ForEach(state.displays) { d in
                    Button {
                        state.setPrimary(d)
                    } label: {
                        if d.isMain {
                            Text("✓ \(state.localizedLabel(for: d))")
                        } else {
                            Text(state.localizedLabel(for: d))
                        }
                    }
                }
            }
        }

        Divider()

        // 2) 外接显示器排列。
        //    关键：当外接屏是非主屏时，操作对象就是该外接屏本身（常规情况）；
        //         当外接屏是主屏时，"移动"操作的对象其实是内置屏，
        //         这时把"移动内置屏到左/右"作为独立项列出，避免语义混乱。
        let externals = state.displays.filter { !$0.isBuiltIn }
        if !externals.isEmpty {
            Section(state.localized(.externalSection)) {
                if state.externalIsMain {
                    // 外接是主屏 → 列出"移动内置屏"
                    if let builtIn = state.builtInDisplay {
                        arrangementMenu(for: builtIn, isBuiltIn: true)
                    }
                } else {
                    // 外接是非主屏 → 列出每个外接屏的排列
                    ForEach(externals) { ext in
                        arrangementMenu(for: ext, isBuiltIn: false)
                    }
                }

                // 镜像 / 扩展：对所有外接屏统一操作（与谁主屏无关）
                Divider()
                if let ext = externals.first {
                    Button(checkMarked(state.localized(.mirrorMain),    active: state.isMirroring(ext))) { state.mirror(ext)   }
                    Button(checkMarked(state.localized(.extendDisplay), active: !state.isMirroring(ext))) { state.unmirror(ext) }
                }
            }
            Divider()
        }

        // 3) 杂项
        Button(state.localized(.refreshList)) { state.refresh() }
            .keyboardShortcut("r")
        Button(state.localized(.settings)) { DockPolicyManager.shared.openSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button(state.localized(.quit)) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// 构建排列二级菜单（左移/右移），在当前生效侧前加 ✓。
    /// - 当 isBuiltIn=true 时，标题用内置屏名称，操作对象也是内置屏。
    @ViewBuilder
    private func arrangementMenu(for display: DisplayInfo, isBuiltIn: Bool) -> some View {
        let currentSide = state.side(of: display)

        Menu(display.localizedTypeName(l10n: l10n)) {
            Button(checkMarked(state.localized(.moveLeft),  active: currentSide == .left)) {
                state.moveArrangement(display, side: .left)
            }
            Button(checkMarked(state.localized(.moveRight), active: currentSide == .right)) {
                state.moveArrangement(display, side: .right)
            }
        }
    }

    /// 若 active 为 true，在文字前加 ✓（与主屏列表的勾号风格一致）。
    private func checkMarked(_ text: String, active: Bool) -> String {
        active ? "✓ \(text)" : text
    }
}

// MARK: - UI 状态

/// 持有屏幕列表与所有操作的 UI 状态对象。
/// displayplacer 调用是同步阻塞的，故放在后台线程执行，
/// 完成后再回主线程更新列表。
final class AppState: ObservableObject {

    @Published var displays: [DisplayInfo] = []

    private let manager = DisplayManager.shared
    private let queue = DispatchQueue(label: "moniswitch.ops")

    init() {
        refresh()
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
        runOp { [self, displays] in manager.setPrimary(d, in: displays) }
    }

    func mirror(_ ext: DisplayInfo) {
        runOp { [self, displays] in
            guard let main = displays.first(where: { $0.isMain }) else { return false }
            return manager.mirror(ext, to: main)
        }
    }

    func unmirror(_ ext: DisplayInfo) {
        runOp { [self, displays] in
            guard let main = displays.first(where: { $0.isMain }) else { return false }
            return manager.unmirror(main: main, external: ext)
        }
    }

    /// 通用排列移动：按 display 是主屏还是非主屏，走对应分支。
    /// - 非主屏（外接或内置）：移动该屏本身
    /// - 主屏（外接为主屏时）：保持自身不动，平移其他屏到对侧
    func moveArrangement(_ display: DisplayInfo, side: HorizontalSide) {
        runOp { [self, displays] in manager.moveExternal(display, side: side, in: displays) }
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

    /// 在后台执行一个切换操作，完成后刷新列表。
    private func runOp(_ work: @escaping () -> Bool) {
        queue.async { [weak self] in
            _ = work()
            let list = self?.manager.currentDisplays() ?? []
            DispatchQueue.main.async {
                self?.displays = list
            }
        }
    }
}

// MARK: - 本地化便捷方法（供 View 层使用）

private extension AppState {
    /// 取一条文案。
    func localized(_ key: TextKey) -> String {
        L10n.shared.t(key)
    }

    /// 某个显示器的本地化菜单标签：名称 (宽x高)。
    func localizedLabel(for d: DisplayInfo) -> String {
        "\(d.localizedTypeName(l10n: L10n.shared)) (\(d.resolution.width)x\(d.resolution.height))"
    }
}
