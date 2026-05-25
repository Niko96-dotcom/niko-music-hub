import Foundation
import SwiftUI

public struct ToolFeatureID: Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public var description: String {
        rawValue
    }
}

public struct ToolCapability: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let producesFiles = ToolCapability(rawValue: 1 << 0)
    public static let runsJobs = ToolCapability(rawValue: 1 << 1)
}

public struct ToolMetadata: Hashable, Codable, Sendable {
    public let id: ToolFeatureID
    public let displayName: String
    public let shortLabel: String
    public let systemImage: String
    public let capabilities: ToolCapability

    public init(
        id: ToolFeatureID,
        displayName: String,
        shortLabel: String,
        systemImage: String,
        capabilities: ToolCapability = []
    ) {
        self.id = id
        self.displayName = displayName
        self.shortLabel = shortLabel
        self.systemImage = systemImage
        self.capabilities = capabilities
    }
}

public protocol ToolFeature: Sendable {
    var metadata: ToolMetadata { get }

    @MainActor
    func makeView(context: ToolContext) -> AnyView
}
