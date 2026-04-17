//
//  MenuBarItem.swift
//  Menu Bar Dock
//
//  Created by Ethan Sarif-Kattan on 11/04/2021.
//  Copyright © 2021 Ethan Sarif-Kattan. All rights reserved.
//

import Cocoa

protocol MenuBarItemDataSource: AnyObject {
	func appOpeningMethod(for app: OpenableApp) -> AppOpeningMethod?
    var rightClickByDefault: Bool { get }
}

protocol MenuBarItemDelegate: AnyObject {
	func didSetAppOpeningMethod(_ method: AppOpeningMethod?, _ app: OpenableApp)
}

class MenuBarItem {
	private(set) var statusItem: NSStatusItem
	private(set) var app: OpenableApp?
	private var currentIconSize: CGFloat = 0

	public var position: CGFloat {
		return statusItem.button!.superview!.window!.frame.minX
	}

	public weak var userPrefsDataSource: MenuBarItemDataSource!
	public weak var delegate: MenuBarItemDelegate?

	init(
		statusItem: NSStatusItem,
        userPrefsDataSource: MenuBarItemDataSource
 	) {
		self.statusItem = statusItem
		self.userPrefsDataSource = userPrefsDataSource
		initButton()

	}

	func update(for app: OpenableApp, appIconSize: CGFloat, slotWidth: CGFloat, badge: String?) {
		self.app = app
		self.currentIconSize = appIconSize
 		let imageSize = appIconSize
        let menuBarHeight: CGFloat = 22 // do not use NSApplication.shared.mainMenu?.menuBarHeight, it doesn't work on MBP 16 inch with notch, because the menu bar reports as bigger than the actual height it uses. 22 is a good fixed height.
		let newView = NSImageView(
			frame: NSRect(
				x: (slotWidth - imageSize) / 2,
				y: -(imageSize - menuBarHeight) / 2,
				width: imageSize, height: imageSize)
		)

		app.icon.size = NSSize(width: imageSize, height: imageSize)
		newView.image = BadgeRenderer.compose(icon: app.icon, badge: badge, iconSize: imageSize)
		newView.wantsLayer = true

		if let existingSubview = statusItem.button?.subviews.first as? NSImageView {
			statusItem.button?.replaceSubview(existingSubview, with: newView) // we have to replace it to get the correct sizing
		} else {
			statusItem.button?.addSubview(newView)
		}

		statusItem.length = slotWidth
	}

	/// Narrow redraw: re-composite the icon image on the existing NSImageView
	/// without rebuilding the status item's subview tree.
	func updateBadge(_ badge: String?) {
		guard let app = self.app,
		      let imageView = statusItem.button?.subviews.first as? NSImageView else { return }
		imageView.image = BadgeRenderer.compose(icon: app.icon, badge: badge, iconSize: currentIconSize)
	}

	func reset() {
		self.app = nil
        if let button = statusItem.button {
            for subview in button.subviews {
                subview.removeFromSuperview()
            }
        }
	}

	private func initButton() {
		statusItem.button?.wantsLayer = true
		statusItem.button?.target = self
		statusItem.button?.action = #selector(handleClick)
		statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
		statusItem.button?.appearance = NSAppearance(named: .aqua)
 	}

	@objc private func handleClick() {
        if userPrefsDataSource.rightClickByDefault == true {
            showDropdownMenu()
            return
        }

		let event = NSApp.currentEvent
		switch event?.type {
		case .rightMouseUp:
			showDropdownMenu()
		case .leftMouseUp:
			app?.open()
		default: break

		}
	}

	func showDropdownMenu() {
		statusItem.button?.appearance = NSAppearance(named: NSAppearance.current.name)

		let menu = NSMenu()
		guard let appName = app?.name else { return }

        if let runningApplication = app?.runningApplication {
            _ = addMenuItem(
                menu: menu,
                title: "Activate \(appName)",
                action: #selector(activateApp),
                keyEquivalent: "a"
            )

            _ = addMenuItem(
                menu: menu,
                title: "Launch \(appName)",
                action: #selector(launchApp),
                keyEquivalent: "l"
            )

            _ = addMenuItem(
                menu: menu,
                title: "\(runningApplication.isHidden ? "Unhide" : "Hide") \(appName)",
                action: #selector(toggleAppHidden),
                keyEquivalent: "h"
            )
        } else {
            _ = addMenuItem(
                menu: menu,
                title: "Launch \(appName)",
                action: #selector(launchApp),
                keyEquivalent: "l"
            )
        }

		_ = addMenuItem(
			menu: menu,
			title: "Reveal \(appName) in Finder",
			action: #selector(revealAppInFinder),
			keyEquivalent: "r"
		)

		addAppOpeningMethodMenuItem(menu: menu)

        if app?.runningApplication != nil {
            _ = addMenuItem(
                menu: menu,
                title: "Quit \(appName)",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
        }

		statusItem.popUpMenu(menu)
	}

	private func addAppOpeningMethodMenuItem(menu: NSMenu) {
		guard let app = app else { return }
		let appOpeningMethodMenuItem = addMenuItem(
			menu: menu,
			title: "Change opening method for \(app.name)",
			action: nil,
			keyEquivalent: ""
		)
		appOpeningMethodMenuItem.submenu = NSMenu()

		let launchItem = addMenuItem(
			menu: appOpeningMethodMenuItem.submenu!,
			title: "Launch",
			action: #selector(setAppOpeningMethodLaunch),
			keyEquivalent: ""
		)

		let activateItem = addMenuItem(
			menu: appOpeningMethodMenuItem.submenu!,
			title: "Activate",
			action: #selector(setAppOpeningMethodActivate),
			keyEquivalent: ""
		)

		switch userPrefsDataSource.appOpeningMethod(for: app) {
		case .launch:
			launchItem.state = .on
			activateItem.state = .off
		case .activate:
			launchItem.state = .off
			activateItem.state = .on
		default:
			launchItem.state = .off
			activateItem.state = .off
		}
 	}

	private func addMenuItem(menu: NSMenu, title: String, action: Selector?, keyEquivalent: String) -> NSMenuItem {
		let item = NSMenuItem(
			title: title,
			action: action,
			keyEquivalent: keyEquivalent
		)
		item.target = self
		menu.addItem(item)
		return item
	}

	@objc private func quitApp() {
		app?.quit()
	}

	@objc private func revealAppInFinder() {
		app?.revealInFinder()
	}

	@objc private func toggleAppHidden() {
		if let runningApplication = app?.runningApplication {
			app?.setIsHidden(isHidden: !runningApplication.isHidden)
		}
	}

	@objc private func activateApp() {
		app?.activate()
	}

	@objc private func launchApp() {
		app?.launch()
	}

	@objc private func openNewAppInstance() {
		app?.openNewAppInstance()
	}

	@objc private func setAppOpeningMethodLaunch() {
		guard let app = app else { return }
		delegate?.didSetAppOpeningMethod(userPrefsDataSource.appOpeningMethod(for: app) == .launch ? nil : .launch, app) // toggle the current state
 	}

	@objc private func setAppOpeningMethodActivate() {
		guard let app = app else { return }
		delegate?.didSetAppOpeningMethod(userPrefsDataSource.appOpeningMethod(for: app) == .activate ? nil : .activate, app)
 	}

}
