import AppKit

/// Borderless `NSPanel` styled as a slim, chromeless floating surface.
///
/// We deliberately drop `.titled` (and therefore the macOS traffic-light
/// buttons) — every vertical pixel matters in the panel and the title row
/// added nothing useful. The panel is still draggable by background and
/// resizable by edge, becomes key for typing/Esc, and renders its own
/// rounded ultra-thin-material chrome from SwiftUI.
final class FloatingPanel: NSPanel {
    /// Invoked when the panel receives `cancelOperation(_:)` (Esc, via the
    /// responder chain). Handled at the `NSPanel` level so Esc works
    /// regardless of which SwiftUI view inside the hosting view is focused —
    /// otherwise Esc only fires when a `TextField` is first responder.
    var onCancel: (() -> Void)?

    /// Invoked for ⌘C when nothing in the responder chain handles `copy:`
    /// natively (i.e. there's no active text selection). Lets us fall back
    /// to "copy the full response" while still letting a live text
    /// selection inside the Markdown view win the shortcut.
    var onCopyFallback: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // Intentionally NOT `.nonactivatingPanel`: a non-activating
            // panel never enters the system's active-app MRU list, so even
            // after `NSApp.activate(...)` brings us frontmost, Cmd+Tab's
            // default highlight (the previously-active app) skips past us.
            // Selection capture has already completed by the time the panel
            // is shown, so there's no reason to suppress activation.
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        // Transparent window so the SwiftUI rounded background shows through.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc key. We intentionally don't call `super` — the default
    /// implementation walks further up the responder chain and, finding
    /// nothing, produces the "not valid" system beep.
    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Intercept ⌘C. First try to dispatch `copy:` down the responder
    /// chain so a live text selection (e.g. inside the Markdown view)
    /// copies just the selected text. Only if nothing handles `copy:` do
    /// we fall back to copying the entire response.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "c" {
            if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                return true
            }
            onCopyFallback?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
