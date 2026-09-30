import Foundation

protocol LLMProvider {
    func streamResponse(request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, Error>
    func complete(request: LLMRequest) async throws -> LLMResponse
}
