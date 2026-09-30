import Foundation

enum LLMError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
    case transport(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No API key configured for the selected model."
        case .invalidURL: return "The model's base URL is invalid."
        case .http(let status, let body):
            let snippet = body.prefix(300)
            return "Request failed (\(status)): \(snippet)"
        case .decoding(let msg): return "Could not decode response: \(msg)"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        case .cancelled: return "Request cancelled."
        }
    }
}
