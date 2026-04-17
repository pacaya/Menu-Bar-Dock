//
//  AppDelegate.swift
//  MenuBarDock
//
//  Created by Ethan Sarif-Kattan on 02/03/2019.
//  Copyright © 2019 Ethan Sarif-Kattan. All rights reserved.
//

import Cocoa
import ServiceManagement

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate {
	let popover = NSPopover()
	var storyboard: NSStoryboard!
	var preferencesWindow = NSWindow()
	var aboutWindowController: NSWindowController?
	var infoWindowController: NSWindowController?

	var userPrefs =  UserPrefs()
	var menuBarItems: MenuBarItems! // need reference so it stays alive
	var openableApps: OpenableApps!
	var appTracker: AppTracker!
	var runningApps: RunningApps!
	var regularApps: RegularApps!
	var badgeMonitor: BadgeMonitor!

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		initApp()
		setupLaunchAtLogin()
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		badgeMonitor?.stop()
		userPrefs.save()
	}

	func initApp() {
		userPrefs.load()
		storyboard = NSStoryboard(name: "Main", bundle: nil)
		menuBarItems = MenuBarItems(
			userPrefsDataSource: userPrefs
		)
		menuBarItems.delegate = self

		appTracker = AppTracker()
		appTracker.delegate = self

		runningApps = RunningApps(userPrefsDataSource: userPrefs)
		regularApps = RegularApps(userPrefsDataSource: userPrefs)

		openableApps = OpenableApps(userPrefsDataSource: userPrefs, runningApps: runningApps, regularApps: regularApps)

		badgeMonitor = BadgeMonitor()
		badgeMonitor.delegate = menuBarItems

		updateMenuBarItems()

		configureBadgeMonitorForCurrentPrefs()
	}

	/// Starts the BadgeMonitor based on the current pref. Never shows an AX
	/// prompt at launch — prompting only happens when the user explicitly
	/// opts in via the Preferences checkbox. If the pref is ON but AX hasn't
	/// been granted yet, we silently poll until it is.
	private func configureBadgeMonitorForCurrentPrefs() {
		guard userPrefs.showDockBadges else {
			badgeMonitor.stop()
			return
		}
		badgeMonitor.waitForPermissionThenStart()
	}

	func setupLaunchAtLogin() {
		let launcherAppId = Constants.App.launcherBundleId
		let runningApps = NSWorkspace.shared.runningApplications

        if #available(macOS 13.0, *) {
            do {
                let appService = SMAppService.loginItem(identifier: launcherAppId)
                if userPrefs.launchAtLogin {
                    try appService.register()
                } else {
                    try appService.unregister()
                }
            } catch {
                print("Failed to register/unregister login item: \(error)")
            }
        } else {
            SMLoginItemSetEnabled(launcherAppId as CFString, false) // needs to be set to false to actually create the loginitems.501.plist file, then we can set it to the legit value...weird
            SMLoginItemSetEnabled(launcherAppId as CFString, userPrefs.launchAtLogin)
        }

		let isLauncherRunning = !runningApps.filter { $0.bundleIdentifier == launcherAppId }.isEmpty
		if isLauncherRunning {
			DistributedNotificationCenter.default().post(name: Notification.Name("killLauncher"), object: Bundle.main.bundleIdentifier!)
		}
	}

	private func updateMenuBarItems() {
		menuBarItems.update(openableApps: openableApps)
		badgeMonitor?.setObservedApps(openableApps.apps)
	}
}

extension AppDelegate: MenuBarItemsDelegate {
	func didSetAppOpeningMethod(_ method: AppOpeningMethod?, _ app: OpenableApp) {
		userPrefs.appOpeningMethods[app.id] = method
		userPrefsWasUpdated()
	}

	func didOpenPreferencesWindow() {
		openPreferencesWindow()
	}

	func didRequestQuit() {
		NSApp.terminate(nil)
	}

	func openPreferencesWindow() {
		if let viewController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: Constants.Identifiers.ViewControllers.preferences) as? PreferencesViewController {
			viewController.userPrefsDataSource = userPrefs
			viewController.delegate = self

			if !preferencesWindow.isVisible == true {
				preferencesWindow = NSWindow(contentViewController: viewController)
				preferencesWindow.makeKeyAndOrderFront(self)
			}
			preferencesWindow.makeKeyAndOrderFront(self)

			preferencesWindow.minSize = preferencesWindow.frame.size
			preferencesWindow.windowController?.showWindow(self)
			NSApp.activate(ignoringOtherApps: true)// stops bugz n shiz i think
		}
	}
}

extension AppDelegate: AppTrackerDelegate {
	func appWasActivated(runningApp: NSRunningApplication) {
		runningApps.handleAppActivation(runningApp: runningApp)
		regularApps.handleAppActivation(runningApp: runningApp)

		appActivationChange()
	}

	func appWasQuit(runningApp: NSRunningApplication) {
		runningApps.handleAppQuit(runningApp: runningApp)
		regularApps.handleAppQuit(runningApp: runningApp)

		appActivationChange()
	}

	private func appActivationChange() {
		runningApps.update()
		//		regularApps.update() //doesn't make sense to update regular apps based on app activations. we could if we wanted to due to the hot reactive code structure, but best not to.
		openableApps.update(runningApps: runningApps, regularApps: regularApps)

		updateMenuBarItems()
	}
}

extension AppDelegate: PreferencesViewControllerDelegate {
	func maxRunningAppsSliderDidChange(_ value: Int) {
		userPrefs.maxRunningApps = value
		userPrefsWasUpdated()
	}

