import SwiftUI

/// 面板和设置共用的尺寸令牌；旧的展开/悬停动画刻度已随改版删除。
enum BubbleMetrics {
    static let settingsCardCornerRadius: CGFloat = 10
    static let iconBadgeCornerRadius: CGFloat = 8
    static let keycapCornerRadius: CGFloat = 6
    static let sidebarSelectionOpacity: CGFloat = 0.10
    static let headerBlurRamp: CGFloat = 24
    static let headerBlurFadeTail: CGFloat = 18

    static let fontBody: CGFloat = 13
    static let fontControl: CGFloat = 12
    static let fontCaption: CGFloat = 11
    static let fontMini: CGFloat = 10
    static let cardSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 2

    static let panelTopPadding: CGFloat = 5
    static let panelColumnWidth: CGFloat = 380
    static let shadowBreathingSide: CGFloat = 12
    static let shadowBreathingBottom: CGFloat = 12
    static var hostContentWidth: CGFloat { panelColumnWidth + shadowBreathingSide * 2 }
}

extension Color {
    /// 6 位 hex（如 "#a6ad6f"）→ Color；非法输入回退 .clear。
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .clear
            return
        }
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255.0,
                  green: Double((v >> 8) & 0xFF) / 255.0,
                  blue: Double(v & 0xFF) / 255.0, opacity: 1)
    }
}
