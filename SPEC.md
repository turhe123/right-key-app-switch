# RightKeyAppSwitch — specification

**Tagline:** Hold the right Command key and tap a letter to jump straight to an app or cycle its windows.

**Category:** Menu Bar Utility

**Inspired by (paid):** rcmd ($15 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, ApplicationServices, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does. rcmd costs about 15 dollars as a lifetime license, with a free tier and a 14-day trial. It turns the right Command key into an app launcher: right Command plus the first letter of an app focuses it, and repeated presses cycle windows. Its Pro tier adds Spaces navigation and window jumping, and it has been covered by Cult of Mac, which together with steady word-of-mouth in productivity circles shows demand. Our clean-room version implements the free-tier concept with automatic letter assignment and manual overrides.

(2) Feature set. While the right Command key is held, pressing a letter or digit key activates the app bound to it. Bindings are generated automatically from the first letter of each running regular app, resolving conflicts by trying the second letter and then the next free letter. The user may override bindings in Settings. If the bound app is already frontmost, repeated presses cycle through that app's windows. If the app is not running, optionally launch it. Right Command plus the slash key shows a small overlay listing all current bindings. Right Command plus Option and a letter hides the app instead.

(3) UI spec. MenuBarExtra with a command-key symbol. The menu shows Pause Switching toggle, Show Bindings, Settings and Quit. The bindings overlay is a centered borderless panel with a grid of app icons and their key caps, dismissed on key release. Settings window fields: auto-assign toggle, launch-if-not-running toggle, include background-only apps toggle, a table of overrides with app, key and remove, and launch at login toggle. Empty state: when Input Monitoring is not granted, the menu shows a Grant Access row and the overlay explains why.

(4) Technical approach. Create a CGEventTap at the session level listening for key down, key up and flags changed events. Detect the right Command key by checking the device-dependent flag bit for right Command in the event flags together with the standard command mask. When the right-Command-only state is active and a mapped key arrives, consume the event by returning nil and perform the switch. This requires the Input Monitoring permission, requested with CGRequestListenEventAccess and checked with CGPreflightListenEventAccess, and because the tap can swallow events macOS may also need Accessibility, so request AXIsProcessTrustedWithOptions too. Apps are enumerated from NSWorkspace runningApplications filtered to the regular activation policy. Activate with the NSRunningApplication activate method, and launch with NSWorkspace openApplication using the bundle URL. Window cycling uses AXUIElement to read kAXWindowsAttribute and raise the next window with the raise action. Persist overrides in UserDefaults as a dictionary of key to bundle identifier. Launch at login via SMAppService.

(5) Edge cases. If the tap is disabled by the system due to timeout, re-enable it from the callback upon receiving the disabled-by-timeout event type. Ensure that a plain right Command tap with no letter still passes through so the system shortcuts keep working. Ignore events while a secure input field is active. Handle keyboards without a distinct right Command. Recompute auto-assignments whenever apps launch or quit but keep existing bindings stable so muscle memory does not shift. Minimized windows should be unminimized when cycled.
