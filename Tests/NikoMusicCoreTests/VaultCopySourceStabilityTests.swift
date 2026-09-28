import Darwin
import Foundation
import XCTest
@testable import NikoMusicCore

final class VaultCopySourceStabilityTests: XCTestCase {
    func testSameObservedContentIgnoresOnlyAllocation() {
        let fixedDate = Date(timeIntervalSince1970: 1_767_225_600)
        let directory = VaultManifest.Entry(
            relativePath: "Audio",
            type: .directory,
            byteCount: 0,
            modifiedAt: fixedDate,
            sha256: nil,
            allocatedByteCount: 4096,
            extendedAttributeBytes: 0
        )
        let file = VaultManifest.Entry(
            relativePath: "Audio/take.wav",
            type: .regularFile,
            byteCount: 5,
            modifiedAt: fixedDate,
            sha256: String(repeating: "a", count: 64),
            allocatedByteCount: 8192,
            extendedAttributeBytes: 128
        )
        let before = VaultManifest(entries: [directory, file])
        let directoryAllocChanged = VaultManifest.Entry(
            relativePath: "Audio",
            type: .directory,
            byteCount: 0,
            modifiedAt: fixedDate,
            sha256: nil,
            allocatedByteCount: 12288,
            extendedAttributeBytes: 0
        )
        let fileAllocChanged = VaultManifest.Entry(
            relativePath: "Audio/take.wav",
            type: .regularFile,
            byteCount: 5,
            modifiedAt: fixedDate,
            sha256: String(repeating: "a", count: 64),
            allocatedByteCount: 16384,
            extendedAttributeBytes: 128
        )
        let allocOnly = VaultManifest(entries: [directoryAllocChanged, fileAllocChanged])
        XCTAssertTrue(before.hasSameObservedContent(as: allocOnly))
        XCTAssertFalse(before.entries == allocOnly.entries, "the old whole-Entry check would fire on allocation alone")

        let pathChanged = VaultManifest(entries: [directory, VaultManifest.Entry(
            relativePath: "Audio/take2.wav",
            type: .regularFile,
            byteCount: 5,
            modifiedAt: fixedDate,
            sha256: String(repeating: "a", count: 64),
            allocatedByteCount: 8192,
            extendedAttributeBytes: 128
        )])
        XCTAssertFalse(before.hasSameObservedContent(as: pathChanged), "relativePath change must fail")

        let typeChanged = VaultManifest(entries: [directory, VaultManifest.Entry(
            relativePath: "Audio/take.wav",
            type: .directory,
            byteCount: 5,
            modifiedAt: fixedDate,
            sha256: String(repeating: "a", count: 64),
            allocatedByteCount: 8192,
            extendedAttributeBytes: 128
        )])
        XCTAssertFalse(before.hasSameObservedContent(as: typeChanged), "type change must fail")

        let sizeChanged = VaultManifest(entries: [directory, VaultManifest.Entry(
            relativePath: "Audio/take.wav",
            type: .regularFile,
            byteCount: 6,
            modifiedAt: fixedDate,
            sha256: String(repeating: "a", count: 64),
            allocatedByteCount: 8192,
            extendedAttributeBytes: 128
        )])
        XCTAssertFalse(before.hasSameObservedContent(as: sizeChanged), "byteCount change must fail")

        let mtimeChanged = VaultManifest(entries: [directory, VaultManifest.Entry(
            relativePath: "Audio/take.wav",
            type: .regularFile,
            byteCount: 5,
            modifiedAt: fixedDate.addingTimeInterval(1),
            sha256: String(repeating: "a", count: 64),
            allocatedByteCount: 8192,
            extendedAttributeBytes: 128
        )])
        XCTAssertFalse(before.hasSameObservedContent(as: mtimeChanged), "modifiedAt change must fail")

        let hashChanged = VaultManifest(entries: [directory, VaultManifest.Entry(
            relativePath: "Audio/take.wav",
            type: .regularFile,
            byteCount: 5,
            modifiedAt: fixedDate,
            sha256: String(repeating: "b", count: 64),
            allocatedByteCount: 8192,
            extendedAttributeBytes: 128
        )])
        XCTAssertFalse(before.hasSameObservedContent(as: hashChanged), "sha256 change must fail")

        let xattrChanged = VaultManifest(entries: [directory, VaultManifest.Entry(
            relativePath: "Audio/take.wav",
            type: .regularFile,
            byteCount: 5,
            modifiedAt: fixedDate,
            sha256: String(repeating: "a", count: 64),
            allocatedByteCount: 8192,
            extendedAttributeBytes: 129
        )])
        XCTAssertFalse(before.hasSameObservedContent(as: xattrChanged), "extendedAttributeBytes change must fail")

        let extraEntry = VaultManifest.Entry(
            relativePath: "Audio/extra.wav",
            type: .regularFile,
            byteCount: 1,
            modifiedAt: fixedDate,
            sha256: String(repeating: "c", count: 64),
            allocatedByteCount: 4096,
            extendedAttributeBytes: 0
        )
        let extra = VaultManifest(entries: [directory, file, extraEntry])
        XCTAssertFalse(before.hasSameObservedContent(as: extra), "extra entry must fail")

        let rooted = VaultManifest(entries: [directory, file], rootAllocatedByteCount: 4096, rootExtendedAttributeBytes: 32)
        let rootAllocationChanged = VaultManifest(entries: [directory, file], rootAllocatedByteCount: 8192, rootExtendedAttributeBytes: 32)
        let rootAttributesChanged = VaultManifest(entries: [directory, file], rootAllocatedByteCount: 4096, rootExtendedAttributeBytes: 64)
        XCTAssertTrue(rooted.hasSameObservedContent(as: rootAllocationChanged), "root allocation alone must pass")
        XCTAssertFalse(rooted.hasSameObservedContent(as: rootAttributesChanged), "root extendedAttributeBytes change must fail")
    }

