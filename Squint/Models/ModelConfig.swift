import Foundation

struct ModelConfig: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var displayName: String
    var provider: ProviderKind
    var modelName: String
    var baseURL: URL
    var apiKeyReference: String
    var supportsVision: Bool
    var supportsStreaming: Bool
    var maxInputTokens: Int?
    /// Free-form value sent as `reasoning_effort` in the chat completions body
    /// when non-empty. OpenAI currently accepts "minimal", "low", "medium", "high".
    /// Leave empty / nil for non-reasoning models.
    var reasoningEffort: String?

    init(
        id: UUID = UUID(),
        displayName: String,
        provider: ProviderKind = .openAICompatible,
        modelName: String,
        baseURL: URL,
        apiKeyReference: String? = nil,
        supportsVision: Bool = false,
        supportsStreaming: Bool = true,
        maxInputTokens: Int? = nil,
        reasoningEffort: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.modelName = modelName
        self.baseURL = baseURL
        self.apiKeyReference = apiKeyReference ?? id.uuidString
        self.supportsVision = supportsVision
        self.supportsStreaming = supportsStreaming
        self.maxInputTokens = maxInputTokens
        self.reasoningEffort = reasoningEffort
    }
}
