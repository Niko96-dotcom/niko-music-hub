import Foundation

public protocol FileActions: Sendable {
    @MainActor
    func chooseOutputFolder() -> URL?

    @MainActor
    func revealInFinder(_ url: URL)
}
