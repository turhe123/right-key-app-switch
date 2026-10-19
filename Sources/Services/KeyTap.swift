import AppKit
import Carbon
import CoreGraphics

/// Owns the session-level CGEventTap and turns "right Command + key" chords into high-level callbacks.
/// Everything that is not a right-Command chord for a bound key passes through untouched.
@MainActor
final class KeyTap {
    /// Called with the pressed key (e.g. "s") and whether Option was held. Return `true` to swallow the event.
    var onKey: (String, Bool) -> Bool = { _, _ in false }
    /// Called when right Command + `/` is pressed.
    var onOverlay: () -> Void = {}
    /// Called when the Command key is released.
    var onRelease: () -> Void = {}
    /// When true, every event passes through.
    var isPaused: () -> Bool = { false }

    private(set) var isRunning = false
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Fallback state for keyboards that do not report device-dependent modifier bits.
    private var rightCommandDown = false
    /// Key codes whose key-down we swallowed, so the matching key-up is swallowed too.
    private var swallowed = Set<Int64>()

    private static let rightCmdBit: UInt64 = 0x10   // NX_DEVICERCMDKEYMASK
    private static let leftCmdBit: UInt64 = 0x08    // NX_DEVICELCMDKEYMASK
    private static let rightCmdKeyCode: Int64 = 54
    private static let slashKeyCode: Int64 = 44

    /// ANSI virtual key codes for letters and digits.
    private static let keyMap: [Int64: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0", 31: "o",
        32: "u", 34: "i", 35: "p", 37: "l", 38: "j", 40: "k", 45: "n", 46: "m",
    ]

    /// Attempts to install the tap. Returns false when permissions are missing.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        port = tap
        source = src
        isRunning = true
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass
        case .flagsChanged:
            let flags = event.flags
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.rightCmdKeyCode {
                rightCommandDown = flags.contains(.maskCommand)
            }
            if !flags.contains(.maskCommand) {
                rightCommandDown = false
                onRelease()
            }
            return pass  // never swallow modifiers, so a bare right-Command tap still works
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowed.remove(code) != nil ? nil : pass
        case .keyDown:
            return handleKeyDown(event) ? nil : pass
        default:
            return pass
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let flags = event.flags
        guard !isPaused(), !IsSecureEventInputEnabled(), isRightCommandOnly(flags) else { return false }
        guard !flags.contains(.maskControl), !flags.contains(.maskShift) else { return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return swallowed.contains(code)
        }
        var handled = false
        if code == Self.slashKeyCode, !flags.contains(.maskAlternate) {
            onOverlay()
            handled = true
        } else if let key = Self.keyMap[code] {
            handled = onKey(key, flags.contains(.maskAlternate))
        }
        if handled { swallowed.insert(code) }
        return handled
    }

    /// True when Command is held via the right key only. Falls back to key-code tracking
    /// on keyboards that do not set the device-dependent left/right bits.
    private func isRightCommandOnly(_ flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskCommand) else { return false }
        let raw = flags.rawValue
        let right = raw & Self.rightCmdBit != 0
        let left = raw & Self.leftCmdBit != 0
        if right || left { return right && !left }
        return rightCommandDown
    }
}

private func keyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { tap.handle(type: type, event: event) }
}
