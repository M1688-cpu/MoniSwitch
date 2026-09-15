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

    /// 气泡分区标题颜色：低饱和浅灰（参考 Tutti 的小型大写标签），浅/深模式通用。
    static let sectionLabelColor = Color(hex: "#94A3B8")

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

    /// 分区标题字距（全大写小型标签风格，加宽字距提升可读性；中文标题同样受益）。
    static let sectionLabelTracking: CGFloat = 1.0

    // MARK: 间距刻度

    /// 面板内卡片纵向间距（与面板外边距一致，视觉等距）。
    static let cardSpacing: CGFloat = 14
    /// 卡内列表行间距。
    static let rowSpacing: CGFloat = 2

    // MARK: 显示器图标圆框（DeviceIconBadge）

    /// 圆框直径：主屏卡按主从状态着色、排列卡统一主题色
    /// （2026-09-12 由 24 调大到 28，用户要求「稍微调大一点」）。
    static let deviceIconDiameter: CGFloat = 28
    /// 圆框内类型图标字号（约为直径的 50%，保持光学平衡；fontControl=12 被
    /// 镜像按钮/预设卡/设置页共用，不能跟随圆框一起放大，故单列常量）。
    static let deviceIconFontSize: CGFloat = 14
    /// 未选中（非主屏）圆框填充：半透明主色，浅色模式呈浅灰暗态、深色模式自动提亮。
    static let deviceIconInactiveFillOpacity: CGFloat = 0.12

    // MARK: 底部工具栏按钮级 hover

    /// 单个图标按钮 hover 放大倍率（仅缩放图标本体，2D 仿射不栅格化；
    /// 触区/布局不动，无边缘振荡问题——区别于整卡 bubbleHoverLift）。
    static let toolbarIconHoverScale: CGFloat = 1.15
    /// hover 高亮底色不透明度（圆角矩形，叠在气泡底色上）。
    static let toolbarHoverFillOpacity: CGFloat = 0.07
    /// 按钮放大/还原弹簧。
    static let buttonHoverSpring = Animation.spring(response: 0.25, dampingFraction: 0.7)

    // MARK: 悬停补充气泡（MirrorTargetTooltip）

    /// 停留多久后弹出（对齐系统 tooltip 的 dwell 手感）。
    static let tooltipDwell: TimeInterval = 0.45
    /// 入场起始缩放（自按钮上缘向上生长，弹跳缓动）。
    static let tooltipPopScale: CGFloat = 0.85
    /// 入场弹簧：欠阻尼带轻微回弹，近似参考的 bouncy 贝塞尔（0.175, 0.885, 0.32, 1.275）。
    static let tooltipSpring = Animation.spring(response: 0.3, dampingFraction: 0.65)

    // MARK: 气泡 hover 浮起（bubbleHoverLift()，全仿射变换保原生锐度）

    /// hover 时整卡放大倍率（仿射 scaleEffect，不栅格化，HiDPI 下保持原生分辨率）。
    /// 锚点固定 .bottom（见 BubbleHoverLiftModifier 注释）：底边不动、只向上/向两侧
    /// 扩张，hover 命中区不会向内越过指针——曾配 offset(y:-2) 上浮，底边内拉 2pt
    /// 在卡片边缘形成 hover 进出死区带，指针扫过时整卡持续振荡跳动（2026-09 已移除）。
    /// 注意：不要改用 rotation3DEffect 做 3D 效果——3D 透视变换会栅格化重采样，
    /// HiDPI 下有效分辨率减半（hover 模糊事故的根因，2026-09 实测）。
    static let liftScale: CGFloat = 1.02
    /// hover 增强阴影（叠在 bubbleShadow 双层之上，营造「浮起」层次）。
    static let liftShadowOpacity: Double = 0.10
    static let liftShadowRadius: CGFloat = 16
    static let liftShadowY: CGFloat = 8
    /// 浮起/落回弹簧。
    static let liftSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    // MARK: 面板内嵌套滚动

    /// SelectionRow 选项列表限高：超过则列表内部滚动，面板高度可控（面板级 ScrollView 已废弃，勿混淆）。
    static let selectionListMaxHeight: CGFloat = 216
}

extension View {
    /// 气泡悬浮阴影：BubbleCard / 面板底部操作栏 / SettingsCard 共用，
    /// 呈现「浮于背景之上」的层次。双层弥散（ambient 大半径低透明铺开 +
    /// key 小半径贴边勾勒），与底色的过渡比单层阴影更柔和、无硬边界感。
    /// - Parameter opacity: 整体强度系数（1 = 面板标准；设置页卡片 0.85 稍浅）。
    func bubbleShadow(opacity: Double = 1) -> some View {
        shadow(color: .black.opacity(0.06 * opacity), radius: 11, x: 0, y: 5)
            .shadow(color: .black.opacity(0.09 * opacity), radius: 3.5, x: 0, y: 1.5)
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