    func testFirstCloneTrimmingPreallocatedSourceBlocksIsNotSourceMutated() async throws {
        let fixture = try CopyStageFixture()
        defer { fixture.remove() }
        // A tagged song folder: the clone must not disturb root xattrs either.
        try copyStabilitySetExtendedAttribute("com.nikomusichub.test", Data("root-tag".utf8), at: fixture.source)
        try copyStabilityPreallocate(at: fixture.takeURL, extraBytes: 4_194_304)
        try FileManager.default.setAttributes(
            [.modificationDate: fixture.fixedDate],
            ofItemAtPath: fixture.takeURL.path
        )
        let allocatedBefore = try copyStabilityAllocatedBytes(at: fixture.takeURL)
        let originalBytes = try Data(contentsOf: fixture.takeURL)
        let roundedUp = ((Int64(originalBytes.count) + 4095) / 4096) * 4096
        guard allocatedBefore > roundedUp else {
            throw XCTSkip("filesystem ignored F_PREALLOCATE")
        }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            writeAdmission: { _, operation in try await operation() }
        )
        let record = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        XCTAssertEqual(record.state, .archiveVerified)
        let allocatedAfter = try copyStabilityAllocatedBytes(at: fixture.takeURL)
        XCTAssertLessThan(allocatedAfter, allocatedBefore, "the first clone trims preallocated source blocks")
        XCTAssertEqual(try Data(contentsOf: fixture.takeURL), originalBytes, "source bytes must be unchanged")
        let manifest = try XCTUnwrap(record.manifest)
        try VaultManifestBuilder().verifyArchive(manifest, at: record.destinationURL)
        XCTAssertEqual(
            try copyStabilityManifestAllocation(of: "Audio/take.wav", in: manifest),
            try copyStabilityManifestAllocation(of: "Audio/take.wav", in: VaultManifestBuilder().build(at: fixture.source)),
            "the persisted manifest records the trimmed allocation, as a retry would have"
        )
    }

    func testAllocationOnlyChangeDuringCopyIsNotSourceMutated() async throws {
        let fixture = try CopyStageFixture()
        defer { fixture.remove() }
        let takeURL = fixture.takeURL
        let allocatedBefore = try copyStabilityAllocatedBytes(at: takeURL)
        let allocationBeforeCopy = try copyStabilityManifestAllocation(
            of: "Audio/take.wav", in: VaultManifestBuilder().build(at: fixture.source)
        )
        let hook = CopyStageHook {
            let previous = try copyStabilityModificationTime(at: takeURL)
            try copyStabilityPreallocate(at: takeURL, extraBytes: 4_194_304)
            try copyStabilitySetModificationTime(previous, at: takeURL)
            let grown = try copyStabilityAllocatedBytes(at: takeURL)
            XCTAssertGreaterThan(grown, allocatedBefore, "preallocation must grow allocated blocks")
        }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, _ in
                if point == .copyingToArchiveStaging { hook.arm() }
            },
            writeAdmission: { _, operation in
                try await operation()
                try hook.fireIfArmed()
            }
        )
        let record = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
        XCTAssertTrue(hook.didFire, "the allocation mutation must run once during the copy")
        XCTAssertEqual(record.state, .archiveVerified)
        let persistedAllocation = try copyStabilityManifestAllocation(of: "Audio/take.wav", in: XCTUnwrap(record.manifest))
        XCTAssertGreaterThan(persistedAllocation, allocationBeforeCopy)
        XCTAssertEqual(
            persistedAllocation,
            try copyStabilityManifestAllocation(of: "Audio/take.wav", in: VaultManifestBuilder().build(at: fixture.source)),
            "the persisted manifest carries the after-copy allocation"
        )
    }

    func testContentChangeDuringCopyIsSourceMutated() async throws {
        let fixture = try CopyStageFixture()
        defer { fixture.remove() }
        let takeURL = fixture.takeURL
        let originalBytes = try Data(contentsOf: takeURL)
        let mutatedBytes = Data(originalBytes.map { $0 ^ 0xFF })
        XCTAssertNotEqual(mutatedBytes, originalBytes)
        let hook = CopyStageHook {
            let previous = try copyStabilityModificationTime(at: takeURL)
            let descriptor = takeURL.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return Darwin.open(path, O_WRONLY)
            }
            guard descriptor >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: takeURL.path])
            }
            defer { Darwin.close(descriptor) }
            try mutatedBytes.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EINVAL), userInfo: [NSFilePathErrorKey: takeURL.path])
                }
                var written = 0
                while written < mutatedBytes.count {
                    let result = Darwin.pwrite(descriptor, base.advanced(by: written), mutatedBytes.count - written, off_t(written))
                    if result < 0 {
                        if errno == EINTR { continue }
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: takeURL.path])
                    }
                    written += result
                }
            }
            try copyStabilitySetModificationTime(previous, at: takeURL)
        }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, _ in
                if point == .copyingToArchiveStaging { hook.arm() }
            },
            writeAdmission: { _, operation in
                try await operation()
                try hook.fireIfArmed()
            }
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("a content change during the copy must throw sourceMutated")
        } catch let error as LocalVaultTransferError {
            XCTAssertEqual(error, .sourceMutated)
        }
        XCTAssertTrue(hook.didFire, "the content mutation must run once during the copy")
        let records = try store.allTransferRecords()
        let persisted = try XCTUnwrap(records.first)
        XCTAssertEqual(persisted.state, .failedRecoverable)
        XCTAssertEqual(persisted.error?.origin, .copyingToArchiveStaging)
        XCTAssertEqual(persisted.error?.reason, .sourceMutated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path), "the Active source must be kept")
        XCTAssertEqual(try Data(contentsOf: takeURL), mutatedBytes, "the Active source keeps the new bytes")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: persisted.destinationURL.path),
            "no generation may be promoted from a mutated source"
        )
    }

    func testModificationTimeOnlyChangeDuringCopyIsSourceMutated() async throws {
        let fixture = try CopyStageFixture()
        defer { fixture.remove() }
        let takeURL = fixture.takeURL
        let fixedDate = fixture.fixedDate
        let originalBytes = try Data(contentsOf: takeURL)
        let hook = CopyStageHook {
            try FileManager.default.setAttributes(
                [.modificationDate: fixedDate.addingTimeInterval(60)],
                ofItemAtPath: takeURL.path
            )
        }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, _ in
                if point == .copyingToArchiveStaging { hook.arm() }
            },
            writeAdmission: { _, operation in
                try await operation()
                try hook.fireIfArmed()
            }
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("an mtime change during the copy must throw sourceMutated")
        } catch let error as LocalVaultTransferError {
            XCTAssertEqual(error, .sourceMutated)
        }
        XCTAssertTrue(hook.didFire, "the mtime mutation must run once during the copy")
        let records = try store.allTransferRecords()
        let persisted = try XCTUnwrap(records.first)
        XCTAssertEqual(persisted.state, .failedRecoverable)
        XCTAssertEqual(persisted.error?.origin, .copyingToArchiveStaging)
        XCTAssertEqual(persisted.error?.reason, .sourceMutated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path), "the Active source must be kept")
        XCTAssertEqual(try Data(contentsOf: takeURL), originalBytes, "bytes must be unchanged")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: persisted.destinationURL.path),
            "no generation may be promoted from a mutated source"
        )
    }

    func testExtendedAttributeChangeDuringCopyIsSourceMutated() async throws {
        let fixture = try CopyStageFixture()
        defer { fixture.remove() }
        let takeURL = fixture.takeURL
        let originalBytes = try Data(contentsOf: takeURL)
        let hook = CopyStageHook {
            let previous = try copyStabilityModificationTime(at: takeURL)
            try copyStabilitySetExtendedAttribute("com.nikomusichub.test", Data("xattr-payload".utf8), at: takeURL)
            try copyStabilitySetModificationTime(previous, at: takeURL)
        }
        let store = try SQLiteVaultTransferStore(databaseURL: fixture.databaseURL)
        let engine = try LocalVaultTransferEngine(
            activeRoot: fixture.active,
            archiveRoot: fixture.archive,
            store: store,
            faultInjector: { point, _ in
                if point == .copyingToArchiveStaging { hook.arm() }
            },
            writeAdmission: { _, operation in
                try await operation()
                try hook.fireIfArmed()
            }
        )
        do {
            _ = try await engine.archive(projectID: ProjectID(), sourceURL: fixture.source)
            XCTFail("an xattr change during the copy must throw sourceMutated")
        } catch let error as LocalVaultTransferError {
            XCTAssertEqual(error, .sourceMutated)
        }
        XCTAssertTrue(hook.didFire, "the xattr mutation must run once during the copy")
        let records = try store.allTransferRecords()
        let persisted = try XCTUnwrap(records.first)
        XCTAssertEqual(persisted.state, .failedRecoverable)
        XCTAssertEqual(persisted.error?.origin, .copyingToArchiveStaging)
        XCTAssertEqual(persisted.error?.reason, .sourceMutated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.source.path), "the Active source must be kept")
        XCTAssertEqual(try Data(contentsOf: takeURL), originalBytes, "bytes must be unchanged")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: persisted.destinationURL.path),
            "no generation may be promoted from a mutated source"
        )
    }
}

