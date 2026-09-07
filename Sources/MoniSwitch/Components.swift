import SwiftUI
import AppKit

// 全站共享视觉组件：菜单栏面板（PanelView）与设置窗口（SettingsView/SettingsTabs）
// 共用的颜色、背景、卡片容器与行控件。刻度常量见 BubbleMetrics。

/// 强调色：跟随 macOS 系统强调色（系统设置 > 外观 > 强调色）。
///
/// 不再使用自定义品牌蓝：改读 `NSColor.controlAccentColor`（动态色），
/// 用户在「系统设置 > 外观」切换强调色时本界面实时刷新。
/// 项目约定「纯 SPM、无 xcassets」，故不引入 AccentColor.colorset，直接桥接 AppKit 动态色。
enum BrandColor {
    static var accent: Color { Color(NSColor.controlAccentColor) }
}

// MARK: - 背景与卡片容器

/// 气泡背景修饰器：不透明填充 + 自适应淡描边。
///
/// 改为不透明后不再涉及 material vibrancy（之前用 thinMaterial 时必须用 shape-style 重载、
/// 且 `.foregroundStyle(.primary)` 依赖 material 上下文，曾导致菜单栏字体变黑的回归）。
/// 现在直接用纯色填充：浅色=纯白，深色=BubbleMetrics.bubbleDarkFill（接近系统卡片色）。
/// `.foregroundStyle(.primary)` 在不透明背景下仍能正常自适应（浅=黑字、深=白字），无需特殊处理。
///
/// 设置卡片、菜单栏 BubbleCard/bottomToolbar 共用。
struct BubbleBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: BubbleMetrics.cardCornerRadius)
        // 浅色纯白、深色用固定卡片色（避免纯白在深色窗口上刺眼）。
        let fill: Color = colorScheme == .light ? .white : BubbleMetrics.bubbleDarkFill
        // 描边：不透明卡片在窗口上需要稍清晰边界，浅色用 0.10，深色用 0.18 提亮边缘。
        let strokeOpacity: Double = colorScheme == .light ? 0.10 : 0.18
        return content
            .background(fill, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1))
    }
}

/// 菜单栏面板的圆角气泡卡片：顶部标题行（强调色图标方块 + 标题）+ 自定义内容。
///
/// 无边框：不加 stroke 描边，仅靠不透明填充（BubbleBackground）与圆角呈现气泡形态，
/// 四周悬浮阴影与背景拉开层次。
struct BubbleCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行：强调色圆角方块图标 + 标题
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: BubbleMetrics.iconBadgeCornerRadius)
                    .fill(accent)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: BubbleMetrics.fontControl, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text(title)
                    .font(.system(size: BubbleMetrics.fontTitle, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            content
        }
        .padding(16)
        // 不透明填充（浅色纯白 / 深色卡片色）+ 自适应淡描边（与设置卡片同源）。
        .modifier(BubbleBackground())
        // 四周悬浮阴影：气泡与原生毛玻璃背景拉开层次，呈现「浮于桌面之上」的观感。
        .bubbleShadow()
        // hover 整卡微放大 + 上浮 + 阴影增强（最外层，全仿射保原生锐度）。仅菜单栏面板使用。
        .bubbleHoverLift()
    }
}

/// 设置分组卡片：头部（纯图标 + 标题）+ 自定义内容。
/// 视觉与菜单栏 BubbleCard 同源：BubbleBackground（不透明填充）+ 悬浮阴影。
struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                PlainIcon(systemImage: systemImage, size: 16)
                Text(title)
                    .font(.system(size: BubbleMetrics.fontBody, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            content
        }
        .padding(16)
        .modifier(BubbleBackground())
        // 悬浮阴影稍浅（强度系数 0.85，与菜单栏 BubbleCard 同款双层弥散）。
        .bubbleShadow(opacity: 0.85)
    }
}

// MARK: - 图标

/// 同色系渐变圆角图标方块：跟随系统强调色（亮端 0.85 → 深端 1.0）。
/// 仅关于页 dev 模式图标回退时使用；边栏/卡片头部已改用无背景纯图标（PlainIcon）。
struct GradientIconSquare: View {
    let systemImage: String
    var size: CGFloat = 22
    var cornerRadius: CGFloat = BubbleMetrics.iconBadgeCornerRadius
    /// 自定义渐变色；nil 时用系统强调色渐变。
    var colors: [Color]? = nil

