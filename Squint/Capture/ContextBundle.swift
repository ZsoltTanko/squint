import Foundation

struct ContextBundle: Codable, Equatable {
    var selectedText: String
    var frontmostAppName: String?
    var frontmostWindowTitle: String?
    var captureMethod: CaptureMethod
    var timestamp: Date

    static func empty(method: CaptureMethod = .manualInput) -> ContextBundle {
        ContextBundle(
            selectedText: "",
            frontmostAppName: nil,
            frontmostWindowTitle: nil,
            captureMethod: method,
            timestamp: Date()
        )
    }
}
