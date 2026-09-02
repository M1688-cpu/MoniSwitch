#!/usr/bin/env swift
//
// make-dmg-preview.swift
// 合成一张 DMG 安装窗口预览图，用作 README 展示。
// 内容与真实 Finder 打开 DMG 看到的一致：背景 + MoniSwitch.app 图标(左) + Applications 图标(右)。
// 图标位置/尺寸与 build-app.sh osascript 段一致：{140,180} / {480,180} / 128pt。
//
// 注：这是「预览图」——真实 DMG 里的 .DS_Store 已独立写入同样的布局（见 build-app.sh），
// 这里只是为 README 渲染一张可读的 png，因为沙箱里 screencapture 不可靠。
//
// 用法：swift Support/make-dmg-preview.swift
//

import AppKit
import Foundation

let PROJECT_DIR = FileManager.default.currentDirectoryPath
let BG_PATH = "\(PROJECT_DIR)/Resources/dmg-background.png"
let APP_ICON_PATH = "\(PROJECT_DIR)/Resources/AppIcon.icns"
let OUT_PATH = "\(PROJECT_DIR)/screenshots/dmg-install.png"

// 逻辑尺寸（与 Finder 窗口一致）
let LOGICAL_W = 660, LOGICAL_H = 400
let SCALE = 2  // @2x，输出 1320×800

// MARK: - 载入

guard let bgData = FileManager.default.contents(atPath: BG_PATH),
      let bg = NSImage(data: bgData) else {
    FileHandle.standardError.write("✗ 缺少 \(BG_PATH)，请先跑 Support/make-dmg-background.swift\n".data(using: .utf8)!)
    exit(1)
}
guard let appIcon = NSImage(contentsOfFile: APP_ICON_PATH) else {
    FileHandle.standardError.write("✗ 缺少 \(APP_ICON_PATH)\n".data(using: .utf8)!)
    exit(1)
}

// Applications 文件夹图标：直接取真实 /Applications 的系统图标（最稳，永远存在）
let appsIcon = NSWorkspace.shared.icon(forFile: "/Applications")
appsIcon.size = NSSize(width: 128, height: 128)

// MARK: - 画布

let OUT_W = LOGICAL_W * SCALE, OUT_H = LOGICAL_H * SCALE
guard let ctx = CGContext(
    data: nil, width: OUT_W, height: OUT_H,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

// 背景（CG 原点左下，Finder 显示时左上对齐 → 整图直接铺满即可，因为背景已含箭头）
guard let bgCG = bg.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(1) }
ctx.draw(bgCG, in: CGRect(x: 0, y: 0, width: OUT_W, height: OUT_H))

// 画图标：Finder 的 icon view 坐标原点在窗口左上，position 是图标中心点。
// 这里 CG 坐标原点在左下，需 y = OUT_H - logicalY*2 - iconSize
func drawIcon(_ img: NSImage, atLogicalCenter cx: Int, _ cy: Int, size pt: Int) {
    img.size = NSSize(width: pt, height: pt)
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let s = pt * SCALE
    // CG: left = (cx - pt/2)*2 ; bottom = OUT_H - (cy + pt/2)*2
    let left = (cx - pt/2) * SCALE
    let bottom = OUT_H - (cy + pt/2) * SCALE
    ctx.draw(cg, in: CGRect(x: left, y: bottom, width: s, height: s))
}

// MoniSwitch.app 图标在左 {140,180}
// 注意：app 图标在 Finder 里显示时系统会自动套 squircle mask，但预览图里 .icns 本身已是圆角方形，直接画即可
drawIcon(appIcon, atLogicalCenter: 140, 180, size: 128)
// Applications 文件夹图标在右 {480,180}
drawIcon(appsIcon, atLogicalCenter: 480, 180, size: 128)

// MARK: - 输出

guard let outCG = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: outCG)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let outDir = (OUT_PATH as NSString).deletingLastPathComponent
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
try png.write(to: URL(fileURLWithPath: OUT_PATH))
print("✓ 预览图: \(OUT_PATH)  \(OUT_W)×\(OUT_H)")
