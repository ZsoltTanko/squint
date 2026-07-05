import Foundation
import Combine

@MainActor
final class PanelViewModel: ObservableObject {
    @Published var bundle: ContextBundle = .empty()
    @Published var manualSelectedText: String = ""
    @Published var selectedPresetID: UUID?
    @Published var selectedModelID: UUID?
    @Published var userInput: String = ""
    @Published var followUpInput: String = ""
    /// Whether the follow-up bar is visible. Lifted out of `PanelView`'s
    /// local `@State` so panel-level Esc handling (in `FloatingPanel`) can
    /// collapse the follow-up bar before closing the panel.
    @Published var isFollowUpOpen: Bool = false
    /// Changes on every `reset(...)`. Views observe this with `.onChange`
    /// to trigger per-invocation side effects (e.g. auto-focusing the
    /// preset's user-input field) without needing a stable bundle ID.
    @Published private(set) var invocationToken: UUID = UUID()

    @Published private(set) var conversation: [ChatMessage] = []
    @Published private(set) var streamingText: String = ""
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastResolution: PromptResolution?

    let modelStore: ModelStore
    let presetStore: PromptPresetStore
    let settings: SettingsStore
    private let registry: ProviderRegistry
    private let promptBuilder = PromptBuilder()

    private var streamTask: Task<Void, Never>?

    init(modelStore: ModelStore, presetStore: PromptPresetStore, registry: ProviderRegistry, settings: SettingsStore) {
        self.modelStore = modelStore
        self.presetStore = presetStore
        self.registry = registry
        self.settings = settings
        self.selectedPresetID = presetStore.defaultPreset?.id
        self.selectedModelID = effectiveModel(for: presetStore.defaultPreset)?.id
    }

    var effectiveSelectedText: String {
        bundle.selectedText.isEmpty ? manualSelectedText : bundle.selectedText
    }

    /// One display row of the panel's transcript.
    struct ConversationTurn: Identifiable, Equatable {
        enum Kind: Equatable {
            case user
            case assistant
        }

        let id: Int
        let kind: Kind
        let text: String
    }

    /// The transcript the panel renders: every exchange so far, not just the
    /// latest response. Derived from `conversation` (the LLM-context source
    /// of truth) plus the in-flight `streamingText`, so the view never has
    /// to reconcile the two itself.
    ///
    /// The system message and the *first* user message are skipped — the
    /// first user message is the captured selection (or the preset's input
    /// field), which is already visible in the panel chrome above the
    /// response area; repeating it in the transcript would be noise.
    /// Follow-up questions *are* included.
    var conversationTurns: [ConversationTurn] {
        var turns: [ConversationTurn] = []
        var seenFirstUserMessage = false
        for (index, message) in conversation.enumerated() {
            switch message.role {
            case .system:
                continue
            case .user:
                if !seenFirstUserMessage {
                    seenFirstUserMessage = true
                    continue
                }
                turns.append(ConversationTurn(id: index, kind: .user, text: message.content))
            case .assistant:
                turns.append(ConversationTurn(id: index, kind: .assistant, text: message.content))
            }
        }
        if isStreaming, !streamingText.isEmpty {
            // In-flight response. Its id is the conversation index the
            // assistant message will occupy once the stream completes, so
            // SwiftUI keeps the same row identity across the transition.
            turns.append(ConversationTurn(id: conversation.count, kind: .assistant, text: streamingText))
        } else if turns.isEmpty, !streamingText.isEmpty {
            // Restored history entry: `applyHistoryEntry` clears
            // `conversation` but keeps the recorded response in
            // `streamingText`.
            turns.append(ConversationTurn(id: 0, kind: .assistant, text: streamingText))
        }
        return turns
    }

    /// ID of the most recent follow-up question row, used by the view to
    /// scroll a just-sent follow-up into view.
    var latestUserTurnID: Int? {
        conversationTurns.last(where: { $0.kind == .user })?.id
    }

    var selectedPreset: PromptPreset? {
        presetStore.preset(byID: selectedPresetID) ?? presetStore.defaultPreset
    }

    var selectedModel: ModelConfig? {
        if let id = selectedModelID, let m = modelStore.models.first(where: { $0.id == id }) { return m }
        return modelStore.defaultModel
    }

    var canSend: Bool {
        guard let preset = selectedPreset, selectedModel != nil else { return false }
        if preset.requiresSelection, effectiveSelectedText.isEmpty { return false }
        if preset.requiresUserInput, userInput.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        // If neither selection nor user input is required, still need *something*
        // to send to the model (avoid empty user message + empty system).
        if effectiveSelectedText.isEmpty
            && userInput.trimmingCharacters(in: .whitespaces).isEmpty
            && preset.systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        return true
    }

    func reset(with bundle: ContextBundle, presetOverride: PromptPreset? = nil) {
        cancelStreaming()
        self.bundle = bundle
        self.manualSelectedText = ""
        let preset = presetOverride ?? presetStore.defaultPreset
        self.selectedPresetID = preset?.id
        self.selectedModelID = effectiveModel(for: preset)?.id
        self.userInput = ""
        self.followUpInput = ""
        self.isFollowUpOpen = false
        self.conversation = []
        self.streamingText = ""
        self.lastError = nil
        self.lastResolution = nil
        self.invocationToken = UUID()
    }

