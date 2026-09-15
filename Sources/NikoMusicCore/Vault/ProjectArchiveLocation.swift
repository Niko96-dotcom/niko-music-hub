import Foundation

/// Resolves ordinary, catalog-linked archive folders separately from managed generations.
public struct ProjectArchiveLocationResolver: Sendable {
    public let rootID: UUID
    public let rootURL: URL

    public init(rootID: UUID, rootURL: URL) {
        self.rootID = rootID
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func resolve(_ location: ProjectLocation) -> URL? {
        guard location.rootID == rootID, location.kind == .archive,
              Self.isOrdinaryArchivePath(location.relativePath) else { return nil }
        let candidate = rootURL.appendingPathComponent(location.relativePath, isDirectory: true)
        guard PathSafety().isResolvedContainedWithoutNestedSymlinks(candidate, in: rootURL) else { return nil }
        return candidate.standardizedFileURL
    }

    public static func isOrdinaryArchivePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && !path.contains("\0")
            && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
            && !["generations", ".niko-staging"].contains(parts[0].lowercased())
    }
}

/// Metadata-only availability. A locally present provider directory does not imply
/// that its project files and audio have been downloaded.
public struct ProjectArchiveAvailabilityProbe: Sendable {
    private let fileAvailability: @Sendable (URL) throws -> Availability

    public init() {
        fileAvailability = Self.foundationAvailability
    }

    init(fileAvailability: @escaping @Sendable (URL) throws -> Availability) {
        self.fileAvailability = fileAvailability
    }

    public func availability(at folder: URL) throws -> Availability {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        var enumerationFailed = false
        guard let walker = manager.enumerator(
            at: folder, includingPropertiesForKeys: Array(keys),
            errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw FileProviderArchiveStorageError.lookupUnavailable }
        var availability = Availability.local
        for case let url as URL in walker {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { throw FileProviderArchiveStorageError.lookupUnavailable }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw FileProviderArchiveStorageError.lookupUnavailable }
            switch try fileAvailability(url) {
            case .local: break
            case .onlineOnly:
                if availability != .materializing { availability = .onlineOnly }
            case .materializing: availability = .materializing
            case .missing: throw FileProviderArchiveStorageError.lookupUnavailable
            }
        }
        guard !enumerationFailed else { throw FileProviderArchiveStorageError.lookupUnavailable }
        return availability
    }

    private static func foundationAvailability(at url: URL) throws -> Availability {
        if !FileManager.default.isUbiquitousItem(at: url) { return .local }
        let values = try url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingErrorKey,
        ])
        guard values.ubiquitousItemDownloadingError == nil else {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
        if values.ubiquitousItemIsDownloading == true { return .materializing }
        switch values.ubiquitousItemDownloadingStatus {
        case .current?: return .local
        case .downloaded?, .notDownloaded?: return .onlineOnly
        default: throw FileProviderArchiveStorageError.lookupUnavailable
        }
    }
}
