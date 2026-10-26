import Foundation

/// 亮度数值策略：把「DDC 读到的原始值 / 上次成功值 / 用户百分比」解析成
/// 可安全写入的 max 与 raw。纯函数、无硬件依赖，单测锁定。
///
/// 背景（2026-10-25 真机 bug）：refresh() 在 DDC 读失败时把 maxValue 兜底成 1，
/// 导致 F1/F2 的单步 = 100%——F1 直接写 0（最暗），F2 写 1 仍接近 0；
/// 只有重新打开面板触发一次成功读才恢复。兜底链必须收敛到一处。
enum BrightnessValue {
    /// DDC 读失败且没有历史 max 时的安全兜底：绝大多数显示器亮度范围 0...100。
    static let defaultMaxValue: UInt16 = 100
    /// 小于 2 的 max 视为无效读（DDC 读失败的常见形态），不参与步进/映射。
    static let minimumValidMaxValue: UInt16 = 2

    /// 解析本轮可用的 max：合法读 > 上次成功读 > 默认 100。
    /// 绝不返回 1——1 会让单步变成 100%，F1 一按就写到最暗。
    static func resolvedMax(readMax: UInt16?, cachedMax: UInt16?) -> UInt16 {
        if let readMax, readMax >= minimumValidMaxValue {
            return readMax
        }
        if let cachedMax, cachedMax >= minimumValidMaxValue {
            return cachedMax
        }
        return defaultMaxValue
    }

    /// 解析本轮百分比：合法读 > 持久化值 > 50%。
    static func resolvedPercent(readCurrent: UInt16?, readMax: UInt16?, savedPercent: Double?) -> Double {
        if let readCurrent, let readMax, readMax >= minimumValidMaxValue {
            return clamp(Double(readCurrent) / Double(readMax))
        }
        if let savedPercent {
            return clamp(savedPercent)
        }
        return 0.5
    }

    /// 百分比 → DDC 原始值（0...max）。
    static func rawValue(percent: Double, maxValue: UInt16) -> UInt16 {
        let maxValue = Swift.max(maxValue, 1)
        return UInt16((clamp(percent) * Double(maxValue)).rounded())
    }

    /// 单次按键步进占总范围的比例（max/16 向下取整、至少 1）。
    static func stepPercent(maxValue: UInt16) -> Double {
        let maxValue = Swift.max(maxValue, 1)
        return Double(DDC.brightnessStep(maxValue: maxValue)) / Double(maxValue)
    }

    /// 按一次 F1/F2 后的新百分比（0...1）。
    static func adjusted(percent: Double, up: Bool, maxValue: UInt16) -> Double {
        let step = stepPercent(maxValue: maxValue)
        return clamp(percent + (up ? step : -step))
    }

    private static func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, 0), 1)
    }
}
