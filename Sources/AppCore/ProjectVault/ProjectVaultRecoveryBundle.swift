import CryptoKit
import Darwin
import Foundation
import NikoMusicCore

/// Bounded Project Vault recovery bundle: a METADATA backup, not Vault content.
///
/// A bundle directory holds `archive-database.sqlite` (consistent online
/// backup, normalized to standalone DELETE mode), `app-settings.json`, and
/// `recovery-manifest.json` (version + SHA256). Import validates
/// (manifest/version, checksums, settings schema, read-only DB integrity)
/// then stages into a NEW/empty recovery destination with automation forced
/// off. Never replaces live state, never deletes bundle originals, never
/// touches music files. Caller must hold the Vault mutation lease and quiesce
/// transfers before export; the DB snapshot and settings JSON are each
/// point-in-time consistent but not a joint transaction.
public enum ProjectVaultRecoveryBundle {
    public static let bundleVersion = 1
    public static let databaseFileName = "archive-database.sqlite"
    public static let settingsFileName = "app-settings.json"
    public static let manifestFileName = "recovery-manifest.json"
    public static let recoveredSettingsFileName = "app-settings.recovered.json"

    static let scopeNote = "METADATA backup only. Vault file content must be backed up separately; not a replacement-Mac proof. Re-point paths and re-grant sandbox bookmarks on restore. Contains no deletion authorization. Recovered settings disable automation (isEnabled=false, automaticArchiving=false, automationEmergencyStop=true)."

    public struct RecoveryImportResult: Equatable, Sendable {
        public let databaseURL: URL
        public let settingsURL: URL
        public let settings: AppSettings
        public let bundleVersion: Int

        public init(databaseURL: URL, settingsURL: URL, settings: AppSettings, bundleVersion: Int) {
            self.databaseURL = databaseURL
            self.settingsURL = settingsURL
            self.settings = settings
            self.bundleVersion = bundleVersion
        }
    }

    public enum BundleError: Error, Equatable, Sendable, CustomStringConvertible {
        case bundleOccupied(String)
        case recoveryDestinationOccupied(String)
        case bundleNotFound(String)
        case manifestInvalid(String)
        case unsupportedVersion(Int)
        case checksumMismatch(file: String, expected: String, actual: String)
        case settingsSchemaInvalid(String)
        case databaseIntegrityFailed(String)
        case databaseBackupFailed(String)
        case ioFailed(String)

        public var description: String {
            switch self {
            case .bundleOccupied(let detail): "recovery bundle destination occupied: \(detail)"
            case .recoveryDestinationOccupied(let detail): "recovery destination occupied: \(detail)"
            case .bundleNotFound(let detail): "recovery bundle not found: \(detail)"
            case .manifestInvalid(let detail): "recovery manifest invalid: \(detail)"
            case .unsupportedVersion(let version): "unsupported recovery bundle version: \(version)"
            case .checksumMismatch(let file, let expected, let actual):
                "checksum mismatch for \(file): expected \(expected), got \(actual)"
            case .settingsSchemaInvalid(let detail): "recovery settings schema invalid: \(detail)"
            case .databaseIntegrityFailed(let detail): "recovery database integrity failed: \(detail)"
            case .databaseBackupFailed(let detail): "recovery database export failed: \(detail)"
            case .ioFailed(let detail): "recovery bundle I/O failed: \(detail)"
            }
        }
    }

    struct RecoveryManifest: Codable, Equatable, Sendable {
        var version: Int
        var createdAt: Date
        var files: [String: String]
        var note: String
    }

    // MARK: - Export

