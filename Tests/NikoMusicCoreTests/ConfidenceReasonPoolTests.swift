import Foundation
@testable import NikoMusicCore
import XCTest

final class ConfidenceReasonPoolTests: XCTestCase {
    private func candidate(_ name: String, reasons: [String]) -> PreviewCandidate {
        PreviewCandidate(
            filePath: URL(fileURLWithPath: "/tmp/pool/\(name).wav"), fileName: "\(name).wav", folderRole: .mixdown,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000), detectedRole: .mainMix, detectedVersionNumber: 3,
            durationSeconds: 215.5, confidenceScore: 42, confidenceReasons: reasons)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func sameStorage(_ left: [String], _ right: [String]) -> Bool {
        left.withUnsafeBufferPointer { l in right.withUnsafeBufferPointer { r in l.baseAddress == r.baseAddress } }
    }

    func testDecodedCandidatesRoundTrip() throws {
        var original = candidate("Song v3", reasons: ["folder:mixdown", "role:full-mix", "extension:wav", "recency"])
        original.namedDeliveryModifiedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let decoded = try decoder().decode(PreviewCandidate.self, from: try encoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testRowsWithoutTheOptionalKeysStillDecode() throws {
        let json = """
        {"id":"/tmp/a.wav","filePath":"file:///tmp/a.wav","fileName":"a.wav","folderRole":"root","modifiedAt":"2023-11-14T22:13:20Z",
         "detectedRole":"unknown","fileExtension":"wav","confidenceScore":1.5,"confidenceReasons":["recency"]}
        """
        let decoded = try decoder().decode(PreviewCandidate.self, from: Data(json.utf8))
        XCTAssertNil(decoded.detectedVersionNumber)
        XCTAssertNil(decoded.durationSeconds)
        XCTAssertNil(decoded.namedDeliveryModifiedAt)
        XCTAssertEqual(decoded.confidenceReasons, ["recency"])
    }

    func testARowMissingARequiredKeyStillFails() {
        let json = #"{"id":"/tmp/a.wav","fileName":"a.wav"}"#
        XCTAssertThrowsError(try decoder().decode(PreviewCandidate.self, from: Data(json.utf8)))
    }

    func testCandidatesWithTheSameReasonsShareOneArray() throws {
        let reasons = ["folder:mixdown", "role:full-mix", "pool-test:unique-\(UUID().uuidString)", "recency"]
        let data = try encoder().encode([candidate("One", reasons: reasons), candidate("Two", reasons: reasons)])
        let decoded = try decoder().decode([PreviewCandidate].self, from: data)
        XCTAssertEqual(decoded[0].confidenceReasons, reasons)
        XCTAssertTrue(sameStorage(decoded[0].confidenceReasons, decoded[1].confidenceReasons))
    }

    func testDifferentReasonsStayDifferent() {
        let pool = ConfidenceReasonPool.shared
        let first = pool.canonical(["pool-test:a-\(UUID().uuidString)"])
        let second = pool.canonical(["pool-test:b-\(UUID().uuidString)"])
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(pool.canonical([]), [])
    }
}
