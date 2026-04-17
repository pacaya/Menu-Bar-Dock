//
//  ArrowMenuBarItem.swift
//  MenuBarDock
//

import Cocoa

protocol ArrowMenuBarItemDelegate: AnyObject {
    func arrowDidToggle()
    func arrowDidOpenPreferences()
    func arrowDidRequestQuit()
}

class ArrowMenuBarItem {
    private(set) var statusItem: NSStatusItem
    weak var delegate: ArrowMenuBarItemDelegate?

    var isExpanded: Bool = false {
        didSet { if oldValue != isExpanded { updateIcon() } }
    }
    var sideToShowRunningApps: SideToShowRunningApps = .right {
        didSet { if oldValue != sideToShowRunningApps { updateIcon() } }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setupButton()
        updateIcon()
    }

    private func setupButton() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateIcon() {
        // Chevron points into the app cluster: right-side cluster → point right when collapsed
        let symbolName: String
        switch sideToShowRunningApps {
        case .right:
            symbolName = isExpanded ? "chevron.left" : "chevron.right"
        case .left:
            symbolName = isExpanded ? "chevron.right" : "chevron.left"
        }
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.isTemplate = true
            statusItem.button?.image = image
        }
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            delegate?.arrowDidToggle()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(
            title: "\(Constants.App.name) Preferences\u{2026}",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        let quitItem = NSMenuItem(
            title: "Quit \(Constants.App.name)",
            action: #selector(quit),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.popUpMenu(menu)
    }

    @objc private func openPreferences() {
        delegate?.arrowDidOpenPreferences()
    }

    @objc private func quit() {
        delegate?.arrowDidRequestQuit()
    }
}