    /// Exports a versioned bundle. `bundleURL` must not exist and must not be
    /// a symlink; only owned content is removed on failure (directory removed
    /// only while still empty so raced-in files are never deleted).
    public static func exportBundle(
        database: SQLiteArchiveDatabase,
        settings: AppSettings,
        to bundleURL: URL
    ) throws {
        if isSymlink(at: bundleURL) {
            throw BundleError.bundleOccupied("symlink destination refused: \(bundleURL.path)")
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory) {
            throw BundleError.bundleOccupied(bundleURL.path)
        }
        do {
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: false)
        } catch {
            if isSymlink(at: bundleURL) || FileManager.default.fileExists(atPath: bundleURL.path) {
                throw BundleError.bundleOccupied(bundleURL.path)
            }
            throw BundleError.ioFailed("cannot create bundle directory \(bundleURL.path): \(error)")
        }
        var ownedFiles: [URL] = []
        var completed = false
        defer {
            if !completed {
                for file in ownedFiles {
                    try? FileManager.default.removeItem(at: file)
                    // Owned sidecars alongside owned files only; bundle inputs
                    // are never removed. Symlinks are left for validation to
                    // fail closed on (only regular files are removed here).
                    for suffix in ["-wal", "-shm", "-journal"] {
                        let sidecar = file.path + suffix
                        if (try? FileManager.default.destinationOfSymbolicLink(atPath: sidecar)) != nil {
                            continue
                        }
                        if FileManager.default.fileExists(atPath: sidecar) {
                            try? FileManager.default.removeItem(atPath: sidecar)
                        }
                    }
                }
                // Remove the owned directory only if nothing raced into it.
                if let remaining = try? FileManager.default.contentsOfDirectory(atPath: bundleURL.path),
                   remaining.isEmpty
                {
                    try? FileManager.default.removeItem(at: bundleURL)
                }
            }
        }
        let databaseURL = bundleURL.appendingPathComponent(databaseFileName, isDirectory: false)
        do {
            try database.backup(to: databaseURL)
        } catch let backupError as SQLiteArchiveDatabase.BackupError {
            throw BundleError.databaseBackupFailed(String(describing: backupError))
        } catch {
            throw BundleError.databaseBackupFailed(String(describing: error))
        }
        ownedFiles.append(databaseURL)

        // Lossless dates: secondsSince1970 preserves fractional seconds that
        // ISO8601 without fractional digits would truncate.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .secondsSince1970
        let settingsData: Data
        do {
            settingsData = try encoder.encode(settings)
        } catch {
            throw BundleError.ioFailed("cannot encode settings: \(error)")
        }
        let settingsURL = bundleURL.appendingPathComponent(settingsFileName, isDirectory: false)
        do {
            try settingsData.write(to: settingsURL, options: [.atomic])
        } catch {
            throw BundleError.ioFailed("cannot write settings \(settingsURL.path): \(error)")
        }
        ownedFiles.append(settingsURL)

