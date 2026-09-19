import Darwin
import Foundation

/// Fail-closed errors from the local Vault persistence barrier.
///
/// Every case preserves the staged or promoted bytes: the barrier never
/// deletes, moves, or renames anything. A thrown error means "durability is
/// not proven, keep every copy", never "the data is gone".
public enum LocalVaultDurabilityBarrierError: Error, Equatable, Sendable {
    case missingNode(URL)
    case locationOutsideArchiveRoot(URL)
    case symlinkEscape(URL)
    case unexpectedNodeType(URL)
    case unsupportedFilesystem(String)
    case deviceMismatch(URL)
    case fileFlushFailed(URL, errno: Int32)
    case directoryFlushFailed(URL, errno: Int32)
    case fullSyncFailed(URL, errno: Int32)
}

extension LocalVaultDurabilityBarrierError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingNode(let url):
            "The archive copy at \(url.path) disappeared before durability could be confirmed. Existing copies were kept."
        case .locationOutsideArchiveRoot(let url):
            "The archive copy at \(url.path) is outside the configured archive folder, or resolves through a link that escapes it. Existing copies were kept."
        case .symlinkEscape(let url):
            "The archive copy contains a symbolic link at \(url.path) that could divert durability or promotion outside the archive folder. Existing copies were kept."
        case .unexpectedNodeType(let url):
            "The archive copy contains an unsupported filesystem node at \(url.path). Only regular files and directories are archived. Existing copies were kept."
        case .unsupportedFilesystem(let name):
            "The archive volume uses the \"\(name)\" filesystem, which cannot confirm local persistence with F_FULLFSYNC. The archive copy was kept; reconnect a supported local volume or keep the Active copy."
        case .deviceMismatch(let url):
            "The archive copy at \(url.path) changed volumes or was replaced during the transfer (device or inode identity no longer matches the traversed node). Existing copies were kept."
        case .fileFlushFailed(let url, let errno):
            "Persisting file data at \(url.path) failed (errno \(errno)). The archive copy was kept."
        case .directoryFlushFailed(let url, let errno):
            "Persisting a directory entry at \(url.path) failed (errno \(errno)). The archive copy was kept."
        case .fullSyncFailed(let url, let errno):
            "Draining the device queue for \(url.path) failed (errno \(errno)). An earlier plain sync is not sufficient evidence, so durability is not claimed. The archive copy was kept."
        }
    }
}

/// Narrow injectable seam for the local Vault persistence barrier.
///
/// The barrier walks real directories and opens real descriptors, but every
/// durability decision flows through these closures so tests can fail each
/// flush deterministically and assert the exact flush order without touching
/// real volumes, rebooting, or disconnecting drives.
///
/// Closure order for `synchronize` / `drainDeviceQueue` is
/// `(descriptor, url, isDirectory)`.
public struct LocalVaultFlushSeam: Sendable {
    public var deviceIDOf: @Sendable (URL) throws -> UInt64
    public var inodeOf: @Sendable (URL) throws -> UInt64
    public var filesystemTypeOf: @Sendable (URL) throws -> String
    public var filesystemTypeOfDescriptor: @Sendable (Int32, URL) throws -> String
    public var synchronize: @Sendable (Int32, URL, Bool) throws -> Void
    public var drainDeviceQueue: @Sendable (Int32, URL, Bool) throws -> Void
    public var checkCancellation: @Sendable () throws -> Void

    public init(
        deviceIDOf: @escaping @Sendable (URL) throws -> UInt64,
        inodeOf: @escaping @Sendable (URL) throws -> UInt64,
        filesystemTypeOf: @escaping @Sendable (URL) throws -> String,
        filesystemTypeOfDescriptor: @escaping @Sendable (Int32, URL) throws -> String,
        synchronize: @escaping @Sendable (Int32, URL, Bool) throws -> Void,
        drainDeviceQueue: @escaping @Sendable (Int32, URL, Bool) throws -> Void,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) {
        self.deviceIDOf = deviceIDOf
        self.inodeOf = inodeOf
        self.filesystemTypeOf = filesystemTypeOf
        self.filesystemTypeOfDescriptor = filesystemTypeOfDescriptor
        self.synchronize = synchronize
        self.drainDeviceQueue = drainDeviceQueue
        self.checkCancellation = checkCancellation
    }

