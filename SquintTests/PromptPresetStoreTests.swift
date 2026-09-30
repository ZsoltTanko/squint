import XCTest
@testable import Squint

@MainActor
final class PromptPresetStoreTests: XCTestCase {
    private func makeStore(seed: Bool = true) -> PromptPresetStore {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("prompts-\(UUID()).json")
        let defaults = UserDefaults(suiteName: "PromptPresetStoreTests-\(UUID().uuidString)")!
        return PromptPresetStore(fileURL: tmp, defaults: defaults, seedIfEmpty: seed)
    }

    func testFirstLaunchSeedsFactoryPresetsWithFirstAsDefault() {
        let store = makeStore()
        XCTAssertEqual(store.presets.count, PromptPreset.factorySeeds.count)
        XCTAssertEqual(store.defaultPreset?.name, PromptPreset.seed.name)
    }

    func testNoSeedWhenSuppressed() {
        let store = makeStore(seed: false)
        XCTAssertTrue(store.presets.isEmpty)
        XCTAssertNil(store.defaultPresetID)
    }

    func testDeleteMovesDefault() {
        let store = makeStore()
        let extra = PromptPreset(name: "Other", systemPrompt: "X")
        store.add(extra)
        store.setDefault(extra.id)
        store.delete(id: extra.id)
        XCTAssertEqual(store.defaultPresetID, store.presets.first?.id)
    }

    func testPersistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prompts-\(UUID()).json")
        let defaults = UserDefaults(suiteName: "PromptPresetStorePersist-\(UUID()).json")!
        let s1 = PromptPresetStore(fileURL: url, defaults: defaults)
        s1.add(PromptPreset(name: "Persisted", systemPrompt: "P"))
        let s2 = PromptPresetStore(fileURL: url, defaults: defaults)
        XCTAssertTrue(s2.presets.contains(where: { $0.name == "Persisted" }))
    }

    func testImportAssignsNewIDs() throws {
        let store = makeStore()
        let p = PromptPreset(name: "Imported", systemPrompt: "X")
        let data = try JSONEncoder().encode([p])
        let added = try store.importBundle(data)
        XCTAssertEqual(added.count, 1)
        XCTAssertNotEqual(added.first?.id, p.id)
    }

    func testMigrationInstallsNewFactorySeedsForExistingCatalog() throws {
        // Simulate an existing user whose `prompts.json` was written by an
        // older app version that only shipped a subset of today's factory
        // seeds (no `installedFactorySeedNames` key in defaults yet).
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prompts-\(UUID()).json")
        let defaults = UserDefaults(suiteName: "PromptPresetStoreMigrate-\(UUID().uuidString)")!
        let legacy = PromptPreset(name: "Explain", systemPrompt: "old-explain", autoSend: true, sortOrder: 0)
        try JSONEncoder().encode([legacy]).write(to: url)

        let store = PromptPresetStore(fileURL: url, defaults: defaults)
        XCTAssertEqual(store.presets.filter { $0.name == "Explain" }.count, 1,
                       "Existing Explain must not be duplicated by migration")
        for seedName in PromptPreset.factorySeeds.map(\.name) {
            XCTAssertTrue(store.presets.contains(where: { $0.name == seedName }),
                          "Factory seed \(seedName) should be present after migration")
        }
        XCTAssertEqual(store.presets.first(where: { $0.name == "Explain" })?.systemPrompt,
                       "old-explain",
                       "User's existing seed copy must be left untouched")
    }

    func testMigrationDoesNotReinstallDeletedSeeds() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prompts-\(UUID()).json")
        let defaults = UserDefaults(suiteName: "PromptPresetStoreMigrateDel-\(UUID().uuidString)")!

        // First run: full seed install + offered-names recorded.
        do {
            let store = PromptPresetStore(fileURL: url, defaults: defaults)
            guard let prompt = store.presets.first(where: { $0.name == "Prompt" }) else {
                return XCTFail("Prompt seed should have been installed on first launch")
            }
            store.delete(id: prompt.id)
            XCTAssertFalse(store.presets.contains(where: { $0.name == "Prompt" }))
        }
        // Second run: the deleted seed must not come back.
        let reopened = PromptPresetStore(fileURL: url, defaults: defaults)
        XCTAssertFalse(reopened.presets.contains(where: { $0.name == "Prompt" }),
                       "A factory seed the user deleted must not be re-installed on next launch")
    }

    func testReorderUpdatesSortOrder() {
        let store = makeStore()
        let a = PromptPreset(name: "A", systemPrompt: "x", sortOrder: 1)
        let b = PromptPreset(name: "B", systemPrompt: "y", sortOrder: 2)
        store.add(a); store.add(b)
        let originalFirst = store.sortedPresets.first?.id
        store.move(from: IndexSet(integer: 0), to: 2)
        XCTAssertNotEqual(store.sortedPresets.first?.id, originalFirst)
    }
}