private struct CopyStageFixture {
    let root: URL
    let active: URL
    let archive: URL
    let source: URL
    let takeURL: URL
    let databaseURL: URL
    let fixedDate: Date

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-copy-stability-\(UUID().uuidString)", isDirectory: true)
        active = root.appendingPathComponent("Active", isDirectory: true)
        archive = root.appendingPathComponent("Archive", isDirectory: true)
        source = active.appendingPathComponent("Artist Song", isDirectory: true)
        takeURL = source.appendingPathComponent("Audio/take.wav", isDirectory: false)
        databaseURL = root.appendingPathComponent("state/vault.sqlite", isDirectory: false)
        fixedDate = Date(timeIntervalSince1970: 1_767_225_600)
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("Audio", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("cubase-project".utf8).write(to: source.appendingPathComponent("Artist Song.cpr", isDirectory: false))
        try Data((0..<1_048_576).map { UInt8($0 % 251) }).write(to: takeURL)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: takeURL.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class CopyStageHook: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private var fired = false
    private let mutation: @Sendable () throws -> Void

    init(mutation: @escaping @Sendable () throws -> Void) {
        self.mutation = mutation
    }

    func arm() {
        lock.withLock { armed = true }
    }

    var didFire: Bool {
        lock.withLock { fired }
    }

    func fireIfArmed() throws {
        let action: (@Sendable () throws -> Void)? = lock.withLock {
            guard armed, !fired else { return nil }
            fired = true
            armed = false
            return mutation
        }
        try action?()
    }
}

fileprivate func copyStabilityAllocatedBytes(at url: URL) throws -> Int64 {
    var info = stat()
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return Darwin.lstat(path, &info)
    }
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
    return Int64(info.st_blocks) * 512
}

