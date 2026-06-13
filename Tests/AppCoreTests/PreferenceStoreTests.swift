import AppCore
import XCTest

final class PreferenceStoreTests: XCTestCase {
    func testUserDefaultsPreferenceStoreRoundTripsBoolAndData() throws {
        let suiteName = "PreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsPreferenceStore(userDefaults: defaults)
        XCTAssertNil(store.bool(forKey: "flag"))
        XCTAssertNil(store.data(forKey: "blob"))

        store.set(true, forKey: "flag")
        store.set(Data("value".utf8), forKey: "blob")

        XCTAssertEqual(store.bool(forKey: "flag"), true)
        XCTAssertEqual(store.data(forKey: "blob"), Data("value".utf8))

        store.removeObject(forKey: "flag")
        store.removeObject(forKey: "blob")
        XCTAssertNil(store.bool(forKey: "flag"))
        XCTAssertNil(store.data(forKey: "blob"))
    }
}
