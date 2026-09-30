import AppKit

final class ServicesHandler: NSObject {
    static let shared = ServicesHandler()

    private weak var panelController: FloatingPanelController?
    private var captureService: SelectionCaptureService?
    private var settings: SettingsStore?
    private weak var presetStore: PromptPresetStore?

    func configure(
        panelController: FloatingPanelController,
        captureService: SelectionCaptureService,
        settings: SettingsStore,
        presetStore: PromptPresetStore
    ) {
        self.panelController = panelController
        self.captureService = captureService
        self.settings = settings
        self.presetStore = presetStore
    }

    /// Bound to the `NSMessage = askSquint` Service entry in Info.plist.
    @objc func askSquint(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        // Pull what we need off the pasteboard *here* (the system can
        // recycle it after this method returns). The MainActor hop below
        // owns the actual presentation and any preset-store reads.
        let pasteboardText = pasteboard.string(forType: .string) ?? ""
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let timestamp = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Services hands us the user's selection. If the default preset
            // is a direct-prompt one (`capturesSelection == false`), discard
            // the selection so the panel stays in its declared mode rather
            // than surfacing a selection the preset will never use.
            let defaultCapturesSelection = self.presetStore?.defaultPreset?.capturesSelection ?? true
            let bundle: ContextBundle
            if defaultCapturesSelection {
                bundle = ContextBundle(
                    selectedText: pasteboardText,
                    frontmostAppName: appName,
                    frontmostWindowTitle: nil,
                    captureMethod: .servicesInput,
                    timestamp: timestamp
                )
            } else {
                bundle = .empty()
            }
            let autoSend = self.settings?.autoSendOnInvocation ?? false
            NSApp.activate(ignoringOtherApps: true)
            self.panelController?.present(with: bundle, autoSend: autoSend)
        }
    }
}
