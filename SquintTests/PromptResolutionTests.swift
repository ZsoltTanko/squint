import XCTest
@testable import Squint

final class PromptResolutionTests: XCTestCase {
    private let model = ModelConfig(
        displayName: "Test",
        modelName: "test-model",
        baseURL: URL(string: "https://api.example.com/v1")!
    )

    func testExpandsKnownVariables() {
        let out = PromptBuilder.expand(
            template: "Hi {{app}}, look at {{selection}} ({{userInput}})",
            selection: "the cat",
            userInput: "explain",
            app: "Notes",
            windowTitle: ""
        )
        XCTAssertEqual(out, "Hi Notes, look at the cat (explain)")
    }

    func testLeavesUnknownVariablesIntact() {
        let out = PromptBuilder.expand(
            template: "Hello {{nope}}",
            selection: "", userInput: "", app: "", windowTitle: ""
        )
        XCTAssertEqual(out, "Hello {{nope}}")
    }

    func testUnknownVariablesIsReported() {
        let unknowns = PromptBuilder.unknownVariables(in: "{{selection}} {{nope}} {{also_bad}} {{app}}")
        XCTAssertEqual(Set(unknowns), Set(["nope", "also_bad"]))
    }

    func testResolveProducesSnapshotAndMessages() {
        let preset = PromptPreset(
            name: "Translate",
            systemPrompt: "Translate to {{userInput}}",
            requiresUserInput: true,
            temperature: 0.2,
            maxOutputTokens: 256,
            reasoningEffort: "low"
        )
        let bundle = ContextBundle(
            selectedText: "Hello",
            frontmostAppName: "Mail",
            frontmostWindowTitle: nil,
            captureMethod: .accessibility,
            timestamp: Date()
        )
        let (messages, resolution) = PromptBuilder().resolve(
            preset: preset,
            bundle: bundle,
            userInput: "French",
            model: model
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[0].content, "Translate to French")
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[1].content, "Hello")
        XCTAssertEqual(resolution.systemPrompt, "Translate to French")
        XCTAssertEqual(resolution.userMessage, "Hello")
        XCTAssertEqual(resolution.temperature, 0.2)
        XCTAssertEqual(resolution.maxOutputTokens, 256)
        XCTAssertEqual(resolution.reasoningEffort, "low")
        XCTAssertEqual(resolution.modelDisplayName, "Test")
    }

    func testDirectPromptUsesUserInputAsUserMessage() {
        // Direct-prompt presets (capturesSelection == false) treat the
        // user-typed input as the LLM's user message — there is no
        // selection involved at all.
        let preset = PromptPreset(
            name: "Prompt",
            systemPrompt: "You are a helpful assistant.",
            requiresUserInput: true,
            autoSend: true,
            capturesSelection: false
        )
        let bundle = ContextBundle.empty()
        let (messages, resolution) = PromptBuilder().resolve(
            preset: preset,
            bundle: bundle,
            userInput: "What is the capital of Hungary?",
            model: model
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[0].content, "You are a helpful assistant.")
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[1].content, "What is the capital of Hungary?")
        XCTAssertEqual(resolution.userMessage, "What is the capital of Hungary?")
    }

    func testCapturesSelectionRoundTripsThroughEncodeAndDecode() throws {
        // Regression guard: a custom `init(from:)` disables Swift's
        // synthesis of `encode(to:)`, which previously dropped the
        // `capturesSelection` field on save. Round-trip must preserve it
        // for both `true` and `false`.
        for original in [true, false] {
            let preset = PromptPreset(
                name: "RT",
                systemPrompt: "S",
                requiresUserInput: true,
                capturesSelection: original
            )
            let data = try JSONEncoder().encode(preset)
            // Field must appear in the encoded payload — not just survive a
            // same-process round trip via property defaults.
            let asString = String(data: data, encoding: .utf8) ?? ""
            XCTAssertTrue(asString.contains("\"capturesSelection\""),
                          "Encoded JSON must contain capturesSelection: \(asString)")
            let decoded = try JSONDecoder().decode(PromptPreset.self, from: data)
            XCTAssertEqual(decoded.capturesSelection, original)
        }
    }

    func testCapturesSelectionDefaultsTrueWhenDecodingOlderJSON() throws {
        // Older on-disk catalogs (predating the field) must decode with
        // `capturesSelection == true` so existing presets keep capturing.
        let json = #"""
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "systemPrompt": "Hi",
          "requiresUserInput": false,
          "requiresSelection": false,
          "autoSend": true,
          "pinnedInDropdown": true,
          "sortOrder": 0
        }
        """#.data(using: .utf8)!
        let preset = try JSONDecoder().decode(PromptPreset.self, from: json)
        XCTAssertTrue(preset.capturesSelection)
    }

    func testEffectiveReasoningPrefersPresetThenModel() {
        var modelCopy = model; modelCopy.reasoningEffort = "high"
        var preset = PromptPreset(name: "X", systemPrompt: "Y")
        XCTAssertEqual(PromptBuilder.effectiveReasoningEffort(preset: preset, model: modelCopy), "high")
        preset.reasoningEffort = "minimal"
        XCTAssertEqual(PromptBuilder.effectiveReasoningEffort(preset: preset, model: modelCopy), "minimal")
        preset.reasoningEffort = "  "
        XCTAssertEqual(PromptBuilder.effectiveReasoningEffort(preset: preset, model: modelCopy), "high")
    }
}