    private var gradientColors: [Color] {
        // 自定义色按原样使用（不叠 0.85 透明，保持指定色准确）；默认渐变保持亮端 0.85。
        colors ?? [BrandColor.accent.opacity(0.85), BrandColor.accent]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// 无背景纯图标：用于内容区标题/卡片头部，对齐 macOS 系统设置的分块标题风格。
/// 与 GradientIconSquare 的区别：去掉彩色方块背景，只渲染 SF Symbol，颜色用 .secondary
/// （深灰、与副标题同色、浅深色自适应）。与正文文字层次一致，视觉极简统一。
struct PlainIcon: View {
    let systemImage: String
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

// MARK: - 行控件

/// 通用面板行按钮：整行可点（contentShape 全行命中）+ hover 高亮 + plain 样式。
///
/// 主显示器行 / 预设行 / SelectionRow 展开选项行共用同一交互形态，
/// 内容（图标/文字/角标）由调用方自由组合（单尾闭包，用法同 Button(action:) { label }）。
struct RowButton<Content: View>: View {
    let action: () -> Void
    /// 行内边距：主行默认 (5, 4)，展开选项等紧凑行可调小。
    var verticalPadding: CGFloat = 5
    var horizontalPadding: CGFloat = 4
    /// hover 高亮向两侧外扩点数（透传 hoverRowHighlight）。展开列表内的选项行
    /// 传 0：其自带 h:6 内边距已足够，再外扩会溢出浅灰圆角容器。
    var highlightExpansion: CGFloat = 6
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            content
                .contentShape(Rectangle())
                .padding(.vertical, verticalPadding)
                .padding(.horizontal, horizontalPadding)
                .hoverRowHighlight(horizontalExpansion: highlightExpansion)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// 类原生菜单的行 hover 高亮：鼠标悬停时给一层柔和的强调色叠加，
    /// 提升可点性与「鲜活/原生」感。修饰在已带 .contentShape 的行上。
    /// - Parameter horizontalExpansion: 高亮向左右两侧外扩的点数。行内容的水平
    ///   内边距普遍很窄（SelectionRow 触发行为 0），不外扩时高亮边界贴着文字
    ///   显得局促，默认外扩 6pt；空间受限的调用方（工具栏按钮、展开列表选项行）
    ///   传 0。
    @ViewBuilder
    func hoverRowHighlight(horizontalExpansion: CGFloat = 6) -> some View {
        modifier(HoverRowHighlightModifier(horizontalExpansion: horizontalExpansion))
    }

    /// 把任意视图包装成 plain Button（保留视图原样，仅接管整块命中区点击）。
    /// ActivePill 等自绘控件用它与系统按钮样式解耦。
    func asButton(action: @escaping () -> Void) -> some View {
        Button(action: action) { self }
            .buttonStyle(.plain)
    }
}

/// 激活态胶囊：active 时强调色实心 + 白字，非激活时透明底 + 主色字。
/// 镜像/扩展切换按钮与位置分段控件的段共用，激活态视觉由此统一。
/// - `strokeWhenInactive`：非激活时是否给整胶囊加淡描边（镜像/扩展按钮用；
///   位置分段的描边由外层分段容器统一承担，传 false）。
/// - 未激活态悬停时给一层 14% 强调色胶囊底（与行高亮同款），两类控件一并获得
///   悬停反馈；激活态本就是强调色实心，不再叠加。
struct ActivePill<Content: View>: View {
    let active: Bool
    var verticalPadding: CGFloat = 3
    var strokeWhenInactive = false
    @ViewBuilder let content: Content

    /// 悬停态跟踪。显式 init：加 @State 后默认成员构造器会变 private，
    /// 手写保持 PanelView 侧调用签名不变。
    @State private var isHovered = false

    init(active: Bool,
         verticalPadding: CGFloat = 3,
         strokeWhenInactive: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.active = active
        self.verticalPadding = verticalPadding
        self.strokeWhenInactive = strokeWhenInactive
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, verticalPadding)
            .background {
                if active {
                    Capsule().fill(BrandColor.accent)
                } else {
                    // hover 底色在下、描边在上，静止态层次不变。
                    ZStack {
                        if isHovered {
                            Capsule().fill(BrandColor.accent.opacity(0.14))
                        }
                        if strokeWhenInactive {
                            Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        }
                    }
                }
            }
            .foregroundStyle(active ? Color.white : Color.primary)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

/// 行 hover 高亮修饰器：用局部 @State 跟踪悬停态，叠加半透明强调色背景。
/// 强调色直接读 BrandColor.accent（桥接的动态色，系统强调色切换时自动更新）。
private struct HoverRowHighlightModifier: ViewModifier {
    /// 高亮向两侧外扩点数（见 hoverRowHighlight 注释）。
    var horizontalExpansion: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: BubbleMetrics.hoverCornerRadius)
                    .fill(BrandColor.accent.opacity(isHovered ? 0.14 : 0))
                    .animation(.easeInOut(duration: 0.12), value: isHovered)
                    // 负 padding 让高亮矩形向两侧外扩：只扩视觉、不占布局空间，
                    // 文字与行内其他元素的位置不受影响。
                    .padding(.horizontal, -horizontalExpansion)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - 气泡 hover 浮起

/// 气泡悬浮交互：hover 时整卡微放大 + 上浮 + 阴影增强（「浮起的小板」质感），离开弹簧落回。
///
/// **全部用 2D 仿射变换实现（scaleEffect/offset/shadow）**——仿射变换走 CALayer
/// 路径不栅格化，HiDPI 下保持系统原生渲染分辨率。曾用 rotation3DEffect 做
/// Atoll 式 3D 倾斜，3D 透视变换会把卡片栅格化重采样、悬停时整卡文字明显变糊
/// （用户实测反馈），已整体移除；含文字的卡片禁用 3D 透视效果（详见 AGENTS 风格约定）。
/// 幅度/弹簧常量收在 BubbleMetrics（liftScale/liftOffset/liftShadow*/liftSpring）。
/// 系统开启「减弱动态效果」时自动关闭。挂在卡片阴影链最外层（bubbleShadow 之后），
/// 增强阴影叠在双层弥散阴影之上。
struct BubbleHoverLiftModifier: ViewModifier {
    /// 悬停态跟踪（全站 hover 范式：@State + onHover）。
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let lifting = isHovered && !reduceMotion
        content
            .scaleEffect(lifting ? BubbleMetrics.liftScale : 1)
            .offset(y: lifting ? -BubbleMetrics.liftOffset : 0)
            .shadow(color: .black.opacity(lifting ? BubbleMetrics.liftShadowOpacity : 0),
                    radius: BubbleMetrics.liftShadowRadius,
                    x: 0, y: BubbleMetrics.liftShadowY)
            .onHover { isHovered = $0 }
            .animation(BubbleMetrics.liftSpring, value: isHovered)
    }
}

extension View {
    /// 气泡 hover 浮起：整卡微放大 + 上浮 + 阴影增强（见 BubbleHoverLiftModifier，全仿射保锐度）。
    /// 用于菜单栏面板的全部大气泡（BubbleCard 各卡片 + 底部工具栏两气泡）。
    func bubbleHoverLift() -> some View {
        modifier(BubbleHoverLiftModifier())
    }
}

// MARK: - 进度指示

/// 不确定进度条：一段强调色胶囊在轨道内循环流动，用于后台切换操作进行中的提示。
struct IndeterminateBar: View {
    var accent: Color
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * 0.28
            Capsule()
                .fill(accent.opacity(0.85))
                .frame(width: barWidth, height: 2.5)
                .offset(x: -barWidth + phase * (geo.size.width + barWidth))
        }
        .frame(height: 2.5)
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

// MARK: - 控件配色

extension View {
    /// 菜单样式下拉框的中性灰 tint：箭头指示胶囊渲染为灰底白箭头。
    ///
    /// macOS 15 实机上，设置窗口曾在根级传过桥接 AppKit 动态色的 tint
    ///（`Color(NSColor.controlAccentColor)`），下拉框箭头胶囊被实况渲染成红色
    ///（2026-08 实测，15.5 SDK 编译亦出现；离屏渲染不可复现，属实况合成路径的
    /// 桥接动态色解析失败）。此处刻意用 SwiftUI 静态灰 `Color.gray`
    ///（非桥接动态色，深浅外观恒定），避开同类桥接色风险；
    /// 若胶囊不跟随 tint 也无副作用（回落系统默认样式）。
    func menuPickerNeutralTint() -> some View {
        tint(Color.gray)
    }
}
