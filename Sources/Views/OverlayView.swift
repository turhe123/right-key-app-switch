import AppKit
import SwiftUI

/// Shows the bindings overlay in a centered, borderless, non-activating panel.
@MainActor
final class OverlayController {
    private let state: AppState
    private var panel: NSPanel?
    private var dismissOnRelease = false
    private var monitors: [Any] = []
    private var hideTimer: Timer?

    init(state: AppState) { self.state = state }

    /// `dismissOnRelease` is used for the keyboard trigger; the menu trigger dismisses on click or after a delay.
    func show(dismissOnRelease: Bool) {
        hide()
        self.dismissOnRelease = dismissOnRelease
        let hosting = NSHostingView(rootView: OverlayView(state: state))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        if !dismissOnRelease {
            let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
            if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
                MainActor.assumeIsolated { AppState.shared.hideOverlay() }
            }) { monitors.append(global) }
            hideTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
                MainActor.assumeIsolated { AppState.shared.hideOverlay() }
            }
        }
    }

    func releaseDismiss() {
        if dismissOnRelease { hide() }
    }

    func hide() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

extension AppState {
    func hideOverlay() { overlay.hide() }
}

/// Grid of app icons with their key caps, or an explanation when access is missing.
struct OverlayView: View {
    @ObservedObject var state: AppState
    private let columns = Array(repeating: GridItem(.fixed(84), spacing: 12), count: 6)

    var body: some View {
        VStack(spacing: 14) {
            Label("Right ⌘ Bindings", systemImage: "command")
                .font(.headline)
            if !state.hasAccess {
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield").font(.system(size: 34)).foregroundStyle(.orange)
                    Text("Input Monitoring is not granted")
                        .font(.title3.bold())
                    Text("RightKeyAppSwitch needs Input Monitoring and Accessibility access to see the right Command key and switch apps. Use “Grant Access…” in the menu bar.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 380)
            } else if state.bindings.isEmpty {
                Text("No bindings yet. Launch an app or add an override in Settings.")
                    .foregroundStyle(.secondary)
                    .frame(width: 360)
            } else {
                LazyVGrid(columns: Array(columns.prefix(min(6, state.bindings.count))), spacing: 12) {
                    ForEach(state.bindings) { binding in
                        VStack(spacing: 4) {
                            Image(nsImage: binding.icon)
                                .resizable().frame(width: 44, height: 44)
                                .opacity(binding.isRunning ? 1 : 0.45)
                            KeyCap(key: binding.key)
                            Text(binding.name).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                        }
                        .frame(width: 84)
                    }
                }
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }
}

/// A small keyboard-key style label.
struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key.uppercased())
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.secondary.opacity(0.4)))
    }
}
