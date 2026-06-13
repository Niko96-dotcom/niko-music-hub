import Foundation

public enum StemBackendHealth: Equatable, Sendable {
    case missing
    case unusable(message: String)
    case modelCacheMissing
    case ready(version: String)
}
