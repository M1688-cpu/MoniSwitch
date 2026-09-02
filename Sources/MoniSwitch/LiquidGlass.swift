import SwiftUI

// 液态玻璃（Liquid Glass）视觉组件：手工绘制的跨版本实现。
//
// 为什么不用系统 API：本机工具链 SDK 为 15.5，`glassEffect` 需要 macOS 26 SDK
// 才能编译；且项目最低支持 macOS 13。手工绘制在 13~26 观感完全一致、且小尺寸
// 控件上的高光/折射层次比系统 glassEffect 更可控。
//
// 视觉语言（对应 Apple Liquid Glass 的四要素）：
//   1. 染色基底 —— tint 色半透明填充（透出底色的玻璃体）
//   2. 镜面高光 —— 上缘一条亮色渐变（玻璃球面对上方光线的反射）
//   3. 边缘亮线 —— 一圈细白描边（玻璃厚度 + 全内反射的 specular edge）
//   4. 内阴影   —— 下缘暗渐变（玻璃体自身的体积感）
// 外加柔和落影把玻璃从背景上「浮」起来。

// MARK: - 玻璃表面修饰器

/// 给任意形状内容叠一层液态玻璃质感。
///
/// - Parameters:
///   - tint: 染色；nil 为中性玻璃（浅色近白雾、深色近石墨，自适应）。
///   - hoverBoost: 悬停时高光增强的比例（0 关闭交互反馈）。
struct LiquidGlassSurfaceModifier: ViewModifier {
    var tint: Color?
    var hoverBoost: Double

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    /// 悬停增益：玻璃被「点亮」一点，模拟光线随交互变化。
    private var boost: Double { isHovered ? hoverBoost : 0 }

    func body(content: Content) -> some View {
        let shape = Capsule()
        let base: Color = tint != nil
            ? tint!.opacity(colorScheme == .dark ? 0.82 : 0.88)
            : Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08)

        return content
            .background(
                ZStack {
                    // 1. 染色基底
                    shape.fill(base)
                    // 2. 上缘镜面高光：白从顶部 45% 渐隐到中部
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.42 + boost * 0.5), location: 0),
                                .init(color: .white.opacity(0.10 + boost * 0.2), location: 0.48),
                                .init(color: .white.opacity(0), location: 0.55)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // 3. 下缘内阴影：底部一圈暗渐变，压出玻璃体积
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0), location: 0.62),
                                .init(color: .black.opacity(tint != nil ? 0.16 : 0.10), location: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            )
            // 4. 边缘亮线：染色玻璃用白亮线（specular edge），中性玻璃用自适应细线
            .overlay(
                shape.strokeBorder(
                    (tint != nil ? Color.white : Color.white.opacity(0.5))
                        .opacity(colorScheme == .dark ? 0.28 : 0.45),
                    lineWidth: 1
                )
            )
            // 柔和落影：染色玻璃的影更深一档
            .shadow(color: .black.opacity(tint != nil ? 0.22 : 0.12), radius: 2.5, x: 0, y: 1.5)
            .onHover { hovering in
                guard hoverBoost > 0 else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            }
    }
}

extension View {
    /// 液态玻璃表面：染色基底 + 上缘镜面高光 + 边缘亮线 + 下缘内阴影 + 落影。
    /// - Parameters:
    ///   - tint: 染色；nil 为中性玻璃。跟随系统强调色请传 `Color.accentColor`。
    ///   - hoverBoost: 悬停高光增强比例（默认 0.5；传 0 关闭交互反馈）。
    func liquidGlass(tint: Color? = nil, hoverBoost: Double = 0.5) -> some View {
        modifier(LiquidGlassSurfaceModifier(tint: tint, hoverBoost: hoverBoost))
    }
}

// MARK: - 液态玻璃开关

/// 液态玻璃风格的 Toggle：玻璃胶囊轨道（开启时强调色染色）+ 玻璃珠滑块。
///
/// 尺寸对齐系统 NSSwitch（40×23），可直接替换 `.toggleStyle(.switch)`。
/// 轨道与滑块都是玻璃材质：轨道是染色玻璃槽，滑球是不透明感更强的玻璃珠
/// （顶部高光弧 + 落影），拨动用 spring 动画。
struct LiquidGlassToggleStyle: ToggleStyle {

    // 与 NSSwitch 对齐的刻度
    private let trackSize = CGSize(width: 40, height: 23)
    private let knobDiameter: CGFloat = 17
    /// 轨道内边距：滑球贴边但不顶出。
    private var knobInset: CGFloat { (trackSize.height - knobDiameter) / 2 }
    private var travel: CGFloat { trackSize.width - knobDiameter - knobInset * 2 }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    configuration.isOn.toggle()
                }
            } label: {
                track(isOn: configuration.isOn)
            }
            .buttonStyle(.plain)
        }
    }

    /// 玻璃轨道 + 玻璃珠滑块。
    private func track(isOn: Bool) -> some View {
        HStack(spacing: 0) {
            knob
                .offset(x: isOn ? travel : 0)
            Spacer(minLength: 0)
        }
        .padding(knobInset)
        .frame(width: trackSize.width, height: trackSize.height)
        // 轨道玻璃：开启 = 强调色染色玻璃；关闭 = 中性玻璃。hover 反馈关闭
        //（点击瞬间的 spring 动画已足够，常驻 hover 提亮反而显得闪烁）。
        .liquidGlass(tint: isOn ? Color.accentColor : nil, hoverBoost: 0)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isOn)
    }

    /// 玻璃珠滑块：暖白基底 + 顶部高光弧 + 微透边缘 + 落影。
    private var knob: some View {
        Circle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: Color(white: 0.96), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                // 顶部高光弧：珠面上方的镜面反射
                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.95), location: 0),
                                .init(color: .white.opacity(0), location: 0.55)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .padding(1.5)
            )
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            )
            .frame(width: knobDiameter, height: knobDiameter)
            .shadow(color: .black.opacity(0.28), radius: 1.5, x: 0, y: 1)
    }
}

extension ToggleStyle where Self == LiquidGlassToggleStyle {
    /// 液态玻璃开关样式（`.toggleStyle(.liquidGlass)`）。
    static var liquidGlass: LiquidGlassToggleStyle { .init() }
}
