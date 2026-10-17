// 面板内置主题锁定（2026-10-17）：7 组三档色值录自用户提供的 Chrome 主题色卡
// 截图（逐圆像素扫描提取：左上象限最深/右上象限中间/下半圆最浅；初版 13 组经用户
// 二次筛选删除品红/紫/绿/黄/粉/青）；深色派生期望值由独立实现（python colorsys，
// 2026-10-17 运行记录）计算——改算法或色值必须带出处同步更新，并经用户在真实壁纸
// 浅/深两模式下人肉验收。
import Testing
import SwiftUI
@testable import MoniSwitch

@Suite struct PanelThemeTests {

    // MARK: 浅色三档锁定（像素扫描原值）

    @Test("浅色三档 = 色卡像素扫描原值（背景档/高亮档/实心档）")
    func lightTiersLocked() {
        let locked: [(id: String, light: String, mid: String, deep: String)] = [
            ("rose",      "#FADBDF", "#DDBFC3", "#70585C"),
            ("sage",      "#DAE6D3", "#BECAB8", "#566253"),
            ("orange",    "#FFDCC7", "#FFB787", "#8E4E1D"),
            ("tan",       "#FBDCCC", "#DEC1B1", "#705A4D"),
            ("blue",      "#D6E3FF", "#AAC7FF", "#3A5E98"),
            ("blueGray",  "#D6E3FF", "#BAC7E3", "#525F77"),
            ("tealGray",  "#D4E6E9", "#B8CACD", "#516164"),
        ]
        #expect(PanelTheme.all.count == locked.count)
        for (theme, exp) in zip(PanelTheme.all, locked) {
            #expect(theme.id == exp.id, "\(theme.id) 顺序漂移（色卡网格行主序）")
            #expect(theme.lightHex == exp.light, "\(theme.id).light")
            #expect(theme.midHex == exp.mid, "\(theme.id).mid")
            #expect(theme.deepHex == exp.deep, "\(theme.id).deep")
        }
    }

    // MARK: 角色映射（浅色）

    @Test("浅色派生：单色相 + L* 目标（bg 94 / hi 80 / solid 40）与交互不透明度")
    func lightDerivationLocked() {
        // 2026-10-17 A 方案：浅色不再直用色卡三档（原「卡底 L*90 / 高亮 L*80」只差
        // 10 L*，14% 叠上去仅 1.4 L*，高亮不可见）。期望值为独立 python 实现
        // （sRGB→CIELAB L* + 二分）的输出；改算法/目标必须同步重算。
        let cases: [(bg: String, highlight: String, solid: String)] = [
            ("#F1EDED", "#E4BCC2", "#9C404C"), // rose
            ("#ECEEEB", "#A8D392", "#3F692B"), // sage
            ("#F2ECE9", "#ECBD9E", "#914C1E"), // orange
            ("#F0EEEC", "#DFC1B0", "#845236"), // tan
            ("#EBEEF3", "#B2C8F0", "#3C5D9D"), // blue
            ("#ECEEF1", "#B9C6E3", "#3F5D9B"), // blueGray
            ("#EBEEEF", "#9DCED7", "#2E666F"), // tealGray
        ]
        #expect(PanelTheme.all.count == cases.count)
        for (theme, exp) in zip(PanelTheme.all, cases) {
            let got = PanelTheme.lightDerived(midHex: theme.midHex, deepHex: theme.deepHex)
            #expect(got.bg == exp.bg, "\(theme.id) bg")
            #expect(got.highlight == exp.highlight, "\(theme.id) highlight")
            #expect(got.solid == exp.solid, "\(theme.id) solid")
            #expect(got.surface == exp.bg, "\(theme.id) surface 与卡底同色")

            // 目标明度（hex 经 8bit 舍入，容差 0.6 L*）。
            #expect(abs((PanelThemeMath.lstar(hex: got.bg) ?? 0) - 94) < 0.6, "\(theme.id) bg L*")
            #expect(abs((PanelThemeMath.lstar(hex: got.highlight) ?? 0) - 80) < 0.6, "\(theme.id) hi L*")
            #expect(abs((PanelThemeMath.lstar(hex: got.solid) ?? 0) - 40) < 0.6, "\(theme.id) solid L*")

            let p = theme.palette(dark: false)
            #expect(p.background == Color(hex: exp.bg), "\(theme.id) 卡底")
            #expect(p.surface == Color(hex: exp.bg), "\(theme.id) 浮面")
            #expect(p.highlight == Color(hex: exp.highlight), "\(theme.id) 高亮")
            #expect(p.solid == Color(hex: exp.solid), "\(theme.id) 实心")
            #expect(p.solidText == Color.white, "\(theme.id) L*40 实心应白字")
            #expect(p.hoverOpacity == 0.42, "\(theme.id) hover 0.42")
            #expect(p.litOpacity == 0.50, "\(theme.id) lit 0.50")
            #expect(p.subtleHoverOpacity == 0.22, "\(theme.id) pill hover 0.22")
            #expect(p.sectionLabel != nil, "\(theme.id) 浅色标签应染实心档")
            #expect(p.cardBorder != nil, "\(theme.id) 浅色描边应染实心档")
        }
    }

