import AppKit
import Testing
@testable import MoniSwitch

struct PanelPresentationTests {
    @Test @MainActor
    func nativeGlassKeepsActiveAppearanceWithoutKeyboardFocus() throws {
        _ = NSApplication.shared
        let panel = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 404, height: 1000))
        // Liquid Glass 从 AppKit 窗口读取此状态，独立于 SwiftUI.appearsActive。
        // 不把窗口显示为 key：背景/原生菜单跟踪导致的焦点变化也应保持玻璃。
        #expect(!panel.isKeyWindow)
        #expect(!panel.isMainWindow)
        let selector = NSSelectorFromString("_hasActiveAppearance")
        #expect(panel.responds(to: selector))
        let implementation = try #require(panel.method(for: selector))
        let hasActiveAppearance = unsafeBitCast(
            implementation, to: (@convention(c) (AnyObject, Selector) -> Bool).self
        )
        #expect(hasActiveAppearance(panel, selector))
    }

    @Test @MainActor
    func panelMovesToTheDesktopWhereItIsOpened() {
        let panel = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 404, height: 1000))
        #expect(panel.collectionBehavior.contains(.moveToActiveSpace))
        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.animationBehavior == .none)
    }

    @Test
    func clickOnAnotherDesktopOpensInsteadOfClosingTheOldPanel() {
        #expect(!PanelWindow.shouldCloseOnToggle(isVisible: true, isOnActiveSpace: false))
        #expect(!PanelWindow.shouldCloseOnToggle(isVisible: false, isOnActiveSpace: false))
        #expect(!PanelWindow.shouldCloseOnToggle(isVisible: false, isOnActiveSpace: true))
        #expect(PanelWindow.shouldCloseOnToggle(isVisible: true, isOnActiveSpace: true))
    }
}