    /// Live syscalls. `synchronize` issues `fsync` per node; a single terminal
    /// `drainDeviceQueue` issues `F_FULLFSYNC` on the archive root after all
    /// `fsync`s. A `drainDeviceQueue` failure is reported as `fullSyncFailed`
    /// even when every earlier `fsync` succeeded: there is no downgrade from
    /// a failed full flush to a plain-sync success claim.
    ///
    /// Primary sources:
    /// - https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2
    /// - https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fsync.2
    /// - https://developer.apple.com/documentation/xcode/reducing-disk-writes
    public static var live: Self {
        Self(
            deviceIDOf: { url in try Self.liveDeviceID(of: url) },
            inodeOf: { url in try Self.liveInodeOf(of: url) },
            filesystemTypeOf: { url in try Self.liveFilesystemType(of: url) },
            filesystemTypeOfDescriptor: { descriptor, url in try Self.liveFilesystemType(ofDescriptor: descriptor, url: url) },
            synchronize: { descriptor, url, isDirectory in
                guard Darwin.fsync(descriptor) == 0 else {
                    let code = errno
                    if isDirectory {
                        throw LocalVaultDurabilityBarrierError.directoryFlushFailed(url, errno: code)
                    }
                    throw LocalVaultDurabilityBarrierError.fileFlushFailed(url, errno: code)
                }
            },
            drainDeviceQueue: { descriptor, url, _ in
                guard Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 else {
                    throw LocalVaultDurabilityBarrierError.fullSyncFailed(url, errno: errno)
                }
            },
            checkCancellation: { try Task.checkCancellation() }
        )
    }

    static func liveDeviceID(of url: URL) throws -> UInt64 {
        var information = stat()
        guard url.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw LocalVaultDurabilityBarrierError.missingNode(url)
        }
        return UInt64(information.st_dev)
    }

    static func liveInodeOf(of url: URL) throws -> UInt64 {
        var information = stat()
        guard url.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw LocalVaultDurabilityBarrierError.missingNode(url)
        }
        return UInt64(information.st_ino)
    }

    static func liveFilesystemType(of url: URL) throws -> String {
        // `Darwin.statfs` resolves to the `statfs` struct constructor on the
        // actual Swift SDK (the path-based C function is not addressable as
        // `Darwin.statfs`), so qualify via a descriptor instead. Opening with
        // `O_NOFOLLOW` keeps a swapped-in symlink fail-closed (`ELOOP` maps to
        // `missingNode`), and `fstatfs` binds the query to the opened node
        // rather than a re-resolved path.
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw LocalVaultDurabilityBarrierError.missingNode(url)
        }
        defer { _ = Darwin.close(descriptor) }
        return try liveFilesystemType(ofDescriptor: descriptor, url: url)
    }

    /// Filesystem qualification bound to an already-opened descriptor: the
    /// terminal drain calls this on the drain fd itself (same descriptor as
    /// the drain `fstat`), so a volume replacement between the start-of-run
    /// qualification and the drain cannot mis-qualify. Anything unlisted
    /// (including `exfat`/`nfs`/`smbfs`) fails closed with
    /// `unsupportedFilesystem`.
    static func liveFilesystemType(ofDescriptor descriptor: Int32, url: URL) throws -> String {
        var volume = statfs()
        guard Darwin.fstatfs(descriptor, &volume) == 0 else {
            throw LocalVaultDurabilityBarrierError.unsupportedFilesystem("unknown")
        }
        let rawName = volume.f_fstypename
        let bytes = withUnsafeBytes(of: rawName) { Array($0) }
        let name = String(bytes: bytes.prefix(while: { $0 != 0 }), encoding: .utf8)
        return (name ?? "unknown").lowercased()
    }
}

