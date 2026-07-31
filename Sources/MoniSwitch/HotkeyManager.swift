import Carbon   // RegisterEventHotKey / InstallEventHandler / GetEventDispatcherTarget / kVK_*
import AppKit
import Combine
import os.log   // 诊断日志:GUI App 无 stderr 终端,改用 os_log 写入系统 Console(可见)

/// 全局快捷键管理(单例)。
///
/// 底层用 Carbon 的 `RegisterEventHotKey` 注册系统级全局快捷键。
/// 选择 Carbon 而非 CGEventTap 的原因:
///   - **无需辅助功能权限**(RegisterEventHotKey 是系统提供给所有 App 的标准 API),
///     与本项目"零权限依赖、开箱即用"的调性一致。
///
/// 之前曾实现一版因不稳定被移除,本版按 AGENTS.md 经验修复:
///   1. 事件处理器必须装在 `GetEventDispatcherTarget()`(不是 GetApplicationEventTarget)。
///      SwiftUI/MenuBarExtra App 不跑传统 Carbon 事件循环,只有 dispatcher target 能投递。
///   2. 录键强制"修饰键+主键"组合,拒绝单独按键 / 纯修饰键,避免误录。
///   3. 命中回调读 hotKeyId 必须取完整 EventHotKeyID 结构体的 .id 字段,
///      不能写进单个 UInt32(详见 `handleHotKeyEvent` 注释)。
///   4. keyCode → 显示字符用 `kVK_*` 静态映射表(详见 `displayString` 注释)。
///
/// 额外加固:热键随 presets 变化做**全量原子重注册**(先全部 Unregister 再 Register),
/// 而非按 diff 增删——消除"删旧 ref 与加新 ref 之间的窗口"导致的不稳定。
/// 热键命中回调里所有 PresetManager/AppSettings 访问统一回主线程。
final class HotkeyManager: ObservableObject {

    static let shared = HotkeyManager()

    /// 统一的诊断日志句柄。运行 .app 时 stderr 不可见,改用 os_log:
    /// 在「控制台.app」或终端 `log stream --predicate 'subsystem == "com.moniswitch.hotkey"'` 可实时看到,
    /// 便于定位热键链路的断点(安装 → 注册 → 命中 → 匹配)。
    private let log = Logger(subsystem: "com.moniswitch.hotkey", category: "HotkeyManager")

    // MARK: - UI 可观察状态

    /// 是否正处于"录制中"态(供 PresetRow 切换按钮文案)。
    @Published private(set) var isRecording = false
    /// 当前正在为哪个预设录键(nil 表示未在录制)。供 UI 高亮对应行。
    @Published private(set) var recordingFor: Preset.ID?

    // MARK: - 注册表(主线程访问)

    /// hotKeyId(本类自增分配)→ presetId。命中回调据此找到要应用的预设。
    private var bindings: [UInt32: Preset.ID] = [:]
    /// hotKeyId → Carbon 返回的热键句柄。解绑/重注册时用。
    private var refs: [UInt32: EventHotKeyRef] = [:]
    /// 下一个可用的 hotKeyId。从 1 开始(0 是 Carbon 保留值)。
    private var nextID: UInt32 = 1
    /// 一次性事件处理器是否已安装。
    private var handlerInstalled = false

    // MARK: - 录键

    /// 录键用的本地 NSEvent monitor(仅 App 处于前台时捕获)。nil 表示未在监听。
    private var recordMonitor: Any?

    private init() {}

    // MARK: - 一次性事件处理器安装

