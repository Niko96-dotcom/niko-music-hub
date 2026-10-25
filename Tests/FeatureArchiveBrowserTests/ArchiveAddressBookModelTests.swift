import AppCore
@testable import FeatureArchiveBrowser
import Foundation
import NikoMusicCore
import XCTest

/// The address book owner on its own: a failed load keeps the last list and warns, names are
/// trimmed, and a staged removal ends whether the delete works or not.
@MainActor
final class ArchiveAddressBookModelTests: XCTestCase {
    private struct NoDiagnostics: Diagnostics {
        func log(_ level: DiagnosticLevel, _ message: String) {}
    }

    private final class Store: CollaboratorStoring, @unchecked Sendable {
        var rows: [Collaborator] = []
        var failLoad = false
        var failDelete = false
        struct Failure: Error {}

        func loadAll() throws -> [Collaborator] {
            if failLoad { throw Failure() }
            return rows
        }

        func upsert(_ collaborator: Collaborator) throws {
            rows.removeAll { $0.id == collaborator.id }
            rows.append(collaborator)
        }

        func delete(id: String) throws {
            if failDelete { throw Failure() }
            rows.removeAll { $0.id == id }
        }
    }

    private func makeBook(_ store: Store?, warnings: @escaping @MainActor (String) -> Void = { _ in }) -> ArchiveAddressBookModel {
        ArchiveAddressBookModel(store: store, diagnostics: NoDiagnostics(), reportWarning: warnings)
    }

    func testAFailedLoadKeepsTheLastListAndWarns() {
        let store = Store()
        store.rows = [Collaborator(id: "maria", displayName: "Maria")]
        var warnings: [String] = []
        let book = makeBook(store) { warnings.append($0) }
        book.load()

        store.failLoad = true
        book.load()

        XCTAssertEqual(book.collaborators.map(\.id), ["maria"], "names stay resolvable")
        XCTAssertEqual(warnings.count, 1)
    }

    func testAddTrimsTheNameAndRefusesAnEmptyOne() {
        let store = Store()
        let book = makeBook(store)

        XCTAssertNil(book.add(name: "   "))
        let added = book.add(name: "  Jamie Rivera ")

        XCTAssertEqual(added?.displayName, "Jamie Rivera")
        XCTAssertEqual(book.collaborators.map(\.displayName), ["Jamie Rivera"])
    }

    func testWithoutAStoreNothingIsWritten() {
        let book = makeBook(nil)

        XCTAssertFalse(book.canWrite)
        XCTAssertNil(book.add(name: "Jamie"))
        XCTAssertTrue(book.collaborators.isEmpty)
    }

    func testAStagedRemovalEndsWhenTheDeleteWorksOrFails() throws {
        let store = Store()
        let book = makeBook(store)
        let jamie = try XCTUnwrap(book.add(name: "Jamie"))
        let maria = try XCTUnwrap(book.add(name: "Maria"))

        book.requestRemoval(jamie)
        try book.deletePendingCollaborator()
        XCTAssertNil(book.pendingCollaboratorRemoval)
        XCTAssertEqual(book.collaborators.map(\.id), [maria.id])

        store.failDelete = true
        book.requestRemoval(maria)
        XCTAssertThrowsError(try book.deletePendingCollaborator())
        XCTAssertNil(book.pendingCollaboratorRemoval)
        XCTAssertEqual(book.collaborators.map(\.id), [maria.id], "a failed delete keeps the row")
    }
}
