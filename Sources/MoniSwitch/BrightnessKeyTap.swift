import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// F1/F2 亮度键 = 主动 CGEventTap（会吞事件），需「辅助功能」权限。
///
/// 语义（2026-10-17 用户拍板，对齐 MonitorControl）：
/// - 裸按 F1/F2：调「鼠标所在屏」的亮度。可 DDC 控制的外接屏由 App 接管
///   （吞事件 + DDC 写 + HUD）；内置屏 / 不可控屏放行原生事件，内置屏继续走
///   系统原生亮度 + 系统 OSD（笔记本手感不变）。
/// - ⌥+F1/F2：同步调全部可 DDC 控制的外接屏（保留旧能力），并弹 HUD。
/// - 未授权辅助功能：不建 tap，快捷键回到系统原生行为；设置页负责状态与引导。
///
/// 权限模型（2026-10-17 从「输入监控」升级）：listen-only 只能旁听、拦不住内置屏
/// 跟随 F1/F2，无法实现「只调鼠标所在屏」；吞事件必须 active tap，其 TCC 服务是
/// 「辅助功能」（MonitorControl 官方同样要求）。设置页的状态检查/请求/深链全部
/// 走 AX API。
///
/// 事件解析抄 MediaKeyTap（MonitorControl fork，MIT）：NX_SYSDEFINED 事件里
/// subtype==8 为按键类，键码在 data1 高 16 位，按下态在 (data1 & 0xFF00)>>8==0xA。
/// 亮度键码取 IOKit ev_keymap.h：NX_KEYTYPE_BRIGHTNESS_UP=2 / DOWN=3。
final class BrightnessKeyTap {
    static let shared = BrightnessKeyTap()

    /// IOKit ev_keymap.h（C 宏不进 Swift，本地固化；SDK 头文件为唯一来源）。
    fileprivate static let brightnessUpKeycode: Int32 = 2
    fileprivate static let brightnessDownKeycode: Int32 = 3
    /// NX_SYSDEFINED = 14（本 SDK 的 CGEventType Swift overlay 无 case 名，rawValue 恒定）。
    fileprivate static let nxSysDefined = CGEventType(rawValue: 14)!
    /// 按键类 NX_SYSDEFINED 事件的 subtype。
    private static let keyEventSubtype = 8

    fileprivate var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoopQueue: DispatchQueue?
    /// tap 专属 runloop（stop 时 CFRunLoopStop 用；CFRunLoopRun 不接受外部停止
    /// 信号会永远阻塞队列线程——2026-10 code-review 抓的泄漏）。跨线程写一次后
    /// 只在主线程读，属良性竞态（MediaKeyTap 同款模式）。
    private var runLoop: CFRunLoop?

    var isRunning: Bool { tapPort != nil }

