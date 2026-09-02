#!/usr/bin/env swift
//
// make-dmg-background.swift
// 生成 DMG 安装包背景图（1320×800 @2x，对应 Finder 窗口 660×400 逻辑点）
//
// 做法：载入波浪参考图 → 居中裁取中部 33:20 比例 → 缩放到 1320×800
//       → 在 {230→440, y≈195} 绘制半透明白曲线箭头 + 柔影（y 与图标中心对齐）
//       → 导出 Resources/dmg-background.png
//
// 纯 CoreGraphics/AppKit，零第三方依赖。改背景图改 --source，改箭头改 drawArrow()。
//
// 用法：swift Support/make-dmg-background.swift [--source PATH] [--output PATH]
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - 参数解析

var sourcePath = "/tmp/moniswitch-ref/ref1-wave.png"
var outputPath = "Resources/dmg-background.png"

let args = CommandLine.arguments.dropFirst()
var iter = args.makeIterator()
while let a = iter.next() {
    switch a {
    case "--source":
        sourcePath = iter.next() ?? sourcePath
    case "--output":
        outputPath = iter.next() ?? outputPath
    case "-h", "--help":
        print("用法: swift Support/make-dmg-background.swift [--source PATH] [--output PATH]")
        print("  --source  波浪背景源图（默认 /tmp/moniswitch-ref/ref1-wave.png）")
        print("  --output  输出路径（默认 Resources/dmg-background.png）")
        exit(0)
    default:
        FileHandle.standardError.write("未知参数: \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

// MARK: - 常量

let OUT_W = 1320          // 输出宽度 @2x
let OUT_H = 800           // 输出高度 @2x（对应 660×400 逻辑点）
let CROP_RATIO = 33.0 / 20.0  // 33:20 裁剪比例（≈窗口比例）

// MARK: - 载入源图

guard let srcData = FileManager.default.contents(atPath: sourcePath),
      let srcImage = NSImage(data: srcData) else {
    FileHandle.standardError.write("✗ 无法载入源图: \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}
let srcW = Int(srcImage.size.width.rounded())
let srcH = Int(srcImage.size.height.rounded())
print("源图: \(sourcePath)  \(srcW)×\(srcH)")

// MARK: - 居中裁取 33:20 中部

// 目标：保持宽度方向充满，高度按比例裁短（源是正方形 1024×1024，裁成 1024×620 左右）
let cropH = Int((Double(srcW) / CROP_RATIO).rounded())
let cropY = max(0, (srcH - cropH) / 2)            // 垂直居中
let cropRect = CGRect(x: 0, y: cropY, width: srcW, height: cropH)
print("裁取: \(Int(cropRect.width.rounded()))×\(Int(cropRect.height.rounded())) @ y=\(cropY)")

guard let croppedCG = srcImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?
    .cropping(to: cropRect) else {
    FileHandle.standardError.write("✗ 裁剪失败\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - 建位图上下文

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: OUT_W,
    height: OUT_H,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("✗ 无法创建位图上下文\n".data(using: .utf8)!)
    exit(1)
}

// CG 坐标系原点在左下角，与 Finder 背景显示无冲突（背景图按整体铺满）

// MARK: - 绘制背景（缩放铺满）

ctx.interpolationQuality = .high
ctx.draw(croppedCG, in: CGRect(x: 0, y: 0, width: OUT_W, height: OUT_H))

// MARK: - 绘制箭头（.app → Applications）
// 逻辑坐标 {230,250} → {440,250}（Finder 位置），换算 @2x：×2
// 这里 y 用 CG 坐标（原点左下），逻辑 y=250 对应 CG y = OUT_H - 2*250 = 300

// 箭头 y 与图标中心(y=180)对齐，略下移避开图标主体
drawArrow(ctx: ctx,
          from: CGPoint(x: 230 * 2, y: OUT_H - 195 * 2),
          to:   CGPoint(x: 440 * 2, y: OUT_H - 195 * 2))

// MARK: - 导出 PNG

guard let outImage = ctx.makeImage() else {
    FileHandle.standardError.write("✗ makeImage 失败\n".data(using: .utf8)!)
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: outImage)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("✗ PNG 编码失败\n".data(using: .utf8)!)
    exit(1)
}

// 确保输出目录存在
let outDir = (outputPath as NSString).deletingLastPathComponent
if !outDir.isEmpty {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("✓ 输出: \(outputPath)  \(OUT_W)×\(OUT_H)")

// MARK: - 箭头绘制

/// 画一条带柔影的水平曲线箭头：起点左、终点右，中间略上拱
func drawArrow(ctx: CGContext, from start: CGPoint, to end: CGPoint) {
    ctx.saveGState()

    // 柔影
    ctx.setShadow(offset: CGSize(width: 0, height: -3),
                  blur: 6,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))

    // 箭头描边：半透明白
    let stroke = CGColor(red: 1, green: 1, blue: 1, alpha: 0.92)
    ctx.setStrokeColor(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(7)

    // 主干：二次贝塞尔，控制点在两端中点上方一点点（轻微上拱）
    let mid = CGPoint(x: (start.x + end.x) / 2,
                      y: (start.y + end.y) / 2 + 18)
    ctx.move(to: start)
    ctx.addQuadCurve(to: end, control: mid)
    ctx.strokePath()

    // 箭头头部：在 end 处画一个 V 形（朝右）
    // 关掉阴影画头部，避免重影
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let headLen: CGFloat = 20
    let headAngle: CGFloat = .pi / 6   // 30°
    // 主干在 end 处的切线方向：end - control（归一化）
    let tangent = unit(end - mid)
    let back = CGPoint(x: end.x - tangent.x * headLen,
                       y: end.y - tangent.y * headLen)
    // 上下两条边：绕 end 反向 ±headAngle
    ctx.move(to: end)
    ctx.addLine(to: rotate(point: back, around: end, by: headAngle))
    ctx.move(to: end)
    ctx.addLine(to: rotate(point: back, around: end, by: -headAngle))
    ctx.strokePath()

    ctx.restoreGState()
}

// MARK: - 几何小工具

func unit(_ p: CGPoint) -> CGPoint {
    let len = sqrt(p.x * p.x + p.y * p.y)
    return len == 0 ? .zero : CGPoint(x: p.x / len, y: p.y / len)
}

func rotate(point p: CGPoint, around c: CGPoint, by angle: CGFloat) -> CGPoint {
    let dx = p.x - c.x
    let dy = p.y - c.y
    return CGPoint(x: c.x + dx * cos(angle) - dy * sin(angle),
                   y: c.y + dx * sin(angle) + dy * cos(angle))
}

// CGPoint 加减（Swift 没有，自己补）
func +(a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
func -(a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
