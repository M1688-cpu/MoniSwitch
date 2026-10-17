import SwiftUI

// 面板内置主题（2026-10-17）：色源 = 用户提供的 Chrome 主题色卡截图，三档色值经
// 像素扫描逐圆提取并锁定（Tests/PanelThemeTests）；派生规则与「跟随系统」行为
// 见各类型注释。作用范围 = 菜单栏面板 + 亮度 HUD；设置窗口保持原生观感不注入。

// MARK: - 三档色板

/// 面板主题色板。色源 = Chrome 色卡三档，但**浅色/深色各自派生**，并不直用：
/// - 浅色（2026-10-17 改版，A 方案）：取中间档色相，按 L* 目标重算——卡底 L*94
///   （S=0.10–0.26 的单色相淡染）、高亮 L*80（S≥0.42）、实心 L*40（S≥0.42，S 取
///   最深档源值）。三档拉开明度后，高亮不再与卡底只差 10 L*；标签/描边也取实心档
///   染色（小字对比 ≈4.7:1）。行 hover 不透明度 0.42、布局点亮 0.50、胶囊悬停 0.22。
/// - 深色（沿用 2026-10-17 初版派生，**不动**）：bg L0.15、highlight L0.62、
///   solid L0.52、surface L0.21（HSL 明度）。标签/描边保持中性 slate/primary，
///   hover 0.14、点亮 0.28——即用户已验收的 C 方案。
/// - 「跟随系统」：不染，卡底浅白/深卡色，高亮/实心取系统强调色。
/// `surface`：浅色=派生卡底（与卡底同色，靠描边 + 阴影分层）；深色=派生 L0.21。
struct PanelPalette {
    /// 卡片底色；nil = 不染（跟随系统默认：浅色纯白 / 深色 BubbleMetrics.bubbleDarkFill）。
    var background: Color?
    var highlight: Color
    var solid: Color
    /// 实心档上的文字/图标色：按实心档亮度自动选白/黑（青/绿/黄系深色模式的实心
    /// 派生档偏亮，白字对比度不足）；「跟随系统」沿用既有行为恒白。
    var solidText: Color
    /// 二级气泡浮面；nil = 回退中性表面（浅纯白/深卡片色，跟随系统时）。
    var surface: Color?

    /// 行 hover 高亮填充不透明度（浅色派生 0.42；深色/跟随系统 0.14）。
    var hoverOpacity: Double = 0.14
    /// 布局图点亮填充不透明度（浅色派生 0.50；深色/跟随系统 0.28）。
    var litOpacity: Double = 0.28
    /// 小控件（未激活胶囊）悬停底不透明度（浅色派生 0.22；其余 0.14）。
    var subtleHoverOpacity: Double = 0.14
    /// 分区小标题颜色；nil = BubbleMetrics.sectionLabelColor（slate）。
    var sectionLabel: Color?
    /// 卡片/浮层描边颜色；nil = Color.primary.opacity(surfaceStrokeOpacity) 中性描边。
    var cardBorder: Color?

    static let system = PanelPalette(background: nil, highlight: BrandColor.accent,
                                     solid: BrandColor.accent, solidText: .white, surface: nil)

    /// 深色派生构造（bg/highlight/solid/surface 均来自 darkDerived），
    /// 标签/描边与交互透明度全部走默认值，保持 C 深色观感不变。
    static func themed(bg: String, highlight: String, solid: String, surface: String) -> PanelPalette {
        PanelPalette(background: Color(hex: bg),
                     highlight: Color(hex: highlight),
                     solid: Color(hex: solid),
                     solidText: Self.contrastText(on: solid),
                     surface: Color(hex: surface))
    }

    /// 浅色派生构造（A 方案）：标签/描边取实心档染色，交互透明度按浅色明度差标定。
    static func themedLight(bg: String, highlight: String, solid: String, surface: String) -> PanelPalette {
        let solidColor = Color(hex: solid)
        return PanelPalette(background: Color(hex: bg),
                            highlight: Color(hex: highlight),
                            solid: solidColor,
                            solidText: Self.contrastText(on: solid),
                            surface: Color(hex: surface),
                            hoverOpacity: 0.42,
                            litOpacity: 0.50,
                            subtleHoverOpacity: 0.22,
                            sectionLabel: solidColor.opacity(0.90),
                            cardBorder: solidColor.opacity(0.22))
    }

    /// 实心档上叠字的对比色：伽马空间亮度 > 0.55 用黑字，否则白字。
    static func contrastText(on hex: String) -> Color {
        guard let c = PanelThemeMath.rgb(hex) else { return .white }
        let y = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return y > 0.55 ? .black : .white
    }
}

// MARK: - 环境注入

private struct PanelPaletteKey: EnvironmentKey {
    static let defaultValue: PanelPalette = .system
}

extension EnvironmentValues {
    /// 面板主题色板。PanelView 根部与亮度 HUD 各自按当前设置解析后注入；
    /// 设置窗口不注入（defaultValue = .system，保持系统强调色与原生卡片观感）。
    /// BubbleBackground / ActivePill / 行 hover 高亮及面板私有视图从环境读取。
    var panelPalette: PanelPalette {
        get { self[PanelPaletteKey.self] }
        set { self[PanelPaletteKey.self] = newValue }
    }
}

