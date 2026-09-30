import Foundation

enum CaptureMethod: String, Codable {
    case servicesInput
    case accessibility
    case clipboardCurrent
    case clipboardFallback
    case manualInput
}