/// Honest local persistence barrier for one Vault generation directory.
///
/// Before the transfer engine may treat a staged or promoted generation as
/// durable (and therefore before anything may authorize removal of the Active
/// copy), the barrier:
///
/// 1. Confines the generation to the configured archive root, checking the
///    requested (standardized, unresolved) path with `PathSafety` *before*
///    resolving symlinks, plus per-node `lstat` checks. Pre-resolving would
///    hide a nested symlink in the requested prefix. The well-known macOS
///    `/tmp`→`/private/tmp` and `/var`→`/private/var` alias spellings are
///    normalized for this check only, so a legitimate user spelling still
///    confines while nested symlinks keep failing closed.
/// 2. Qualifies the volume via a descriptor (`fstatfs`): only filesystems
///    with documented `F_FULLFSYNC` support count as local-durable. Anything
///    else fails closed with `unsupportedFilesystem`, preserving every byte.
///    Qualification happens at start AND again on the terminal drain
///    descriptor itself (same fd as the drain `fstat`), so a volume
///    replacement between start and drain cannot mis-qualify.
/// 3. Binds every traversed node to a device+inode identity (`st_dev` plus
///    `st_ino`, observed through the seam and re-verified with `fstat` on the
///    opened descriptor at flush time). A mid-traversal volume replacement or
///    same-device same-type path replacement fails closed with
///    `deviceMismatch` instead of flushing the wrong object.
/// 4. Flushes in order: `fsync` every regular file, then `fsync` directories
///    deepest-first (including the generation root), then `fsync` the
///    promotion ancestor chain from the generation parent inside-out through
///    the configured archive root, so the final rename entry is persisted
///    too. A generation equal to the archive root traverses the full tree
///    (no root-only shortcut).
/// 5. Drains once: a single terminal `F_FULLFSYNC` on the archive root (same
///    `st_dev` and same qualified filesystem type, both verified at open on
///    the drain descriptor itself) after all `fsync`s. Per XNU `fcntl(2)`, a
///    successful `F_FULLFSYNC` drains the device queue, so previously synced
///    data on that device persists; one drain replaces per-file drains
///    without weakening the claim and avoids per-file full-sync cost.
/// 6. Never downgrades: a failed terminal drain reports `fullSyncFailed` even
///    when every earlier `fsync` succeeded.
///
/// Barrier success returns `.verifiedLocal` and means the operating system
/// accepted the full persistence sequence on a qualified local filesystem.
/// It is not a guarantee of hardware power-loss survival: drives may ignore
/// flush requests, and only the hardware vendor's contract governs the
/// platters. See `docs/vault-durability.md`.
///
/// The cloud (File Provider) contract is distinct: this barrier makes no
/// claim about remote upload or sync. See `FileProviderArchiveStorage`.
public struct LocalVaultDurabilityBarrier: @unchecked Sendable {
    /// Filesystem type names with documented `F_FULLFSYNC` support, matching
    /// the XNU `fcntl(2)` manual (APFS/HFS/FAT/UDF; macOS reports FAT as
    /// `msdos`). Anything else — including `exfat`, `nfs`, and `smbfs` — is
    /// unqualified until primary evidence confirms its flush contract, and
    /// fails closed with `unsupportedFilesystem`.
    ///
    /// Primary source:
    /// https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/man/man2/fcntl.2
    public static let supportedFilesystemTypeNames: Set<String> = ["apfs", "hfs", "msdos", "udf"]

    private let archiveRoot: URL
    private let fileManager: FileManager
    private let seam: LocalVaultFlushSeam

    public init(
        archiveRoot: URL,
        fileManager: FileManager = .default,
        seam: LocalVaultFlushSeam = .live
    ) {
        self.archiveRoot = archiveRoot
        self.fileManager = fileManager
        self.seam = seam
    }

