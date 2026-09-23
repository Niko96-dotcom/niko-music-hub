import Foundation

public enum MusicRootRole: String, Codable, Sendable, CaseIterable {
    case scanOnly
    case active
    case archive
}

public struct StoredMusicRoot: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var role: MusicRootRole
    public var displayName: String
    public var pathFallback: String
    public var securityScopedBookmark: Data?
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        role: MusicRootRole,
        displayName: String,
        pathFallback: String,
        securityScopedBookmark: Data? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.role = role
        self.displayName = displayName
        self.pathFallback = pathFallback
        self.securityScopedBookmark = securityScopedBookmark
        self.isEnabled = isEnabled
    }

    public init(
        id: UUID = UUID(),
        role: MusicRootRole,
        url: URL,
        securityScopedBookmark: Data? = nil,
        isEnabled: Bool = true
    ) {
        self.init(
            id: id,
            role: role,
            displayName: url.lastPathComponent,
            pathFallback: url.standardizedFileURL.path,
            securityScopedBookmark: securityScopedBookmark,
            isEnabled: isEnabled
        )
    }

    public var fallbackURL: URL {
        URL(fileURLWithPath: pathFallback, isDirectory: true).standardizedFileURL
    }
}

public enum SecurityScopedBookmarkError: Error, Equatable, Sendable {
    case missingBookmark
    case staleBookmark
}

public protocol SecurityScopedBookmarkProviding: Sendable {
    func makeBookmark(for url: URL) throws -> Data
}

public protocol SecurityScopedBookmarkResolving: Sendable {
    func resolveBookmark(_ data: Data) throws -> URL
}

public struct FoundationSecurityScopedBookmarks: SecurityScopedBookmarkProviding, SecurityScopedBookmarkResolving {
    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard !isStale else { throw SecurityScopedBookmarkError.staleBookmark }
        return url.standardizedFileURL
    }
}

public extension StoredMusicRoot {
    /// Resolves persisted sandbox access, falling back to the stored path only when no
    /// bookmark exists. A corrupt or stale bookmark fails closed instead of silently
    /// changing the selected root's identity.
    func resolvedURL(using resolver: any SecurityScopedBookmarkResolving) throws -> URL {
        guard let securityScopedBookmark else { return fallbackURL }
        return try resolver.resolveBookmark(securityScopedBookmark)
    }
}

public final class SecurityScopedRootAccess: @unchecked Sendable {
    public let url: URL
    private let didStartAccessing: Bool

    public init(url: URL) {
        self.url = url.standardizedFileURL
        self.didStartAccessing = self.url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

public enum MusicRootValidationError: Error, Equatable, Sendable {
    case rootDoesNotExist(URL)
    case rootIsNotDirectory(URL)
    case rootsOverlap(active: URL, archive: URL)
    case rootOverlapsApplicationData(URL)
}

public struct MusicRootValidator: @unchecked Sendable {
    private let fileManager: FileManager
    private let applicationDataRoots: [URL]

    public init(
        fileManager: FileManager = .default,
        applicationDataRoots: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.applicationDataRoots = applicationDataRoots ?? Self.defaultApplicationDataRoots(fileManager: fileManager)
    }

    public func validate(activeRoot: URL, archiveRoot: URL) throws {
        let active = try validateCandidate(activeRoot)
        let archive = try validateCandidate(archiveRoot)

        guard !overlaps(active, archive) else {
            throw MusicRootValidationError.rootsOverlap(active: active, archive: archive)
        }
    }

    @discardableResult
    public func validateCandidate(_ root: URL) throws -> URL {
        let validated = try validatedDirectory(root)
        if applicationDataRoots.contains(where: { overlaps(validated, canonical($0)) }) {
            throw MusicRootValidationError.rootOverlapsApplicationData(validated)
        }
        return validated
    }

    public func canonicalURL(for url: URL) -> URL {
        canonical(url)
    }

    private func validatedDirectory(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw MusicRootValidationError.rootDoesNotExist(standardized)
        }
        guard isDirectory.boolValue else {
            throw MusicRootValidationError.rootIsNotDirectory(standardized)
        }
        return canonical(standardized)
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private func overlaps(_ lhs: URL, _ rhs: URL) -> Bool {
        PathSafety().resolvedPathsOverlapIgnoringCase(canonical(lhs), canonical(rhs))
    }

    private static func defaultApplicationDataRoots(fileManager: FileManager) -> [URL] {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return []
        }
        return [support.appendingPathComponent("Niko Music Hub", isDirectory: true)]
    }
}
