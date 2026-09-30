import XCTest
@testable import Squint

@MainActor
final class ModelStoreTests: XCTestCase {
    private func makeStore() -> ModelStore {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID()).json")
        let defaults = UserDefaults(suiteName: "ModelStoreTests-\(UUID().uuidString)")!
        return ModelStore(fileURL: tmp, defaults: defaults)
    }

    func testAddSetsFirstAsDefault() {
        let store = makeStore()
        let m = ModelConfig(displayName: "A", modelName: "x", baseURL: URL(string: "https://api.openai.com/v1")!)
        store.add(m)
        XCTAssertEqual(store.models.count, 1)
        XCTAssertEqual(store.defaultModelID, m.id)
    }

    func testDeleteMovesDefault() {
        let store = makeStore()
        let a = ModelConfig(displayName: "A", modelName: "x", baseURL: URL(string: "https://api.openai.com/v1")!)
        let b = ModelConfig(displayName: "B", modelName: "y", baseURL: URL(string: "https://api.openai.com/v1")!)
        store.add(a)
        store.add(b)
        store.delete(id: a.id)
        XCTAssertEqual(store.models.count, 1)
        XCTAssertEqual(store.defaultModelID, b.id)
    }

    func testPersistsAcrossInstances() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("models-\(UUID()).json")
        let defaults = UserDefaults(suiteName: "ModelStorePersistTests-\(UUID().uuidString)")!
        let s1 = ModelStore(fileURL: url, defaults: defaults)
        let m = ModelConfig(displayName: "Persisted", modelName: "x", baseURL: URL(string: "https://api.openai.com/v1")!)
        s1.add(m)
        let s2 = ModelStore(fileURL: url, defaults: defaults)
        XCTAssertEqual(s2.models.first?.displayName, "Persisted")
    }
}
