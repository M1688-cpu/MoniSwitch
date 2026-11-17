import SwiftUI

/// 一块玻璃瓷砖。面板没有整体背板，瓷砖直接浮在壁纸上；
/// 不加外投影（阴影直接落壁纸的观感 2026-09-14 被否决过）。
/// macOS 26+ 用系统 Liquid Glass，14/15 回退系统材质。
/// `interactive` 打开系统玻璃的按压反馈（底栏图标键用），14/15 无此效果。
struct PanelGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 22
    var isSelected = false
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                content.background {
                    shape.fill(Color(nsColor: .windowBackgroundColor)).allowsHitTesting(false)
                }
            } else if #available(macOS 26.0, *) {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            } else {
                content.background {
                    shape.fill(.regularMaterial).allowsHitTesting(false)
                }
            }
        }
        .overlay {
            if isSelected {
                shape.strokeBorder(BrandColor.accent, lineWidth: 1.5).allowsHitTesting(false)
            }
        }
    }
}

/// 保持非激活面板中的原生控件活动外观，同时遵从禁用状态。
struct PanelGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { content.environment(\.appearsActive, true) }
}

/// 底栏的单个玻璃图标键（设置 / 自动排列 / 刷新 / 退出各一个）。
/// 名称走原生 `.help` 悬停提示与无障碍标签，键面只放 SF Symbol。
struct PanelIconButton: View {
    let symbol: String
    let title: String
    /// true 时键面换成小转圈（操作进行中），调用方同时负责禁用。
    var showsProgress = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if showsProgress {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isHovered && isEnabled ? Color.primary : Color.secondary)
                }
            }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(PanelGlassSurface(cornerRadius: 20, interactive: isEnabled))
        .opacity(isEnabled || showsProgress ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

/// 圆形玻璃动作键（设为主屏 / 镜像 / 扩展）；选中态用系统强调色。
struct GlassRoundAction: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .frame(width: 40, height: 40)
                    .background {
                        Circle().fill(isOn ? BrandColor.accent : Color.primary.opacity(0.10))
                    }
                Text(title)
                    .font(.system(size: BubbleMetrics.fontCaption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