fileprivate func copyStabilityManifestAllocation(of relativePath: String, in manifest: VaultManifest) throws -> Int64 {
    let entry = try XCTUnwrap(manifest.entries.first(where: { $0.relativePath == relativePath }))
    return try XCTUnwrap(entry.allocatedByteCount)
}

fileprivate func copyStabilitySetExtendedAttribute(_ name: String, _ value: Data, at url: URL) throws {
    let result = value.withUnsafeBytes { buffer in
        url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0)
        }
    }
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
}

fileprivate func copyStabilityPreallocate(at url: URL, extraBytes: Int64) throws {
    let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return Darwin.open(path, O_RDWR)
    }
    guard descriptor >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
    defer { Darwin.close(descriptor) }
    var request = fstore_t(
        fst_flags: UInt32(F_ALLOCATEALL),
        fst_posmode: F_PEOFPOSMODE,
        fst_offset: 0,
        fst_length: off_t(extraBytes),
        fst_bytesalloc: 0
    )
    let result = Darwin.fcntl(descriptor, F_PREALLOCATE, &request)
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
}

fileprivate func copyStabilityModificationTime(at url: URL) throws -> timespec {
    var info = stat()
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return Darwin.lstat(path, &info)
    }
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
    return info.st_mtimespec
}

fileprivate func copyStabilitySetModificationTime(_ mtime: timespec, at url: URL) throws {
    let omitted = timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))
    let times = [omitted, mtime]
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
        guard let path else { return -1 }
        return times.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return Darwin.utimensat(AT_FDCWD, path, base, 0)
        }
    }
    guard result == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
}
