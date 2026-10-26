import CoreGraphics
import Foundation

/// 亮度键的目标方向（纯逻辑，单元测试覆盖）。
enum BrightnessKeyTarget: Equatable {
    /// 放行原生事件：内置屏、不可 DDC 控制的屏、鼠标不在任何屏内。
    case passThrough
    /// 吞掉事件并由 App 调这块屏的 DDC 亮度。
    case control(CGDirectDisplayID)
}

/// 一块在线屏的判定快照。bounds 用 CG 全局显示坐标（原点是主屏左上角、y 向下），
/// 与 `CGEvent.location` / `CGDisplayBounds` 同一坐标系，避免 NSScreen 的
/// 左下原点换算。
struct BrightnessScreenSnapshot: Equatable {
    let displayID: CGDirectDisplayID
    let bounds: CGRect
    let isBuiltIn: Bool
    let isControllable: Bool
}

/// 鼠标位置 → 目标屏判定。
enum BrightnessKeyRouting {

    /// 取包含该点的第一块屏；内置屏或不可控屏一律放行原生事件。
    ///
    /// 坐标系契约：point 与 bounds 都是 CG 全局显示坐标（主屏左上为原点，y 向下）。
    /// 扩展布局下各屏 bounds 不重叠；镜像时多屏共享同一 bounds，取列表中的第一块
    ///（镜像组里能否调节取决于该组在 CG 在线列表里的顺序，属已知边缘情况）。
    static func target(for point: CGPoint, screens: [BrightnessScreenSnapshot]) -> BrightnessKeyTarget {
        guard let screen = screens.first(where: { $0.bounds.contains(point) }) else {
            return .passThrough
        }
        guard !screen.isBuiltIn, screen.isControllable else {
            return .passThrough
        }
        return .control(screen.displayID)
    }
}

/// 可 DDC 控制屏 ID 的线程安全快照。
///
/// 写方 = BrightnessManager（主线程，发现/刷新后声明）；读方 = F1/F2 事件 tap 的
/// 专属队列（同步判定「要不要吞事件」）。事件 tap 回调必须同步返回，不能用
/// `DispatchQueue.main.async` 等主线程状态，所以这层快照用锁而不是 actor。
final class BrightnessControlRegistry: @unchecked Sendable {
    static let shared = BrightnessControlRegistry()

    private let lock = NSLock()
    private var displayIDs: Set<CGDirectDisplayID> = []

    private init() {}

    /// 声明当前可控制的外接屏集合（无外接屏时传空集）。
    func update(_ newDisplayIDs: Set<CGDirectDisplayID>) {
        lock.lock()
        displayIDs = newDisplayIDs
        lock.unlock()
    }

    /// 当前可控制的外接屏集合（线程安全快照拷贝）。
    func snapshot() -> Set<CGDirectDisplayID> {
        lock.lock()
        defer { lock.unlock() }
        return displayIDs
    }
}
