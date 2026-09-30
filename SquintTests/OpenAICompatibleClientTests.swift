import XCTest
@testable import Squint

final class OpenAICompatibleClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeModel() -> ModelConfig {
        ModelConfig(
            displayName: "Test",
            provider: .openAICompatible,
            modelName: "gpt-4o-mini",
            baseURL: URL(string: "https://example.test/v1")!,
            apiKeyReference: "test"
        )
    }

    override func tearDown() {
        super.tearDown()
        StubURLProtocol.handler = nil
    }

    func testCompleteParsesContent() async throws {
        StubURLProtocol.handler = { _ in
            let body = """
            {"model":"gpt-4o-mini","choices":[{"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}]}
            """
            let response = HTTPURLResponse(url: URL(string: "https://example.test/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }

        let client = OpenAICompatibleClient(session: makeSession(), apiKeyProvider: { _ in "key" })
        let req = LLMRequest(model: makeModel(), messages: [.init(role: .user, content: "hi")], temperature: nil, maxTokens: nil, stream: false)
        let res = try await client.complete(request: req)
        XCTAssertEqual(res.text, "Hello")
        XCTAssertEqual(res.finishReason, "stop")
    }

    func testStreamParsesSSEDeltas() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"He"}}]}

        data: {"choices":[{"delta":{"content":"llo"}}]}

        data: [DONE]

        """
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.test/v1/chat/completions")!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            return (response, Data(sse.utf8))
        }

        let client = OpenAICompatibleClient(session: makeSession(), apiKeyProvider: { _ in "key" })
        let req = LLMRequest(model: makeModel(), messages: [.init(role: .user, content: "hi")], temperature: nil, maxTokens: nil, stream: true)
        let stream = try await client.streamResponse(request: req)
        var collected = ""
        for try await token in stream {
            if !token.delta.isEmpty { collected += token.delta }
        }
        XCTAssertEqual(collected, "Hello")
    }

    func testMissingAPIKeyOnRemoteHostThrows() async {
        let client = OpenAICompatibleClient(session: makeSession(), apiKeyProvider: { _ in nil })
        let req = LLMRequest(model: makeModel(), messages: [], temperature: nil, maxTokens: nil, stream: false)
        do {
            _ = try await client.complete(request: req)
            XCTFail("Expected missingAPIKey")
        } catch let LLMError.missingAPIKey {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHTTPErrorSurfacesStatusAndBody() async {
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.test/v1/chat/completions")!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("unauthorized".utf8))
        }
        let client = OpenAICompatibleClient(session: makeSession(), apiKeyProvider: { _ in "key" })
        let req = LLMRequest(model: makeModel(), messages: [], temperature: nil, maxTokens: nil, stream: false)
        do {
            _ = try await client.complete(request: req)
            XCTFail("Expected http error")
        } catch let LLMError.http(status, body) {
            XCTAssertEqual(status, 401)
            XCTAssertTrue(body.contains("unauthorized"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - URLProtocol stub

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
