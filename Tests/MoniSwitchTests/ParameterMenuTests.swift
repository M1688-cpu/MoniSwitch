import AppKit
import SwiftUI
import Testing
@testable import MoniSwitch

struct ParameterMenuTests {
    @Test @MainActor
    func replacingTheTargetInvalidatesAQueuedActionWithIdenticalLabels() {
        _ = NSApplication.shared
        var changes = 0
        let coordinator = ParameterMenuTrigger.Coordinator()
        let options: [ParameterMenuOption] = [.init(title: "Apply") { changes += 1 }]
        coordinator.update(title: "Display", currentValue: "Display", options: options,
                           isEnabled: true, contextID: "screen-A")
        let menu = coordinator.prepareMenu()
        menu.menu.performActionForItem(at: 0)
        coordinator.update(title: "Display", currentValue: "Display", options: options,
                           isEnabled: true, contextID: "screen-B")
        menu.performSelection()
        #expect(changes == 0)
    }

    @Test @MainActor
    func commandTriggerAllowsOneItemAndAccessibilityPressRespectsDisabledState() throws {
        let host = NSHostingView(rootView: ParameterMenuTrigger(title: "Presets", currentValue: "Manage…",
            options: [.init(title: "Manage…", action: {})], presentation: .command).frame(width: 240, height: 26))
        let window = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 26))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func find(in view: NSView) -> ParameterPopUpButton? {
            (view as? ParameterPopUpButton) ?? view.subviews.lazy.compactMap { find(in: $0) }.first
        }
        let button = try #require(find(in: host))
        #expect(button.isEnabled)
        #expect(button.pullsDown)
        var opens = 0
        button.openMenu = { _ in opens += 1 }
        #expect(button.accessibilityPerformPress())
        #expect(opens == 1)
        button.isEnabled = false
        #expect(!button.accessibilityPerformPress())
        button.performClick(nil)
        #expect(opens == 1)
    }

    @Test @MainActor
    func submenuSelectionIsDeferredAndDisabledCommandsCannotRun() throws {
        _ = NSApplication.shared
        var changes = [Int]()
        let controller = ParameterMenuController(title: "Options", options: [
            .init(title: "Refresh", children: [
                .init(title: "60 Hz", isSelected: true) { changes.append(60) },
                .init(title: "120 Hz", isEnabled: false) { changes.append(120) }
            ]),
            .separator,
            .init(title: "Main", isEnabled: false) { changes.append(1) }
        ])
        let submenu = try #require(controller.menu.items.first?.submenu)
        #expect(controller.menu.items[1].isSeparatorItem)
        #expect(!submenu.items[1].isEnabled)
        submenu.performActionForItem(at: 1)
        controller.performSelection()
        #expect(changes.isEmpty)
        submenu.performActionForItem(at: 0)
        #expect(changes.isEmpty)
        controller.performSelection()
        #expect(changes == [60])
    }

    @Test @MainActor
    func equalLabelsWithDifferentTargetsHaveDifferentSignatures() {
        let first = ParameterMenuOption(id: "screen-A", title: "Display", action: {})
        let second = ParameterMenuOption(id: "screen-B", title: "Display", action: {})
        #expect(first.signature != second.signature)
        let group = ParameterMenuOption(title: "Targets", children: [first])
        let replacement = ParameterMenuOption(title: "Targets", children: [second])
        #expect(group.signature != replacement.signature)
    }

    @Test @MainActor
    func nativeMenuKeepsEveryOptionAndTheCurrentCheckmark() {
        let controller = ParameterMenuController(title: "Resolution", options: (0..<80).map { index in
            ParameterMenuOption(title: "Mode \(index)", isSelected: index == 47, action: {})
        })
        #expect(controller.menu.numberOfItems == 80)
        #expect(controller.menu.items.allSatisfy { $0.isEnabled })
        #expect(controller.menu.items[47].state == .on)
        #expect(controller.menu.items.filter { $0.state == .on }.count == 1)
        #expect(controller.menu.items.last?.title == "Mode 79")
        #expect(controller.menu.items.allSatisfy { $0.view == nil })
    }

    @Test @MainActor
    func selectionIsDeferredUntilTrackingEndsAndRunsOnlyOnce() {
        // NSMenu 通过 NSApplication 分发 target/action；测试进程也需建立应用对象。
        _ = NSApplication.shared
        var chosen = [Int]()
        let controller = ParameterMenuController(title: "Refresh rate", options: [
            .init(title: "60 Hz", isSelected: false) { chosen.append(60) },
            .init(title: "120 Hz", isSelected: true) { chosen.append(120) }
        ])
        controller.menu.performActionForItem(at: 0)
        #expect(chosen.isEmpty)
        controller.performSelection()
        controller.performSelection()
        #expect(chosen == [60])
    }

    @Test @MainActor
    func invalidatedMenuDiscardsAnAlreadyQueuedSelection() {
        _ = NSApplication.shared
        var changes = 0
        let controller = ParameterMenuController(title: "Position", options: [
            .init(title: "Left", isSelected: true) { changes += 1 }
        ])
        controller.menu.performActionForItem(at: 0)
        controller.cancel()
        controller.performSelection()
        #expect(changes == 0)
    }

    @Test @MainActor
    func busyStateReachesTheNativeTrigger() throws {
        let root = ParameterMenuTrigger(title: "Refresh rate", currentValue: "60 Hz", options: [
            .init(title: "60 Hz", isSelected: true, action: {}),
            .init(title: "120 Hz", isSelected: false, action: {})
        ]).disabled(true).frame(width: 300, height: 38)
        let host = NSHostingView(rootView: root)
        let window = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 38))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func buttons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
        }
        let button = try #require(buttons(in: host).first)
        #expect(!button.isEnabled)
        #expect(button.accessibilityLabel() == "Refresh rate")
        #expect(button.accessibilityValue() as? String == "60 Hz")
    }

    @Test @MainActor
    func cancelledMenuDoesNotChangeDisplaySettings() {
        var changes = 0
        let controller = ParameterMenuController(title: "Position", options: [
            .init(title: "Left", isSelected: true) { changes += 1 }
        ])
        controller.performSelection()
        #expect(changes == 0)
    }
}
