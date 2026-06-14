import AppCore
import FeatureStemSeparation
import Foundation

final class MockStemSeparationBackend: StemSeparationBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [StemSeparationBackendRequest] = []
    private var canceled = false

    var requestedResult: StemSeparationResult = .failed(message: "not configured")
    var filesToWrite: [(StemRole, String)] = []

    var requests: [StemSeparationBackendRequest] { lock.withLock { recordedRequests } }
    var isCanceled: Bool { lock.withLock { canceled } }

    var supportedPresets: [StemSeparationPreset] {
        StemSeparationPreset.allCases
    }

    func health(settings: HelperToolSettings) async -> StemBackendHealth {
        .ready(version: "mock")
    }

    func separate(
        request: StemSeparationBackendRequest,
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) async -> StemSeparationResult {
        lock.withLock { recordedRequests.append(request) }

        for (index, file) in filesToWrite.enumerated() {
            if Task.isCancelled || isCanceled {
                return .canceled
            }
            let url = request.outputFolderURL.appendingPathComponent(file.1)
            try? FileManager.default.createDirectory(
                at: request.outputFolderURL,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: Data("stem".utf8))
            onProgress(Double(index + 1) / Double(filesToWrite.count), "Wrote \(file.1)")
        }

        if case .success(_, let stems) = requestedResult {
            return .success(outputFolderURL: request.outputFolderURL, stems: stems)
        }
        return requestedResult
    }

    func cancel() {
        lock.withLock { canceled = true }
    }
}
