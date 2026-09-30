import Foundation

/// Snapshot of how a prompt was rendered for a particular invocation. Stored in
/// history so that re-running an old conversation always shows what actually
/// went over the wire, even after the user later edited the preset.
struct PromptResolution: Equatable {
    var presetID: UUID?
    var presetName: String
    var systemPrompt: String
    var userMessage: String
    var modelID: UUID
    var modelDisplayName: String
    var temperature: Double?
    var maxOutputTokens: Int?
    var reasoningEffort: String?
}

/// Builds the messages, model, and inference parameters for a single LLM call
/// from a `PromptPreset`, captured selection, and optional user instruction.
///
/// Contract:
/// - **system message** = preset's `systemPrompt` with template variables expanded.
/// - **user message** =
///     - the captured selected text when `preset.capturesSelection == true`
///       (the canonical "lens over selection" mode), or
///     - the user-typed input when `preset.capturesSelection == false`
///       (the direct-prompt mode where the panel has no selection at all).
struct PromptBuilder {
    func resolve(
        preset: PromptPreset,
        bundle: ContextBundle,
        userInput: String,
        model: ModelConfig
    ) -> (messages: [ChatMessage], resolution: PromptResolution) {
        let system = Self.expand(
            template: preset.systemPrompt,
            selection: bundle.selectedText,
            userInput: userInput,
            app: bundle.frontmostAppName ?? "",
            windowTitle: bundle.frontmostWindowTitle ?? ""
        )
        let user = preset.capturesSelection ? bundle.selectedText : userInput

        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: system),
            ChatMessage(role: .user, content: user)
        ]

        let resolution = PromptResolution(
            presetID: preset.id,
            presetName: preset.name,
            systemPrompt: system,
            userMessage: user,
            modelID: model.id,
            modelDisplayName: model.displayName,
            temperature: preset.temperature,
            maxOutputTokens: preset.maxOutputTokens,
            reasoningEffort: Self.effectiveReasoningEffort(preset: preset, model: model)
        )

        return (messages, resolution)
    }

    /// Resolved reasoning effort: preset overrides model. Empty strings count
    /// as "unset" so users can clear the inherited value.
    static func effectiveReasoningEffort(preset: PromptPreset, model: ModelConfig) -> String? {
        let presetTrim = preset.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let p = presetTrim, !p.isEmpty { return p }
        let modelTrim = model.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = modelTrim, !m.isEmpty { return m }
        return nil
    }

    /// Variable substitution. Unknown `{{vars}}` are left as-is at runtime so
    /// users can spot them in the response and fix the preset; the editor's
    /// preview pane warns about them.
    static func expand(
        template: String,
        selection: String,
        userInput: String,
        app: String,
        windowTitle: String,
        date: Date = Date()
    ) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let dateString = isoFormatter.string(from: date)

        let substitutions: [String: String] = [
            "selection": selection,
            "userInput": userInput,
            "app": app,
            "windowTitle": windowTitle,
            "date": dateString
        ]

        var out = template
        for (key, value) in substitutions {
            out = out.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return out
    }

    /// Returns the names of any `{{var}}` tokens in `template` that don't map to
    /// a known substitution. Used by the editor preview pane to warn authors.
    static func unknownVariables(in template: String) -> [String] {
        let known: Set<String> = ["selection", "userInput", "app", "windowTitle", "date"]
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}"#) else {
            return []
        }
        let ns = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        var seen: Set<String> = []
        var out: [String] = []
        for m in matches where m.numberOfRanges >= 2 {
            let name = ns.substring(with: m.range(at: 1))
            if !known.contains(name), !seen.contains(name) {
                seen.insert(name)
                out.append(name)
            }
        }
        return out
    }

    func appendFollowUp(messages: [ChatMessage], userInput: String) -> [ChatMessage] {
        messages + [ChatMessage(role: .user, content: userInput)]
    }
}
