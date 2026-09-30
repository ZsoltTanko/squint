import AppKit
import Carbon.HIToolbox

/// Opt-in capture path: stash pasteboard, simulate Cmd+C, read result, restore pasteboard.
enum ClipboardFallbackCapture {
    static func capture(restore: Bool) async -> String? {
        let pb = NSPasteboard.general
        let saved: [NSPasteboard.PasteboardType: Data] = restore ? snapshot(pb) : [:]
        let beforeCount = pb.changeCount

        sendCommandC()

        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if pb.changeCount != beforeCount { break }
        }

        let captured = pb.string(forType: .string)

        if restore {
            pb.clearContents()
            for (type, data) in saved {
                pb.setData(data, forType: type)
            }
        }

        guard let s = captured, !s.isEmpty else { return nil }
        return s
    }

    private static func snapshot(_ pb: NSPasteboard) -> [NSPasteboard.PasteboardType: Data] {
        var result: [NSPasteboard.PasteboardType: Data] = [:]
        for type in pb.types ?? [] {
            if let data = pb.data(forType: type) {
                result[type] = data
            }
        }
        return result
    }

    private static func sendCommandC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey = CGKeyCode(kVK_ANSI_C)
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
