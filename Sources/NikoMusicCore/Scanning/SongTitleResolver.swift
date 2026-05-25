import Foundation

public struct SongTitleResolver: Sendable {
    public init() {}

    public func displayTitle(fromFolderName name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
