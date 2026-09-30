import Foundation
import Combine

/// One past query entry. Captures everything needed to repaint the panel
/// exactly as the user saw it on the original invocation: the effective
/// selection (`text`), the preset's user-input field (`userInput`, empty
/// for presets that don't take one), and the streamed response
/// (`responseText`). Timestamp is purely informational; ordering is by
/// insertion (most-recent first).
struct QueryHistoryEntry: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var text: String
    var userInput: String
    var responseText: String
    /// Model used for this invocation, so re-picking from history restores
    /// the model dropdown to what the user actually saw. Optional because
    /// older on-disk entries don't have it (and a model that's since been
    /// deleted from the catalog falls back to whatever's currently
    /// selected at apply time).
    var modelID: UUID?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        userInput: String = "",
        responseText: String = "",
        modelID: UUID? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.userInput = userInput
        self.responseText = responseText
        self.modelID = modelID
        self.timestamp = timestamp
    }
}

extension QueryHistoryEntry {
    /// Backwards-compat decoder: older on-disk entries (pre-response capture)
    /// only had `id`, `text`, `timestamp`. Decode missing fields as empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.text = try c.decode(String.self, forKey: .text)
        self.userInput = try c.decodeIfPresent(String.self, forKey: .userInput) ?? ""
        self.responseText = try c.decodeIfPresent(String.self, forKey: .responseText) ?? ""
        self.modelID = try c.decodeIfPresent(UUID.self, forKey: .modelID)
        self.timestamp = try c.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }
}

/// Persists a small rolling history of past queries, keyed by prompt
/// preset ID. Distinct from `LocalHistoryStore` (which stores full
/// system-prompt + response snapshots when the user opts in): this store
/// only powers the per-preset "recent queries" dropdown in the panel and
/// is on by default with a low cap.
///
/// Cap is controlled by `SettingsStore.queryHistoryLimit`; setting it to
/// 0 disables recording entirely and clears the visible list (existing
/// entries on disk are kept untouched so re-enabling restores them).
@MainActor
final class QueryHistoryStore: ObservableObject {
    static let shared = QueryHistoryStore()

    @Published private(set) var entries: [UUID: [QueryHistoryEntry]] = [:]

    private let fileURL: URL

    init(fileURL: URL? = nil) {
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
            self.fileURL = dir.appendingPathComponent("query-history.json")
        }
        load()
    }

    /// Most-recent-first list for a preset, capped to `limit`. Returns an
    /// empty list when `limit <= 0` so the UI can collapse the dropdown
    /// when history is disabled.
    func recent(presetID: UUID?, limit: Int) -> [QueryHistoryEntry] {
        guard let presetID, limit > 0 else { return [] }
        let list = entries[presetID] ?? []
        return Array(list.prefix(limit))
    }

    /// Records a completed query+response. Empty/whitespace-only `text`
    /// or `responseText` is ignored (a cancelled or errored stream
    /// shouldn't pollute the dropdown). Move-to-top dedupe is keyed on
    /// `(text, userInput)` so re-asking the exact same query just bumps
    /// the existing entry rather than duplicating it.
    func record(
        text: String,
        userInput: String,
        responseText: String,
        modelID: UUID?,
        presetID: UUID?,
        limit: Int
    ) {
        guard let presetID, limit > 0 else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !trimmedResponse.isEmpty else { return }

        let normalisedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = entries[presetID] ?? []
        list.removeAll { $0.text == trimmedText && $0.userInput == normalisedInput }
        list.insert(
            QueryHistoryEntry(
                text: trimmedText,
                userInput: normalisedInput,
                responseText: responseText,
                modelID: modelID,
                timestamp: Date()
            ),
            at: 0
        )
        if list.count > limit { list.removeLast(list.count - limit) }
        entries[presetID] = list
        save()
    }

    func clear(presetID: UUID? = nil) {
        if let presetID {
            entries.removeValue(forKey: presetID)
        } else {
            entries.removeAll()
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([UUID: [QueryHistoryEntry]].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            AppLogger.shared.error("Failed to persist query history: \(error.localizedDescription)")
        }
    }
}
