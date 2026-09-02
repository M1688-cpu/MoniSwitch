import SwiftUI

/// 全站气泡圆角刻度（设置页 + 菜单栏面板统一引用，避免数值在多处漂移）。
///
/// 引入背景：原 `SettingsCard`（12）、`BubbleCard`（16）、`bottomToolbar`（12）、
/// 徽章/hover/键帽（4/8/6）等圆角散落在 `SettingsView.swift`/`PanelView.swift`，
/// 调一处要改多处且容易遗漏。现统一集中到此处，改一处即全站同步。
enum BubbleMetrics {
    /// 卡片/气泡主体圆角：SettingsCard、BubbleCard、bottomToolbar 共用。
    static let cardCornerRadius: CGFloat = 20
    /// 渐变图标徽章圆角：GradientIconSquare、BubbleCard 内联徽章共用。
    static let iconBadgeCornerRadius: CGFloat = 8
    /// 列表行 hover 高亮背景圆角。
    static let hoverCornerRadius: CGFloat = 12
    /// 热键键帽/小标签圆角。
    static let keycapCornerRadius: CGFloat = 6

    /// 气泡不透明填充色（深色模式）。
    /// 选 #2B2B2D：接近系统 NSBox/控件卡片色，深色下不刺眼；浅色模式用纯白（BubbleBackground 内分支）。
    static let bubbleDarkFill = Color(red: 0.17, green: 0.17, blue: 0.18)

    /// 边栏选中行背景：比灰底深一档的半透明黑（浅深色自适应）。
    static let sidebarSelectionOpacity: CGFloat = 0.10

    /// 设置页顶部滚动毛玻璃：渐入斜坡——内容滚出多少 pt 内透明度从 0 到 1。
    static let headerBlurRamp: CGFloat = 24
    /// 设置页顶部滚动毛玻璃：底边渐隐尾巴长度（延伸到标题栏下方，内容穿过时无硬切线）。
    static let headerBlurFadeTail: CGFloat = 18

    // MARK: 字号刻度（面板 + 设置页统一，避免 9~14 的魔法数散落各视图）

    /// 卡片标题（BubbleCard / SettingsCard 头部）。
    static let fontTitle: CGFloat = 14
    /// 行主文字 / 设置行标签。
    static let fontBody: CGFloat = 13
    /// 胶囊按钮文字 / 行内图标。
    static let fontControl: CGFloat = 12
    /// 副标题 / 表单行标题 / 展开选项。
    static let fontCaption: CGFloat = 11
    /// 徽章 / 底部工具栏文字。
    static let fontMini: CGFloat = 10

    // MARK: 间距刻度

    /// 面板内卡片纵向间距（与面板外边距一致，视觉等距）。
    static let cardSpacing: CGFloat = 14
    /// 卡内列表行间距。
    static let rowSpacing: CGFloat = 2
}

extension View {
    /// 气泡悬浮阴影：BubbleCard / 面板底部工具栏 / SettingsCard 共用，
    /// 呈现「浮于背景之上」的层次。设置页卡片可用稍浅的 opacity。
    func bubbleShadow(opacity: Double = 0.12) -> some View {
        shadow(color: .black.opacity(opacity), radius: 6, x: 0, y: 2)
    }
}

extension Color {
    /// 6 位 hex（如 "#a6ad6f"）→ Color；非法输入回退 .clear。
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .clear
            return
        }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
