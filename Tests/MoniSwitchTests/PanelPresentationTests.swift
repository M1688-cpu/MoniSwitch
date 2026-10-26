import AppKit
import SwiftUI
import Testing
@testable import MoniSwitch

struct PanelPresentationTests {
    @Test @MainActor
    func openingKeepsHostingTopFixed() throws {
        let hosting = NSHostingView(rootView: Color.clear.frame(width: 404, height: 1000))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.wantsLayer = true
        hosting.frame = NSRect(x: 0, y: 0, width: 404, height: 1000)
        PanelController.configurePresentationAnchor(for: hosting)
        let layer = try #require(hosting.layer)

        // 真实 NSHostingView 的翻转坐标曾让 (0.5,1) 错锚到底部。
        for scale in [0.96, 0.98, 1.0] {
            layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            #expect(abs(layer.frame.minY) < 0.001)
            #expect(abs(layer.frame.midX - 202) < 0.001)
        }
    }

    @Test @MainActor
    func unflippedHostKeepsVisualTopFixed() throws {
        let hosting = NSView(frame: NSRect(x: 0, y: 0, width: 404, height: 1000))
        hosting.wantsLayer = true
        PanelController.configurePresentationAnchor(for: hosting)
        let layer = try #require(hosting.layer)
        layer.setAffineTransform(CGAffineTransform(scaleX: 0.96, y: 0.96))
        #expect(abs(layer.frame.maxY - 1000) < 0.001)
        #expect(abs(layer.frame.midX - 202) < 0.001)
    }
}