    /// When the user picks a different preset in the panel, honor that preset's
    /// preferred model (if any) — otherwise fall back to whatever was selected
    /// before, then to the global default.
    ///
    /// Also clears any captured selection when switching *into* a direct-prompt
    /// preset (`capturesSelection == false`). Otherwise the selection captured
    /// for the previously-active capturing preset would linger in the bundle
    /// — invisible because the panel hides the preview row in this mode, but
    /// `PromptBuilder.expand` would still substitute it into `{{selection}}`
    /// and an inquisitive author would be surprised to see it. Keeping the
    /// data and the UI coherent here means direct-prompt invocations always
    /// look the same regardless of how the panel was originally opened.
    func onPresetChanged() {
        if let preset = selectedPreset {
            if let modelID = preset.preferredModelID,
               modelStore.models.contains(where: { $0.id == modelID }) {
                selectedModelID = modelID
            }
            if !preset.capturesSelection {
                bundle.selectedText = ""
                manualSelectedText = ""
            }
        }
    }

    func send() {
        guard let preset = selectedPreset else {
            lastError = "No prompt preset configured."
            return
        }
        guard let model = effectiveModel(for: preset) else {
            lastError = "No model configured. Open Settings to add one."
            return
        }
        let activeBundle = currentBundleForSend()
        let (messages, resolution) = promptBuilder.resolve(
            preset: preset,
            bundle: activeBundle,
            userInput: userInput,
            model: model
        )
        conversation = messages
        lastResolution = resolution
        runRequest(model: model, preset: preset)
    }

    func sendFollowUp() {
        let trimmed = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let preset = selectedPreset, let model = effectiveModel(for: preset) else { return }
        if conversation.isEmpty {
            let (messages, resolution) = promptBuilder.resolve(
                preset: preset,
                bundle: currentBundleForSend(),
                userInput: userInput,
                model: model
            )
            conversation = messages
            lastResolution = resolution
        }
        conversation.append(ChatMessage(role: .user, content: trimmed))
        followUpInput = ""
        runRequest(model: model, preset: preset)
    }

    /// Restore the panel to the exact state it was in for a previous
    /// invocation: the captured selection, the preset's user-input field,
    /// and the streamed response — without re-running the LLM. The user
    /// can still hit ⌘↵ to re-ask, which will produce a fresh response.
    func applyHistoryEntry(_ entry: QueryHistoryEntry) {
        cancelStreaming()
        bundle.selectedText = entry.text
        manualSelectedText = ""
        userInput = entry.userInput
        streamingText = entry.responseText
        lastError = nil
        conversation = []
        // Restore the model used for the original invocation when it's
        // still in the catalog. If it was deleted since, leave the
        // current selection alone rather than nilling it out.
        if let modelID = entry.modelID,
           modelStore.models.contains(where: { $0.id == modelID }) {
            selectedModelID = modelID
        }
    }

    func closeFollowUp() {
        isFollowUpOpen = false
        followUpInput = ""
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func effectiveModel(for preset: PromptPreset?) -> ModelConfig? {
        if let preset, let id = preset.preferredModelID,
           let model = modelStore.models.first(where: { $0.id == id }) {
            return model
        }
        if let id = selectedModelID, let m = modelStore.models.first(where: { $0.id == id }) {
            return m
        }
        return modelStore.defaultModel
    }

    private func currentBundleForSend() -> ContextBundle {
        if !bundle.selectedText.isEmpty { return bundle }
        var copy = bundle
        copy.selectedText = manualSelectedText
        return copy
    }

    private func runRequest(model: ModelConfig, preset: PromptPreset) {
        cancelStreaming()
        lastError = nil
        streamingText = ""
        isStreaming = true

        let request = LLMRequest(
            model: model,
            messages: conversation,
            temperature: preset.temperature,
            maxTokens: preset.maxOutputTokens,
            reasoningEffort: preset.reasoningEffort,
            stream: settings.streamResponses && model.supportsStreaming
        )
        let provider = registry.provider(for: model)

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                if request.stream {
                    let stream = try await provider.streamResponse(request: request)
                    for try await token in stream {
                        if Task.isCancelled { break }
                        if !token.delta.isEmpty {
                            await MainActor.run { self.streamingText += token.delta }
                        }
                    }
                } else {
                    let response = try await provider.complete(request: request)
                    await MainActor.run { self.streamingText = response.text }
                }

                await MainActor.run {
                    self.conversation.append(ChatMessage(role: .assistant, content: self.streamingText))
                    self.isStreaming = false
                    self.recordHistory(model: model, preset: preset)
                    QueryHistoryStore.shared.record(
                        text: self.effectiveSelectedText,
                        userInput: self.userInput,
                        responseText: self.streamingText,
                        modelID: model.id,
                        presetID: preset.id,
                        limit: self.settings.queryHistoryLimit
                    )
                }
            } catch is CancellationError {
                await MainActor.run { self.isStreaming = false }
            } catch {
                await MainActor.run {
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    self.isStreaming = false
                }
            }
        }
    }

    private func recordHistory(model: ModelConfig, preset: PromptPreset) {
        guard settings.historyEnabled, !streamingText.isEmpty else { return }
        guard let resolution = lastResolution else { return }
        let item = LocalHistoryItem(
            timestamp: Date(),
            selectedText: effectiveSelectedText,
            userInput: userInput,
            responseText: streamingText,
            appName: bundle.frontmostAppName,
            windowTitle: bundle.frontmostWindowTitle,
            resolution: resolution
        )
        LocalHistoryStore.shared.append(item)
    }
}
