import Foundation
import XCTest

enum SourceTestSupport {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func read(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let url = packageRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Required source file is missing: \(relativePath)", file: file, line: line)
            throw SourceTestError.missing(relativePath)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private enum SourceTestError: Error {
    case missing(String)
}
