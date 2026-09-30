import Foundation

struct ChatMessage: Codable, Equatable {
    let role: Role
    let content: String
}

enum Role: String, Codable {
    case system
    case user
    case assistant
}

struct LLMRequest {
    var model: ModelConfig
    var messages: [ChatMessage]
    var temperature: Double?
    var maxTokens: Int?
    /// Per-request override for the model's reasoning effort. When non-nil and
    /// non-empty, overrides `model.reasoningEffort`. When nil, the model's own
    /// value is used.
    var reasoningEffort: String?
    var stream: Bool
}
