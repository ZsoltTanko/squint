import Foundation

enum ManualInputCapture {
    static func emptyBundle() -> ContextBundle {
        ContextBundle.empty(method: .manualInput)
    }
}