// MARK: - 内置主题

/// 一组内置主题：同色系三档 hex（2026-10-17 从 Chrome 主题色卡截图像素扫描提取：
/// 每个圆卡 = 左上象限最深 / 右上象限中间 / 下半圆最浅）。浅色模式取中间档色相、
/// 按 L* 目标重算三档（见 lightDerived）；深色模式保留色相、按档位目标重算明度/
/// 饱和度（见 darkDerived）。
struct PanelTheme: Identifiable {
    let id: String
    let nameKey: TextKey
    /// 最浅档（背景档）hex。
    let lightHex: String
    /// 中间档（高亮档）hex。
    let midHex: String
    /// 最深档（实心档）hex。
    let deepHex: String

    /// 该主题在指定外观下的色板。浅色 = 单色相 L* 派生（A 方案）；深色 = 初版派生
    /// （C 方案，保持用户已验收的观感不变）。
    func palette(dark: Bool) -> PanelPalette {
        if !dark {
            let d = PanelTheme.lightDerived(midHex: midHex, deepHex: deepHex)
            return .themedLight(bg: d.bg, highlight: d.highlight, solid: d.solid, surface: d.surface)
        }
        let d = PanelTheme.darkDerived(lightHex: lightHex, midHex: midHex, deepHex: deepHex)
        return .themed(bg: d.bg, highlight: d.highlight, solid: d.solid, surface: d.surface)
    }
}

extension PanelTheme {
    /// 「跟随系统」项的 id（AppSettings.panelThemeID 默认值）。
    static let systemID = "system"

    /// 7 组低饱和同色系主题（2026-10-17 用户从初版 13 组里二次筛选：删掉
    /// 品红/紫/绿/黄/粉/青，只留低饱和的玫瑰红/鼠尾草绿/橙/棕褐/蓝/蓝灰/青灰）。
    /// 色卡截图里另有 2 组蓝灰混合卡中间档是纯灰 #C7C7C7，做高亮在浅灰底上
    /// 不可见，从未收录；顺序沿用色卡网格行主序。
    static let all: [PanelTheme] = [
        PanelTheme(id: "rose",      nameKey: .themeRose,      lightHex: "#FADBDF", midHex: "#DDBFC3", deepHex: "#70585C"),
        PanelTheme(id: "sage",      nameKey: .themeSage,      lightHex: "#DAE6D3", midHex: "#BECAB8", deepHex: "#566253"),
        PanelTheme(id: "orange",    nameKey: .themeOrange,    lightHex: "#FFDCC7", midHex: "#FFB787", deepHex: "#8E4E1D"),
        PanelTheme(id: "tan",       nameKey: .themeTan,       lightHex: "#FBDCCC", midHex: "#DEC1B1", deepHex: "#705A4D"),
        PanelTheme(id: "blue",      nameKey: .themeBlue,      lightHex: "#D6E3FF", midHex: "#AAC7FF", deepHex: "#3A5E98"),
        PanelTheme(id: "blueGray",  nameKey: .themeBlueGray,  lightHex: "#D6E3FF", midHex: "#BAC7E3", deepHex: "#525F77"),
        PanelTheme(id: "tealGray",  nameKey: .themeTealGray,  lightHex: "#D4E6E9", midHex: "#B8CACD", deepHex: "#516164"),
    ]

    /// 按设置里的主题 id 解析色板；system / 未知 id 一律回落「跟随系统」。
    static func palette(id: String, dark: Bool) -> PanelPalette {
        guard id != systemID, let theme = all.first(where: { $0.id == id }) else { return .system }
        return theme.palette(dark: dark)
    }
}

// MARK: - 浅色模式派生

extension PanelTheme {
    /// 浅色模式四值派生（2026-10-17 A 方案）：取**中间档色相**作为唯一色相源，
    /// 按 L* 目标重算三档，避免直用色卡原值时「卡底 L*90 / 高亮 L*80」只差 10 L*、
    /// 14% 叠上去只有 1.4 L* 的不可见问题；同时把低饱和的最深档提饱和，消除
    /// 浅色下实心档发灰。目标与饱和度：
    /// - bg：L*94，S = clamp(0.04 + 原S×0.22, 0.10...0.26) —— 近白淡染的纸面；
    /// - highlight：L*80，S = clamp(原S, 0.42...0.68) —— 行 hover / 点亮；
    /// - solid：L*40，S = clamp(最深档原S, 0.42...0.66) —— 实心强调；
    /// - surface：与 bg 同色（二级气泡靠描边 + 阴影分层）。
    /// 色相统一取中间档：蓝灰的浅色卡底因此从「和蓝主题同色」变成真正的灰蓝。
    /// 纯函数，输出由测试独立锁定（python，L* 用 sRGB 相对亮度）。
    static func lightDerived(midHex: String, deepHex: String)
        -> (bg: String, highlight: String, solid: String, surface: String) {
        guard let mid = PanelThemeMath.rgb(midHex),
              let deep = PanelThemeMath.rgb(deepHex) else {
            return (midHex, midHex, deepHex, midHex)
        }
        let m = PanelThemeMath.hsl(mid.r, mid.g, mid.b)
        let d = PanelThemeMath.hsl(deep.r, deep.g, deep.b)
        let bg = PanelThemeMath.color(h: m.h,
                                      s: min(0.26, max(0.10, 0.04 + m.s * 0.22)),
                                      lstar: 94)
        let highlight = PanelThemeMath.color(h: m.h,
                                             s: min(0.68, max(0.42, m.s)),
                                             lstar: 80)
        let solid = PanelThemeMath.color(h: m.h,
                                         s: min(0.66, max(0.42, d.s)),
                                         lstar: 40)
        return (bg, highlight, solid, bg)
    }
}

