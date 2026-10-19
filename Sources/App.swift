import AppKit
import SwiftUI

/// Entry point: a menu-bar-only app with a Settings window.
@main
struct RightKeyAppSwitchApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("RightKeyAppSwitch", systemImage: "command") {
            MenuContent(state: state)
        }
        .menuBarExtraStyle(.menu)

        Window("RightKeyAppSwitch Settings", id: "settings") {
            SettingsView(state: state)
        }
        .windowResizability(.contentSize)
    }
}

/// Opens the donation page.
enum Support {
    static func open() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}

/// Items of the menu bar dropdown.
struct MenuContent: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !state.hasAccess {
            Button("⚠️ Grant Access…") { state.requestAccess() }
            Divider()
        }
        Toggle("Pause Switching", isOn: $state.isPaused)
        Button("Show Bindings") { state.showOverlay() }
            .keyboardShortcut("/")
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Divider()
        Button("Support / Donate ❤️") { Support.open() }
        Divider()
        Button("Quit RightKeyAppSwitch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
