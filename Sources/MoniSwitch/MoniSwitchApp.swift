import SwiftUI
import AppKit

/// MoniSwitch 入口：一个纯菜单栏 App（无 Dock 图标、无主窗口，靠 Info.plist 的 LSUIElement=YES 实现）。
@main
struct MoniSwitchApp: App {

    @StateObject private var state = AppState()

    var body: some Scene {
        // 顶部菜单栏图标 + 下拉菜单（系统标准 .menu 样式）
        MenuBarExtra {
            menuContent
        } label: {
            // 菜单栏图标：先用 SF Symbol 占位，后续替换为自定义图标
            Image(systemName: "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.menu)
    }

    @ViewBuilder
    private var menuContent: some View {
        // 1) 显示器列表：点击即设为主屏，主屏项打勾
        if state.displays.isEmpty {
            Text("未检测到显示器")
            Divider()
        } else {
            Section("显示器（点击设为主屏）") {
                ForEach(state.displays) { d in
                    Button {
                        state.setPrimary(d)
                    } label: {
                        if d.isMain {
                            // 主屏前加勾
                            Text("✓ \(d.menuLabel)")
                        } else {
                            Text(d.menuLabel)
                        }
                    }
                }
            }
        }

        Divider()

        // 2) 外接显示器子菜单：左右移动、镜像/扩展
        let externals = state.displays.filter { !$0.isBuiltIn }
        if !externals.isEmpty {
            Section("外接显示器") {
                ForEach(externals) { ext in
                    Menu(ext.typeName) {
                        Button("移到主屏左侧") { state.moveExternal(ext, side: .left) }
                        Button("移到主屏右侧") { state.moveExternal(ext, side: .right) }
                        Divider()
                        Button("镜像主屏") { state.mirror(ext) }
                        Button("扩展显示（取消镜像）") { state.unmirror(ext) }
                    }
                }
            }
            Divider()
        }

        // 3) 杂项
        Button("刷新列表") { state.refresh() }
            .keyboardShortcut("r")
        Divider()
        Button("退出 MoniSwitch") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

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

    func moveExternal(_ ext: DisplayInfo, side: HorizontalSide) {
        runOp { [self, displays] in manager.moveExternal(ext, side: side, in: displays) }
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