    /// Flush one generation directory (staging or promoted) and its promotion
    /// ancestors through the archive root. Returns `.verifiedLocal` only when
    /// the full sequence succeeded. Throws fail-closed otherwise, preserving
    /// all bytes. `CancellationError` from the seam propagates unwrapped so
    /// callers keep cancellation semantics.
    @discardableResult
    public func makeDurable(at generationURL: URL) throws -> VaultDurability {
        try seam.checkCancellation()
        let canonicalRoot = archiveRoot.standardizedFileURL.resolvingSymlinksInPath()
        // Check the requested path BEFORE resolving: pre-resolving would hide
        // a nested symlink in the requested prefix from PathSafety's
        // per-component `lstat` walk.
        let requestedGeneration = generationURL.standardizedFileURL
        let filesystem = try seam.filesystemTypeOf(canonicalRoot)
        guard Self.supportedFilesystemTypeNames.contains(filesystem) else {
            throw LocalVaultDurabilityBarrierError.unsupportedFilesystem(filesystem)
        }
        let rootDevice = try seam.deviceIDOf(canonicalRoot)
        let rootInode = try seam.inodeOf(canonicalRoot)
        let safety = PathSafety(fileManager: fileManager)
        // Narrow alias tolerance: map the well-known `/tmp` and `/var`
        // spellings onto their `/private` canonical forms for the safety
        // check only. Arbitrary symlinks still fail closed inside
        // `PathSafety`'s per-component `lstat` walk; only these two system
        // prefixes are rewritten.
        let requestedForSafety = Self.normalizedSafetyURL(requestedGeneration)
        guard safety.isResolvedContainedWithoutNestedSymlinks(requestedForSafety, in: canonicalRoot) else {
            throw LocalVaultDurabilityBarrierError.locationOutsideArchiveRoot(generationURL)
        }
        let canonicalGeneration = requestedGeneration.resolvingSymlinksInPath()
        // A generation equal to the archive root traverses the full tree
        // below; there is no root-only shortcut (flushing only the root would
        // falsely claim the whole tree durable).
        let generationInode = try validateGenerationNode(canonicalGeneration, expectedDevice: rootDevice)
        var files: [(url: URL, inode: UInt64)] = []
        var directories: [(url: URL, inode: UInt64)] = [(canonicalGeneration, generationInode)]
        try collect(node: canonicalGeneration, expectedDevice: rootDevice, files: &files, directories: &directories)
        let orderedFiles = files.sorted(by: { $0.url.path < $1.url.path })
        let orderedDirectories = directories.sorted(by: {
            if $0.url.path.count != $1.url.path.count { return $0.url.path.count > $1.url.path.count }
            return $0.url.path < $1.url.path
        })
        // Phase 1: fsync every file, then every directory deepest-first.
        for file in orderedFiles {
            try seam.checkCancellation()
            try synchronizeNode(at: file.url, expectedDevice: rootDevice, expectedInode: file.inode, isDirectory: false)
        }
        for directory in orderedDirectories {
            try seam.checkCancellation()
            try synchronizeNode(at: directory.url, expectedDevice: rootDevice, expectedInode: directory.inode, isDirectory: true)
        }
        // Phase 2: fsync the promotion ancestors inside-out. Each ancestor is
        // snapshotted (lstat + seam identity, rejecting symlinks) before its
        // own open+verify, so an ancestor replacement or symlink swap between
        // traversal and flush fails closed.
        for ancestor in Self.ancestors(of: canonicalGeneration, through: canonicalRoot) {
            try seam.checkCancellation()
            let ancestorInode = try snapshotAncestorIdentity(at: ancestor, expectedDevice: rootDevice)
            try synchronizeNode(at: ancestor, expectedDevice: rootDevice, expectedInode: ancestorInode, isDirectory: true)
        }
        // Phase 3: one terminal drain on the archive root (same device and
        // same qualified filesystem, both verified at open on the drain
        // descriptor itself). A failure here reports fullSyncFailed even
        // though every fsync succeeded: no downgrade to plain-sync success.
        // A filesystem drift at drain reports unsupportedFilesystem.
        try seam.checkCancellation()
        try drainDeviceQueueOnce(at: canonicalRoot, expectedDevice: rootDevice, expectedInode: rootInode)
        return .verifiedLocal
    }

    /// Maps only the well-known macOS alias spellings onto canonical form
    /// for the containment pre-check. `/tmp` is a symlink to `/private/tmp`
    /// (likewise `/var` to `/private/var`); a user spelling must confine
    /// without accepting nested symlinks. Anything else passes through
    /// untouched so `PathSafety` still rejects nested/file/dir/ancestor
    /// symlink escapes.
    static func normalizedSafetyURL(_ url: URL) -> URL {
        let path = url.standardizedFileURL.path
        if path == "/tmp" || path.hasPrefix("/tmp/") {
            return URL(fileURLWithPath: "/private" + path)
        }
        if path == "/var" || path.hasPrefix("/var/") {
            return URL(fileURLWithPath: "/private" + path)
        }
        return url.standardizedFileURL
    }

