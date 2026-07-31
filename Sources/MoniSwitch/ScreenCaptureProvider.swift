import AppKit

/// 屏幕画面截图提供方（单例）。
///
/// **当前为脚手架占位**：为「画面预览」功能预留接口，本期不引入真实截屏逻辑，
/// 所有方法返回 nil，零运行时影响。
///
/// 将来实现的路线（已注释，供后续接入参考）：
///   1. 用 `CGDisplayCreateImage(_:)` 抓取指定显示器的整屏位图；
///   2. 按 thumbnail 尺寸等比缩放（NSImage size + NSBitmapImageRep 重采样）；
///   3. 缩存到内存（key=displayId+版本号），避免每次打开面板都重抓。
///
/// 权限注意（重要，决定上线时机）：
///   - macOS 15+ 对 `CGDisplayCreateImage` / ScreenCaptureKit 的截屏要求「屏幕录制」
///     授权（系统设置 → 隐私与安全性 → 屏幕录制）。首次调用会触发系统授权弹窗。
///   - 本 App 是纯菜单栏工具，引入权限弹窗会影响首次体验，故本期暂不启用，
///     先用布局示意图（LayoutPreviewCard）作为视觉占位，待授权流程打磨好再接入。
final class ScreenCaptureProvider {

    static let shared = ScreenCaptureProvider()

    private init() {}

    /// 取某块屏的缩略图。
    ///
    /// - Parameter displayId: displayplacer 的 persistent id。
    ///   注意：displayplacer 的 id 是字符串 UUID，与 CoreGraphics 的 `CGDirectDisplayID`
    ///   （整数）不是同一套。将来实现时需先做一次 id 映射（通过 NSScreen.deviceDescription
    ///   的 `"NSScreenNumber"` 反查 CGDirectDisplayID）。
    /// - Returns: 缩略图；当前恒返回 nil（占位）。
    func thumbnail(for displayId: String) -> NSImage? {
        // TODO: 将来接入 CGDisplayCreateImage + 缩放 + 缓存。
        // 目前返回 nil，LayoutPreviewCard 会回退到纯几何示意图。
        return nil
    }

    /// 该 id 对应的屏当前是否已取得截屏授权。
    /// 占位：未实现真实截屏，恒返回 false。
    var isAuthorized: Bool {
        // TODO: 将来用 CGPreflightScreenCaptureAccess() / CGRequestScreenCaptureAccess() 判定。
        return false
    }
}
