import AppKit
import ApplicationServices

/// Activates, hides, launches apps and cycles their windows through the Accessibility API.
enum AppSwitcher {
    static func runningApp(_ bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID && !$0.isTerminated }
    }

    /// Switches to (or hides) the app; returns false when nothing could be done.
    @discardableResult
    static func trigger(bundleID: String, hide: Bool, launchIfNeeded: Bool) -> Bool {
        if let app = runningApp(bundleID) {
            if hide { return app.hide() }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                cycleWindows(of: app)
            } else {
                if app.isHidden { app.unhide() }
                if !app.activate() || windows(of: app).isEmpty { open(bundleID) }
            }
            return true
        }
        guard !hide, launchIfNeeded else { return false }
        return open(bundleID)
    }

    /// Launches or re-opens the app via its bundle URL.
    @discardableResult
    static func open(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("RightKeyAppSwitch: could not open \(bundleID): \(error.localizedDescription)") }
        }
        return true
    }

    /// Standard windows of the app in front-to-back order (minimized ones included).
    static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list.filter { (string($0, kAXSubroleAttribute) ?? kAXStandardWindowSubrole) == kAXStandardWindowSubrole }
    }

    /// Raises the back-most window, so repeated presses walk through every window.
    static func cycleWindows(of app: NSRunningApplication) {
        let list = windows(of: app)
        guard let target = list.count > 1 ? list.last : list.first(where: isMinimized) else { return }
        if isMinimized(target) {
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

/// Checks and requests the Input Monitoring and Accessibility permissions.
enum Permissions {
    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func request() {
        if !inputMonitoring { _ = CGRequestListenEventAccess() }
        if !accessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    static func openSystemSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
