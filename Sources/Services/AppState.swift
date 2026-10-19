import AppKit
import Combine
import ServiceManagement

/// One row of the binding table, resolved for display.
struct AppBinding: Identifiable, Hashable {
    let key: String
    let bundleID: String
    let name: String
    let isRunning: Bool
    let isOverride: Bool
    var id: String { key }

    var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
    }
}

/// Central coordinator: wires the event tap to the binding store, tracks app launches/quits,
/// permission state and the overlay.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var bindings: [AppBinding] = []
    @Published private(set) var hasAccess = false
    @Published var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: Prefs.paused) }
    }

    let store = BindingStore()
    private let tap = KeyTap()
    lazy var overlay = OverlayController(state: self)
    private var observers: [NSObjectProtocol] = []
    private var permissionTimer: Timer?

    private init() {
        UserDefaults.standard.register(defaults: [
            Prefs.autoAssign: true, Prefs.launchIfNotRunning: true,
            Prefs.includeBackground: false, Prefs.paused: false,
        ])
        isPaused = UserDefaults.standard.bool(forKey: Prefs.paused)

        tap.isPaused = { [unowned self] in isPaused }
        tap.onKey = { [unowned self] key, hide in handle(key: key, hide: hide) }
        tap.onOverlay = { [unowned self] in overlay.show(dismissOnRelease: true) }
        tap.onRelease = { [unowned self] in overlay.releaseDismiss() }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildIfChanged() }
            })

        refresh()
        startTapOrPoll()
    }

    // MARK: Permissions

    func requestAccess() {
        Permissions.request()
        startTapOrPoll()
    }

    /// Tries to install the tap; until it succeeds, re-checks every two seconds.
    private func startTapOrPoll() {
        hasAccess = tap.start()
        guard !hasAccess, permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let state = self else { return }
                state.hasAccess = state.tap.start()
                if state.hasAccess {
                    state.permissionTimer?.invalidate()
                    state.permissionTimer = nil
                }
            }
        }
    }

    // MARK: Bindings

    /// Running apps eligible for automatic assignment.
    var eligibleApps: [NSRunningApplication] {
        let includeBackground = UserDefaults.standard.bool(forKey: Prefs.includeBackground)
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.bundleIdentifier != nil, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            return app.activationPolicy == .regular || (includeBackground && app.activationPolicy == .accessory)
        }
        .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
    }

    func refresh() {
        if UserDefaults.standard.bool(forKey: Prefs.autoAssign) { store.refresh(running: eligibleApps) }
        rebuild()
    }

    private var lastSettings: [Bool] = []

    /// Re-runs assignment only when a setting that affects it actually changed.
    private func rebuildIfChanged() {
        let defaults = UserDefaults.standard
        let settings = [defaults.bool(forKey: Prefs.autoAssign), defaults.bool(forKey: Prefs.includeBackground)]
        guard settings != lastSettings else { return }
        lastSettings = settings
        refresh()
    }

    private func rebuild() {
        let effective = store.effective
        let overrides = store.overrides
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        bindings = effective.map { key, id in
            AppBinding(key: key, bundleID: id, name: Self.displayName(for: id),
                       isRunning: running.contains(id), isOverride: overrides[key] == id)
        }
        .sorted { $0.key < $1.key }
    }

    static func displayName(for bundleID: String) -> String {
        if let app = AppSwitcher.runningApp(bundleID), let name = app.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    func setOverride(key: String, bundleID: String) {
        store.setOverride(key: key, bundleID: bundleID)
        refresh()
    }

    func removeOverride(key: String) {
        store.removeOverride(key: key)
        refresh()
    }

    private func handle(key: String, hide: Bool) -> Bool {
        guard let bundleID = store.effective[key] else { return false }
        let launch = UserDefaults.standard.bool(forKey: Prefs.launchIfNotRunning)
        return AppSwitcher.trigger(bundleID: bundleID, hide: hide, launchIfNeeded: launch)
    }

    // MARK: Overlay

    func showOverlay() { overlay.show(dismissOnRelease: false) }
}

/// Wraps `SMAppService` for the launch-at-login toggle.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