    /// 「辅助功能」权限是否已授予。
    static var permissionGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 请求「辅助功能」权限（系统弹窗）；返回调用时的授权状态。
    /// 已授权时直接返回 true，不会弹窗。
    @discardableResult
    static func requestPermission() -> Bool {
        guard !permissionGranted else { return true }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// 系统设置「隐私与安全性 > 辅助功能」深链。
    static func openPermissionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// 启动监听（主线程调用）。无权限/未开启时静默跳过。
    func start() {
        assert(Thread.isMainThread)
        guard AppSettings.shared.brightnessKeysEnabled else { return }
        guard Self.permissionGranted else { return }
        guard tapPort == nil else { return }

        let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1) << Self.nxSysDefined.rawValue,
            callback: brightnessTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let port else { return }
        tapPort = port

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorSystemDefault, port, 0)
        guard let source = runLoopSource else {
            CFMachPortInvalidate(port)
            tapPort = nil
            return
        }
        runLoopQueue = DispatchQueue(label: "moniswitch.brightnesskeytap")
        runLoopQueue?.async { [weak self] in
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            if let self {
                self.runLoop = runLoop
            }
            CFRunLoopRun()
        }
    }

    /// 让 tap 实际状态与「开关 + 授权」一致：授权后自动拉起、撤销/关闭后自动停。
    /// 由 App 的 2s 权限看门狗与设置页刷新共同调用（幂等，可高频调用）。
    /// 同时兜底系统把 tap 置为 disabled（超时/用户输入打断后未自愈）或端口失效。
    func reconcile() {
        assert(Thread.isMainThread)
        let enabled = AppSettings.shared.brightnessKeysEnabled
        let trusted = Self.permissionGranted
        if enabled && trusted {
            start()
            if let tapPort {
                if !CFMachPortIsValid(tapPort) {
                    stop()
                    start()
                } else if !CGEvent.tapIsEnabled(tap: tapPort) {
                    CGEvent.tapEnable(tap: tapPort, enable: true)
                }
            }
        } else {
            stop()
        }
    }

    /// 停止监听并拆除 tap（主线程调用）：先摘 runloop source 并停掉 runloop
    /// （否则 CFRunLoopRun 永不返回，队列线程常驻泄漏）。
    func stop() {
        assert(Thread.isMainThread)
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        if let tapPort {
            CFMachPortInvalidate(tapPort)
        }
        runLoopSource = nil
        runLoop = nil
        tapPort = nil
        runLoopQueue = nil
    }

    /// 事件解析（跑在 tap 专属队列）：命中亮度键则判定目标屏并决定是否吞掉。
    /// 返回 true = 吞掉事件（App 接管）；false = 放行给系统原生处理。
    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.keyEventSubtype else { return false }
        let keycode = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        // 0xA = NX_KEYDOWN；按住不放的重复事件也是 down 态。key up 放行（系统
        // 只用 key down 触发媒体键动作，孤立 key up 无副作用）。
        let keyPressed = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard keyPressed else { return false }

        let isUp: Bool
        switch keycode {
        case Self.brightnessUpKeycode: isUp = true
        case Self.brightnessDownKeycode: isUp = false
        default: return false
        }

        // ⌥：全部外接屏同步（旧能力）。无可控外接屏时放行原生事件。
        if nsEvent.modifierFlags.contains(.option) {
            guard !BrightnessControlRegistry.shared.snapshot().isEmpty else { return false }
            DispatchQueue.main.async {
                guard let percent = BrightnessManager.shared.adjustAllExternal(up: isUp) else { return }
                BrightnessHUD.shared.show(percent: percent)
            }
            return true
        }

        // 裸按：调鼠标所在屏。内置屏 / 不可控屏 / 屏外一律放行原生事件。
        let point = CGEvent(source: nil)?.location ?? .zero
        let screens = Self.onlineScreens()
        let target = BrightnessKeyRouting.target(for: point, screens: screens)
        guard case .control(let displayID) = target else {
            return false
        }
        DispatchQueue.main.async {
            guard let percent = BrightnessManager.shared.adjustBrightness(up: isUp, for: displayID) else { return }
            BrightnessHUD.shared.show(percent: percent)
        }
        return true
    }

    /// 在线屏快照（CG 全局坐标）。CGDisplay* 系列可从任意线程调用；可控集合
    /// 走 BrightnessControlRegistry 的锁快照，不碰 MainActor 状态。
    private static func onlineScreens() -> [BrightnessScreenSnapshot] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let controllable = BrightnessControlRegistry.shared.snapshot()
        return ids.prefix(Int(count)).map { id in
            BrightnessScreenSnapshot(
                displayID: id,
                bounds: CGDisplayBounds(id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isControllable: controllable.contains(id)
            )
        }
    }
}

/// @convention(c) 兼容的游离函数回调（static 存储属性闭包 + 泛型 Unmanaged 会触发
/// 「covariant Self 不能在存储属性初始化器里引用」的编译器限制，游离函数无此问题）。
private func brightnessTapCallback(
    _: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<BrightnessKeyTap>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // 惯例自愈：超时/用户输入打断被系统禁用时重新启用（MediaKeyTap 同款）
        if let port = tap.tapPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == BrightnessKeyTap.nxSysDefined else { return Unmanaged.passUnretained(event) }
    // 吞掉（返回 nil）只发生在「App 接管的亮度键」上；其余事件原样放行。
    return tap.handle(event) ? nil : Unmanaged.passUnretained(event)
}
