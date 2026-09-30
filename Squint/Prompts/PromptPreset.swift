import Foundation

/// User-defined recipe for invoking the LLM. Mirrors `ModelConfig` in shape and
/// persistence pattern. The collection of presets is owned by `PromptPresetStore`.
///
/// The `systemPrompt` may reference template variables which are expanded at
/// invocation time by `PromptBuilder.expand(...)`:
///
/// - `{{selection}}`     – the captured selected text (or empty string if none)
/// - `{{userInput}}`     – text the user typed into the panel's instruction field
///                         (only meaningful when `requiresUserInput == true`)
/// - `{{app}}`           – frontmost app name at capture time (or empty)
/// - `{{windowTitle}}`   – frontmost window title at capture time (or empty)
/// - `{{date}}`          – ISO-8601 date at invocation time
struct PromptPreset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var systemPrompt: String

    var requiresUserInput: Bool
    var userInputPlaceholder: String?
    var requiresSelection: Bool
    var autoSend: Bool

    /// Whether this preset reads a selection (or pasteboard) at invocation
    /// time. When `false`, the app skips the capture pipeline entirely and
    /// the panel hides the selection preview — the preset is a pure
    /// "type a question, get an answer" wrapper around the LLM and the
    /// user-input field becomes the LLM's user message.
    ///
    /// Defaults to `true` so older on-disk catalogs decode unchanged.
    var capturesSelection: Bool

    // Optional overrides — nil falls back to model / user defaults.
    var preferredModelID: UUID?
    var temperature: Double?
    var maxOutputTokens: Int?
    /// Free-form value sent as `reasoning_effort` when non-empty. Common values
    /// are "minimal", "low", "medium", "high"; some providers accept bespoke
    /// values like "xhigh". Treat as opaque text.
    var reasoningEffort: String?

    var pinnedInDropdown: Bool
    var sortOrder: Int

    /// Optional per-preset panel size in points. When `nil`, falls back to
    /// `PanelPositioner.defaultSize`. Lets a "long-form translation" preset
    /// open a tall panel while a "quick lookup" preset stays compact.
    /// Both must be set to take effect — a single dimension is ignored.
    var panelWidth: Double?
    var panelHeight: Double?

    init(
        id: UUID = UUID(),
        name: String,
        systemPrompt: String,
        requiresUserInput: Bool = false,
        userInputPlaceholder: String? = nil,
        requiresSelection: Bool = false,
        autoSend: Bool = false,
        capturesSelection: Bool = true,
        preferredModelID: UUID? = nil,
        temperature: Double? = nil,
        maxOutputTokens: Int? = nil,
        reasoningEffort: String? = nil,
        pinnedInDropdown: Bool = true,
        sortOrder: Int = 0,
        panelWidth: Double? = nil,
        panelHeight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.requiresUserInput = requiresUserInput
        self.userInputPlaceholder = userInputPlaceholder
        self.requiresSelection = requiresSelection
        self.autoSend = autoSend
        self.capturesSelection = capturesSelection
        self.preferredModelID = preferredModelID
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.reasoningEffort = reasoningEffort
        self.pinnedInDropdown = pinnedInDropdown
        self.sortOrder = sortOrder
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
    }

    // Custom decoder so older on-disk catalogs (no `capturesSelection`
    // field) decode cleanly with the historical default of `true` —
    // every preset before this field existed captured selection.
    enum CodingKeys: String, CodingKey {
        case id, name, systemPrompt
        case requiresUserInput, userInputPlaceholder, requiresSelection, autoSend
        case capturesSelection
        case preferredModelID, temperature, maxOutputTokens, reasoningEffort
        case pinnedInDropdown, sortOrder
        case panelWidth, panelHeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        self.requiresUserInput = try c.decodeIfPresent(Bool.self, forKey: .requiresUserInput) ?? false
        self.userInputPlaceholder = try c.decodeIfPresent(String.self, forKey: .userInputPlaceholder)
        self.requiresSelection = try c.decodeIfPresent(Bool.self, forKey: .requiresSelection) ?? false
        self.autoSend = try c.decodeIfPresent(Bool.self, forKey: .autoSend) ?? false
        self.capturesSelection = try c.decodeIfPresent(Bool.self, forKey: .capturesSelection) ?? true
        self.preferredModelID = try c.decodeIfPresent(UUID.self, forKey: .preferredModelID)
        self.temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        self.maxOutputTokens = try c.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        self.reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        self.pinnedInDropdown = try c.decodeIfPresent(Bool.self, forKey: .pinnedInDropdown) ?? true
        self.sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        self.panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth)
        self.panelHeight = try c.decodeIfPresent(Double.self, forKey: .panelHeight)
    }

    // Explicit encode(to:) paired with the explicit init(from:) above.
    // Swift only auto-synthesises `encode(to:)` when init(from:) is also
    // synthesised — providing a custom init(from:) silently disables the
    // synthesis for any field whose CodingKey wasn't explicitly written,
    // which is how `capturesSelection` was getting dropped on save and
    // round-tripping back as the legacy default of `true` on next launch.
    // Every key in `CodingKeys` must be encoded here.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(systemPrompt, forKey: .systemPrompt)
        try c.encode(requiresUserInput, forKey: .requiresUserInput)
        try c.encodeIfPresent(userInputPlaceholder, forKey: .userInputPlaceholder)
        try c.encode(requiresSelection, forKey: .requiresSelection)
        try c.encode(autoSend, forKey: .autoSend)
        try c.encode(capturesSelection, forKey: .capturesSelection)
        try c.encodeIfPresent(preferredModelID, forKey: .preferredModelID)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        try c.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
        try c.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try c.encode(pinnedInDropdown, forKey: .pinnedInDropdown)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encodeIfPresent(panelWidth, forKey: .panelWidth)
        try c.encodeIfPresent(panelHeight, forKey: .panelHeight)
    }
}

