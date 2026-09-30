import Foundation

struct LLMToken {
    var delta: String
    var isFinal: Bool

    static let final = LLMToken(delta: "", isFinal: true)
}