    @Test("深色色板 = 初版派生（C 方案）且标签/交互透明度保持中性")
    func darkPaletteLocked() {
        // 用户已验收的深色观感必须逐值不变：色板取 darkDerived，hover 0.14 /
        // 点亮 0.28 / 胶囊 0.14，标签与描边保持 slate/primary（nil）。
        for theme in PanelTheme.all {
            let d = PanelTheme.darkDerived(lightHex: theme.lightHex,
                                           midHex: theme.midHex,
                                           deepHex: theme.deepHex)
            let p = theme.palette(dark: true)
            #expect(p.background == Color(hex: d.bg), "\(theme.id) bg")
            #expect(p.surface == Color(hex: d.surface), "\(theme.id) surface")
            #expect(p.highlight == Color(hex: d.highlight), "\(theme.id) highlight")
            #expect(p.solid == Color(hex: d.solid), "\(theme.id) solid")
            #expect(p.hoverOpacity == 0.14, "\(theme.id) hover")
            #expect(p.litOpacity == 0.28, "\(theme.id) lit")
            #expect(p.subtleHoverOpacity == 0.14, "\(theme.id) pill hover")
            #expect(p.sectionLabel == nil, "\(theme.id) 深色标签应回退 slate")
            #expect(p.cardBorder == nil, "\(theme.id) 深色描边应回退中性")
        }
    }

    // MARK: 深色派生锁定（期望值 = python colorsys 独立计算）

    @Test("深色派生：bg←最浅档 / highlight←中间档 / solid←最深档 + surface 浮面（python colorsys 独立锁定）")
    func darkDerivationLocked() {
        // (输入: light/mid/deep) → (bg, highlight, solid, surface)，
        // 全部来自 2026-10-17 角色掰正后的 python 运行输出（bg 取最浅档、highlight 取中间档）。
        let cases: [(String, String, String, String, String, String, String)] = [
            // light, mid, deep, bg, highlight, solid, surface
            ("#FADBDF", "#DDBFC3", "#70585C", "#36171B", "#C87580", "#B15967", "#4B2026"), // rose
            ("#DAE6D3", "#BECAB8", "#566253", "#233319", "#92C17B", "#6CAE5B", "#314824"), // sage
            ("#FFDCC7", "#FFB787", "#8E4E1D", "#362217", "#D89264", "#D07B39", "#4B3020"), // orange
            ("#FBDCCC", "#DEC1B1", "#705A4D", "#362117", "#CC9171", "#B57855", "#4B2F20"), // tan
            ("#D6E3FF", "#AAC7FF", "#3A5E98", "#172136", "#648CD8", "#4476C5", "#202E4B"), // blue
            ("#D6E3FF", "#BAC7E3", "#525F77", "#172136", "#708DCC", "#5576B5", "#202E4B"), // blueGray
            ("#D4E6E9", "#B8CACD", "#516164", "#193034", "#7AB8C2", "#59A2B0", "#234348"), // tealGray
        ]
        for c in cases {
            let got = PanelTheme.darkDerived(lightHex: c.0, midHex: c.1, deepHex: c.2)
            #expect(got.bg == c.3, "bg ← light \(c.0) → \(got.bg)，期望 \(c.3)")
            #expect(got.highlight == c.4, "highlight ← mid \(c.1) → \(got.highlight)，期望 \(c.4)")
            #expect(got.solid == c.5, "solid ← deep \(c.2) → \(got.solid)，期望 \(c.5)")
            #expect(got.surface == c.6, "surface ← light \(c.0) → \(got.surface)，期望 \(c.6)")
        }
    }

    // MARK: 解析与回落

    @Test("system/未知 id 回落跟随系统（不染卡底、交互透明度与中性次要色）")
    func fallbackToSystem() {
        for id in [PanelTheme.systemID, "nonexistent"] {
            let p = PanelTheme.palette(id: id, dark: false)
            #expect(p.background == nil)
            #expect(p.surface == nil)
            #expect(p.hoverOpacity == 0.14)
            #expect(p.litOpacity == 0.28)
            #expect(p.subtleHoverOpacity == 0.14)
            #expect(p.sectionLabel == nil)
            #expect(p.cardBorder == nil)
        }
    }

    @Test("主题 id 与名称键一一对应（设置页圆点可寻址）")
    func idsMatchNameKeys() {
        let keyNames: [String: TextKey] = [
            "rose": .themeRose, "sage": .themeSage, "orange": .themeOrange,
            "tan": .themeTan, "blue": .themeBlue, "blueGray": .themeBlueGray,
            "tealGray": .themeTealGray,
        ]
        #expect(keyNames.count == PanelTheme.all.count)
        for theme in PanelTheme.all {
            #expect(theme.nameKey == keyNames[theme.id], "\(theme.id) 的名称键漂移")
        }
    }

    @Test("实心档对比文字：亮实心底黑字、深实心底白字")
    func solidContrastText() {
        // 深色派生的 teal 实心档 #39D0C5 偏亮 → 黑字；浅色 teal 实心档 #006A62 深 → 白字。
        #expect(PanelPalette.contrastText(on: "#39D0C5") == .black)
        #expect(PanelPalette.contrastText(on: "#006A62") == .white)
    }
}
