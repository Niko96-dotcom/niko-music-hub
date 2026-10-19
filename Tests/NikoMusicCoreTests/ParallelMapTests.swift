import XCTest
@testable import NikoMusicCore

final class ParallelMapTests: XCTestCase {
    func testMatchesSerialMapAndKeepsOrder() {
        let input = Array(0..<5_000)
        XCTAssertEqual(ParallelMap.map(input) { $0 * 3 + 1 }, input.map { $0 * 3 + 1 })
    }

    func testSmallAndEmptyInputsRunSerially() {
        XCTAssertEqual(ParallelMap.map([Int]()) { $0 }, [])
        XCTAssertEqual(ParallelMap.map([7]) { $0 + 1 }, [8])
        XCTAssertEqual(ParallelMap.map(Array(0..<10)) { $0 * $0 }, (0..<10).map { $0 * $0 })
    }

    func testRunsOnSeveralThreadsForLargeInput() throws {
        let lock = NSLock()
        nonisolated(unsafe) var threads = Set<Thread>()
        _ = ParallelMap.map(Array(0..<2_000), minimumParallelCount: 8) { value -> Int in
            lock.withLock { _ = threads.insert(Thread.current) }
            Thread.sleep(forTimeInterval: 0.0002)
            return value
        }
        if ProcessInfo.processInfo.activeProcessorCount > 1 {
            XCTAssertGreaterThan(lock.withLock { threads.count }, 1)
        }
    }

    func testRethrowsTheFailureWithTheLowestIndex() {
        struct Failure: Error, Equatable { let index: Int }
        let input = Array(0..<4_000)
        XCTAssertThrowsError(try ParallelMap.map(input) { value -> Int in
            if value % 500 == 499 { throw Failure(index: value) }
            return value
        }) { error in
            XCTAssertEqual(error as? Failure, Failure(index: 499))
        }
    }

    func testNormalizingSongsMatchesTheSerialPass() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let songs = (0..<400).map { index -> Song in
            let folder = URL(fileURLWithPath: "/tmp/parallel-\(index)", isDirectory: true)
            let names = ["Song \(index) mix.wav", "Song \(index) v2 master.wav", "Song \(index) instr.wav", "Song \(index) (Bass).wav"]
            let previews = names.map { name in
                PreviewCandidate(
                    filePath: folder.appendingPathComponent("Mixdown").appendingPathComponent(name),
                    fileName: name, folderRole: .mixdown, modifiedAt: date, detectedRole: .unknown,
                    durationSeconds: Double(40 + index % 7)
                )
            }
            return Song(folderPath: folder, originalFolderName: "Song \(index)", displayTitle: "Song \(index)",
                        previewCandidates: previews)
        }
        XCTAssertEqual(PreviewAutoSelectionNormalizer.normalized(songs), songs.map(PreviewAutoSelectionNormalizer.normalized))
    }
}
