#!/usr/bin/env swift
//
// make-app-icon-design.swift
// 自绘 MoniSwitch 应用图标（1024×1024，Liquid Glass 风格）
//
// 图标构成：圆角 squircle 渐变底（对角渐变 + 顶部玻璃高光 + rim light 描边）
// + 显示器（屏幕壁纸渐变、红绿灯、石墨机身、支架底座）。
// 红绿灯两种摆法：
//   screen — 屏幕内左上角，像 macOS 窗口标题栏（默认）
//   bezel  — 显示器下巴（底边框）上，像实体指示灯
//
// 用法：
//   swift Support/make-app-icon-design.swift --theme blue --traffic screen \
//        --output Resources/AppIcon-source.png
//   swift Support/make-app-icon-design.swift --all   # 全部主题×摆法对比预览图
//        （预览图默认 Support/icon-previews.png，单图另存 /tmp/moniswitch-icon-variants/）
//

import AppKit
import CoreText
import Foundation

// MARK: - 主题定义

/// 渐变 stops：hex 颜色 + 位置（背景/屏幕均为对角线 左上→右下）
typealias ColorStops = [(hex: UInt32, loc: CGFloat)]

struct Theme {
    let id: String          // 命令行参数名
    let name: String        // 预览图显示名
    let bg: ColorStops      // squircle 背景
    let screen: ColorStops  // 屏幕壁纸
}

let themes: [Theme] = [
    Theme(id: "blue", name: "靛蓝",
          bg: [(0x45A6FF, 0), (0x0A55D6, 1)],
          screen: [(0x7FD4FF, 0), (0x1E7BFF, 1)]),
    Theme(id: "violet", name: "紫罗兰",
          bg: [(0xA78BFA, 0), (0x5B21B6, 1)],
          screen: [(0xC4B5FD, 0), (0x7C3AED, 1)]),
    Theme(id: "green", name: "翡翠绿",
          bg: [(0x34D399, 0), (0x047857, 1)],
          screen: [(0x6EE7B7, 0), (0x059669, 1)]),
    Theme(id: "orange", name: "日落橙",
          bg: [(0xFF9E4F, 0), (0xD9480F, 1)],
          screen: [(0xFFD9A0, 0), (0xF97316, 1)]),
    Theme(id: "graphite", name: "石墨",
          bg: [(0x4B5563, 0), (0x111827, 1)],
          screen: [(0x9EC5FF, 0), (0x2F6BFF, 1)]),
    Theme(id: "rainbow", name: "多彩",
          bg: [(0xE9EDF4, 0), (0xA9B4C4, 1)],
          screen: [(0xFF6B6B, 0), (0xFFD93D, 0.25), (0x6BCB77, 0.5),
                   (0x4D96FF, 0.75), (0x9B5DE5, 1)]),
]

// macOS 窗口红绿灯系统色
let trafficLightColors: [UInt32] = [0xFF5F57, 0xFEBC2E, 0x28C840]

enum Traffic: String { case screen, bezel }

// MARK: - 几何常量（1024 逻辑坐标，CG 坐标系 y 向上）

let S: CGFloat = 1024

// squircle：824×824 居中，圆角 ≈22.4%（macOS 图标规范），四周留 100 透明边距
let shapeRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let shapeRadius: CGFloat = 185

// 显示器机身（含边框）+ 支架，水平居中；整体内容纵向 242~780，恰好居中于 squircle
let monW: CGFloat = 640
let monH: CGFloat = 450
let monX = (S - monW) / 2
let monY: CGFloat = 330
let monR: CGFloat = 40

// 屏幕区域：四周 inset 26；bezel 摆法下巴加厚到 74 以容纳红绿灯
func screenRect(_ traffic: Traffic) -> CGRect {
    let inset: CGFloat = 26
    let chin: CGFloat = traffic == .bezel ? 74 : 26
    return CGRect(x: monX + inset, y: monY + chin,
                  width: monW - inset * 2, height: monH - inset - chin)
}

let neckRect = CGRect(x: S / 2 - 48, y: 272, width: 96, height: 58)
let baseRect = CGRect(x: S / 2 - 125, y: 242, width: 250, height: 30)

// MARK: - 绘制工具

func cg(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha)
}

func gradientOf(_ stops: ColorStops) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: stops.map { cg($0.hex) } as CFArray,
               locations: stops.map { $0.loc })!
}

