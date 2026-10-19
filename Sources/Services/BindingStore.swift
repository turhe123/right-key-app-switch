import AppKit

/// Keys used for persisted settings, shared between views (`@AppStorage`) and services.
enum Prefs {
    static let autoAssign = "autoAssign"
    static let launchIfNotRunning = "launchIfNotRunning"
    static let includeBackground = "includeBackgroundApps"
    static let paused = "pauseSwitching"
    static let overrides = "overrides"
    static let autoAssignments = "autoAssignments"
    static let validKeys = Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)
}

/// Persists manual overrides and stable automatic key assignments (both `[key: bundleID]`),
/// and computes the effective binding table.
final class BindingStore {
    private let defaults = UserDefaults.standard

    var overrides: [String: String] {
        get { defaults.dictionary(forKey: Prefs.overrides) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Prefs.overrides) }
    }

    private var auto: [String: String] {
        get { defaults.dictionary(forKey: Prefs.autoAssignments) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Prefs.autoAssignments) }
    }

    /// Effective bindings: overrides win, then (if enabled) automatic assignments.
    var effective: [String: String] {
        var result = defaults.bool(forKey: Prefs.autoAssign) ? auto : [:]
        let overridden = Set(overrides.values)
        result = result.filter { !overridden.contains($0.value) }
        result.merge(overrides) { _, override in override }
        return result
    }

    func setOverride(key: String, bundleID: String) {
        var current = overrides.filter { $0.value != bundleID }
        current[key] = bundleID
        overrides = current
    }

    func removeOverride(key: String) {
        var current = overrides
        current.removeValue(forKey: key)
        overrides = current
    }

    /// Assigns keys to newly seen apps without moving existing assignments. A key held by an
    /// app that is no longer running is only reused when no free candidate is left.
    func refresh(running: [NSRunningApplication]) {
        let reserved = Set(overrides.keys)
        let overridden = Set(overrides.values)
        var assigned = auto.filter { !reserved.contains($0.key) && !overridden.contains($0.value) }
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))

        for app in running {
            guard let id = app.bundleIdentifier, !overridden.contains(id),
                  !assigned.values.contains(id) else { continue }
            let candidates = Self.candidates(for: app.localizedName ?? id)
            let used = reserved.union(assigned.keys)
            if let key = candidates.first(where: { !used.contains($0) }) {
                assigned[key] = id
            } else if let key = candidates.first(where: { k in
                !reserved.contains(k) && assigned[k].map { !runningIDs.contains($0) } ?? false
            }) {
                assigned[key] = id
            }
        }
        auto = assigned
    }

    /// First letter, second letter, remaining letters of the name, then every other key.
    static func candidates(for name: String) -> [String] {
        var seen = Set<String>()
        let letters = name.lowercased().map(String.init).filter { Prefs.validKeys.contains($0) }
        return (letters + Prefs.validKeys).filter { seen.insert($0).inserted }
    }
}
