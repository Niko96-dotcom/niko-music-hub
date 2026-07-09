import NikoMusicCore
import XCTest

final class SQLiteCollaboratorStoreTests: XCTestCase {
    func testRoundtripCollaborator() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collaborator-\(UUID().uuidString).sqlite")
        let store = try SQLiteCollaboratorStore(databaseURL: databaseURL)
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let collaborator = Collaborator(displayName: "Jamie")

        try store.upsert(collaborator)

        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.map(\.displayName), ["Jamie"])
    }

    func testSQLiteCollaboratorStoreUsesTruthfulStepHandlingAndBusyTimeout() throws {
        let source = try String(
            contentsOfFile: "Sources/NikoMusicCore/Persistence/SQLiteCollaboratorStore.swift",
            encoding: .utf8
        )
        let databaseSource = try String(
            contentsOfFile: "Sources/NikoMusicCore/Persistence/SQLiteArchiveDatabase.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("database.withConnection"))
        XCTAssertTrue(databaseSource.contains("sqlite3_busy_timeout(db, 5_000)"))
        XCTAssertTrue(source.contains("case SQLITE_DONE:"))
        XCTAssertTrue(source.contains("throw StoreError.step(message(db))"))
        XCTAssertFalse(source.contains("while sqlite3_step(statement) == SQLITE_ROW"))
    }
}
