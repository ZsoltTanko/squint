import AppKit
import ApplicationServices

enum AccessibilityCapture {
    /// Returns true when this process is trusted for the Accessibility APIs.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user, opening System Settings if needed.
    @discardableResult
    static func requestTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Reads the focused element's selected text from the frontmost app, if any.
    /// Tries the focused UI element first, then the focused window, then a shallow
    /// descendant walk — many apps don't expose `kAXSelectedTextAttribute` on the
    /// element that holds the keyboard focus.
    static func selectedText() -> String? {
        guard isTrusted else { return nil }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        if let focused = copyAttribute(axApp, kAXFocusedUIElementAttribute),
           CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let element = focused as! AXUIElement // safe: type-checked above
            if let text = readSelectedText(element) { return text }
            if let text = walkForSelectedText(element, depth: 0, maxDepth: 6) { return text }
        }

        if let window = copyAttribute(axApp, kAXFocusedWindowAttribute),
           CFGetTypeID(window) == AXUIElementGetTypeID() {
            let element = window as! AXUIElement // safe: type-checked above
            if let text = walkForSelectedText(element, depth: 0, maxDepth: 6) { return text }
        }

        return nil
    }

    private static func copyAttribute(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value
    }

    private static func readSelectedText(_ element: AXUIElement) -> String? {
        if let value = copyAttribute(element, kAXSelectedTextAttribute), let str = value as? String, !str.isEmpty {
            return str
        }
        return nil
    }

    /// Bounded BFS — defends against pathological AX trees.
    private static func walkForSelectedText(_ root: AXUIElement, depth: Int, maxDepth: Int) -> String? {
        if depth > maxDepth { return nil }
        if let text = readSelectedText(root) { return text }
        guard let children = copyAttribute(root, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children {
            if let text = walkForSelectedText(child, depth: depth + 1, maxDepth: maxDepth) { return text }
        }
        return nil
    }

    /// Best-effort window title for the focused window of the frontmost app.
    static func frontmostWindowTitle() -> String? {
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = copyAttribute(axApp, kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let element = window as! AXUIElement // safe: type-checked above
        return copyAttribute(element, kAXTitleAttribute) as? String
    }
}
