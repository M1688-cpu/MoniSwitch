import AppKit
import SwiftUI
import Testing
@testable import MoniSwitch

struct PanelGlassTests {
    @Test @MainActor
    func panelKeepsActiveAppearanceWhenItsHostIsInactive() throws {
        _ = NSApplication.shared
        let root = PanelGlassGroup {
            AppearanceProbe()
        }
        .environment(\.appearsActive, false)
        .disabled(true)
        .frame(width: 100, height: 100)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()

        let probe = try #require(findProbe(in: host))
        #expect(probe.appearsActive)
        // 固定活动外观不能把操作期间禁用的控件重新启用。
        #expect(!probe.isEnabled)
    }
}

private struct AppearanceProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> AppearanceProbeView {
        AppearanceProbeView()
    }

    func updateNSView(_ view: AppearanceProbeView, context: Context) {
        view.appearsActive = context.environment.appearsActive
        view.isEnabled = context.environment.isEnabled
    }
}

private final class AppearanceProbeView: NSView {
    var appearsActive = false
    var isEnabled = true
}

@MainActor
private func findProbe(in view: NSView) -> AppearanceProbeView? {
    if let probe = view as? AppearanceProbeView { return probe }
    return view.subviews.lazy.compactMap { findProbe(in: $0) }.first
}
