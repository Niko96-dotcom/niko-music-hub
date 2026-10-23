import AppCore
import Foundation

public protocol StemSeparationBackend: Sendable {
    var supportedPresets: [StemSeparationPreset] { get }

    func separate(
        request: StemSeparationBackendRequest,
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) async -> StemSeparationResult

    func cancel()
}
