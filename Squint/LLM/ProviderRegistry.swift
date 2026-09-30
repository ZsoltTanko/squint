import Foundation

final class ProviderRegistry {
    private let modelStore: ModelStore
    private let keychain: KeychainStore

    init(modelStore: ModelStore, keychain: KeychainStore = .shared) {
        self.modelStore = modelStore
        self.keychain = keychain
    }

    func provider(for model: ModelConfig) -> LLMProvider {
        switch model.provider {
        case .openAICompatible:
            return OpenAICompatibleClient { [keychain] cfg in
                keychain.readAPIKey(account: cfg.apiKeyReference)
            }
        }
    }
}
