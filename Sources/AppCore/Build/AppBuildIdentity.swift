import Foundation

public struct AppBuildIdentity: Equatable, Sendable {
    public let marketingVersion: String?
    public let buildID: String?
    public let sourceCommit: String?

    public init(infoDictionary: [String: Any]) {
        marketingVersion = Self.nonEmptyString(infoDictionary["CFBundleShortVersionString"])
        buildID = Self.nonEmptyString(infoDictionary["NMHBuildID"])
        sourceCommit = Self.nonEmptyString(infoDictionary["NMHSourceCommit"])
    }

    public init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public var compactLabel: String {
        guard let value = buildID ?? marketingVersion else { return "" }
        return "v\(value)"
    }

    public var shortSourceCommit: String? {
        sourceCommit.map { String($0.prefix(12)) }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