extension PromptPreset {
    /// Stable identifier used to register a per-preset global hotkey via the
    /// KeyboardShortcuts library. Constant per preset so the binding survives
    /// rename.
    var hotkeyShortcutKey: String { "prompt.preset.\(id.uuidString)" }

    /// Shared copy for the "concise assistant over a selection" framing used
    /// by the `Explain` and `Ask` factory seeds. Kept as a single source of
    /// truth so edits stay consistent.
    fileprivate static let seedBaseSystemPrompt = """
    You are a concise, high-precision assistant embedded in a macOS text-selection utility. The user has selected text from another app and wants help without context switching. Explain the selected text. Be concise but not shallow. If it is technical, include the key mechanism or distinction. You always respond in English, translating any provided text first. If the selection is ambiguous, give the most likely interpretation. Don’t mention uncertainty or hedge - your best guess suffices. Don’t suggest follow-up clarifications or discussion since the user can only see your first message, not respond further.
    """

    /// Framing for the direct-prompt factory seed (`Prompt`). The user is
    /// typing into a small floating panel rather than aiming at a captured
    /// selection, so the prompt drops the "explain the selection" framing
    /// and emphasises a direct, single-shot answer. Same single-source-of-
    /// truth treatment as `seedBaseSystemPrompt` so a future tweak (tone,
    /// length budget, formatting rules) only needs to be made once.
    fileprivate static let seedDirectPromptSystemPrompt = """
    You are a concise, high-precision assistant embedded in a macOS menu-bar utility. The user has typed a question or instruction directly into a small floating panel and wants a focused, single-shot answer without context switching.

    - Answer directly. Lead with the answer; add only the supporting detail that genuinely helps. No preamble, no restating the question, no sign-off.
    - Be concise but not shallow. If the topic is technical, include the key mechanism, distinction, or worked example that makes the answer actually useful.
    - If the request is ambiguous, pick the most likely interpretation and answer it. Don’t ask clarifying questions — the user can only see your first message and cannot reply.
    - Don’t hedge, don’t apologise, don’t mention what you can’t do. Your best guess suffices.
    - Use Markdown for structure when it helps (lists, code fences, short headings) and skip it when prose reads better.
    - Respond in the language the user wrote in.
    """

    /// Presets installed on first launch when the prompts file is missing
    /// or empty. The user is free to rename, edit, or delete any of them;
    /// they are only (re)seeded when the catalog is completely empty.
    static var factorySeeds: [PromptPreset] {
        [
            PromptPreset(
                name: "Explain",
                systemPrompt: seedBaseSystemPrompt,
                requiresUserInput: false,
                requiresSelection: false,
                autoSend: true,
                pinnedInDropdown: true,
                sortOrder: 0
            ),
            PromptPreset(
                name: "Ask",
                systemPrompt: seedBaseSystemPrompt + "\n\nThe user has provided the following additional instruction or question: {{userInput}}",
                requiresUserInput: true,
                requiresSelection: false,
                autoSend: true,
                pinnedInDropdown: true,
                sortOrder: 1
            ),
            PromptPreset(
                name: "Prompt",
                systemPrompt: seedDirectPromptSystemPrompt,
                requiresUserInput: true,
                userInputPlaceholder: "Ask anything…",
                requiresSelection: false,
                autoSend: true,
                capturesSelection: false,
                pinnedInDropdown: true,
                sortOrder: 2
            )
        ]
    }

    /// Back-compat accessor for tests / callers that want "the default
    /// starter preset". Always returns the first factory seed ("Explain").
    static var seed: PromptPreset { factorySeeds[0] }
}
