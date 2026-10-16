import Foundation
import AppKit
import CoreGraphics
import IOKit
import IOKit.hid

/// F1/F2 亮度键监听：listen-only CGEventTap，只旁听不吞事件。
///
/// 设计契约（v2 拍板）：
/// - 裸按 F1/F2：内置屏照常走系统原生调节（原生 OSD 照常显示），我们把同样的
///   步进量同步写到全部外接 DDC 屏（MonitorControl 的「全部屏同步」效果）；
/// - ⌥+F1/F2：仅调外接屏，并弹出 App 自己的 HUD 气泡（修饰键语义 = 显式反馈）；
/// - 无内置屏（Mac mini）时裸按也弹 HUD（否则没有任何视觉反馈）；
/// - listen-only 最坏情况是「无效果」，永远不可能弄坏系统亮度键；
/// - 权限走「输入监控」（IOHIDRequestTypeListenEvent），比辅助功能轻；
///   未授权时静默不生效，设置页负责状态展示与引导。
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

    var isRunning: Bool { tapPort != nil }

    /// 「输入监控」权限是否已授予。
    static var permissionGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 请求「输入监控」权限（弹系统 TCC 提示）；返回是否已授予。
    @discardableResult
    static func requestPermission() -> Bool {
        guard !permissionGranted else { return true }
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        return permissionGranted
    }

    /// 系统设置「隐私与安全性 > 输入监控」深链。
    static func openPermissionSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
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
            options: .listenOnly,
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
        runLoopQueue?.async {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
    }

    /// 停止监听并拆除 tap（主线程调用）。
    func stop() {
        assert(Thread.isMainThread)
        if let runLoopSource {
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let tapPort {
            CFMachPortInvalidate(tapPort)
        }
        runLoopSource = nil
        tapPort = nil
        runLoopQueue = nil
    }

    /// 事件解析（跑在 tap 专属队列）：命中亮度键则回主线程调亮度 + 决定 HUD。
    fileprivate func handle(_ event: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.keyEventSubtype else { return }
        let keycode = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        // 0xA = NX_KEYDOWN；按住不放的重复事件也是 down 态，天然支持连续调节
        let keyPressed = ((keyFlags & 0xFF00) >> 8) == 0xA
        guard keyPressed else { return }

        let isUp: Bool
        switch keycode {
        case Self.brightnessUpKeycode: isUp = true
        case Self.brightnessDownKeycode: isUp = false
        default: return
        }
        let optionHeld = nsEvent.modifierFlags.contains(.option)

        DispatchQueue.main.async {
            // 无外接 DDC 屏时完全静默（原生行为不受任何影响）
            guard let percent = BrightnessManager.shared.adjustBrightness(up: isUp) else { return }
            // HUD「智能显示」：⌥ 修饰键（显式只调外接）或无内置屏（无系统 OSD 可依赖）时弹
            if optionHeld || !DDCDiscovery.hasBuiltInDisplay() {
                BrightnessHUD.shared.show(percent: percent)
            }
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
    if type == .tapDisabledByTimeout {
        // 惯例自愈：超时被系统禁用时重新启用（MediaKeyTap 同款）
        if let port = tap.tapPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == BrightnessKeyTap.nxSysDefined else { return Unmanaged.passUnretained(event) }
    tap.handle(event)
    return Unmanaged.passUnretained(event)
}
