import Foundation

/// Talks to any OpenAI Chat Completions-compatible endpoint:
/// OpenAI, OpenRouter, Ollama (`http://localhost:11434/v1`), LM Studio, etc.
final class OpenAICompatibleClient: LLMProvider {
    private let session: URLSession
    private let apiKeyProvider: (ModelConfig) -> String?

    init(
        session: URLSession = OpenAICompatibleClient.makeStreamingSession(),
        apiKeyProvider: @escaping (ModelConfig) -> String?
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    /// URLSession tuned for SSE: no URL cache, no buffering of chunked responses,
    /// and request timeouts that allow long-running streams.
    static func makeStreamingSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config)
    }

    // MARK: - Non-streaming

    func complete(request: LLMRequest) async throws -> LLMResponse {
        let urlRequest = try buildRequest(from: request, stream: false)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            try Self.validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            let text = decoded.choices.first?.message?.content ?? ""
            return LLMResponse(
                text: text,
                modelName: decoded.model ?? request.model.modelName,
                finishReason: decoded.choices.first?.finishReason
            )
        } catch let err as LLMError {
            throw err
        } catch {
            throw LLMError.transport(error)
        }
    }

    // MARK: - Streaming (SSE)

    func streamResponse(request: LLMRequest) async throws -> AsyncThrowingStream<LLMToken, Error> {
        let urlRequest = try buildRequest(from: request, stream: true)
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                let started = Date()
                AppLogger.shared.info("LLM stream request started: \(request.model.modelName)")
                do {
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    let headersAt = Date().timeIntervalSince(started)
                    AppLogger.shared.info(String(format: "LLM headers received in %.2fs", headersAt))

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw LLMError.http(status: http.statusCode, body: body)
                    }

                    var firstDeltaLogged = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { throw LLMError.cancelled }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            continuation.yield(.final)
                            continuation.finish()
                            return
                        }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
                           let delta = chunk.choices.first?.delta?.content, !delta.isEmpty {
                            if !firstDeltaLogged {
                                let firstAt = Date().timeIntervalSince(started)
                                AppLogger.shared.info(String(format: "LLM first delta in %.2fs", firstAt))
                                firstDeltaLogged = true
                            }
                            continuation.yield(LLMToken(delta: delta, isFinal: false))
                        }
                    }
                    continuation.yield(.final)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    private func buildRequest(from request: LLMRequest, stream: Bool) throws -> URLRequest {
        let endpoint = request.model.baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")

        if let key = apiKeyProvider(request.model), !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        } else if !Self.isLocalHost(request.model.baseURL) {
            throw LLMError.missingAPIKey
        }

        let perRequestEffort = request.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelEffort = request.model.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEffort = (perRequestEffort?.isEmpty == false) ? perRequestEffort : modelEffort
        let body = ChatCompletionBody(
            model: request.model.modelName,
            messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            stream: stream,
            temperature: request.temperature,
            maxTokens: request.maxTokens,
            reasoningEffort: (trimmedEffort?.isEmpty == false) ? trimmedEffort : nil
        )
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    private static func isLocalHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let body = String(data: data, encoding: .utf8) ?? ""
        throw LLMError.http(status: http.statusCode, body: body)
    }
}

// MARK: - Wire types

private struct ChatCompletionBody: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double?
    let maxTokens: Int?
    let reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let role: String?; let content: String? }
        let message: Message?
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case message; case finishReason = "finish_reason" }
    }
    let model: String?
    let choices: [Choice]
}

private struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case delta; case finishReason = "finish_reason" }
    }
    let choices: [Choice]
}