/// 沿路径裁剪后填渐变。diagonal=true 为左上→右下，否则垂直上→下
func fillPathWithGradient(_ ctx: CGContext, _ path: CGPath, _ stops: ColorStops,
                          diagonal: Bool = false) {
    let box = path.boundingBoxOfPath
    var start = CGPoint(x: box.midX, y: box.maxY)
    var end = CGPoint(x: box.midX, y: box.minY)
    if diagonal {
        start = CGPoint(x: box.minX, y: box.maxY)
        end = CGPoint(x: box.maxX, y: box.minY)
    }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradientOf(stops), start: start, end: end, options: [])
    ctx.restoreGState()
}

/// 同色渐隐叠加层（玻璃高光/扫光用）。
/// 注意：ColorStops 的第二个字段是渐变位置 loc，不支持 alpha；
/// 带 alpha 的渐变必须走这里（colorsSpace=nil + 显式 alpha），否则非单调 loc 会整块刷成不透明色
func overlayAlphaFade(_ ctx: CGContext, _ path: CGPath, hex: UInt32,
                      fromAlpha: CGFloat, toAlpha: CGFloat, diagonal: Bool = true) {
    let box = path.boundingBoxOfPath
    var start = CGPoint(x: box.midX, y: box.maxY)
    var end = CGPoint(x: box.midX, y: box.minY)
    if diagonal {
        start = CGPoint(x: box.minX, y: box.maxY)
        end = CGPoint(x: box.maxX, y: box.minY)
    }
    let g = CGGradient(colorsSpace: nil,
                       colors: [cg(hex, fromAlpha), cg(hex, toAlpha)] as CFArray,
                       locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(g, start: start, end: end, options: [])
    ctx.restoreGState()
}

/// 红绿灯圆点：主体色 + 深色描边环 + 左上小高光（玻璃感）
func drawDot(_ ctx: CGContext, center: CGPoint, d: CGFloat, hex: UInt32) {
    let r = d / 2
    let rect = CGRect(x: center.x - r, y: center.y - r, width: d, height: d)
    ctx.setFillColor(cg(hex))
    ctx.fillEllipse(in: rect)
    ctx.setStrokeColor(cg(0x000000, 0.22))
    ctx.setLineWidth(max(1.5, d * 0.08))
    ctx.strokeEllipse(in: rect)
    ctx.setFillColor(cg(0xFFFFFF, 0.5))
    let hr = r * 0.28
    ctx.fillEllipse(in: CGRect(x: center.x - r * 0.35, y: center.y + r * 0.18,
                               width: hr * 2, height: hr * 2))
}

/// 纯 CGContext 文本（预览图标注用，PingFang SC）
func drawText(_ ctx: CGContext, _ text: String, _ x: CGFloat, _ y: CGFloat,
              size: CGFloat, color: CGColor, semibold: Bool = false) {
    let font = CTFontCreateWithName(
        (semibold ? "PingFangSC-Semibold" : "PingFangSC-Regular") as CFString, size, nil)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

func drawTextCentered(_ ctx: CGContext, _ text: String, centerX: CGFloat, baselineY: CGFloat,
                      size: CGFloat, color: CGColor) {
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    drawText(ctx, text, centerX - w / 2, baselineY, size: size, color: color)
}

// MARK: - 图标绘制

func renderIcon(_ theme: Theme, _ traffic: Traffic) -> CGImage? {
    guard let ctx = CGContext(
        data: nil, width: 1024, height: 1024,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let shapePath = CGPath(roundedRect: shapeRect, cornerWidth: shapeRadius,
                           cornerHeight: shapeRadius, transform: nil)

    // ---- 1. squircle 背景：对角渐变 + 玻璃高光 + 底部内影 + 中央柔光 ----
    ctx.saveGState()
    ctx.addPath(shapePath)
    ctx.clip()
    fillPathWithGradient(ctx, shapePath, theme.bg, diagonal: true)
    let box = shapeRect
    // 顶部高光（上 60% 高度内白→透明）
    let hl = CGGradient(colorsSpace: nil,
                        colors: [cg(0xFFFFFF, 0.24), cg(0xFFFFFF, 0)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: box.maxY),
                           end: CGPoint(x: 0, y: box.maxY - box.height * 0.6), options: [])
    // 底部内影（厚度感）
    let sh = CGGradient(colorsSpace: nil,
                        colors: [cg(0x000000, 0), cg(0x000000, 0.12)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(sh, start: CGPoint(x: 0, y: box.minY + box.height * 0.82),
                           end: CGPoint(x: 0, y: box.minY), options: [])
    // 显示器后方柔光
    let glow = CGGradient(colorsSpace: nil,
                          colors: [cg(0xFFFFFF, 0.13), cg(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 620), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 620), endRadius: 430,
                           options: [.drawsAfterEndLocation])
    ctx.restoreGState()

    // ---- 2. rim light 内描边 + 外缘发丝线 ----
    let rimPath = CGPath(roundedRect: shapeRect.insetBy(dx: 4, dy: 4),
                         cornerWidth: shapeRadius - 4, cornerHeight: shapeRadius - 4,
                         transform: nil)
    ctx.addPath(rimPath)
    ctx.setStrokeColor(cg(0xFFFFFF, 0.32))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.addPath(shapePath)
    ctx.setStrokeColor(cg(0x000000, 0.12))
    ctx.setLineWidth(2)
    ctx.strokePath()

    // ---- 3. 显示器 + 支架（石墨渐变，整体投影）----
    let bodyPath = CGPath(roundedRect: CGRect(x: monX, y: monY, width: monW, height: monH),
                          cornerWidth: monR, cornerHeight: monR, transform: nil)
    let neckPath = CGPath(roundedRect: neckRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
    let basePath = CGPath(roundedRect: baseRect, cornerWidth: 15, cornerHeight: 15, transform: nil)

    // 投影：先以纯色垫底统一带阴影，再叠渐变（渐变绘制不吃阴影）
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: cg(0x000000, 0.38))
    ctx.setFillColor(cg(0x20242B))
    for p in [basePath, neckPath, bodyPath] {
        ctx.addPath(p)
        ctx.fillPath()
    }
    ctx.restoreGState()

    let standStops: ColorStops = [(0x2A2F38, 0), (0x171A20, 1)]
    fillPathWithGradient(ctx, basePath, standStops)
    fillPathWithGradient(ctx, neckPath, standStops)
    fillPathWithGradient(ctx, bodyPath, [(0x3A3F47, 0), (0x20242B, 1)])

    // 机身边缘微高光
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(cg(0xFFFFFF, 0.10))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // ---- 4. 屏幕：壁纸渐变 + 玻璃斜扫光 + 内凹描边 ----
    let sr = screenRect(traffic)
    let screenPath = CGPath(roundedRect: sr, cornerWidth: 20, cornerHeight: 20, transform: nil)
    fillPathWithGradient(ctx, screenPath, theme.screen, diagonal: true)
    overlayAlphaFade(ctx, screenPath, hex: 0xFFFFFF, fromAlpha: 0.12, toAlpha: 0)
    ctx.addPath(screenPath)
    ctx.setStrokeColor(cg(0x000000, 0.45))
    ctx.setLineWidth(3)
    ctx.strokePath()

    // ---- 5. 红绿灯 ----
    if traffic == .screen {
        // 屏幕内左上角：半透明标题栏横带 + 三圆点（圆角由屏幕裁剪保证）
        let bandH: CGFloat = 66
        ctx.saveGState()
        ctx.addPath(screenPath)
        ctx.clip()
        let band = CGRect(x: sr.minX, y: sr.maxY - bandH, width: sr.width, height: bandH)
        ctx.setFillColor(cg(0x000000, 0.22))
        ctx.fill(band)
        ctx.setStrokeColor(cg(0xFFFFFF, 0.14))
        ctx.setLineWidth(1.5)
        ctx.move(to: CGPoint(x: sr.minX, y: band.minY))
        ctx.addLine(to: CGPoint(x: sr.maxX, y: band.minY))
        ctx.strokePath()
        ctx.restoreGState()
        let d: CGFloat = 26, spacing: CGFloat = 46
        let cy = sr.maxY - bandH / 2
        for (i, hex) in trafficLightColors.enumerated() {
            drawDot(ctx, center: CGPoint(x: sr.minX + 40 + CGFloat(i) * spacing, y: cy),
                    d: d, hex: hex)
        }
    } else {
        // 下巴居中三个指示灯
        let d: CGFloat = 22, spacing: CGFloat = 40
        let cy = monY + 37
        for (i, hex) in trafficLightColors.enumerated() {
            drawDot(ctx, center: CGPoint(x: S / 2 + (CGFloat(i) - 1) * spacing, y: cy),
                    d: d, hex: hex)
        }
    }

    return ctx.makeImage()
}

// MARK: - 预览图（--all）：4 行（2 摆法 × 浅/深底）× 6 主题

func buildPreview(_ outputPath: String) {
    let cols = themes.count
    let cellW: CGFloat = 248, cellH: CGFloat = 300
    let headerH: CGFloat = 52, margin: CGFloat = 40
    let rows: [(traffic: Traffic, light: Bool, title: String)] = [
        (.screen, true,  "红绿灯在屏幕内 · 浅色底"),
        (.screen, false, "红绿灯在屏幕内 · 深色底"),
        (.bezel,  true,  "红绿灯在边框下巴 · 浅色底"),
        (.bezel,  false, "红绿灯在边框下巴 · 深色底"),
    ]
    let W = Int(margin * 2 + CGFloat(cols) * cellW)
    let H = Int(margin * 2 + CGFloat(rows.count) * (headerH + cellH))

    guard let ctx = CGContext(
        data: nil, width: W, height: H,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        FileHandle.standardError.write("✗ 无法创建预览画布\n".data(using: .utf8)!)
        exit(1)
    }

    // 先渲染全部变体（顺带把单图存到 /tmp 供逐个查看）
    var cache: [String: CGImage] = [:]
    let variantDir = "/tmp/moniswitch-icon-variants"
    for t in themes {
        for p in [Traffic.screen, .bezel] {
            guard let img = renderIcon(t, p) else { continue }
            cache["\(t.id)-\(p.rawValue)"] = img
            writePNG(img, "\(variantDir)/\(t.id)-\(p.rawValue).png")
        }
    }

    // 整体底色
    ctx.setFillColor(cg(0xE2E2E5))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.interpolationQuality = .high

    for (ri, row) in rows.enumerated() {
        let stripTop = margin + CGFloat(ri) * (headerH + cellH)
        let stripH = headerH + cellH
        let stripY = CGFloat(H) - stripTop - stripH
        // 行底色条
        ctx.setFillColor(cg(row.light ? 0xF5F5F7 : 0x1D1D1F))
        ctx.fill(CGRect(x: 0, y: stripY, width: CGFloat(W), height: stripH))
        // 行标题
        drawText(ctx, row.title, margin, CGFloat(H) - stripTop - 38, size: 30,
                 color: cg(row.light ? 0x3A3A3E : 0xE8E8EC), semibold: true)
        // 每主题一格：图标 + 名称
        let iconSize: CGFloat = 216
        for (ci, t) in themes.enumerated() {
            let cx = margin + CGFloat(ci) * cellW + cellW / 2
            let iconTop = stripTop + headerH + 14
            if let img = cache["\(t.id)-\(row.traffic.rawValue)"] {
                ctx.draw(img, in: CGRect(x: cx - iconSize / 2,
                                         y: CGFloat(H) - iconTop - iconSize,
                                         width: iconSize, height: iconSize))
            }
            drawTextCentered(ctx, t.name, centerX: cx,
                             baselineY: CGFloat(H) - iconTop - iconSize - 38,
                             size: 28, color: cg(row.light ? 0x48484C : 0xC9C9CE))
        }
    }

    guard let out = ctx.makeImage() else {
        FileHandle.standardError.write("✗ 预览图 makeImage 失败\n".data(using: .utf8)!)
        exit(1)
    }
    writePNG(out, outputPath)
    print("✓ 预览图: \(outputPath)  \(W)×\(H)")
    print("  单图目录: \(variantDir)/<主题>-<screen|bezel>.png")
}

// MARK: - PNG 导出

func writePNG(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("✗ PNG 编码失败: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let dir = (path as NSString).deletingLastPathComponent
    if !dir.isEmpty {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

// MARK: - 参数与入口

var themeID = "blue"
var trafficRaw = "screen"
var outputPath: String?
var allMode = false

let args = CommandLine.arguments.dropFirst()
var iter = args.makeIterator()
while let a = iter.next() {
    switch a {
    case "--theme": themeID = iter.next() ?? themeID
    case "--traffic": trafficRaw = iter.next() ?? trafficRaw
    case "--output": outputPath = iter.next()
    case "--all": allMode = true
    case "-h", "--help":
        print("用法: swift Support/make-app-icon-design.swift [--theme \(themes.map { $0.id }.joined(separator: "|"))] [--traffic screen|bezel] [--output PATH] [--all]")
        exit(0)
    default:
        FileHandle.standardError.write("未知参数: \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

if allMode {
    buildPreview(outputPath ?? "Support/icon-previews.png")
} else {
    guard let theme = themes.first(where: { $0.id == themeID }) else {
        FileHandle.standardError.write(
            "✗ 未知主题: \(themeID)（可选: \(themes.map { $0.id }.joined(separator: ", "))）\n"
                .data(using: .utf8)!)
        exit(1)
    }
    guard let traffic = Traffic(rawValue: trafficRaw) else {
        FileHandle.standardError.write("✗ 未知摆法: \(trafficRaw)（可选: screen, bezel）\n"
            .data(using: .utf8)!)
        exit(1)
    }
    guard let img = renderIcon(theme, traffic) else {
        FileHandle.standardError.write("✗ 图标渲染失败\n".data(using: .utf8)!)
        exit(1)
    }
    let out = outputPath ?? "Resources/AppIcon-source.png"
    writePNG(img, out)
    print("✓ 输出: \(out)  1024×1024")
    print("  主题: \(theme.name) (\(theme.id))  红绿灯: \(traffic == .screen ? "屏内标题栏" : "边框下巴")")
}
