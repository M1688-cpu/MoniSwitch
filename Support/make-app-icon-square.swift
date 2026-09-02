#!/usr/bin/env swift
//
// make-app-icon-square.swift
// 把任意尺寸的源图规整为 1024×1024 正方形，用作 macOS AppIcon 源图
//
// 策略（比简单 sips resample 更自然，避免纯色边条带感）：
//   1. 从源图四个边缘采样平均色，作为画布主背景
//   2. 新建 1024×1024 画布，填该主背景色
//   3. 源图按比例缩放（短边充满，长边不裁剪 → 保持完整可见），居中合成
//      - 650×557 这类近正方形：短边 557 → 缩放到 1024 高，宽 ≈ 1197 → 超出，
//        改取等比 fit（让宽=1024，高按比例），上下留主背景色填充
//
// 注：上面策略 3 实测对宽图会裁掉左右，不符合「保持完整可见」，故统一用 **aspect-fit**：
//     缩放使较长一边=1024，居中放在 1024×1024 画布上，上下/左右留采样色填充。
//
// 用法：swift Support/make-app-icon-square.swift --source PATH --output PATH
//

import AppKit
import Foundation

let OUT = 1024

var sourcePath = "/tmp/moniswitch-ref/ref2-icon.png"
var outputPath = "Resources/AppIcon-source.png"

let args = CommandLine.arguments.dropFirst()
var iter = args.makeIterator()
while let a = iter.next() {
    switch a {
    case "--source": sourcePath = iter.next() ?? sourcePath
    case "--output": outputPath = iter.next() ?? outputPath
    default:
        FileHandle.standardError.write("未知参数: \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

guard let srcData = FileManager.default.contents(atPath: sourcePath),
      let srcImage = NSImage(data: srcData) else {
    FileHandle.standardError.write("✗ 无法载入源图: \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

let srcW = srcImage.size.width
let srcH = srcImage.size.height
print("源图: \(sourcePath)  \(Int(srcW))×\(Int(srcH))")

// MARK: - 采样背景色
// 源图四周常有透明边（alpha=0），直接取边缘会拿到全 0 → 黑色填充。
// 这里取「中心区域」(中心 60% × 60% 的环形外缘带) 的不透明像素平均色作为画布背景。
func averageEdgeColor(_ img: NSImage) -> NSColor {
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return NSColor(white: 0.97, alpha: 1)
    }
    let w = cg.width
    let h = cg.height
    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return NSColor(white: 0.97, alpha: 1) }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let buf = ctx.data?.assumingMemoryBound(to: UInt8.self) else {
        return NSColor(white: 0.97, alpha: 1)
    }

    // 采样中心 60% 区域的四条边（避开外层透明环）
    let x0 = Int(Double(w) * 0.20), x1 = Int(Double(w) * 0.80)
    let y0 = Int(Double(h) * 0.20), y1 = Int(Double(h) * 0.80)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, count: CGFloat = 0
    func sample(_ x: Int, _ y: Int) {
        let off = (y * w + x) * 4
        // 跳过近透明像素
        if buf[off + 3] < 128 { return }
        r += CGFloat(buf[off])     / 255.0
        g += CGFloat(buf[off + 1]) / 255.0
        b += CGFloat(buf[off + 2]) / 255.0
        count += 1
    }
    let step = Swift.max(1, Swift.min(w, h) / 24)
    var x = x0
    while x < x1 { sample(x, y0); sample(x, y1 - 1); x += step }
    var y = y0
    while y < y1 { sample(x0, y); sample(x1 - 1, y); y += step }

    if count == 0 { return NSColor(white: 0.97, alpha: 1) }
    return NSColor(srgbRed: r/count, green: g/count, blue: b/count, alpha: 1)
}

let bgColor = averageEdgeColor(srcImage)

// MARK: - 建画布

guard let ctx = CGContext(
    data: nil, width: OUT, height: OUT,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("✗ 无法创建画布\n".data(using: .utf8)!)
    exit(1)
}

// 填背景
ctx.setFillColor(bgColor.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: OUT, height: OUT))

// aspect-fit 缩放源图
let scale = min(CGFloat(OUT) / srcW, CGFloat(OUT) / srcH)
let drawW = srcW * scale
let drawH = srcH * scale
let drawX = (CGFloat(OUT) - drawW) / 2
let drawY = (CGFloat(OUT) - drawH) / 2

ctx.interpolationQuality = .high
guard let srcCG = srcImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("✗ 源图 cgImage 失败\n".data(using: .utf8)!)
    exit(1)
}
ctx.draw(srcCG, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))

// MARK: - 导出

guard let outCG = ctx.makeImage() else {
    FileHandle.standardError.write("✗ makeImage 失败\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: outCG)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("✗ PNG 编码失败\n".data(using: .utf8)!)
    exit(1)
}
let outDir = (outputPath as NSString).deletingLastPathComponent
if !outDir.isEmpty {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("✓ 输出: \(outputPath)  \(OUT)×\(OUT)")
print("  背景采样色: \(bgColor)")
print("  源图缩放: \(Int(drawW))×\(Int(drawH)) 居中 @ (\(Int(drawX)),\(Int(drawY)))")
