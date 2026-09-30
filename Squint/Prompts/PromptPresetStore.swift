import Foundation
import Combine

/// Persists the user's `[PromptPreset]` and the chosen default. Mirrors
/// `ModelStore`: JSON file in Application Support, default ID in UserDefaults.
@MainActor
final class PromptPresetStore: ObservableObject {
    @Published private(set) var presets: [PromptPreset] = []
    @Published var defaultPresetID: UUID?

    private let fileURL: URL
    private let defaults: UserDefaults
    private let defaultsKey = "Squint.defaultPresetID"
    /// Tracks which factory seeds (by stable name) have ever been offered
    /// to this catalog. Lets us add *new* factory seeds in later releases
    /// without re-installing seeds the user has explicitly deleted. The
    /// value is a JSON-encoded `[String]` (rather than a `Set` directly)
    /// because `UserDefaults` only round-trips plist-friendly types.
    private let installedSeedsKey = "Squint.installedFactorySeedNames"

    /// `onSeedInstalled` runs for each factory seed as it's added to the
    /// catalog, letting the app attach install-time extras such as the
    /// seed's shipped hotkey.
    init(
        fileURL: URL? = nil,
        defaults: UserDefaults = .standard,
        seedIfEmpty: Bool = true,
        onSeedInstalled: (PromptPreset) -> Void = { _ in }
    ) {
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
            self.fileURL = dir.appendingPathComponent("prompts.json")
        }
        load()
        if let raw = defaults.string(forKey: defaultsKey), let id = UUID(uuidString: raw) {
            defaultPresetID = id
        }
        if presets.isEmpty && seedIfEmpty {
            let seeds = PromptPreset.factorySeeds
            presets = seeds
            if let first = seeds.first {
                defaultPresetID = first.id
                defaults.set(first.id.uuidString, forKey: defaultsKey)
            }
            markFactorySeedsInstalled(seeds.map { $0.name })
            save()
            seeds.forEach(onSeedInstalled)
        } else if seedIfEmpty {
            installNewFactorySeedsIfNeeded(onSeedInstalled: onSeedInstalled)
        }
        if defaultPresetID == nil {
            defaultPresetID = presets.first?.id
        }
    }

    /// Catalog already exists. Install any factory seed (by stable name)
    /// that has never been offered to this catalog before *and* isn't
    /// already present under that name. The two checks together mean:
    ///
    /// - Users who upgrade from a version that didn't ship a given seed
    ///   still receive it on next launch.
    /// - Seeds the user later deleted are *not* re-installed — once a
    ///   name is recorded as "offered", we never offer it again.
    /// - The catalog is never duplicated. On first migration the
    ///   `installedSeedsKey` defaults entry doesn't exist yet, so this
    ///   would naively re-add Explain/Ask too — the "already present by
    ///   name" guard prevents that, and we then record all current seed
    ///   names as offered so the guard isn't load-bearing on subsequent
    ///   launches.
    private func installNewFactorySeedsIfNeeded(onSeedInstalled: (PromptPreset) -> Void) {
        let alreadyOffered = installedFactorySeedNames()
        let existingNames = Set(presets.map { $0.name })
        let candidates = PromptPreset.factorySeeds.filter {
            !alreadyOffered.contains($0.name) && !existingNames.contains($0.name)
        }
        // Append to the end so existing sortOrder values are preserved.
        let nextSortOrder = (presets.map { $0.sortOrder }.max() ?? 0) + 1
        for (offset, seed) in candidates.enumerated() {
            var copy = seed
            copy.sortOrder = nextSortOrder + offset
            presets.append(copy)
            onSeedInstalled(copy)
            AppLogger.shared.info("Installed new factory preset seed: \(seed.name)")
        }
        // Record every current factory-seed name as offered, including ones
        // we skipped because they already existed under that name. This
        // turns the "already present" check into a one-time migration step
        // rather than a forever guard against renames.
        let allSeedNames = Set(PromptPreset.factorySeeds.map { $0.name })
        let updated = alreadyOffered.union(allSeedNames)
        if updated != alreadyOffered { markFactorySeedsInstalled(updated) }
        if !candidates.isEmpty { save() }
    }

    private func installedFactorySeedNames() -> Set<String> {
        guard let data = defaults.data(forKey: installedSeedsKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(arr)
    }

    private func markFactorySeedsInstalled(_ names: any Sequence<String>) {
        let arr = Array(Set(names)).sorted()
        if let data = try? JSONEncoder().encode(arr) {
            defaults.set(data, forKey: installedSeedsKey)
        }
    }

    var defaultPreset: PromptPreset? {
        presets.first(where: { $0.id == defaultPresetID }) ?? presets.first
    }

    var sortedPresets: [PromptPreset] {
        presets.sorted { ($0.sortOrder, $0.name.lowercased()) < ($1.sortOrder, $1.name.lowercased()) }
    }

    var pinnedPresets: [PromptPreset] {
        sortedPresets.filter { $0.pinnedInDropdown }
    }

    func add(_ preset: PromptPreset) {
        var p = preset
        if p.sortOrder == 0 {
            p.sortOrder = (presets.map { $0.sortOrder }.max() ?? 0) + 1
        }
        presets.append(p)
        if defaultPresetID == nil { setDefault(p.id) }
        save()
    }

    func update(_ preset: PromptPreset) {
        guard let idx = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[idx] = preset
        save()
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
        if defaultPresetID == id { defaultPresetID = presets.first?.id }
        if let id = defaultPresetID {
            defaults.set(id.uuidString, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
        save()
    }

    func setDefault(_ id: UUID) {
        defaultPresetID = id
        defaults.set(id.uuidString, forKey: defaultsKey)
    }

    func move(from source: IndexSet, to destination: Int) {
        var sorted = sortedPresets
        sorted.move(fromOffsets: source, toOffset: destination)
        for (i, p) in sorted.enumerated() {
            if let idx = presets.firstIndex(where: { $0.id == p.id }) {
                presets[idx].sortOrder = i
            }
        }
        save()
    }

    func preset(byID id: UUID?) -> PromptPreset? {
        guard let id else { return nil }
        return presets.first(where: { $0.id == id })
    }

    // MARK: - Import / export

    /// Encode a single preset (or all of them) for sharing. Decoded payloads are
    /// either `PromptPreset` or `[PromptPreset]`.
    func exportBundle() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(presets)
    }

    func exportSingle(_ preset: PromptPreset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(preset)
    }

    /// Imports presets from a JSON payload (single object or array). New UUIDs
    /// are assigned to avoid collisions with existing presets, and hotkey
    /// bindings are intentionally not carried over (the importer can rebind).
    @discardableResult
    func importBundle(_ data: Data) throws -> [PromptPreset] {
        let decoder = JSONDecoder()
        let imported: [PromptPreset]
        if let arr = try? decoder.decode([PromptPreset].self, from: data) {
            imported = arr
        } else if let one = try? decoder.decode(PromptPreset.self, from: data) {
            imported = [one]
        } else {
            throw NSError(domain: "PromptPresetStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "File is not a valid prompt preset JSON."])
        }
        var added: [PromptPreset] = []
        for p in imported {
            var copy = p
            copy.id = UUID()
            copy.sortOrder = (presets.map { $0.sortOrder }.max() ?? 0) + 1
            presets.append(copy)
            added.append(copy)
        }
        save()
        return added
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([PromptPreset].self, from: data) else {
            return
        }
        presets = decoded
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            AppLogger.shared.error("Failed to persist prompt presets: \(error.localizedDescription)")
        }
    }
}
