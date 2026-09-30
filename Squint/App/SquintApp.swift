import SwiftUI

/// We intentionally do not expose a SwiftUI `Settings { }` scene here.
/// Settings is presented by `SettingsWindowController` (AppKit), which is
/// reliable under `.accessory` activation policy and does not require
/// tearing down the floating panel to reopen. See
/// `docs/plans/WINDOW_FOCUS_FIXES.md`.
@main
struct SquintApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
