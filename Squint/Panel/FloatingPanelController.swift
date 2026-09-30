import AppKit
import SwiftUI
import Combine

@MainActor
final class FloatingPanelController {
    private let panel: FloatingPanel
    private let viewModel: PanelViewModel
    private let modelStore: ModelStore
    private let presetStore: PromptPresetStore
    private let settings: SettingsStore

    private var resignKeyObserver: NSObjectProtocol?
    private var becomeKeyObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var liveResizeEndObserver: NSObjectProtocol?
    private var settingsCancellable: AnyCancellable?

    init(modelStore: ModelStore, presetStore: PromptPresetStore, registry: ProviderRegistry, settings: SettingsStore) {
        self.modelStore = modelStore
        self.presetStore = presetStore
        self.settings = settings
        self.viewModel = PanelViewModel(modelStore: modelStore, presetStore: presetStore, registry: registry, settings: settings)
        self.panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: PanelPositioner.defaultSize))

        let host = NSHostingView(rootView: PanelView(viewModel: viewModel, onClose: { [weak self] in
            self?.close()
        }))
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host

        // Esc at the panel (NSPanel) level, so it works regardless of which
        // SwiftUI subview holds focus. Collapses the follow-up bar first if
        // open, otherwise closes the panel.
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if self.viewModel.isFollowUpOpen {
                self.viewModel.closeFollowUp()
            } else {
                self.close()
            }
        }

        // ⌘C with no active text selection → copy the full response.
        // See `FloatingPanel.performKeyEquivalent(with:)`.
        panel.onCopyFallback = { [weak self] in
            guard let self else { return }
            let text = self.viewModel.streamingText
            guard !text.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        }

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // Hop through the runloop so `NSApp.keyWindow` is settled before
            // we inspect it. Without this, keyWindow can still be us.
            DispatchQueue.main.async { self?.handleResignKey() }
        }

        becomeKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentLevel()
        }

        // React to live changes of the click-off behaviour setting. Covers
        // both direct `SettingsStore` setters and `@AppStorage` writes made
        // from `GeneralSettingsView` (the latter only emits the UserDefaults
        // notification).
        settingsCancellable = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyCurrentLevel()
            }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentLevel()
        }

        // Persist user-initiated resizes to the active preset, so dragging
        // the panel edges sticks across invocations. `didEndLiveResize`
        // fires only at the end of a mouse-drag resize and notably *not*
        // for programmatic `setFrame` calls — so our own positioning code
        // doesn't loop back through here.
        liveResizeEndObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.persistCurrentSizeToActivePreset() }
        }
    }

    deinit {
        if let o = resignKeyObserver { NotificationCenter.default.removeObserver(o) }
        if let o = becomeKeyObserver { NotificationCenter.default.removeObserver(o) }
        if let o = defaultsObserver { NotificationCenter.default.removeObserver(o) }
        if let o = liveResizeEndObserver { NotificationCenter.default.removeObserver(o) }
    }

    /// Present with the default preset.
    func present(with bundle: ContextBundle, autoSend: Bool) {
        present(with: bundle, preset: presetStore.defaultPreset, autoSendOverride: autoSend)
    }

    /// Present pre-bound to a specific preset (used by per-preset hotkeys and
    /// the status-bar submenu). When `autoSendOverride` is nil, the preset's
    /// own `autoSend` flag wins.
    func present(with bundle: ContextBundle, preset: PromptPreset?, autoSendOverride: Bool? = nil) {
        viewModel.reset(with: bundle, presetOverride: preset)
        PanelPositioner.position(
            panel: panel,
            placement: settings.panelPlacement,
            sizeOverride: resolvedPanelSize(for: preset)
        )
        // Set window level + activation policy *before* `NSApp.activate(...)`
        // — activating while still `.accessory` and only flipping to
        // `.regular` afterwards (e.g. inside the becomeKey observer) makes
        // the app appear in Cmd-Tab but never actually claim frontmost
        // status, so the OS-level MRU still has the source app at slot 1.
        applyPanelLevelForCurrentMode()
        applyActivationPolicyForCurrentMode(panelWillBecomeVisible: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        let shouldAutoSend: Bool
        if let override = autoSendOverride {
            shouldAutoSend = override && (preset?.autoSend ?? true)
        } else {
            shouldAutoSend = preset?.autoSend ?? false
        }
        if shouldAutoSend, viewModel.canSend {
            viewModel.send()
        }
    }

    /// Resolve the panel size for this invocation. Each `present(...)` call
    /// recomputes a definite size — either the preset's per-dimension value
    /// or the default — instead of inheriting the previous invocation's
    /// frame. Otherwise an Explain invocation right after an Ask one would
    /// keep Ask's 800-tall window.
    /// Saves the panel's current size back to the currently-active preset
    /// after a user-initiated resize. Rounded to whole points so the saved
    /// JSON stays clean. No-op if the size already matches what's stored
    /// (e.g. the user dragged a tiny amount that rounds to nothing) so we
    /// don't churn the prompts file or invalidate equality elsewhere.
    private func persistCurrentSizeToActivePreset() {
        guard panel.isVisible else { return }
        guard let presetID = viewModel.selectedPresetID,
              var preset = presetStore.preset(byID: presetID) else { return }

        let size = panel.frame.size
        let newWidth = Double(size.width.rounded())
        let newHeight = Double(size.height.rounded())

        if preset.panelWidth == newWidth && preset.panelHeight == newHeight { return }
        preset.panelWidth = newWidth
        preset.panelHeight = newHeight
        presetStore.update(preset)
    }

    private func resolvedPanelSize(for preset: PromptPreset?) -> NSSize {
        let w = preset?.panelWidth ?? Double(PanelPositioner.defaultSize.width)
        let h = preset?.panelHeight ?? Double(PanelPositioner.defaultSize.height)
        return NSSize(width: max(200, w), height: max(160, h))
    }

    func close() {
        viewModel.cancelStreaming()
        panel.orderOut(nil)
        restoreAccessoryPolicyIfAppropriate()
    }

    func showPermissionsCheck() {
        let prompted = AccessibilityCapture.requestTrust()
        let alert = NSAlert()
        alert.messageText = prompted
            ? "Accessibility access is enabled."
            : "Accessibility access is required for the global hotkey."
        alert.informativeText = prompted
            ? "Squint can read selected text via the hotkey."
            : "You can still use the right-click Services action without it. Open System Settings → Privacy & Security → Accessibility to enable."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// True when the panel is currently visible in a mode that requires the
    /// app to remain `.regular` (currently: `Recede to background`). Lets
    /// `AppDelegate` skip the post-Settings revert to `.accessory` so the
    /// panel doesn't lose its Cmd-Tab entry while it's still alive.
    var requiresRegularActivationPolicy: Bool {
        guard panel.isVisible else { return false }
        switch settings.panelClickOffBehavior {
        case .sendToBack, .stayOnTop: return true
        case .closePanel:             return false
        }
    }

    // MARK: - Click-off behaviour

    /// React to live setting changes (and `didBecomeKey`) — only meaningful
    /// while the panel is visible; offscreen panels get their level + policy
    /// configured by `present(...)` directly.
    private func applyCurrentLevel() {
        guard panel.isVisible else { return }
        applyPanelLevelForCurrentMode()
        applyActivationPolicyForCurrentMode(panelWillBecomeVisible: false)
    }

    private func applyPanelLevelForCurrentMode() {
        switch settings.panelClickOffBehavior {
        case .stayOnTop, .closePanel:
            // `.closePanel` panels are still "on top" while they're alive —
            // we dismiss them on resignKey rather than letting them recede.
            panel.level = .floating
        case .sendToBack:
            panel.level = .normal
        }
    }

    /// Promote the app to `.regular` while a panel that's intended to
    /// outlive a click-off is alive (`Recede to background` and `Stay on
    /// top`), so it gets a Dock + Cmd-Tab entry and the user can always
    /// surface it again. `Close` stays `.accessory` because that panel
    /// dismisses itself on click-off and never needs to be re-fronted.
    /// Settings manages its own policy switch in `AppDelegate`.
    ///
    /// `panelWillBecomeVisible` lets `present(...)` apply the policy
    /// *before* the panel is actually visible — critical because
    /// `NSApp.activate(...)` must happen at the target policy or the app
    /// won't take the frontmost slot in the OS MRU.
    private func applyActivationPolicyForCurrentMode(panelWillBecomeVisible: Bool) {
        let shouldBeRegular: Bool
        if panelWillBecomeVisible || panel.isVisible {
            switch settings.panelClickOffBehavior {
            case .sendToBack, .stayOnTop: shouldBeRegular = true
            case .closePanel:             shouldBeRegular = false
            }
        } else {
            shouldBeRegular = false
        }

        if shouldBeRegular {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else {
            restoreAccessoryPolicyIfAppropriate()
        }
    }

    /// Drop back to `.accessory` when the panel is gone, unless the
    /// Settings window is open (which also requires `.regular`).
    private func restoreAccessoryPolicyIfAppropriate() {
        guard !SettingsWindowController.shared.isVisible else { return }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func handleResignKey() {
        guard panel.isVisible else { return }

        // If another window of our app (Settings, Onboarding, an alert) is
        // now key, never dismiss or recede — `NSApp.keyWindow` only returns
        // windows belonging to us, so a non-nil, non-panel value means a
        // sibling window took focus and the panel should coexist with it.
        if let key = NSApp.keyWindow, key !== panel { return }

        switch settings.panelClickOffBehavior {
        case .stayOnTop:
            return
        case .sendToBack:
            panel.level = .normal
        case .closePanel:
            close()
        }
    }
}