	func itemSlotWidthSliderDidChange(_ value: Double) {
		userPrefs.itemSlotWidth = CGFloat(value)
		userPrefsWasUpdated()
	}

	func appIconSizeSliderDidChange(_ value: Double) {
		userPrefs.appIconSize = CGFloat(value)
		userPrefsWasUpdated()
	}

	func runningAppsSortingMethodDidChange(_ value: RunningAppsSortingMethod) {
		userPrefs.runningAppsSortingMethod = value
		userPrefsWasUpdated()
	}

	func resetPreferencesToDefaultsWasPressed() {
		userPrefs.resetToDefaults()
		userPrefsWasUpdated()
	}

	func resetAppOpeningMethodsWasPressed() {
		userPrefs.resetAppOpeningMethodsToDefaults()
		userPrefsWasUpdated()
	}

	func launchAtLoginDidChange(_ value: Bool) {
		userPrefs.launchAtLogin = value
		let launcherAppId = Constants.App.launcherBundleId
        if #available(macOS 13.0, *) {
            do {
                let appService = SMAppService.loginItem(identifier: launcherAppId)
                if value {
                    try appService.register()
                } else {
                    try appService.unregister()
                }
            } catch {
                print("Failed to register/unregister login item: \(error)")
            }
        } else {
            SMLoginItemSetEnabled(launcherAppId as CFString, value)

        }
		userPrefsWasUpdated()
	}

	func aboutWasPressed() {
		if let windowController = aboutWindowController ?? storyboard.instantiateController(withIdentifier: Constants.Identifiers.WindowControllers.about) as? NSWindowController {
			windowController.showWindow(self)
			aboutWindowController = windowController
		}
	}

	func hideFinderDidChange(_ value: Bool) {
		userPrefs.hideFinderFromRunningApps = value
		userPrefsWasUpdated()
	}

	func hideActiveAppDidChange(_ value: Bool) {
		userPrefs.hideActiveAppFromRunningApps = value
		userPrefsWasUpdated()
	}

    func preserveAppOrderDidChange(_ value: Bool) {
        userPrefs.preserveAppOrder = value
        userPrefsWasUpdated()
    }

    func rightClickByDefaultDidChange(_ value: Bool) {
        userPrefs.rightClickByDefault = value
        userPrefsWasUpdated()
    }

    func showDockBadgesDidChange(_ value: Bool) {
        userPrefs.showDockBadges = value
        userPrefs.save()

        if !value {
            badgeMonitor.stop()
            return
        }

        if AXIsProcessTrusted() {
            badgeMonitor.start()
            return
        }

        // Not trusted yet. Fire the system AX prompt (async) and start
        // polling so the monitor auto-starts when the user grants access.
        // Then surface a clear instructional alert so the user knows what
        // to do. Only an explicit Cancel in that alert rolls the pref back.
        _ = badgeMonitor.ensurePermission(promptIfNeeded: true)
        badgeMonitor.waitForPermissionThenStart()
        presentAccessibilityInstructionsAlert()
    }

    private func presentAccessibilityInstructionsAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission needed"
        alert.informativeText = "Menu Bar Dock reads badge counts from the macOS Dock using the Accessibility API.\n\nOpen System Settings → Privacy & Security → Accessibility and enable Menu Bar Dock. Badges will start appearing automatically once access is granted."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else {
            // User explicitly cancelled — roll back pref, stop polling, sync UI.
            userPrefs.showDockBadges = false
            userPrefs.save()
            badgeMonitor.stop()
            if let vc = preferencesWindow.contentViewController as? PreferencesViewController {
                vc.updateUi()
            }
        }
    }

	func appOpeningMethodDidChange(_ value: AppOpeningMethod) {
		userPrefs.defaultAppOpeningMethod = value
		userPrefsWasUpdated()
	}

	func regularAppsUrlsWereAdded(_ value: [URL]) {
		value.forEach { (url) in
			if !userPrefs.regularAppsUrls.contains(url) {
				userPrefs.regularAppsUrls.append(url)
			}
		}
		userPrefsWasUpdated()
	}

	func regularAppsUrlsWereRemoved(_ removedIndexes: IndexSet) {
		userPrefs.regularAppsUrls.remove(at: removedIndexes)
		userPrefsWasUpdated()
	}

	func regularAppUrlWasMoved(oldIndex: Int, newIndex: Int) {
		let url = userPrefs.regularAppsUrls.remove(at: oldIndex)
		userPrefs.regularAppsUrls.insert(url, at: newIndex)
		userPrefsWasUpdated()
	}

	func sideToShowRunningAppsDidChange(_ value: SideToShowRunningApps) {
		userPrefs.sideToShowRunningApps = value
		userPrefsWasUpdated()
	}

	func hideDuplicateAppsDidChange(_ value: Bool) {
		userPrefs.hideDuplicateApps = value
		userPrefsWasUpdated()
	}

	func duplicateAppsPriorityDidChange(_ value: DuplicateAppsPriority) {
		userPrefs.duplicateAppsPriority = value
		userPrefsWasUpdated()
	}

	func infoWasPressed() {
		if let windowController = infoWindowController ?? storyboard.instantiateController(withIdentifier: Constants.Identifiers.WindowControllers.info) as? NSWindowController {
			windowController.showWindow(self)
			infoWindowController = windowController
		}
	}

	private func userPrefsWasUpdated() {
		userPrefs.save()
		runningApps.update()
		regularApps.update()
		openableApps.update(runningApps: runningApps, regularApps: regularApps)
		updateMenuBarItems()
	}
}
