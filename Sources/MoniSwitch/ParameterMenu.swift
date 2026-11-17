import AppKit
import SwiftUI

struct ParameterMenuOption {
    let id: String
    let title: String
    var isSelected: Bool
    var isEnabled: Bool
    let children: [ParameterMenuOption]
    let isSeparator: Bool
    let action: (() -> Void)?

    init(id: String? = nil, title: String, isSelected: Bool = false, isEnabled: Bool = true,
         children: [ParameterMenuOption] = [], isSeparator: Bool = false, action: (() -> Void)? = nil) {
        self.id = id ?? title
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.children = children
        self.isSeparator = isSeparator
        self.action = action
    }

    static var separator: Self { .init(title: "", isSeparator: true) }

    struct Signature: Equatable {
        let id: String
        let title: String
        let selected: Bool
        let enabled: Bool
        let separator: Bool
        let children: [Signature]
    }

    var signature: Signature {
        .init(id: id, title: title, selected: isSelected, enabled: isEnabled,
              separator: isSeparator, children: children.map(\.signature))
    }
}

/// 菜单及子菜单共用动作表；跟踪结束后才执行选中的显示器操作。
@MainActor
final class ParameterMenuController: NSObject {
    let menu: NSMenu
    private var actions: [() -> Void] = []
    private var selectedIndex: Int?
    private var isCancelled = false

    init(title: String, options: [ParameterMenuOption]) {
        menu = NSMenu(title: title)
        super.init()
        populate(menu, options: options)
    }

    private func populate(_ menu: NSMenu, options: [ParameterMenuOption]) {
        menu.autoenablesItems = false
        for option in options {
            if option.isSeparator { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: option.title, action: nil, keyEquivalent: "")
            item.state = option.isSelected ? .on : .off
            item.isEnabled = option.isEnabled
            if !option.children.isEmpty {
                let submenu = NSMenu(title: option.title)
                populate(submenu, options: option.children)
                item.submenu = submenu
            } else if let action = option.action {
                item.target = self
                item.action = #selector(selectOption(_:))
                item.tag = actions.count
                actions.append(action)
            }
            menu.addItem(item)
        }
    }

    @objc private func selectOption(_ sender: NSMenuItem) {
        guard !isCancelled, sender.isEnabled, actions.indices.contains(sender.tag) else { return }
        selectedIndex = sender.tag
    }

    func cancel() {
        isCancelled = true
        selectedIndex = nil
        menu.cancelTracking()
    }

    func performSelection() {
        guard !isCancelled, let index = selectedIndex else { return }
        selectedIndex = nil
        actions[index]()
    }
}

/// 保留 NSPopUpButton 原生绘制和焦点；跟踪由现有面板生命周期统一管理。
final class ParameterPopUpButton: NSPopUpButton {
    var openMenu: ((NSButton) -> Void)?

    override func mouseDown(with event: NSEvent) { performClick(nil) }
    override func performClick(_ sender: Any?) {
        guard isEnabled else { return }
        openMenu?(self)
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        performClick(nil)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 76, 125, 126].contains(Int(event.keyCode)) {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

struct ParameterMenuTrigger: NSViewRepresentable {
    enum Presentation { case selection, command }
    let title: String
    let currentValue: String
    let options: [ParameterMenuOption]
    var presentation: Presentation = .selection
    var contextID = ""
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ParameterPopUpButton {
        let button = ParameterPopUpButton(frame: .zero, pullsDown: presentation == .command)
        button.font = .systemFont(ofSize: 13)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (button.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        button.openMenu = { [weak coordinator = context.coordinator] in coordinator?.openMenu($0) }
        return button
    }

    func updateNSView(_ button: ParameterPopUpButton, context: Context) {
        button.pullsDown = presentation == .command
        button.isEnabled = isEnabled && options.filter { !$0.isSeparator }.count >= (presentation == .command ? 1 : 2)
        context.coordinator.update(title: title, currentValue: currentValue, options: options,
                                   isEnabled: button.isEnabled, contextID: contextID)
        // 这里只承载按钮标题；真实选项在点击时创建，避免 AppKit 提前执行动作。
        if button.title != currentValue || button.numberOfItems == 0 {
            button.removeAllItems()
            button.addItem(withTitle: currentValue)
        }
        button.setAccessibilityLabel(title)
        button.setAccessibilityValue(currentValue)
        button.toolTip = "\(title): \(currentValue)"
    }

    static func dismantleNSView(_ button: ParameterPopUpButton, coordinator: Coordinator) {
        coordinator.cancel()
        button.openMenu = nil
    }

    @MainActor final class Coordinator: NSObject {
        private var title = ""
        private var currentValue = ""
        private var contextID = ""
        private var options: [ParameterMenuOption] = []
        private var activeController: ParameterMenuController?

        func update(title: String, currentValue: String, options: [ParameterMenuOption],
                    isEnabled: Bool, contextID: String) {
            if !isEnabled || self.title != title || self.currentValue != currentValue
                || self.contextID != contextID || self.options.map(\.signature) != options.map(\.signature) {
                cancel()
            }
            self.title = title
            self.currentValue = currentValue
            self.contextID = contextID
            self.options = options
        }

        func cancel() { activeController?.cancel() }

        func prepareMenu() -> ParameterMenuController {
            cancel()
            let controller = ParameterMenuController(title: title, options: options)
            activeController = controller
            return controller
        }

        func openMenu(_ sender: NSButton) {
            guard sender.isEnabled, sender.window != nil else { return }
            let controller = prepareMenu()
            defer { activeController = nil }
            controller.menu.minimumWidth = sender.bounds.width
            PanelController.shared.trackMenu(controller.menu) {
                controller.menu.popUp(positioning: controller.menu.items.first { $0.state == .on },
                                      at: NSPoint(x: 0, y: sender.bounds.maxY), in: sender)
            }
            guard sender.isEnabled, sender.window != nil, PanelController.shared.isShown else { return }
            controller.performSelection()
        }
    }
}
