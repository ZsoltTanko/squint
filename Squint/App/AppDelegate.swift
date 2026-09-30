import AppKit
import SwiftUI
import KeyboardShortcuts
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    let modelStore = ModelStore()
    let presetStore = PromptPresetStore()
    let settings = SettingsStore.shared
    let registry: ProviderRegistry
    let captureService: SelectionCaptureService
    let panelController: FloatingPanelController

    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?
    private var presetCancellable: AnyCancellable?

    override init() {
        self.registry = ProviderRegistry(modelStore: modelStore)
        self.captureService = SelectionCaptureService(settings: settings)
        self.panelController = FloatingPanelController(
            modelStore: modelStore,
            presetStore: presetStore,
            registry: registry,
            settings: settings
        )
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        rebuildMenuBar()
        // Rebuild the menu bar's "Prompt presets" submenu whenever the catalog
        // changes. `.dropFirst()` skips the synchronous current-value emission
        // that `@Published` delivers on subscription — we already call
        // `rebuildMenuBar()` + `registerPerPresetHotkeys()` explicitly below,
        // and double-registration of hotkey handlers (KeyboardShortcuts
        // *appends* rather than replaces) is exactly what caused the preset
        // hotkey to fire multiple times and appear to crash the app.
        presetCancellable = presetStore.$presets
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenuBar()
                self?.registerPerPresetHotkeys()
            }

        ServicesHandler.shared.configure(
            panelController: panelController,
            captureService: captureService,
            settings: settings,
            presetStore: presetStore
        )
        NSApp.servicesProvider = ServicesHandler.shared
        NSUpdateDynamicServices()

        hotkeyManager = HotkeyManager(
            onInvoke: { [weak self] in self?.invokeFromHotkey(preset: nil) },
            onInvokePreset: { [weak self] preset in self?.invokeFromHotkey(preset: preset) }
        )
        hotkeyManager?.start()
        registerPerPresetHotkeys()

        if !settings.hasCompletedOnboarding {
            OnboardingWindow.show()
        }
    }

    private func rebuildMenuBar() {
        menuBarController = MenuBarController(
            presetStore: presetStore,
            onAsk: { [weak self] in self?.invokeFromMenu(preset: nil) },
            onAskWithPreset: { [weak self] preset in self?.invokeFromMenu(preset: preset) },
            onSettings: { Self.openSettings() },
            onPermissions: { [weak self] in self?.panelController.showPermissionsCheck() },
            onQuit: { NSApp.terminate(nil) }
        )
    }

    private func registerPerPresetHotkeys() {
        hotkeyManager?.syncPresetHotkeys(presets: presetStore.presets) { [weak self] preset in
            self?.invokeFromHotkey(preset: preset)
        }
    }

    func invokeFromHotkey(preset: PromptPreset?) {
        Task { @MainActor in
            // Resolve which preset will own this invocation up-front so we
            // can skip selection capture entirely for direct-prompt presets
            // (`capturesSelection == false`). Capturing a selection we'd
            // immediately discard would only burn latency and, for the
            // clipboard-fallback strategy, briefly clobber the user's
            // pasteboard.
            let effectivePreset = preset ?? presetStore.defaultPreset
            let bundle: ContextBundle
            if effectivePreset?.capturesSelection == false {
                bundle = .empty()
            } else {
                if !AccessibilityCapture.isTrusted {
                    AccessibilityCapture.requestTrust()
                }
                bundle = await captureService.captureForHotkey()
            }
            // For the global "ask" hotkey, fall back to the legacy auto-send
            // setting; for per-preset hotkeys, the preset's own flag wins.
            if let preset {
                panelController.present(with: bundle, preset: preset, autoSendOverride: nil)
            } else {
                panelController.present(with: bundle, autoSend: settings.autoSendOnInvocation)
            }
        }
    }

    func invokeFromMenu(preset: PromptPreset?) {
        Task { @MainActor in
            let effectivePreset = preset ?? presetStore.defaultPreset
            let bundle: ContextBundle
            if effectivePreset?.capturesSelection == false {
                bundle = .empty()
            } else {
                bundle = await captureService.captureForHotkey()
            }
            panelController.present(with: bundle, preset: effectivePreset, autoSendOverride: false)
        }
    }

    private var settingsCloseObserver: NSObjectProtocol?

    static func openSettings() {
        // A menu-bar-only (`.accessory`) app can still present a window, but
        // switching to `.regular` while Settings is open gives the user a
        // Dock icon / Cmd-Tab entry, which is the expected Mac feel for a
        // focused preferences window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Do NOT close the floating panel. Settings is a sibling window; the
        // click-off observer in `FloatingPanelController` knows to ignore
        // resignKey when another of our windows becomes key.
        SettingsWindowController.shared.show()
        shared.observeSettingsCloseOnce()
    }

    private func observeSettingsCloseOnce() {
        guard settingsCloseObserver == nil else { return }
        settingsCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            guard SettingsWindowController.shared.isSettingsWindow(window) else { return }
            // `willClose` fires before the window is actually hidden, so
            // defer the visibility check one runloop tick.
            DispatchQueue.main.async {
                guard !SettingsWindowController.shared.isVisible else { return }
                // A `Recede to background` panel that's still alive needs
                // `.regular` to stay reachable via Cmd-Tab — don't yank the
                // policy out from under it just because Settings closed.
                if self?.panelController.requiresRegularActivationPolicy == true { return }
                NSApp.setActivationPolicy(.accessory)
                if let obs = self?.settingsCloseObserver {
                    NotificationCenter.default.removeObserver(obs)
                    self?.settingsCloseObserver = nil
                }
            }
        }
    }
}
