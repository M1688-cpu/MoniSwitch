import Foundation

/// 一个显示器的完整状态信息（解析自 `displayplacer list` 的输出）。
struct DisplayInfo: Identifiable, Equatable {
    /// displayplacer 的持久化屏幕 ID（通常跨插拔保持稳定）
    /// 设为 var：镜像态解析时需要把合并行 "A+B" 拆开后回填独立 id。
    var id: String
    /// 显示器的人类可读名称，例如 "34 inch external screen" 或 "MacBook built in screen"
    /// 设为 var：镜像态补造被镜像屏的占位信息时需要回填。
    var typeName: String
    /// 当前分辨率（像素），例如 (3440, 1440)
    var resolution: (width: Int, height: Int)
    /// 屏幕左上角的逻辑坐标 (x, y)。origin 为 (0,0) 的屏即为主显示器。
    var origin: (x: Int, y: Int)
    /// 是否为当前主显示器（白条所在屏）
    var isMain: Bool
    /// scaling 状态：on 表示开启 HiDPI 缩放
    let scalingOn: Bool
    /// 刷新率（Hz）
    let hertz: Int
    /// 色深
    let colorDepth: Int
    /// 旋转角度（0/90/180/270）
    let degree: Int
    /// 是否启用
    let enabled: Bool

    /// 当前分辨率下可选的刷新率（去重、升序），用于菜单切换刷新率。
    /// 从 displayplacer list 的 "Resolutions for rotation" 段解析，
    /// 只保留与当前分辨率相同的模式的 hz。空数组表示无多选项（或未解析）。
    var availableRefreshRates: [Int]

    /// 是否为笔记本内置屏（displayplacer 的 Type 里包含 "built in"）
    var isBuiltIn: Bool {
        typeName.localizedCaseInsensitiveContains("built in")
    }

    /// 是否处于镜像状态（通过观察 id 是否被加号拼接判断；这里保留扩展字段）
    var mirroredPeerID: String? = nil

    /// 简短显示文本，用于菜单项：名称 (宽x高)。
    /// 注意：菜单层请优先用 localizedTypeName 做本地化显示。
    var menuLabel: String {
        "\(typeName) (\(resolution.width)x\(resolution.height))"
    }

    /// 把 displayplacer 给出的原始 Type 名称（如 "34 inch external screen"）
    /// 翻译成当前界面语言的友好名称。
    /// - 内置屏 → "MacBook 内置屏" / "MacBook built-in display"
    /// - 外接屏 → "34 英寸外接显示器" / "34-inch external display"
    ///   （保留具体尺寸数字；无法解析时退回原始英文名）
    func localizedTypeName(l10n: L10n) -> String {
        if isBuiltIn {
            return l10n.t(.builtInDisplay)
        }
        // 尝试提取 "34 inch" → "34英寸外接显示器"（中文）/ "34-inch external display"（英文）
        let inchPattern = #"(\d+)\s*inch"#
        if let regex = try? NSRegularExpression(pattern: inchPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: typeName, range: NSRange(typeName.startIndex..., in: typeName)),
           let range = Range(match.range(at: 1), in: typeName) {
            let size = String(typeName[range])
            return "\(size)\(l10n.t(.inch))\(l10n.t(.externalDisplay))"
        }
        // 无法识别格式：外接显示器（原始名）
        return "\(l10n.t(.externalDisplay)) (\(typeName))"
    }

    // MARK: - Equatable（基于 id 即可，结构体含元组需手写）

    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 快捷键绑定

/// 一个可持久化的全局快捷键绑定。
///
/// 存 Carbon 的 keyCode（硬件按键码，跨布局稳定）和 modifier 标志位，
/// 不存字符（字符会随键盘布局/输入法变化）。功能二由 HotkeyManager 使用。
struct HotkeyBinding: Codable, Equatable, Hashable {
    /// Carbon 键码（kVK_* 常量对应的数值）。
    var keyCode: UInt32
    /// Carbon 修饰键标志位（组合 cmdKey/shiftKey/optionKey/controlKey）。
    var modifiers: UInt32

    /// 是否为"未绑定"（keyCode=0 且无修饰键视为空）。
    var isEmpty: Bool { keyCode == 0 && modifiers == 0 }
}

// MARK: - 显示器布局预设

/// 一份显示器布局预设：保存时刻的屏幕配置快照，可一键恢复。
///
/// `screenArgs` 是 displayplacer 的裸参数数组（每块屏一条，不含外层引号），
/// 应用时直接喂给 ShellRunner.run。格式与 DisplayManager.makeScreenArg 同源。
struct Preset: Codable, Identifiable, Equatable {
    /// 唯一标识，跨重命名保持稳定。
    var id: UUID
    /// 用户起的名字，如「办公」「演示」。
    var name: String
    /// 每块屏一条 displayplacer 配置串，应用时整体回放。
    var screenArgs: [String]
    /// 可选绑定的全局快捷键（功能二启用，首批为 nil）。
    var hotkey: HotkeyBinding?

    init(id: UUID = UUID(), name: String, screenArgs: [String], hotkey: HotkeyBinding? = nil) {
        self.id = id
        self.name = name
        self.screenArgs = screenArgs
        self.hotkey = hotkey
    }
}
