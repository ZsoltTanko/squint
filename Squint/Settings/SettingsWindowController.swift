import AppKit
import SwiftUI

/// AppKit-owned Settings window. Replaces the SwiftUI `Settings { }` scene.
///
/// Rationale: the SwiftUI scene is finicky to reopen under `.accessory`
/// activation policy and required a delayed `sendAction(showSettingsWindow:)`
/// dance. Owning the window directly makes "open Settings" a single,
/// reliable call we can make from the gear button, the status-bar menu, or
/// anywhere else — and lets us present Settings without tearing down the
/// floating panel.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private(set) var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: SettingsRoot())
        let win = SettingsWindow(contentViewController: host)
        win.title = "Squint Settings"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 720, height: 520))
        win.contentMinSize = NSSize(width: 720, height: 520)
        win.isReleasedWhenClosed = false
        win.identifier = NSUserInterfaceItemIdentifier("SquintSettings")
        win.setFrameAutosaveName("SquintSettings")
        if !win.setFrameUsingName("SquintSettings") {
            win.center()
        }
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// True if the passed window is the Settings window. Used by the
    /// activation-policy restore observer to match on identity instead of
    /// fragile title/identifier heuristics.
    func isSettingsWindow(_ candidate: NSWindow) -> Bool {
        window === candidate
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }
}

/// `NSWindow` subclass that closes on Esc. Handled at the window level
/// (via `cancelOperation(_:)`) so Esc works regardless of which SwiftUI
/// control inside the Settings tabs is focused.
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }
}

/// The tabbed Settings view. Previously lived in `SettingsScene.swift`
/// under the SwiftUI `Settings { }` scene.
struct SettingsRoot: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModelsSettingsView()
                .tabItem { Label("Models", systemImage: "cpu") }
            PromptsSettingsView()
                .tabItem { Label("Prompts", systemImage: "text.quote") }
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "text.cursor") }
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
    }
}