    /// 安装 Carbon 事件处理器。整个进程生命周期只装一次。
    /// 必须用 `GetEventDispatcherTarget()`——SwiftUI App 不跑传统 Carbon 事件循环,
    /// GetApplicationEventTarget 收不到事件(这是上一版不稳定的根因之一)。
    func installEventHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        // 事件类型:热键按下(kEventHotKeyPressed)。只需这一个。
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        // self 指针作为 userData 传给 C 回调,回调里还原成 HotkeyManager。
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),     // ← 关键:dispatcher target
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef = eventRef, let userData = userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(eventRef)
            },
            1,
            &eventSpec,
            selfPtr,
            nil                              // 不保留 handler ref,装一次永不卸载
        )
        log.info("installEventHandler: handlerInstalled=true, OSStatus=\(installStatus, privacy: .public)")
    }

    /// Carbon 事件回调(系统在主线程投递)。取 hotKeyId → 查 presetId → 应用预设。
    private func handleHotKeyEvent(_ eventRef: EventRef?) -> OSStatus {
        guard let eventRef = eventRef else { return noErr }

        // ⚠️ 必须读完整的 EventHotKeyID 结构体(8 字节:signature + id),
        // 再取其 .id 字段。早期版本误把它写进单个 UInt32(4 字节)缓冲区:
        //   - 栈溢出写坏 4 字节;
        //   - 小端序下读出的是 signature('MSSW'=0x4D535357)而非 id,
        //     导致 bindings 查表恒为 nil,热键按下永远不触发应用 —— 这是
        //     "快捷键功能未恢复"的根因。
        var hotKeyID = EventHotKeyID()
        GetEventParameter(eventRef,
                          UInt32(kEventParamDirectObject),
                          UInt32(typeEventHotKeyID),
                          nil,
                          MemoryLayout<EventHotKeyID>.size,
                          nil,
                          &hotKeyID)
        let hotKeyId = hotKeyID.id

        // 诊断:确认热键事件确实到达了回调(这一行能打印,就说明注册+分发链路全通)。
        log.info("热键事件命中: hotKeyId=\(hotKeyId, privacy: .public), signature=0x\(hotKeyID.signature, privacy: .public), 当前 bindings 数量=\(self.bindings.count, privacy: .public)")

        guard let presetId = bindings[hotKeyId] else {
            // 命中了已注册热键却在表里找不到——理论上不应发生(注册时同步写入
            // bindings)。若出现,说明有竞态,打日志便于诊断。
            log.error("热键命中但无匹配预设 (hotKeyId=\(hotKeyId, privacy: .public))")
            return noErr
        }

        // 诊断:确认匹配到了预设,即将回主线程应用。
        log.info("热键匹配成功,应用预设 presetId=\(presetId.uuidString, privacy: .public)")
        // 所有 PresetManager 访问回主线程,与 UI / 通知路径一致。
        DispatchQueue.main.async {
            PresetManager.shared.applyById(presetId)
        }
        return noErr
    }

    // MARK: - 全量重注册(presets 变化时调用)

    /// 先解绑全部,再按 presets 重新注册。原子地全量刷新,避免增删竞态。
    /// 由 MoniSwitchApp 订阅 PresetManager.$presets 触发(启动时也会跑一次)。
    func reregisterAll(from presets: [Preset]) {
        assert(Thread.isMainThread, "reregisterAll 必须在主线程")
        unregisterAll()

        // 诊断:记录本次重注册的输入(多少预设、其中多少带热键)。
        let withHotkey = presets.filter { $0.hotkey?.isEmpty == false }.count
        log.info("reregisterAll: 共 \(presets.count, privacy: .public) 个预设, 其中 \(withHotkey, privacy: .public) 个带有效热键, 线程=\(Thread.isMainThread ? "main" : "BACKGROUND!!", privacy: .public)")

        // 冲突保护:若两个预设绑了完全相同的组合,只给第一个注册,避免互相抢。
        var seen: Set<HotkeyBinding> = []
        for preset in presets {
            guard let binding = preset.hotkey, !binding.isEmpty else { continue }
            guard !seen.contains(binding) else { continue }
            seen.insert(binding)
            register(binding: binding, for: preset.id)
        }
    }

    /// 注销当前所有热键。
    private func unregisterAll() {
        for (_, ref) in refs {
            UnregisterEventHotKey(ref)
        }
        refs.removeAll()
        bindings.removeAll()
        // nextID 不重置,持续单调递增,避免短时间内重用 id 造成回调错配。
    }

    /// 注册单个热键绑定。失败仅打印日志,不中断流程(如组合被系统占用)。
    private func register(binding: HotkeyBinding, for presetId: Preset.ID) {
        let hotKeyId = nextID
        nextID &+= 1

        // EventHotKeyID.signature:自定义 4 字节签名(任意,用 'MSSW' = MoniSwitch)。
        let id = EventHotKeyID(signature: OSType(0x4D535357), // 'MSSW'
                               id: hotKeyId)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            id,
            GetEventDispatcherTarget(),   // 与 handler 同 target
            0,
            &ref
        )

        guard status == noErr, let ref = ref else {
            log.error("热键注册失败 keyCode=\(binding.keyCode, privacy: .public) mods=\(binding.modifiers, privacy: .public): OSStatus=\(status, privacy: .public)")
            return
        }
        refs[hotKeyId] = ref
        bindings[hotKeyId] = presetId
        log.info("热键注册成功 hotKeyId=\(hotKeyId, privacy: .public) keyCode=\(binding.keyCode, privacy: .public) mods=\(binding.modifiers, privacy: .public)")
    }

    // MARK: - 录键

    /// 开始为指定预设录键。装一个本地 keyDown monitor,捕获下一次有效组合。
    func startRecording(for presetId: Preset.ID) {
        assert(Thread.isMainThread)
        cancelRecording()
        isRecording = true
        recordingFor = presetId

        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordEvent(event, presetId: presetId)
            return event   // 始终返回 event,不吞掉(避免干扰其他焦点控件)
        }
    }

    /// 取消录制(手动按 Esc / 切走焦点 / 关闭窗口时调用)。
    func cancelRecording() {
        if let monitor = recordMonitor {
            NSEvent.removeMonitor(monitor)
            recordMonitor = nil
        }
        isRecording = false
        recordingFor = nil
    }

    /// 处理录键事件。Esc 取消;有效"修饰键+主键"组合 → 写回 preset 并结束录制。
    private func handleRecordEvent(_ event: NSEvent, presetId: Preset.ID) {
        // Esc:取消录制,不写回。
        if event.keyCode == kVK_Escape {
            cancelRecording()
            return
        }

        // 必须至少一个修饰键,且 keyCode 不是修饰键本身(避免把"单独按 ⌘"录进去)。
        let mods = carbonModifiers(from: event.modifierFlags)
        guard mods != 0, !Self.isModifierKeyCode(event.keyCode) else { return }

        let binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: mods)
        PresetManager.shared.setHotkey(binding, forId: presetId)
        cancelRecording()   // 写回即结束(setHotkey 会触发 presets.didSet → 重注册)
    }

    /// NSEvent 修饰键标志 → Carbon 修饰键标志(activeFlag 等无关位过滤掉)。
    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    /// 判断某 keyCode 是否本身就是一个修饰键(单按修饰键不算有效组合)。
    private static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand,
             kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_Function:
            return true
        default:
            return false
        }
    }

    // MARK: - keyCode → 显示字符串(UCKeyTranslate)

    /// 把绑定转成人类可读字符串(如 "⌘⇧F"),用于 UI 显示。
    ///
    /// 实现:硬件 keyCode → 显示字符用内置的 `kVK_*` 静态映射表(见 `keyCodeNames`)。
    ///
    /// 设计权衡:AGENTS.md 记录过最初想用 `UCKeyTranslate` 按当前键盘布局动态转换——
    /// 那样 Dvorak/非英文布局下显示更准。但 macOS 13+ SDK 不再把 TIS 系列 C 函数
    /// (`TISGetCurrentInputSource` 等)导出到 Swift 的 Carbon 模块,纯 Swift 拿不到
    /// 当前布局的 `UCKeyboardLayout*` 数据(需要 C bridging target,与本项目"纯 SPM、
    /// 无子目录"的构建结构冲突)。权衡后选用静态表:
    ///   - 对 QWERTY(绝大多数用户)显示完全正确;
    ///   - 对非 QWERTY 布局,显示的字符是"该键位在 QWERTY 上对应的字符",
    ///     仍可读,且不影响功能(Carbon 用 keyCode 注册,与字符显示解耦)。
    /// 快捷键**注册与触发用 keyCode**(跨布局稳定),此处只影响显示文字。
    func displayString(for binding: HotkeyBinding) -> String {
        var s = ""
        // 修饰键符号按 Carbon 标志位映射(顺序:⌃⌥⇧⌘,与系统快捷键显示习惯一致)。
        if binding.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if binding.modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if binding.modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if binding.modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + Self.keyCodeNames[Int(binding.keyCode), default: "Key\(binding.keyCode)"]
    }

    /// 硬件 keyCode(kVK_* 常量值)→ 可读字符串。覆盖字母/数字/标点/方向键/功能键/特殊键。
    /// 用 QWERTY 布局标注字符;Carbon 注册用的是 keyCode(布局无关),此处仅影响显示。
    private static let keyCodeNames: [Int: String] = [
        // 字母(A–Z,QWERTY 键位)
        kVK_ANSI_A: "A", kVK_ANSI_S: "S", kVK_ANSI_D: "D", kVK_ANSI_F: "F", kVK_ANSI_H: "H",
        kVK_ANSI_G: "G", kVK_ANSI_Z: "Z", kVK_ANSI_X: "X", kVK_ANSI_C: "C", kVK_ANSI_V: "V",
        kVK_ANSI_B: "B", kVK_ANSI_Q: "Q", kVK_ANSI_W: "W", kVK_ANSI_E: "E", kVK_ANSI_R: "R",
        kVK_ANSI_Y: "Y", kVK_ANSI_T: "T", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_6: "6", kVK_ANSI_5: "5", kVK_ANSI_Equal: "=",
        kVK_ANSI_9: "9", kVK_ANSI_7: "7", kVK_ANSI_Minus: "-", kVK_ANSI_8: "8", kVK_ANSI_0: "0",
        kVK_ANSI_RightBracket: "]", kVK_ANSI_O: "O", kVK_ANSI_U: "U", kVK_ANSI_LeftBracket: "[",
        kVK_ANSI_I: "I", kVK_ANSI_P: "P", kVK_ANSI_L: "L", kVK_ANSI_J: "J", kVK_ANSI_Quote: "'",
        kVK_ANSI_K: "K", kVK_ANSI_Semicolon: ";", kVK_ANSI_Backslash: "\\",
        kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/", kVK_ANSI_N: "N", kVK_ANSI_M: "M",
        kVK_ANSI_Period: ".", kVK_ANSI_Grave: "`",

        // 功能键
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11",
        kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
        kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",

        // 特殊键
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "⌦", kVK_Escape: "Esc", kVK_Help: "Help",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",

        // 小键盘(不常用,仍列出)
        kVK_ANSI_KeypadDecimal: ".", kVK_ANSI_KeypadMultiply: "*",
        kVK_ANSI_KeypadPlus: "+", kVK_ANSI_KeypadClear: "⌧",
        kVK_ANSI_KeypadDivide: "/", kVK_ANSI_KeypadEnter: "⏎",
        kVK_ANSI_KeypadMinus: "-", kVK_ANSI_KeypadEquals: "=",
        kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2",
        kVK_ANSI_Keypad3: "3", kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5",
        kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7", kVK_ANSI_Keypad8: "8",
        kVK_ANSI_Keypad9: "9",
    ]
}
