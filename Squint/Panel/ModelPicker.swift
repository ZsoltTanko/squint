import SwiftUI

struct ModelPicker: View {
    @ObservedObject var modelStore: ModelStore
    @Binding var selectedID: UUID?

    var body: some View {
        Picker("Model", selection: $selectedID) {
            if modelStore.models.isEmpty {
                Text("No models").tag(UUID?.none)
            } else {
                ForEach(modelStore.models) { m in
                    Text(m.displayName).tag(Optional(m.id))
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}
