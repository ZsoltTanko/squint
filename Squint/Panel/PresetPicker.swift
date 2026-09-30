import SwiftUI

struct PresetPicker: View {
    @ObservedObject var presetStore: PromptPresetStore
    @Binding var selectedID: UUID?
    var onChange: () -> Void = {}

    var body: some View {
        Picker("Preset", selection: Binding(
            get: { selectedID ?? presetStore.defaultPreset?.id ?? UUID() },
            set: { newValue in
                selectedID = newValue
                onChange()
            }
        )) {
            // Pinned items first.
            ForEach(presetStore.pinnedPresets) { preset in
                Text(preset.name).tag(preset.id)
            }
            let unpinned = presetStore.sortedPresets.filter { !$0.pinnedInDropdown }
            if !unpinned.isEmpty {
                Divider()
                Section("Unpinned") {
                    ForEach(unpinned) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}
