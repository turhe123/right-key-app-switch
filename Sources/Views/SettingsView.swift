import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings window: behaviour toggles, permission status, override table and launch at login.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @AppStorage(Prefs.autoAssign) private var autoAssign = true
    @AppStorage(Prefs.launchIfNotRunning) private var launchIfNotRunning = true
    @AppStorage(Prefs.includeBackground) private var includeBackground = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var newKey = "a"
    @State private var newBundleID = ""
    @State private var inputGranted = Permissions.inputMonitoring
    @State private var axGranted = Permissions.accessibility

    private var overrides: [AppBinding] { state.bindings.filter(\.isOverride) }

    var body: some View {
        Form {
            Section("Behaviour") {
                Toggle("Auto-assign keys from app names", isOn: $autoAssign)
                Toggle("Launch app if it is not running", isOn: $launchIfNotRunning)
                Toggle("Include background-only (menu bar) apps", isOn: $includeBackground)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        loginError = LoginItem.set(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Permissions") {
                permissionRow("Input Monitoring", granted: inputGranted, pane: "Privacy_ListenEvent")
                permissionRow("Accessibility", granted: axGranted, pane: "Privacy_Accessibility")
                if !state.hasAccess {
                    Button("Request Access") { state.requestAccess() }
                    Text("After granting, the switcher starts automatically. If it does not, quit and relaunch the app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Overrides") {
                if overrides.isEmpty {
                    Text("No overrides. Pick an app and a key below.").foregroundStyle(.secondary)
                } else {
                    Table(overrides) {
                        TableColumn("App") { row in
                            HStack {
                                Image(nsImage: row.icon).resizable().frame(width: 18, height: 18)
                                Text(row.name)
                            }
                        }
                        TableColumn("Key") { row in KeyCap(key: row.key) }
                            .width(60)
                        TableColumn("") { row in
                            Button(role: .destructive) { state.removeOverride(key: row.key) } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove override")
                        }
                        .width(40)
                    }
                    .frame(minHeight: 120)
                }
                HStack {
                    Picker("App", selection: $newBundleID) {
                        Text("Choose…").tag("")
                        ForEach(appChoices, id: \.self) { id in
                            Text(AppState.displayName(for: id)).tag(id)
                        }
                    }
                    Button("Other…", action: pickApp)
                    Picker("Key", selection: $newKey) {
                        ForEach(Prefs.validKeys, id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                    .frame(width: 110)
                    Button("Add") { state.setOverride(key: newKey, bundleID: newBundleID) }
                        .disabled(newBundleID.isEmpty)
                }
            }

            Section("Current bindings") {
                Text(state.bindings.map { "\($0.key.uppercased()) → \($0.name)" }.joined(separator: "   "))
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Hold right ⌘ and press a key to switch. Press again to cycle windows. Add ⌥ to hide the app. Right ⌘ + / shows all bindings.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Support / Donate ❤️") { Support.open() }
                    .controlSize(.large)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 680)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            inputGranted = Permissions.inputMonitoring
            axGranted = Permissions.accessibility
        }
    }

    private var appChoices: [String] {
        var ids = state.eligibleApps.compactMap(\.bundleIdentifier) + state.bindings.map(\.bundleID)
        if !newBundleID.isEmpty { ids.append(newBundleID) }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
            .sorted { AppState.displayName(for: $0).localizedCaseInsensitiveCompare(AppState.displayName(for: $1)) == .orderedAscending }
    }

    private func permissionRow(_ title: String, granted: Bool, pane: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(granted ? .green : .red)
            Text(title)
            Spacer()
            if !granted {
                Button("Open System Settings") { Permissions.openSystemSettings(pane) }
            }
        }
    }

    /// Lets the user bind an app that is not currently running.
    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        newBundleID = id
    }
}
