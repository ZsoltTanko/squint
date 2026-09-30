import XCTest
@testable import Squint

final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore(service: "com.zsolttanko.squint.tests")
    private let account = "test-\(UUID().uuidString)"

    override func tearDown() {
        super.tearDown()
        store.deleteAPIKey(account: account)
    }

    func testWriteReadDelete() {
        XCTAssertTrue(store.writeAPIKey("sk-test-123", account: account))
        XCTAssertEqual(store.readAPIKey(account: account), "sk-test-123")
        XCTAssertTrue(store.deleteAPIKey(account: account))
        XCTAssertNil(store.readAPIKey(account: account))
    }

    func testOverwrite() {
        XCTAssertTrue(store.writeAPIKey("first", account: account))
        XCTAssertTrue(store.writeAPIKey("second", account: account))
        XCTAssertEqual(store.readAPIKey(account: account), "second")
    }
}
