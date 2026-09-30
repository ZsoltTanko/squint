import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible: return "OpenAI-compatible"
        }
    }
}
