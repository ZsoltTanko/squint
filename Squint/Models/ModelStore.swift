import Foundation
import Combine

@MainActor
final class ModelStore: ObservableObject {
    @Published private(set) var models: [ModelConfig] = []
    @Published var defaultModelID: UUID?

    private let fileURL: URL
    private let defaults: UserDefaults
    private let defaultsKey = "Squint.defaultModelID"

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = (support ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("Squint", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("models.json")
        }
        load()
        if let raw = defaults.string(forKey: defaultsKey), let id = UUID(uuidString: raw) {
            defaultModelID = id
        }
    }

    var defaultModel: ModelConfig? {
        models.first(where: { $0.id == defaultModelID }) ?? models.first
    }

    func add(_ model: ModelConfig) {
        models.append(model)
        if defaultModelID == nil { setDefault(model.id) }
        save()
    }

    func update(_ model: ModelConfig) {
        guard let idx = models.firstIndex(where: { $0.id == model.id }) else { return }
        models[idx] = model
        save()
    }

    func delete(id: UUID) {
        models.removeAll { $0.id == id }
        if defaultModelID == id { defaultModelID = models.first?.id }
        KeychainStore.shared.deleteAPIKey(account: id.uuidString)
        save()
    }

    func setDefault(_ id: UUID) {
        defaultModelID = id
        defaults.set(id.uuidString, forKey: defaultsKey)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([ModelConfig].self, from: data) else {
            return
        }
        models = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(models)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            AppLogger.shared.error("Failed to persist models: \(error.localizedDescription)")
        }
    }
}
