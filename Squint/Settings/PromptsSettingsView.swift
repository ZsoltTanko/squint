import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers

struct PromptsSettingsView: View {
    @ObservedObject private var presetStore: PromptPresetStore = AppDelegate.shared.presetStore
    @ObservedObject private var modelStore: ModelStore = AppDelegate.shared.modelStore

    @State private var editing: EditTarget?
    @State private var importing = false
    @State private var exportingAll = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Prompt presets")
                    .font(.headline)
                Spacer()
                Button {
                    do {
                        let data = try presetStore.exportBundle()
                        savePanel(suggestedName: "Squint-presets.json", data: data)
                    } catch {
                        importError = error.localizedDescription
                    }
                } label: { Label("Export All", systemImage: "square.and.arrow.up") }
                Button { importing = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                Button {
                    editing = .init(preset: blankPreset(), isNew: true)
                } label: {
                    Label("Add Preset", systemImage: "plus")
                }
            }

            if presetStore.presets.isEmpty {
                emptyState
            } else {
                presetList
            }
        }
        .padding()
        .sheet(item: $editing) { target in
            PromptPresetEditor(
                initial: target.preset,
                isNew: target.isNew,
                modelStore: modelStore,
                conflictNamesFor: { presetID, shortcut in
                    presetsConflictingWith(shortcut: shortcut, excluding: presetID)
                },
                onSave: { saved in
                    if presetStore.presets.contains(where: { $0.id == saved.id }) {
                        presetStore.update(saved)
                    } else {
                        presetStore.add(saved)
                    }
                    editing = nil
                },
                onCancel: { editing = nil }
            )
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    try presetStore.importBundle(data)
                } catch {
                    importError = error.localizedDescription
                }
            case .failure(let err):
                importError = err.localizedDescription
            }
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.quote").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("No presets yet").foregroundStyle(.secondary)
            Text("Click Add Preset to create one. The seed “Explain” preset is recreated automatically if the catalog is empty on next launch.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var presetList: some View {
        List {
            ForEach(presetStore.sortedPresets) { preset in
                presetRow(preset)
            }
            .onMove { src, dst in presetStore.move(from: src, to: dst) }
        }
        .frame(minHeight: 280)
    }

    @ViewBuilder
    private func presetRow(_ preset: PromptPreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.name).font(.system(size: 13, weight: .semibold))
                    if presetStore.defaultPresetID == preset.id {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.tint.opacity(0.2), in: Capsule())
                    }
                    if !preset.pinnedInDropdown {
                        Image(systemName: "pin.slash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if hasHotkeyConflict(for: preset) {
                        Label("Hotkey conflict", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.red)
                            .help("This preset's hotkey is also bound to another action.")
                    }
                }
                Text(preset.systemPrompt.prefix(120) + (preset.systemPrompt.count > 120 ? "…" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let modelID = preset.preferredModelID,
                       let model = modelStore.models.first(where: { $0.id == modelID }) {
                        Text("Model: \(model.displayName)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let effort = preset.reasoningEffort, !effort.isEmpty {
                        Text("Reasoning: \(effort)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if !preset.capturesSelection {
                        Text("Direct prompt").font(.caption2).foregroundStyle(.secondary)
                    }
                    if preset.requiresUserInput {
                        Text("Input").font(.caption2).foregroundStyle(.secondary)
                    }
                    if preset.autoSend {
                        Text("Auto-send").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button("Set Default") { presetStore.setDefault(preset.id) }
                .disabled(presetStore.defaultPresetID == preset.id)
            Button("Edit") { editing = .init(preset: preset, isNew: false) }
            Button {
                if let data = try? presetStore.exportSingle(preset) {
                    savePanel(suggestedName: "\(safeFilename(preset.name)).json", data: data)
                }
            } label: { Image(systemName: "square.and.arrow.up") }
                .help("Export this preset")
            Button(role: .destructive) {
                presetStore.delete(id: preset.id)
            } label: { Image(systemName: "trash") }
                .disabled(presetStore.presets.count <= 1)
                .help(presetStore.presets.count <= 1 ? "Can't delete the last preset" : "Delete preset")
        }
        .padding(.vertical, 2)
    }

    private func blankPreset() -> PromptPreset {
        PromptPreset(name: "New Preset", systemPrompt: "")
    }

    private func presetsConflictingWith(shortcut: KeyboardShortcuts.Shortcut?, excluding presetID: UUID) -> [String] {
        guard let shortcut else { return [] }
        var conflicts: [String] = []
        // Conflict with global "ask" hotkey?
        if let invoke = KeyboardShortcuts.getShortcut(for: .invokePanel), invoke == shortcut {
            conflicts.append("Global Ask hotkey")
        }
        for other in presetStore.presets where other.id != presetID {
            let name = KeyboardShortcuts.Name(other.hotkeyShortcutKey)
            if let s = KeyboardShortcuts.getShortcut(for: name), s == shortcut {
                conflicts.append(other.name)
            }
        }
        return conflicts
    }

    private func hasHotkeyConflict(for preset: PromptPreset) -> Bool {
        let name = KeyboardShortcuts.Name(preset.hotkeyShortcutKey)
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return false }
        return !presetsConflictingWith(shortcut: shortcut, excluding: preset.id).isEmpty
    }

    private func savePanel(suggestedName: String, data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func safeFilename(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?*\"<>|")
        return name.components(separatedBy: bad).joined(separator: "-")
    }
}

private struct EditTarget: Identifiable {
    let id = UUID()
    let preset: PromptPreset
    let isNew: Bool
}
