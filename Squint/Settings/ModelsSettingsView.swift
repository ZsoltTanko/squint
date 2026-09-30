import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject private var modelStore: ModelStore = AppDelegate.shared.modelStore

    @State private var editing: EditTarget?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Configured models")
                    .font(.headline)
                Spacer()
                Button {
                    editing = .init(model: blankModel(), isNew: true)
                } label: {
                    Label("Add Model", systemImage: "plus")
                }
            }

            if modelStore.models.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No models yet")
                        .foregroundStyle(.secondary)
                    Text("Click Add Model to configure an OpenAI-compatible endpoint.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List {
                    ForEach(modelStore.models) { model in
                        modelRow(model)
                    }
                }
                .frame(minHeight: 200)
            }
        }
        .padding()
        .sheet(item: $editing) { target in
            ModelEditor(
                initial: target.model,
                isNew: target.isNew,
                onSave: { saved, key in
                    if modelStore.models.contains(where: { $0.id == saved.id }) {
                        modelStore.update(saved)
                    } else {
                        modelStore.add(saved)
                    }
                    if let key, !key.isEmpty {
                        KeychainStore.shared.writeAPIKey(key, account: saved.apiKeyReference)
                    }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
    }

    @ViewBuilder
    private func modelRow(_ model: ModelConfig) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.system(size: 13, weight: .semibold))
                    if modelStore.defaultModelID == model.id {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.tint.opacity(0.2), in: Capsule())
                    }
                }
                Text("\(model.provider.displayName) · \(model.modelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.baseURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set Default") { modelStore.setDefault(model.id) }
                .disabled(modelStore.defaultModelID == model.id)
            Button("Edit") {
                editing = .init(model: model, isNew: false)
            }
            Button(role: .destructive) {
                modelStore.delete(id: model.id)
            } label: { Image(systemName: "trash") }
        }
        .padding(.vertical, 2)
    }

    private func blankModel() -> ModelConfig {
        ModelConfig(
            displayName: "New Model",
            provider: .openAICompatible,
            modelName: "gpt-4o-mini",
            baseURL: URL(string: "https://api.openai.com/v1")!
        )
    }
}

private struct EditTarget: Identifiable {
    let id = UUID()
    let model: ModelConfig
    let isNew: Bool
}

private struct ModelEditor: View {
    let initial: ModelConfig
    let isNew: Bool
    let onSave: (ModelConfig, String?) -> Void
    let onCancel: () -> Void

    @State private var draft: ModelConfig
    @State private var apiKey: String = ""
    @State private var baseURLString: String
    @State private var reasoningEffort: String

    init(initial: ModelConfig, isNew: Bool, onSave: @escaping (ModelConfig, String?) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: initial)
        self._baseURLString = State(initialValue: initial.baseURL.absoluteString)
        self._reasoningEffort = State(initialValue: initial.reasoningEffort ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Display") {
                    TextField("Display name", text: $draft.displayName)
                }
                Section("Provider") {
                    Picker("Provider", selection: $draft.provider) {
                        ForEach(ProviderKind.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    TextField("Model name", text: $draft.modelName)
                    TextField("Base URL", text: $baseURLString)
                }
                Section("API Key") {
                    SecureField(isNew ? "API key (stored in Keychain)" : "API key — leave blank to keep existing", text: $apiKey)
                    Text("Stored in macOS Keychain. Not required for localhost endpoints (Ollama, LM Studio).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Capabilities") {
                    Toggle("Supports streaming", isOn: $draft.supportsStreaming)
                    Toggle("Supports vision", isOn: $draft.supportsVision)
                }
                Section("Reasoning") {
                    TextField("reasoning_effort", text: $reasoningEffort, prompt: Text("e.g. minimal, low, medium, high"))
                    Text("Sent as the `reasoning_effort` field in the chat completions body. Leave blank for non-reasoning models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isNew ? "Add" : "Save") {
                    var out = draft
                    if let url = URL(string: baseURLString.trimmingCharacters(in: .whitespaces)) {
                        out.baseURL = url
                    }
                    let trimmedEffort = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
                    out.reasoningEffort = trimmedEffort.isEmpty ? nil : trimmedEffort
                    onSave(out, apiKey.isEmpty ? nil : apiKey)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.displayName.isEmpty || draft.modelName.isEmpty || URL(string: baseURLString) == nil)
            }
            .padding(12)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 460, idealHeight: 500)
    }
}