    // MARK: - Traversal

    private func validateGenerationNode(_ url: URL, expectedDevice: UInt64) throws -> UInt64 {
        var information = stat()
        guard url.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw LocalVaultDurabilityBarrierError.missingNode(url)
        }
        let mode = information.st_mode & mode_t(S_IFMT)
        if mode == mode_t(S_IFLNK) {
            throw LocalVaultDurabilityBarrierError.symlinkEscape(url)
        }
        guard mode == mode_t(S_IFDIR) else {
            throw LocalVaultDurabilityBarrierError.unexpectedNodeType(url)
        }
        guard UInt64(information.st_dev) == expectedDevice else {
            throw LocalVaultDurabilityBarrierError.deviceMismatch(url)
        }
        // Bind through the seam as well so volume-replacement faults stay
        // deterministic in tests and live behavior uses one identity.
        guard try seam.deviceIDOf(url) == expectedDevice else {
            throw LocalVaultDurabilityBarrierError.deviceMismatch(url)
        }
        return try seam.inodeOf(url)
    }

    private func collect(
        node: URL,
        expectedDevice: UInt64,
        files: inout [(url: URL, inode: UInt64)],
        directories: inout [(url: URL, inode: UInt64)]
    ) throws {
        let children = try fileManager.contentsOfDirectory(
            at: node,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try seam.checkCancellation()
            // Names come from the directory listing itself, so `..` cannot
            // appear; symlinks are rejected before descending or flushing.
            var information = stat()
            guard child.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
                throw LocalVaultDurabilityBarrierError.missingNode(child)
            }
            let mode = information.st_mode & mode_t(S_IFMT)
            if mode == mode_t(S_IFLNK) {
                throw LocalVaultDurabilityBarrierError.symlinkEscape(child)
            }
            guard UInt64(information.st_dev) == expectedDevice else {
                throw LocalVaultDurabilityBarrierError.deviceMismatch(child)
            }
            guard try seam.deviceIDOf(child) == expectedDevice else {
                throw LocalVaultDurabilityBarrierError.deviceMismatch(child)
            }
            let childInode = try seam.inodeOf(child)
            if mode == mode_t(S_IFDIR) {
                directories.append((child, childInode))
                try collect(node: child, expectedDevice: expectedDevice, files: &files, directories: &directories)
            } else if mode == mode_t(S_IFREG) {
                files.append((child, childInode))
            } else {
                throw LocalVaultDurabilityBarrierError.unexpectedNodeType(child)
            }
        }
    }

    private func snapshotAncestorIdentity(at url: URL, expectedDevice: UInt64) throws -> UInt64 {
        var information = stat()
        guard url.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw LocalVaultDurabilityBarrierError.missingNode(url)
        }
        let mode = information.st_mode & mode_t(S_IFMT)
        if mode == mode_t(S_IFLNK) {
            throw LocalVaultDurabilityBarrierError.symlinkEscape(url)
        }
        guard mode == mode_t(S_IFDIR) else {
            throw LocalVaultDurabilityBarrierError.unexpectedNodeType(url)
        }
        guard UInt64(information.st_dev) == expectedDevice,
              try seam.deviceIDOf(url) == expectedDevice else {
            throw LocalVaultDurabilityBarrierError.deviceMismatch(url)
        }
        return try seam.inodeOf(url)
    }

    /// Ancestor directory chain from the generation parent through (and
    /// including) the archive root, inside-out. Flushing these persists the
    /// promotion rename entry. A generation equal to the root yields no
    /// ancestors (the root itself is already flushed as the generation root).
    /// Comparisons use an explicit `/private` prefix normalization because
    /// Foundation path spellings mix `/var/...` (fixture/temp root) and
    /// `/private/var/...` (directory-listing children) on this Mac, and
    /// `resolvingSymlinksInPath().standardized` alone does not make them
    /// identical. Ancestors above the archive root are never flushed here;
    /// their durability is an external assumption.
    static func ancestors(of generation: URL, through root: URL) -> [URL] {
        if normalizedIdentityPath(generation) == normalizedIdentityPath(root) { return [] }
        var chain: [URL] = []
        var cursor = generation.deletingLastPathComponent()
        while true {
            chain.append(cursor)
            if normalizedIdentityPath(cursor) == normalizedIdentityPath(root) { break }
            let parent = cursor.deletingLastPathComponent()
            guard normalizedIdentityPath(parent) != normalizedIdentityPath(cursor) else { break }
            cursor = parent
        }
        return chain
    }

    private static func normalizedIdentityPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path.hasPrefix("/private/var/") { return String(path.dropFirst("/private".count)) }
        if path == "/private/var" { return "/var" }
        if path.hasPrefix("/private/tmp/") { return String(path.dropFirst("/private".count)) }
        if path == "/private/tmp" { return "/tmp" }
        return path
    }

    // MARK: - Flushing

    private func synchronizeNode(at url: URL, expectedDevice: UInt64, expectedInode: UInt64, isDirectory: Bool) throws {
        let descriptor = try openForFlush(at: url, isDirectory: isDirectory)
        defer { _ = Darwin.close(descriptor) }
        try verifyOpenDescriptor(descriptor, url: url, expectedDevice: expectedDevice, expectedInode: expectedInode, isDirectory: isDirectory)
        try seam.synchronize(descriptor, url, isDirectory)
    }

    private func drainDeviceQueueOnce(at url: URL, expectedDevice: UInt64, expectedInode: UInt64) throws {
        let descriptor = try openForFlush(at: url, isDirectory: true)
        defer { _ = Darwin.close(descriptor) }
        try verifyOpenDescriptor(descriptor, url: url, expectedDevice: expectedDevice, expectedInode: expectedInode, isDirectory: true)
        // Qualify the filesystem ON the drain descriptor itself (same fd as
        // the `fstat` above): a volume replacement between the start-of-run
        // check and the drain cannot mis-qualify into `.verifiedLocal`.
        let drainFilesystem = try seam.filesystemTypeOfDescriptor(descriptor, url)
        guard Self.supportedFilesystemTypeNames.contains(drainFilesystem) else {
            throw LocalVaultDurabilityBarrierError.unsupportedFilesystem(drainFilesystem)
        }
        try seam.drainDeviceQueue(descriptor, url, true)
    }

    private func openForFlush(at url: URL, isDirectory: Bool) throws -> Int32 {
        var flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC
        if isDirectory { flags |= O_DIRECTORY }
        let descriptor = url.path.withCString { Darwin.open($0, flags) }
        guard descriptor >= 0 else {
            let code = errno
            if code == ELOOP {
                throw LocalVaultDurabilityBarrierError.symlinkEscape(url)
            }
            if code == ENOENT {
                throw LocalVaultDurabilityBarrierError.missingNode(url)
            }
            if isDirectory {
                throw LocalVaultDurabilityBarrierError.directoryFlushFailed(url, errno: code)
            }
            throw LocalVaultDurabilityBarrierError.fileFlushFailed(url, errno: code)
        }
        return descriptor
    }

    /// Binds the flush to the actually-opened node: a path swap between
    /// traversal and flush (symlink, cross-device replacement, same-device
    /// same-type inode replacement, type change) fails closed here instead of
    /// flushing the wrong object.
    private func verifyOpenDescriptor(
        _ descriptor: Int32,
        url: URL,
        expectedDevice: UInt64,
        expectedInode: UInt64,
        isDirectory: Bool
    ) throws {
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            let code = errno
            if isDirectory {
                throw LocalVaultDurabilityBarrierError.directoryFlushFailed(url, errno: code)
            }
            throw LocalVaultDurabilityBarrierError.fileFlushFailed(url, errno: code)
        }
        guard UInt64(information.st_dev) == expectedDevice,
              UInt64(information.st_ino) == expectedInode else {
            throw LocalVaultDurabilityBarrierError.deviceMismatch(url)
        }
        let mode = information.st_mode & mode_t(S_IFMT)
        if isDirectory {
            guard mode == mode_t(S_IFDIR) else {
                throw LocalVaultDurabilityBarrierError.unexpectedNodeType(url)
            }
        } else {
            guard mode == mode_t(S_IFREG) else {
                throw LocalVaultDurabilityBarrierError.unexpectedNodeType(url)
            }
        }
    }
}
