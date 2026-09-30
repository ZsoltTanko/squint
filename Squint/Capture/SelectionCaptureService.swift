import AppKit

/// Orchestrates the capture strategies in priority order for the hotkey path.
/// The Services path bypasses this and constructs its own bundle directly.
final class SelectionCaptureService {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Capture priority:
    /// 1. **Accessibility.** Cheap, non-invasive, works in AppKit/Cocoa apps
    ///    that expose `kAXSelectedTextAttribute` (Notes, TextEdit, …).
    /// 2. **Clipboard fallback (Cmd+C simulation).** When enabled. The only path
    ///    that can capture a *highlighted* selection in apps where AX fails
    ///    (Chrome, Cursor, Slack, Electron). Saves and restores the pasteboard.
    /// 3. **Current clipboard contents.** Read-only, non-destructive. Used when
    ///    nothing is highlighted (or Cmd+C simulation is disabled / failed) so
    ///    "I want to ask about what I just copied" still works.
    /// 4. **Manual input.** Empty bundle; the panel asks the user to paste.
    func captureForHotkey() async -> ContextBundle {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName
        let windowTitle = AccessibilityCapture.frontmostWindowTitle()

        if let text = AccessibilityCapture.selectedText() {
            return ContextBundle(
                selectedText: text,
                frontmostAppName: appName,
                frontmostWindowTitle: windowTitle,
                captureMethod: .accessibility,
                timestamp: Date()
            )
        }

        // Try Cmd+C simulation BEFORE reading the clipboard as-is, so that an
        // active selection in apps with no AX text wins over whatever stale
        // value is currently on the clipboard.
        if settings.clipboardFallbackEnabled {
            if let text = await ClipboardFallbackCapture.capture(restore: settings.restoreClipboardAfterCapture) {
                return ContextBundle(
                    selectedText: text,
                    frontmostAppName: appName,
                    frontmostWindowTitle: windowTitle,
                    captureMethod: .clipboardFallback,
                    timestamp: Date()
                )
            }
        }

        // Non-destructive fallback: use the current clipboard contents as input.
        if let pbText = NSPasteboard.general.string(forType: .string),
           !pbText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ContextBundle(
                selectedText: pbText,
                frontmostAppName: appName,
                frontmostWindowTitle: windowTitle,
                captureMethod: .clipboardCurrent,
                timestamp: Date()
            )
        }

        return ContextBundle(
            selectedText: "",
            frontmostAppName: appName,
            frontmostWindowTitle: windowTitle,
            captureMethod: .manualInput,
            timestamp: Date()
        )
    }
}
