//
//  BadgeMonitor.swift
//  Menu Bar Dock
//
//  Reads badge counts from the real macOS Dock via the Accessibility API.
//  AX-based approach inspired by Doll (https://github.com/xiaogdgenuine/Doll);
//  uses only public AX* APIs (no private CoreDock/DockKit).
//
//  Limitations:
//    - An app must be visible in the real Dock's accessibility tree for its
//      badge to be readable. Running apps always appear there (even when the
//      Dock is auto-hidden); a regular app added only to Menu Bar Dock will
//      have no badge.
//    - Keyed by AXTitleAttribute (localized display name), matching
//      OpenableApp.name / NSRunningApplication.localizedName. Two apps with
//      the same display name share one badge — acceptable v1.
//

import Cocoa
import ApplicationServices

protocol BadgeMonitorDelegate: AnyObject {
    func badgesDidChange(_ badges: [String: String], changedAppNames: [String])
}

final class BadgeMonitor {
    weak var delegate: BadgeMonitorDelegate?

    private var timer: Timer?
    private var observedAppNames: Set<String> = []
    private var cachedBadges: [String: String] = [:]
    private var dockElement: AXUIElement?
    private var ticksSincePermissionRecheck = 0
    private let permissionRecheckInterval = 30  // ticks (~30s at 1s interval)
    private let tickInterval: TimeInterval = 1.0

    /// Returns true if Accessibility access is granted.
    /// Pass `promptIfNeeded: true` to display the system prompt if not granted.
    @discardableResult
    func ensurePermission(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard timer == nil else { return }
        ticksSincePermissionRecheck = 0
        let t = Timer(timeInterval: tickInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // Fire immediately so badges show up without waiting a full second on start/prefs-toggle.
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        dockElement = nil

        if !cachedBadges.isEmpty {
            let staleNames = Array(cachedBadges.keys)
            cachedBadges.removeAll()
            delegate?.badgesDidChange([:], changedAppNames: staleNames)
        }
    }

    func setObservedApps(_ apps: [OpenableApp]) {
        observedAppNames = Set(apps.map { $0.name })
    }

    @objc private func tick() {
        // Periodically re-check permission without prompting; if revoked at runtime, quietly stop polling.
        ticksSincePermissionRecheck += 1
        if ticksSincePermissionRecheck >= permissionRecheckInterval {
            ticksSincePermissionRecheck = 0
            if !AXIsProcessTrusted() {
                stop()
                return
            }
        }

        guard !observedAppNames.isEmpty else { return }

        let dock: AXUIElement
        if let cached = dockElement {
            dock = cached
        } else if let fresh = makeDockElement() {
            dock = fresh
            dockElement = fresh
        } else {
            return
        }

        guard let topChildren = copyChildren(dock) else {
            // Dock process may have restarted — rebuild element next tick.
            dockElement = nil
            return
        }

        // Build name → badge for observed apps in a single pass. Dock tiles
        // may be nested one level (a top-level list containing them); expand
        // each top-level child before matching titles.
        var newBadges: [String: String] = [:]
        for topChild in topChildren {
            let tiles: [AXUIElement]
            if let nested = copyChildren(topChild), !nested.isEmpty {
                tiles = nested
            } else {
                tiles = [topChild]
            }
            for tile in tiles {
                guard let title = copyStringAttribute(tile, kAXTitleAttribute as CFString),
                      observedAppNames.contains(title) else { continue }
                if let label = copyStringAttribute(tile, "AXStatusLabel" as CFString), !label.isEmpty {
                    newBadges[title] = label
                }
            }
        }

        // Diff against cache over observed set (both additions and removals).
        var changedNames: [String] = []
        for name in observedAppNames where newBadges[name] != cachedBadges[name] {
            changedNames.append(name)
        }

        cachedBadges = newBadges

        if !changedNames.isEmpty {
            delegate?.badgesDidChange(cachedBadges, changedAppNames: changedNames)
        }
    }

    private func makeDockElement() -> AXUIElement? {
        guard let dockPid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .last?
            .processIdentifier
        else {
            return nil
        }
        return AXUIElementCreateApplication(dockPid)
    }

    private func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
