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
        XCTAssertNil(store.string(forKey: "label"))

        store.set(true, forKey: "flag")
        store.set(Data("value".utf8), forKey: "blob")
        store.set("downloader", forKey: "label")

        XCTAssertEqual(store.bool(forKey: "flag"), true)
        XCTAssertEqual(store.data(forKey: "blob"), Data("value".utf8))
        XCTAssertEqual(store.string(forKey: "label"), "downloader")

        store.removeObject(forKey: "flag")
        store.removeObject(forKey: "blob")
        store.removeObject(forKey: "label")
        XCTAssertNil(store.bool(forKey: "flag"))
        XCTAssertNil(store.data(forKey: "blob"))
        XCTAssertNil(store.string(forKey: "label"))
    }
}