// MARK: - 深色模式派生

extension PanelTheme {
    /// 深色模式四值派生（角色对应与浅色一致）：色卡三档为浅色背景设计，
    /// 深色下直接用会让背景刺眼、实心档沉底。派生保留各自色相，明度取档位目标值、
    /// 饱和度按「底数 + 原饱和度 × 系数（封顶）」重算——
    /// - bg：**最浅档**（卡底色源）压成同色相深色底（L0.15）；
    /// - highlight：**中间档**（高亮色源）提到深色下可读的亮度（L0.62）；
    /// - solid：**最深档**提到深色下可读（L0.52）；
    /// - surface：最浅档派生的浮面（L0.21，比卡底 L0.15 略浅——二级气泡分层来源）。
    /// 纯函数，输出由测试独立锁定（python colorsys）。
    static func darkDerived(lightHex: String, midHex: String, deepHex: String)
        -> (bg: String, highlight: String, solid: String, surface: String) {
        let bg = remapForDark(lightHex, l: 0.15, sFloor: 0.24, sScale: 0.35, sCap: 0.40)
        let highlight = remapForDark(midHex, l: 0.62, sFloor: 0.30, sScale: 0.42, sCap: 0.60)
        let solid = remapForDark(deepHex, l: 0.52, sFloor: 0.30, sScale: 0.50, sCap: 0.62)
        let surface = remapForDark(lightHex, l: 0.21, sFloor: 0.24, sScale: 0.35, sCap: 0.40)
        return (bg, highlight, solid, surface)
    }

    /// 单档重映射：hex → HSL → 替换 L、S 后回 hex；解析失败原样返回。
    private static func remapForDark(_ hex: String, l: Double, sFloor: Double, sScale: Double, sCap: Double) -> String {
        guard let c = PanelThemeMath.rgb(hex) else { return hex }
        let hsl = PanelThemeMath.hsl(c.r, c.g, c.b)
        let s = min(sCap, sFloor + hsl.s * sScale)
        return PanelThemeMath.hex(h: hsl.h, s: s, l: l)
    }
}

// MARK: - 颜色数学（RGB ↔ HSL，hex 解析/生成）

/// 颜色空间换算纯函数（0...1 分量、h∈[0,360)）。测试用独立实现（python colorsys）
/// 锁定过输出，改算法须同步更新测试期望。
enum PanelThemeMath {
    struct RGB { var r, g, b: Double }

    /// "#RRGGBB"（或去 # 的 6 位）→ RGB；非法输入 nil。
    static func rgb(_ hex: String) -> RGB? {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return RGB(r: Double((v >> 16) & 0xFF) / 255.0,
                   g: Double((v >> 8) & 0xFF) / 255.0,
                   b: Double(v & 0xFF) / 255.0)
    }

    /// RGB → HSL（h 单位度，s/l 0...1）。
    static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        if mx == mn { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = ((g - b) / d + (g < b ? 6 : 0)) * 60 }
        else if mx == g { h = ((b - r) / d + 2) * 60 }
        else { h = ((r - g) / d + 4) * 60 }
        return (h, s, l)
    }

    /// HSL → "#RRGGBB"（四舍五入到 8bit）。
    static func hex(h: Double, s: Double, l: Double) -> String {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        func q(_ v: Double) -> Int { Int((v + m).clamped(to: 0...1) * 255 + 0.5) }
        return String(format: "#%02X%02X%02X", q(r1), q(g1), q(b1))
    }

    /// 给定色相/饱和度，二分求使 CIELAB L* 达到 `target` 的 HSL 明度，返回 hex。
    /// 浅色派生用；24 次迭代足以稳定到 8bit。
    static func color(h: Double, s: Double, lstar target: Double) -> String {
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if (lstar(hex: hex(h: h, s: s, l: mid)) ?? 0) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return hex(h: h, s: s, l: (low + high) / 2)
    }

    /// sRGB hex → CIELAB L*（0...100）；解析失败 nil。浅色派生的目标明度基准。
    static func lstar(hex: String) -> Double? {
        guard let c = rgb(hex) else { return nil }
        func linear(_ v: Double) -> Double {
            v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let y = 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
        return y > 0.008856 ? 116 * pow(y, 1.0 / 3.0) - 16 : 903.3 * y
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
