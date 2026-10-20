import Foundation

/// A catalog stores a URL's value, not an enumeration's resource cache or a
/// parsed copy of every path component. A fresh NSURL keeps the same URL text
/// in compact Foundation storage. Encoding remains the existing URL format.
@propertyWrapper
public struct ArchiveFileURL: Hashable, Sendable, Codable {
    public let wrappedValue: URL

    public init(wrappedValue: URL) {
        self.wrappedValue = NSURL(string: wrappedValue.absoluteString).map { $0 as URL } ?? wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(wrappedValue: try container.decode(URL.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}
