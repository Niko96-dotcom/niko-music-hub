import AppCore
import FeatureBPMTapper
import XCTest

final class BPMHistoryStoreTests: XCTestCase {
    func testStartsEmpty() throws {
        let store = makeStore(reset: true)

        XCTAssertEqual(try store.listEntries(), [])
    }

    func testPersistsSavedEntry() throws {
        let suiteName = uniqueSuiteName()
        let store = makeStore(suiteName: suiteName, reset: true)
        let entry = BPMHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            bpm: 128.0,
            rawTappedBPM: 128.0,
            adjustment: .original,
            timestamp: Date(timeIntervalSince1970: 10)
        )

        try store.addEntry(entry)

        let reloaded = makeStore(suiteName: suiteName)
        XCTAssertEqual(try reloaded.listEntries(), [entry])
    }

    func testNewestEntriesAppearFirst() throws {
        let store = makeStore(reset: true)
        let older = BPMHistoryEntry(
            bpm: 100.0,
            rawTappedBPM: 200.0,
            adjustment: .halfTime,
            timestamp: Date(timeIntervalSince1970: 10)
        )
        let newer = BPMHistoryEntry(
            bpm: 130.0,
            rawTappedBPM: 65.0,
            adjustment: .doubleTime,
            timestamp: Date(timeIntervalSince1970: 20)
        )

        try store.addEntry(older)
        try store.addEntry(newer)

        XCTAssertEqual(try store.listEntries(), [newer, older])
    }

    func testClearEntriesRemovesSavedHistory() throws {
        let store = makeStore(reset: true)
        try store.addEntry(BPMHistoryEntry(
            bpm: 128.0,
            rawTappedBPM: 128.0,
            adjustment: .original,
            timestamp: Date(timeIntervalSince1970: 10)
        ))

        try store.clearEntries()

        XCTAssertEqual(try store.listEntries(), [])
    }

    func testPersistsSavedEntryThroughPreferenceStore() throws {
        let suiteName = uniqueSuiteName()
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserDefaultsPreferenceStore(userDefaults: userDefaults)
        let store = UserDefaultsBPMHistoryStore(preferences: preferences)
        let entry = BPMHistoryEntry(
            bpm: 90,
            rawTappedBPM: 180,
            adjustment: .halfTime,
            timestamp: Date(timeIntervalSince1970: 30)
        )

        try store.addEntry(entry)

        let reloaded = UserDefaultsBPMHistoryStore(preferences: preferences)
        XCTAssertEqual(try reloaded.listEntries(), [entry])
    }

    func testListEntriesThrowsOnInvalidData() throws {
        let (store, preferences, key) = makeCorruptStore()

        XCTAssertThrowsError(try store.listEntries(), "unreadable history must surface, not silently empty")

        // The bad bytes are untouched by a read: recovery happens on save.
        XCTAssertEqual(preferences.data(forKey: key), Data("{not-json".utf8))
    }

    func testAddEntryQuarantinesCorruptBytesThenSavesFresh() throws {
        let (store, preferences, _) = makeCorruptStore()
        let entry = BPMHistoryEntry(
            bpm: 128.0,
            rawTappedBPM: 128.0,
            adjustment: .original,
            timestamp: Date(timeIntervalSince1970: 10)
        )

        // Must not trap: the save succeeds on a fresh history.
        try store.addEntry(entry)

        XCTAssertEqual(try store.listEntries(), [entry])
        XCTAssertEqual(
            preferences.data(forKey: store.corruptBackupKey),
            Data("{not-json".utf8),
            "bad bytes must be preserved under the quarantine key"
        )
    }

    func testClearEntriesRemovesCorruptDataWithoutDecoding() throws {
        let (store, preferences, key) = makeCorruptStore()

        XCTAssertNoThrow(try store.clearEntries())

        XCTAssertNil(preferences.data(forKey: key))
        XCTAssertEqual(try store.listEntries(), [])
    }

    func testClearEntriesPreservesExactBadBytesUnderBackupKey() throws {
        let (store, preferences, key) = makeCorruptStore()
        let badBytes = Data("{not-json".utf8)

        try store.clearEntries()

        XCTAssertNil(preferences.data(forKey: key), "live malformed key must be removed after backup")
        XCTAssertEqual(
            preferences.data(forKey: store.corruptBackupKey),
            badBytes,
            "exact malformed bytes must survive under the quarantine key"
        )
        XCTAssertEqual(try store.listEntries(), [])
    }

    func testClearEntriesKeepsLiveBytesWhenBackupCannotBeVerified() {
        let badBytes = Data("{not-json".utf8)
        let preferences = BackupDroppingPreferences(liveKey: "outsideCubaseHub.bpmHistory", liveData: badBytes)
        let store = UserDefaultsBPMHistoryStore(preferences: preferences)

        XCTAssertThrowsError(try store.clearEntries()) { error in
            XCTAssertEqual(error as? BPMHistoryStoreError, .corruptBackupFailed)
        }
        XCTAssertEqual(preferences.data(forKey: "outsideCubaseHub.bpmHistory"), badBytes)
    }

    func testAddEntryKeepsCorruptLiveBytesWhenBackupCannotBeVerified() {
        let badBytes = Data("{not-json".utf8)
        let key = "outsideCubaseHub.bpmHistory"
        let preferences = BackupDroppingPreferences(liveKey: key, liveData: badBytes)
        let store = UserDefaultsBPMHistoryStore(preferences: preferences)

        XCTAssertThrowsError(try store.addEntry(BPMHistoryEntry(bpm: 120, rawTappedBPM: 120, adjustment: .original))) { error in
            XCTAssertEqual(error as? BPMHistoryStoreError, .corruptBackupFailed)
        }
        XCTAssertEqual(preferences.data(forKey: key), badBytes)
    }

    func testBPMTapperFeatureUsesContextPreferences() throws {
        let source = try String(
            contentsOfFile: "Sources/FeatureBPMTapper/BPMTapperFeature.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("context.preferences"))
        XCTAssertFalse(source.contains("UserDefaultsBPMHistoryStore()"))
    }

    private func makeStore(
        suiteName: String = UUID().uuidString,
        reset: Bool = false
    ) -> UserDefaultsBPMHistoryStore {
        let userDefaults = UserDefaults(suiteName: suiteName)!
        if reset {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return UserDefaultsBPMHistoryStore(userDefaults: userDefaults)
    }

    private func uniqueSuiteName() -> String {
        "OutsideCubaseHubBPMHistoryTests.\(UUID().uuidString)"
    }

    /// An isolated preference store pre-seeded with invalid history bytes.
    private func makeCorruptStore() -> (
        store: UserDefaultsBPMHistoryStore,
        preferences: UserDefaultsPreferenceStore,
        key: String
    ) {
        let suiteName = uniqueSuiteName()
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let preferences = UserDefaultsPreferenceStore(userDefaults: userDefaults)
        let key = "outsideCubaseHub.bpmHistory"
        preferences.set(Data("{not-json".utf8), forKey: key)
        return (UserDefaultsBPMHistoryStore(preferences: preferences), preferences, key)
    }
}

/// In-memory preferences that drop writes to the quarantine backup key, so a
/// failed preservation can be exercised without touching UserDefaults.
private final class BackupDroppingPreferences: PreferenceStore, @unchecked Sendable {
    private var datas: [String: Data] = [:]
    private let backupSuffix = ".corruptBackup"

    init(liveKey: String, liveData: Data) {
        datas[liveKey] = liveData
    }

    func bool(forKey key: String) -> Bool? { nil }
    func set(_ value: Bool, forKey key: String) {}
    func data(forKey key: String) -> Data? { datas[key] }
    func set(_ data: Data, forKey key: String) {
        // Simulate a preservation failure: live writes work, backup writes drop.
        if key.hasSuffix(backupSuffix) { return }
        datas[key] = data
    }
    func string(forKey key: String) -> String? { nil }
    func set(_ value: String, forKey key: String) {}
    func removeObject(forKey key: String) { datas.removeValue(forKey: key) }
}
