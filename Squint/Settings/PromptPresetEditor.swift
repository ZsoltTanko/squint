import SwiftUI
import KeyboardShortcuts

struct PromptPresetEditor: View {
    let initial: PromptPreset
    let isNew: Bool
    @ObservedObject var modelStore: ModelStore
    let conflictNamesFor: (UUID, KeyboardShortcuts.Shortcut?) -> [String]
    let onSave: (PromptPreset) -> Void
    let onCancel: () -> Void

    @State private var draft: PromptPreset
    @State private var temperatureText: String
    @State private var maxTokensText: String
    @State private var panelWidthText: String
    @State private var panelHeightText: String
    @State private var sampleSelection: String = "The mitochondrion is the powerhouse of the cell."
    @State private var sampleUserInput: String = ""
    @State private var showAdvanced: Bool = false

    init(
        initial: PromptPreset,
        isNew: Bool,
        modelStore: ModelStore,
        conflictNamesFor: @escaping (UUID, KeyboardShortcuts.Shortcut?) -> [String],
        onSave: @escaping (PromptPreset) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initial = initial
        self.isNew = isNew
        self.modelStore = modelStore
        self.conflictNamesFor = conflictNamesFor
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: initial)
        self._temperatureText = State(initialValue: initial.temperature.map { String($0) } ?? "")
        self._maxTokensText = State(initialValue: initial.maxOutputTokens.map { String($0) } ?? "")
        self._panelWidthText = State(initialValue: initial.panelWidth.map { String(Int($0)) } ?? "")
        self._panelHeightText = State(initialValue: initial.panelHeight.map { String(Int($0)) } ?? "")
    }

    private var hotkeyName: KeyboardShortcuts.Name {
        KeyboardShortcuts.Name(draft.hotkeyShortcutKey)
    }

    var body: some View {
        HSplitView {
            editorForm
                .frame(minWidth: 380, idealWidth: 440)
            previewPane
                .frame(minWidth: 320, idealWidth: 360)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 620)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(isNew ? "Add" : "Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                        || draft.systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .background(.bar)
        }
    }

    private var editorForm: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $draft.name)
            }

            Section("System prompt") {
                TextEditor(text: $draft.systemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                Text("Variables: \(known: "{{selection}}, {{userInput}}, {{app}}, {{windowTitle}}, {{date}}")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Capture selected text on invocation", isOn: $draft.capturesSelection)
                Text("When off, the panel skips selection capture entirely and is a pure direct-prompt wrapper around the LLM — the user-input field becomes the LLM's user message. Pair with “Requires user input” so the panel waits for the user to type.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("Requires user input", isOn: $draft.requiresUserInput)
                if draft.requiresUserInput {
                    TextField(
                        "Input placeholder",
                        text: Binding(
                            get: { draft.userInputPlaceholder ?? "" },
                            set: { draft.userInputPlaceholder = $0.isEmpty ? nil : $0 }
                        ),
                        prompt: Text("e.g. Target language, Question…")
                    )
                }
                Toggle("Requires selection", isOn: $draft.requiresSelection)
                    .disabled(!draft.capturesSelection)
                Toggle("Auto-send on invocation", isOn: $draft.autoSend)
                Toggle("Show in panel dropdown", isOn: $draft.pinnedInDropdown)
            }

            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Global hotkey", name: hotkeyName)
                let conflicts = conflictNamesFor(draft.id, KeyboardShortcuts.getShortcut(for: hotkeyName))
                if !conflicts.isEmpty {
                    Label("Conflicts with: \(conflicts.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Panel size") {
                HStack {
                    TextField("Width", text: $panelWidthText, prompt: Text("Default"))
                    TextField("Height", text: $panelHeightText, prompt: Text("Default"))
                }
                Text("Per-preset width × height in points. Leave a field blank to use the default for that dimension (default: \(Int(PanelPositioner.defaultSize.width)) × \(Int(PanelPositioner.defaultSize.height))).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                Picker("Preferred model", selection: Binding(
                    get: { draft.preferredModelID ?? .zero },
                    set: { draft.preferredModelID = ($0 == .zero) ? nil : $0 }
                )) {
                    Text("Use global default").tag(UUID.zero)
                    ForEach(modelStore.models) { m in
                        Text(m.displayName).tag(m.id)
                    }
                }
            }

            DisclosureGroup("Advanced inference parameters", isExpanded: $showAdvanced) {
                TextField(
                    "Temperature",
                    text: $temperatureText,
                    prompt: Text("Inherit from model")
                )
                TextField(
                    "Max output tokens",
                    text: $maxTokensText,
                    prompt: Text("Inherit from model")
                )
                TextField(
                    "Reasoning effort",
                    text: Binding(
                        get: { draft.reasoningEffort ?? "" },
                        set: { draft.reasoningEffort = $0.isEmpty ? nil : $0 }
                    ),
                    prompt: Text("e.g. minimal, low, medium, high, xhigh")
                )
                Text("Each field is optional. Empty values fall back to the model's default. Reasoning effort is sent verbatim as the `reasoning_effort` field; ignored by models that don't accept it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview").font(.headline)
            GroupBox("Sample inputs") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selection").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $sampleSelection)
                        .font(.system(size: 12))
                        .frame(minHeight: 50, maxHeight: 80)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                    if draft.requiresUserInput {
                        Text("User input").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $sampleUserInput)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 2)
            }

            let unknowns = PromptBuilder.unknownVariables(in: draft.systemPrompt)
            if !unknowns.isEmpty {
                Label("Unknown variables: \(unknowns.map { "{{\($0)}}" }.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            let resolvedSystem = PromptBuilder.expand(
                template: draft.systemPrompt,
                selection: sampleSelection,
                userInput: sampleUserInput,
                app: "Sample.app",
                windowTitle: "Sample window"
            )

            GroupBox("Resolved system message") {
                ScrollView {
                    Text(resolvedSystem)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 120)
            }

            GroupBox("Resolved user message") {
                ScrollView {
                    let userMessage = draft.capturesSelection ? sampleSelection : sampleUserInput
                    Text(userMessage.isEmpty ? "(empty)" : userMessage)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 60, maxHeight: 120)
            }

            Spacer()
        }
        .padding(12)
    }

    private func commit() {
        var out = draft
        // Direct-prompt presets never gate on selection — they don't capture
        // one — so normalize the now-meaningless requiresSelection flag.
        if !out.capturesSelection { out.requiresSelection = false }
        let trimmedTemp = temperatureText.trimmingCharacters(in: .whitespaces)
        out.temperature = Double(trimmedTemp)
        let trimmedMax = maxTokensText.trimmingCharacters(in: .whitespaces)
        out.maxOutputTokens = Int(trimmedMax)
        if let r = out.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines), r.isEmpty {
            out.reasoningEffort = nil
        }
        out.panelWidth = Double(panelWidthText.trimmingCharacters(in: .whitespaces))
        out.panelHeight = Double(panelHeightText.trimmingCharacters(in: .whitespaces))
        onSave(out)
    }
}

private extension UUID {
    /// Sentinel value used to represent "no preferred model" in a Picker.
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}

private extension LocalizedStringKey.StringInterpolation {
    /// Workaround so the variable list renders as plain text in a SwiftUI Form
    /// without LocalizedStringKey treating the curly braces as format directives.
    mutating func appendInterpolation(known str: String) { appendInterpolation(str) }
}