        let databaseDigest: String
        do {
            databaseDigest = try sha256HexOfFile(at: databaseURL)
        } catch {
            throw BundleError.ioFailed("cannot hash bundle files: \(error)")
        }
        let settingsDigest = sha256Hex(of: settingsData)
        // Confirm the written settings bytes equal the hashed bytes.
        do {
            let written = try Data(contentsOf: settingsURL)
            guard written == settingsData else {
                throw BundleError.ioFailed("settings file bytes differ from encoded bytes")
            }
        } catch let error as BundleError {
            throw error
        } catch {
            throw BundleError.ioFailed("cannot verify settings bytes: \(error)")
        }
        let manifest = RecoveryManifest(
            version: bundleVersion,
            createdAt: Date(),
            files: [databaseFileName: databaseDigest, settingsFileName: settingsDigest],
            note: scopeNote
        )
        let manifestEncoder = JSONEncoder()
        manifestEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        manifestEncoder.dateEncodingStrategy = .secondsSince1970
        let manifestData: Data
        do {
            manifestData = try manifestEncoder.encode(manifest)
        } catch {
            throw BundleError.ioFailed("cannot encode manifest: \(error)")
        }
        let manifestURL = bundleURL.appendingPathComponent(manifestFileName, isDirectory: false)
        do {
            try manifestData.write(to: manifestURL, options: [.atomic])
        } catch {
            throw BundleError.ioFailed("cannot write manifest: \(error)")
        }
        ownedFiles.append(manifestURL)
        completed = true
    }

    // MARK: - Import

    /// Validates a bundle and stages it into a NEW or empty recovery
    /// destination. Validation (manifest, checksums, settings, read-only DB
    /// integrity) completes before any recovery write; bundle originals are
    /// never modified (immutable read-only DB open, no sidecar creation).
    public static func importBundle(
        from bundleURL: URL,
        to recoveryDestination: URL
    ) throws -> RecoveryImportResult {
        var isDirectory: ObjCBool = false
        guard !isSymlink(at: bundleURL),
              FileManager.default.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw BundleError.bundleNotFound(bundleURL.path)
        }
        // Fail closed on listing failure (never treat as empty).
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: bundleURL.path)
        } catch {
            throw BundleError.ioFailed("cannot list bundle \(bundleURL.path): \(error)")
        }
        let manifestURL = bundleURL.appendingPathComponent(manifestFileName, isDirectory: false)
        let databaseSourceURL = bundleURL.appendingPathComponent(databaseFileName, isDirectory: false)
        let settingsSourceURL = bundleURL.appendingPathComponent(settingsFileName, isDirectory: false)
        try requireRegularFile(at: manifestURL, error: .manifestInvalid("bundle is missing expected files at \(bundleURL.path)"))
        try requireRegularFile(at: databaseSourceURL, error: .manifestInvalid("bundle is missing expected files at \(bundleURL.path)"))
        try requireRegularFile(at: settingsSourceURL, error: .manifestInvalid("bundle is missing expected files at \(bundleURL.path)"))
        // Unexpected sidecars must never be consumed.
        try rejectDatabaseSidecars(for: databaseSourceURL)

        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw BundleError.ioFailed("cannot read manifest: \(error)")
        }
        let manifestDecoder = JSONDecoder()
        manifestDecoder.dateDecodingStrategy = .secondsSince1970
        let manifest: RecoveryManifest
        do {
            manifest = try manifestDecoder.decode(RecoveryManifest.self, from: manifestData)
        } catch {
            throw BundleError.manifestInvalid("cannot decode manifest: \(error)")
        }
        guard manifest.version == bundleVersion else {
            throw BundleError.unsupportedVersion(manifest.version)
        }
        guard let expectedDatabaseDigest = manifest.files[databaseFileName],
              let expectedSettingsDigest = manifest.files[settingsFileName],
              isHexDigest(expectedDatabaseDigest), isHexDigest(expectedSettingsDigest)
        else {
            throw BundleError.manifestInvalid("manifest is missing file checksums")
        }
        // Settings: hash the exact bytes once, compare, decode the same bytes.
        let settingsData: Data
        do {
            settingsData = try Data(contentsOf: settingsSourceURL)
        } catch {
            throw BundleError.ioFailed("cannot read bundled settings: \(error)")
        }
        let actualSettingsDigest = sha256Hex(of: settingsData)
        guard actualSettingsDigest.lowercased() == expectedSettingsDigest.lowercased() else {
            throw BundleError.checksumMismatch(
                file: settingsFileName, expected: expectedSettingsDigest, actual: actualSettingsDigest
            )
        }
        let decodedSettings = try decodeStrictSettings(settingsData)
        // Database: hash, immutable read-only integrity (no sidecars, header +
        // schema + integrity_check), then re-hash to detect mutation mid-check.
        let digestBefore: String
        do {
            digestBefore = try sha256HexOfFile(at: databaseSourceURL)
        } catch {
            throw BundleError.ioFailed("cannot hash bundle files: \(error)")
        }
        guard digestBefore.lowercased() == expectedDatabaseDigest.lowercased() else {
            throw BundleError.checksumMismatch(
                file: databaseFileName, expected: expectedDatabaseDigest, actual: digestBefore
            )
        }
        do {
            try checkReadOnlyIntegrity(at: databaseSourceURL)
        } catch {
            throw BundleError.databaseIntegrityFailed(String(describing: error))
        }
        do {
            let digestAfter = try sha256HexOfFile(at: databaseSourceURL)
            guard digestAfter.lowercased() == expectedDatabaseDigest.lowercased() else {
                throw BundleError.checksumMismatch(
                    file: databaseFileName, expected: expectedDatabaseDigest, actual: digestAfter
                )
            }
        } catch let error as BundleError {
            throw error
        } catch {
            throw BundleError.ioFailed("cannot re-hash bundle database: \(error)")
        }

        // Prepare destination only after validation.
        if isSymlink(at: recoveryDestination) {
            throw BundleError.recoveryDestinationOccupied("symlink destination refused: \(recoveryDestination.path)")
        }
        var createdRecoveryDirectory = false
        var stagedFiles: [URL] = []
        var succeeded = false
        defer {
            // On failure remove only owned staged files; remove an owned
            // directory only while still empty so raced-in files survive.
            if !succeeded {
                for staged in stagedFiles { try? FileManager.default.removeItem(at: staged) }
                if createdRecoveryDirectory {
                    if let remaining = try? FileManager.default.contentsOfDirectory(atPath: recoveryDestination.path),
                       remaining.isEmpty
                    {
                        try? FileManager.default.removeItem(at: recoveryDestination)
                    }
                }
            }
        }
        // Materialize destination handling without the [] fallback.
        var destIsDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: recoveryDestination.path, isDirectory: &destIsDirectory) {
            guard destIsDirectory.boolValue else {
                throw BundleError.recoveryDestinationOccupied(recoveryDestination.path)
            }
            let existing: [String]
            do {
                existing = try FileManager.default.contentsOfDirectory(atPath: recoveryDestination.path)
            } catch {
                throw BundleError.ioFailed("cannot list recovery destination \(recoveryDestination.path): \(error)")
            }
            guard existing.isEmpty else {
                throw BundleError.recoveryDestinationOccupied(recoveryDestination.path)
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: recoveryDestination, withIntermediateDirectories: false)
            } catch {
                if isSymlink(at: recoveryDestination) || FileManager.default.fileExists(atPath: recoveryDestination.path) {
                    throw BundleError.recoveryDestinationOccupied(recoveryDestination.path)
                }
                throw BundleError.ioFailed(
                    "cannot create recovery destination \(recoveryDestination.path): \(error)"
                )
            }
            createdRecoveryDirectory = true
        }

        let stagedDatabaseURL = recoveryDestination.appendingPathComponent(databaseFileName, isDirectory: false)
        let stagedSettingsURL = recoveryDestination.appendingPathComponent(recoveredSettingsFileName, isDirectory: false)
        // Stage via private temp names, then no-replace link promotion so a
        // raced destination file is never overwritten.
        let tempDatabaseURL = recoveryDestination.appendingPathComponent(
            ".staging-\(UUID().uuidString).sqlite", isDirectory: false
        )
        do {
            if FileManager.default.fileExists(atPath: stagedDatabaseURL.path) || isSymlink(at: stagedDatabaseURL) {
                throw BundleError.recoveryDestinationOccupied(stagedDatabaseURL.path)
            }
            try FileManager.default.copyItem(at: databaseSourceURL, to: tempDatabaseURL)
        } catch let error as BundleError {
            Self.removeOwnedTempFile(at: tempDatabaseURL)
            throw error
        } catch {
            Self.removeOwnedTempFile(at: tempDatabaseURL)
            throw BundleError.ioFailed("cannot stage database: \(error)")
        }
        do {
            let stagedDigest = try sha256HexOfFile(at: tempDatabaseURL)
            guard stagedDigest.lowercased() == expectedDatabaseDigest.lowercased() else {
                throw BundleError.checksumMismatch(
                    file: databaseFileName, expected: expectedDatabaseDigest, actual: stagedDigest
                )
            }
            try checkReadOnlyIntegrity(at: tempDatabaseURL)
            try exclusiveLink(from: tempDatabaseURL, to: stagedDatabaseURL)
            Self.removeOwnedTempFile(at: tempDatabaseURL)
            stagedFiles.append(stagedDatabaseURL)
        } catch let error as BundleError {
            Self.removeOwnedTempFile(at: tempDatabaseURL)
            throw error
        } catch {
            Self.removeOwnedTempFile(at: tempDatabaseURL)
            throw BundleError.databaseIntegrityFailed(String(describing: error))
        }

        var recovered = decodedSettings
        recovered.vault.isEnabled = false
        recovered.vault.automaticArchiving = false
        recovered.vault.automationEmergencyStop = true
        let recoveredEncoder = JSONEncoder()
        recoveredEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        recoveredEncoder.dateEncodingStrategy = .secondsSince1970
        let tempSettingsURL = recoveryDestination.appendingPathComponent(
            ".staging-\(UUID().uuidString).json", isDirectory: false
        )
        do {
            if FileManager.default.fileExists(atPath: stagedSettingsURL.path) || isSymlink(at: stagedSettingsURL) {
                throw BundleError.recoveryDestinationOccupied(stagedSettingsURL.path)
            }
            let recoveredData = try recoveredEncoder.encode(recovered)
            try recoveredData.write(to: tempSettingsURL, options: [.atomic])
            try exclusiveLink(from: tempSettingsURL, to: stagedSettingsURL)
            Self.removeOwnedTempFile(at: tempSettingsURL)
            stagedFiles.append(stagedSettingsURL)
        } catch let error as BundleError {
            Self.removeOwnedTempFile(at: tempSettingsURL)
            throw error
        } catch {
            Self.removeOwnedTempFile(at: tempSettingsURL)
            throw BundleError.ioFailed("cannot stage recovered settings: \(error)")
        }
        succeeded = true
        return RecoveryImportResult(
            databaseURL: stagedDatabaseURL,
            settingsURL: stagedSettingsURL,
            settings: recovered,
            bundleVersion: manifest.version
        )
    }

    // MARK: - Helpers

    static func isSymlink(at url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private static func isRegularFile(at url: URL) -> Bool {
        if isSymlink(at: url) { return false }
        var info = stat()
        guard url.path.withCString({ Darwin.fstatat(AT_FDCWD, $0, &info, AT_SYMLINK_NOFOLLOW) }) == 0 else { return false }
        return (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    private static func requireRegularFile(at url: URL, error: BundleError) throws {
        guard isRegularFile(at: url) else { throw error }
    }

    private static func rejectDatabaseSidecars(for databaseURL: URL) throws {
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = databaseURL.path + suffix
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: sidecar)) != nil {
                throw BundleError.databaseIntegrityFailed("unexpected sidecar \(URL(fileURLWithPath: sidecar).lastPathComponent)")
            }
            if FileManager.default.fileExists(atPath: sidecar) {
                throw BundleError.databaseIntegrityFailed("unexpected sidecar \(URL(fileURLWithPath: sidecar).lastPathComponent)")
            }
        }
    }

    private static func isHexDigest(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    /// Decodes the exact hashed bytes; rejects non-object payloads and
    /// payloads lacking the expected `vault` section rather than silently
    /// defaulting arbitrary JSON.
    private static func decodeStrictSettings(_ data: Data) throws -> AppSettings {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw BundleError.settingsSchemaInvalid("cannot decode \(settingsFileName): \(error)")
        }
        guard let object = raw as? [String: Any], object["vault"] != nil else {
            throw BundleError.settingsSchemaInvalid("settings payload is missing expected schema")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            throw BundleError.settingsSchemaInvalid("cannot decode \(settingsFileName): \(error)")
        }
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Streams a file through SHA256 in 1 MiB chunks; lowercase hex.
    static func sha256HexOfFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func exclusiveLink(from staging: URL, to destination: URL) throws {
        if isSymlink(at: destination) {
            throw BundleError.recoveryDestinationOccupied("symlink destination refused: \(destination.path)")
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory) {
            throw BundleError.recoveryDestinationOccupied(destination.path)
        }
        let result = staging.path.withCString { src in
            destination.path.withCString { dst in Darwin.link(src, dst) }
        }
        guard result == 0 else {
            if errno == EEXIST {
                throw BundleError.recoveryDestinationOccupied(destination.path)
            }
            throw BundleError.ioFailed("cannot promote staged file to \(destination.path) (errno \(errno))")
        }
    }

    /// Removes an owned staging temp file and any sidecars alongside it.
    /// Idempotent (missing files are ignored). Only regular files are
    /// removed; symlinks are left untouched. Call only for owned temp paths
    /// created by import staging, never for bundle inputs.
    private static func removeOwnedTempFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = url.path + suffix
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: sidecar)) != nil {
                continue
            }
            if FileManager.default.fileExists(atPath: sidecar) {
                try? FileManager.default.removeItem(atPath: sidecar)
            }
        }
    }

    /// Read-only integrity check delegating to the Core SQLite helper (which
    /// owns the SQLite linkage), so this service never opens databases
    /// directly. Immutable open creates no sidecars and consumes no WAL.
    static func checkReadOnlyIntegrity(at url: URL) throws {
        do {
            try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: url)
        } catch {
            throw BundleError.databaseIntegrityFailed(String(describing: error))
        }
    }
}
