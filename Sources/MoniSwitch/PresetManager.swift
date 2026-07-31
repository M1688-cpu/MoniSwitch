import Foundation
import Combine

/// 预设管理（单例 + @Published + UserDefaults JSON 持久化）。
///
/// 职责：保存/删除/重命名/应用 显示器布局预设。
/// 与 AppSettings 分离：AppSettings 管标量偏好，PresetManager 管预设数组。
/// 预设用 JSON 编码后以 Data 形式存 UserDefaults（数组持久化的标准做法）。
final class PresetManager: ObservableObject {

    static let shared = PresetManager()

    /// UserDefaults 存储键。
    private let storageKey = "displayPresets"

    /// 所有预设。变化时自动持久化，UI 自动刷新。
    @Published var presets: [Preset] {
        didSet { persist() }
    }

    private let manager = DisplayManager.shared
    private let queue = DispatchQueue(label: "moniswitch.presets")

    private init() {
        self.presets = PresetManager.loadPresets(key: "displayPresets")
    }

    // MARK: - 持久化

    /// 把当前 presets 数组 JSON 编码后写入 UserDefaults。
    private func persist() {
        do {
            let data = try JSONEncoder().encode(presets)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            fputs("预设持久化失败: \(error)\n", stderr)
        }
    }

    /// 从 UserDefaults 读取并解码预设数组。失败返回空数组。
    private static func loadPresets(key: String) -> [Preset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([Preset].self, from: data)
        } catch {
            fputs("预设读取失败: \(error)\n", stderr)
            return []
        }
    }

    // MARK: - CRUD

    /// 把当前显示器布局保存为新预设。
    /// - Parameter name: 预设名称。
    /// - Returns: 新建的预设；当前无显示器时返回 nil。
    @discardableResult
    func captureCurrent(name: String) -> Preset? {
        let args = manager.currentSnapshotArgs()
        guard !args.isEmpty else { return nil }
        let preset = Preset(name: name, screenArgs: args)
        presets.append(preset)
        return preset
    }

    /// 删除指定预设。
    func delete(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
    }

    /// 重命名指定预设。
    func rename(_ preset: Preset, to newName: String) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].name = newName
    }

    /// 绑定/解绑快捷键到指定预设（功能二使用，首批调用为空操作）。
    func setHotkey(_ hotkey: HotkeyBinding?, for preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index].hotkey = hotkey
    }

    /// 绑定/解绑快捷键到指定预设（按 id 查找）。
    /// 给 HotkeyManager 录键回调用——它手上有 id、但未必有完整 Preset 引用。
    func setHotkey(_ hotkey: HotkeyBinding?, forId presetId: Preset.ID) {
        guard let index = presets.firstIndex(where: { $0.id == presetId }) else { return }
        presets[index].hotkey = hotkey
    }

    // MARK: - 应用

    /// 应用一份预设：在后台线程回放其 displayplacer 参数，完成后发通知。
    ///
    /// 注意：通知的发送不依赖 displayplacer 的退出码。原因——displayplacer 对
    /// 单屏失败（如 persistent id 漂移导致找不到屏）采用"跳过+报错+继续"策略，
    /// 仍会尽力应用其他屏，整体命令可能返回非零退出码，但对用户而言预设已生效。
    /// 因此只要执行了，就提示用户（与"看到布局变化"的体感一致）。
    func apply(_ preset: Preset) {
        let args = preset.screenArgs
        let settings = AppSettings.shared
        queue.async {
            _ = self.manager.applyArgs(args)
            DispatchQueue.main.async {
                settings.sendSwitchNotification(.presetApplied)
            }
        }
    }

    /// 按 id 应用预设。给全局热键命中回调用——Carbon 回调只手握 hotKeyId→presetId,
    /// 走这条路复用 apply 的队列与通知逻辑,不另起实现。
    func applyById(_ presetId: Preset.ID) {
        guard let preset = presets.first(where: { $0.id == presetId }) else { return }
        apply(preset)
    }
}
