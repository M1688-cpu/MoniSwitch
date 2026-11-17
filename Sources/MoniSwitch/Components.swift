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

/// 设置分组卡片（2026-10-17 原生化改版，系统设置范式）：小字 semibold 标签置于
/// 卡**上方**，卡体纯色填充、圆角 10、无阴影无描边——原生分组卡靠底色差呈现层次，
/// 与菜单栏面板独立，保持现有设置页的原生分组外观。
/// 卡体颜色（2026-10-17 用户拍板「白底灰卡」）：浅色 = windowBackgroundColor 浅灰
/// （内容区已改纯白），深色 = controlBackgroundColor；两侧均与内容区差一档。
/// 行内容由调用方给，行间 Divider 由调用方排（原生分组的行分隔样式）。
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: BubbleMetrics.fontBody, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 8)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: BubbleMetrics.rowSpacing) {
                content
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                colorScheme == .light
                    ? Color(nsColor: .windowBackgroundColor)
                    : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: BubbleMetrics.settingsCardCornerRadius)
            )
        }
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

// MARK: - 设置页下拉选择胶囊

/// 设置页的下拉选择胶囊（自绘外壳 + 原生菜单弹出）。
///
/// 为什么不用原生 `Picker(.menu)`：macOS 27 实机（2026-10-17 用户前后台对比截图）
/// 上，原生菜单下拉框在**活动窗口**里反而渲染成近透明的浅底 + 灰字，非活动窗口
/// 才是灰底黑字——与原生控件惯例相反，视觉上「前台比后台更暗」。这里自绘外壳，
/// 按窗口 key 状态显式走惯例方向：活动窗口 = 更实的灰底 + 主文字色；非活动窗口 =
/// 更浅的底 + 5 成文字色（数值对应用户截图：活动 ≈#EEE / 非活动 ≈#F9F9F9）。
/// 弹出菜单仍用原生 `Menu`（选中项由 `Toggle` 呈现系统勾选标记）。
struct SettingsMenuPicker<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    /// 所在窗口是否为 key 窗口（由零尺寸 AppKit 探针回写）。
    @State private var windowIsKey = true

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Toggle(isOn: Binding(
                    get: { selection == option },
                    set: { isOn in
                        // 点击已选中项时系统会尝试取消勾选，这里忽略，保持单选语义。
                        guard isOn else { return }
                        selection = option
                    }
                )) {
                    Text(title(option))
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title(selection))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(chevronColor)
            }
            .font(.system(size: BubbleMetrics.fontBody))
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(WindowKeyStateReader(isKey: $windowIsKey))
    }

    /// 活动窗口 #EEEEEE / 非活动 #F9F9F9（用户截图实测），深色模式随 primary 自动反转。
    private var fillColor: Color {
        Color.primary.opacity(windowIsKey ? 0.08 : 0.028)
    }
    private var textColor: Color {
        windowIsKey ? Color.primary : Color.primary.opacity(0.55)
    }
    private var chevronColor: Color {
        Color.primary.opacity(windowIsKey ? 0.7 : 0.4)
    }
}

/// 把所在窗口的 key 状态回写成 Binding（下拉胶囊在活动/非活动窗口用不同配色）。
///
/// 零尺寸探针挂在 background：`viewDidMoveToWindow` 时订阅该窗口的
/// didBecomeKey/didResignKey 通知并立即上报当前值。不用 SwiftUI 的
/// `controlActiveState`（无公开环境键）；也不读 `NSApp.isActive`——那是 App 级
/// 概念，同 App 多窗口时窗口 key 状态才是原生控件的判据。
private struct WindowKeyStateReader: NSViewRepresentable {
    @Binding var isKey: Bool

    func makeNSView(context: Context) -> WindowKeyProbe {
        let view = WindowKeyProbe()
        view.onChange = { isKey = $0 }
        return view
    }

    func updateNSView(_ nsView: WindowKeyProbe, context: Context) {
        nsView.onChange = { isKey = $0 }
    }
}

private final class WindowKeyProbe: NSView {
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let window else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.onChange?(true)
        })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.onChange?(false)
        })
        // 首次上报延后一拍：viewDidMoveToWindow 落在 SwiftUI 更新事务里，同步写
        // @State 会触发「Modifying state during view update」告警。
        let current = window.isKeyWindow
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(current)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
