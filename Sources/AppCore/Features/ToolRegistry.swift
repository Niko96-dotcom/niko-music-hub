import Foundation

public struct DuplicateToolFeatureID: Error, Equatable, Sendable, CustomStringConvertible {
    public let id: ToolFeatureID

    public init(id: ToolFeatureID) {
        self.id = id
    }

    public var description: String {
        "Duplicate tool feature id: \(id.rawValue)"
    }
}

public struct ToolRegistry: Sendable {
    public let features: [any ToolFeature]
    public let metadata: [ToolMetadata]

    public init(features: [any ToolFeature]) throws {
        var seenIDs = Set<ToolFeatureID>()
        var orderedMetadata: [ToolMetadata] = []

        for feature in features {
            let metadata = feature.metadata
            guard seenIDs.insert(metadata.id).inserted else {
                throw DuplicateToolFeatureID(id: metadata.id)
            }
            orderedMetadata.append(metadata)
        }

        self.features = features
        self.metadata = orderedMetadata
    }

    public var firstFeatureID: ToolFeatureID? {
        metadata.first?.id
    }

    /// Default sidebar selection when the shell opens.
    public var preferredDefaultFeatureID: ToolFeatureID? {
        feature(for: "archive-browser")?.metadata.id
            ?? feature(for: "wav-converter")?.metadata.id
            ?? firstFeatureID
    }

    public func feature(for id: ToolFeatureID) -> (any ToolFeature)? {
        features.first { $0.metadata.id == id }
    }
}
