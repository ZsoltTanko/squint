import Foundation

struct LocalHistoryItem: Codable, Identifiable {
    var id: UUID = UUID()
    var timestamp: Date
    var selectedText: String
    var userInput: String
    var responseText: String
    var appName: String?
    var windowTitle: String?
    /// Snapshot of how the prompt was rendered. Stored verbatim so editing or
    /// deleting the source preset never rewrites history.
    var resolution: HistoryResolution

    init(
        id: UUID = UUID(),
        timestamp: Date,
        selectedText: String,
        userInput: String,
        responseText: String,
        appName: String?,
        windowTitle: String?,
        resolution: PromptResolution
    ) {
        self.id = id
        self.timestamp = timestamp
        self.selectedText = selectedText
        self.userInput = userInput
        self.responseText = responseText
        self.appName = appName
        self.windowTitle = windowTitle
        self.resolution = HistoryResolution(
            presetID: resolution.presetID,
            presetName: resolution.presetName,
            systemPrompt: resolution.systemPrompt,
            userMessage: resolution.userMessage,
            modelID: resolution.modelID,
            modelDisplayName: resolution.modelDisplayName,
            temperature: resolution.temperature,
            maxOutputTokens: resolution.maxOutputTokens,
            reasoningEffort: resolution.reasoningEffort
        )
    }
}

struct HistoryResolution: Codable {
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

/// Off by default. When enabled, persists a small JSON list locally.
/// No sync, no analytics.
final class LocalHistoryStore {
    static let shared = LocalHistoryStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "Squint.history")
    private(set) var items: [LocalHistoryItem] = []

    init() {
        let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = (support ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Squint", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func append(_ item: LocalHistoryItem) {
        queue.async {
            self.items.append(item)
            self.save()
        }
    }

    func clear() {
        queue.async {
            self.items.removeAll()
            self.save()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LocalHistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
