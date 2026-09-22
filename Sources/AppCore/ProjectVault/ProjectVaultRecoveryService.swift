import Foundation
import NikoMusicCore

/// App-facing Project Vault recovery integration over the bounded
/// `ProjectVaultRecoveryBundle` backend contract.
///
/// A recovery bundle is a METADATA backup (consistent database snapshot +
/// settings), never Vault file content and never music files. Export captures
/// the settings snapshot and the full database while holding the same
/// cross-process `ProjectVaultMutationFileLease` the runtime holds for Vault
/// mutations, so no Vault mutation can interleave. The two captures are each
/// point-in-time consistent but deliberately NOT a joint transaction, and the
/// service never claims a global transaction across unrelated setting writes.
///
/// Import validates through the backend, then stages into a NEW isolated
/// library: a unique `NikoMusicHub.Recovered.<UUID>` settings suite with its
/// `Isolated/<suite>/archive-index.sqlite` support directory (the same layout
/// `AppComposition` uses for isolated suites). The current settings and
/// database are never modified, an occupied recovery directory is never
/// overwritten, and imported settings stay disabled/paused until the user
/// explicitly chooses otherwise. Opening the recovered library is an explicit
/// separate action owned by the app target; this service never launches apps.
public struct ProjectVaultRecoveredLibrary: Sendable, Equatable {
    /// Fresh isolated defaults suite holding the recovered (disabled/paused) settings.
    public let settingsSuiteName: String
    /// `Isolated/<suite>` directory holding the recovered `archive-index.sqlite`.
    public let supportDirectoryURL: URL
    /// Recovered database at the app-expected `archive-index.sqlite` name.
    public let databaseURL: URL
    /// Recovered settings (automation disabled/paused, identities preserved).
    public let settings: AppSettings

    public init(
        settingsSuiteName: String,
        supportDirectoryURL: URL,
        databaseURL: URL,
        settings: AppSettings
    ) {
        self.settingsSuiteName = settingsSuiteName
        self.supportDirectoryURL = supportDirectoryURL
        self.databaseURL = databaseURL
        self.settings = settings
    }
}

public enum ProjectVaultRecoveryServiceError: Error, Equatable, Sendable {
    case databaseUnavailable
    case recoveredSuiteUnavailable
    case recoveryDestinationOccupied(String)
    case ioFailed(String)
}

public struct ProjectVaultRecoveryService: Sendable {
    /// Returns the `Niko Music Hub` application-support directory; the service
    /// appends `Isolated/<suite>`. Injected in tests so fixtures stay under tmp.
    public typealias SupportBaseProvider = @Sendable () -> URL
    /// Returns (creating if needed) the defaults for an isolated suite.
    /// Injected in tests so only fixture suites are touched.
    public typealias DefaultsProvider = @Sendable (String) -> UserDefaults?
    /// Generates unique recovered-suite names. Injected in tests to pin names.
    public typealias SuiteNameProvider = @Sendable () -> String

    public static let recoveredSuitePrefix = "NikoMusicHub.Recovered."
    /// App-expected database file name inside an isolated support directory.
    public static let recoveredDatabaseFileName = "archive-index.sqlite"

    private let database: SQLiteArchiveDatabase?
    private let settingsStore: any SettingsStore
    private let supportBase: SupportBaseProvider
    private let defaultsProvider: DefaultsProvider
    private let suiteNameProvider: SuiteNameProvider

    public init(
        database: SQLiteArchiveDatabase?,
        settingsStore: any SettingsStore,
        supportBase: SupportBaseProvider? = nil,
        defaultsProvider: DefaultsProvider? = nil,
        suiteNameProvider: SuiteNameProvider? = nil
    ) {
        self.database = database
        self.settingsStore = settingsStore
        self.supportBase = supportBase ?? Self.defaultSupportBase
        self.defaultsProvider = defaultsProvider ?? { UserDefaults(suiteName: $0) }
        self.suiteNameProvider = suiteNameProvider ?? {
            Self.recoveredSuitePrefix + UUID().uuidString
        }
    }

    // MARK: - Export

    /// Exports a recovery bundle while holding the runtime's cross-process
    /// Vault mutation lease (derived exactly like
    /// `SQLiteVaultTransferStore.mutationLeaseURL`). Throws
    /// `databaseUnavailable` when there is no healthy database, so a damaged
    /// catalog fails closed instead of exporting a partial copy.
    public func exportRecoveryBundle(to bundleURL: URL) throws {
        guard let database else {
            throw ProjectVaultRecoveryServiceError.databaseUnavailable
        }
        let lease = try ProjectVaultMutationFileLease(
            url: database.fileURL.appendingPathExtension("project-vault.lock")
        )
        defer { lease.release() }
        let settings = try settingsStore.loadSettings()
        try ProjectVaultRecoveryBundle.exportBundle(
            database: database,
            settings: settings,
            to: bundleURL
        )
    }

    // MARK: - Import

    /// Validates `bundleURL` through the backend and stages a NEW isolated
    /// library. Never touches the current settings/database and never depends
    /// on a healthy current database.
    public func importRecoveredLibrary(from bundleURL: URL) throws -> ProjectVaultRecoveredLibrary {
        try Self.importRecoveredLibrary(
            from: bundleURL,
            supportBase: supportBase(),
            defaultsProvider: defaultsProvider,
            suiteNameProvider: suiteNameProvider
        )
    }

    /// Standalone import that works even when the current database is damaged:
    /// it reads only the bundle and writes only fresh isolated state.
    public static func importRecoveredLibrary(
        from bundleURL: URL,
        supportBase: URL? = nil,
        defaultsProvider: DefaultsProvider? = nil,
        suiteNameProvider: SuiteNameProvider? = nil
    ) throws -> ProjectVaultRecoveredLibrary {
        let base = supportBase ?? defaultSupportBase()
        let defaults = defaultsProvider ?? { UserDefaults(suiteName: $0) }
        let suiteNames = suiteNameProvider ?? {
            Self.recoveredSuitePrefix + UUID().uuidString
        }
        // A fixed (test-injected) suite name may collide with an occupied
        // directory; generated UUID names cannot realistically collide, but
        // retrying keeps the "never overwrite" guarantee total.
        var lastError: Error?
        for _ in 0..<8 {
            do {
                return try importOnce(
                    from: bundleURL,
                    supportBase: base,
                    suiteName: suiteNames(),
                    defaultsProvider: defaults
                )
            } catch let error as ProjectVaultRecoveryBundle.BundleError {
                guard case .recoveryDestinationOccupied = error else { throw error }
                lastError = error
                continue
            } catch let error as ProjectVaultRecoveryServiceError {
                guard case .recoveryDestinationOccupied = error else { throw error }
                lastError = error
                continue
            }
        }
        if let lastError { throw lastError }
        throw ProjectVaultRecoveryServiceError.recoveryDestinationOccupied(base.path)
    }

    // MARK: - Defaults

    public static func defaultSupportBase() -> URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("Niko Music Hub", isDirectory: true)
    }

    // MARK: - Private

    private static func importOnce(
        from bundleURL: URL,
        supportBase: URL,
        suiteName: String,
        defaultsProvider: DefaultsProvider
    ) throws -> ProjectVaultRecoveredLibrary {
        let supportDirectory = supportBase
            .appendingPathComponent("Isolated", isDirectory: true)
            .appendingPathComponent(sanitizedPathComponent(suiteName), isDirectory: true)
        if isSymlink(at: supportDirectory) {
            throw ProjectVaultRecoveryBundle.BundleError
                .recoveryDestinationOccupied(
                    "symlink destination refused: \(supportDirectory.path)"
                )
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: supportDirectory.path, isDirectory: &isDirectory) {
            throw ProjectVaultRecoveryServiceError.recoveryDestinationOccupied(supportDirectory.path)
        }
        guard let suiteDefaults = defaultsProvider(suiteName) else {
            throw ProjectVaultRecoveryServiceError.recoveredSuiteUnavailable
        }
        // A fresh suite must not already hold persisted settings; refusing here
        // keeps a reused suite name from silently inheriting foreign state.
        if let domain = suiteDefaults.persistentDomain(forName: suiteName), !domain.isEmpty {
            throw ProjectVaultRecoveryServiceError.recoveryDestinationOccupied(
                "settings suite occupied: \(suiteName)"
            )
        }
        let isolatedParent = supportDirectory.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: isolatedParent,
                withIntermediateDirectories: true
            )
        } catch {
            throw ProjectVaultRecoveryServiceError.ioFailed(
                "cannot create isolated support parent \(isolatedParent.path): \(error)"
            )
        }
        // Backend validates (manifest/version, checksums, settings schema,
        // read-only DB integrity) before staging anything, and refuses an
        // occupied destination without touching it. Bundle originals are never
        // modified.
        let staged: ProjectVaultRecoveryBundle.RecoveryImportResult
        do {
            staged = try ProjectVaultRecoveryBundle.importBundle(
                from: bundleURL,
                to: supportDirectory
            )
        } catch {
            // Backend removes only its own staged files on failure; the owned
            // directory is removed only while still empty.
            throw error
        }
        var ownedFiles: [URL] = [staged.databaseURL, staged.settingsURL]
        var completed = false
        defer {
            if !completed {
                for owned in ownedFiles {
                    if !isSymlink(at: owned) {
                        try? FileManager.default.removeItem(at: owned)
                    }
                }
                if let remaining = try? FileManager.default.contentsOfDirectory(
                    atPath: supportDirectory.path
                ), remaining.isEmpty {
                    try? FileManager.default.removeItem(at: supportDirectory)
                }
            }
        }
        // Promote the staged database to the app-expected name. Same-directory
        // rename is atomic; the destination cannot exist in a fresh directory,
        // and an occupied name fails closed instead of overwriting.
        let finalDatabaseURL = supportDirectory.appendingPathComponent(
            recoveredDatabaseFileName,
            isDirectory: false
        )
        if FileManager.default.fileExists(atPath: finalDatabaseURL.path) || isSymlink(at: finalDatabaseURL) {
            throw ProjectVaultRecoveryServiceError.recoveryDestinationOccupied(finalDatabaseURL.path)
        }
        do {
            try FileManager.default.moveItem(at: staged.databaseURL, to: finalDatabaseURL)
        } catch {
            throw ProjectVaultRecoveryServiceError.ioFailed(
                "cannot place recovered database: \(error)"
            )
        }
        ownedFiles.removeAll { $0 == staged.databaseURL }
        ownedFiles.append(finalDatabaseURL)
        // Re-verify the placed file through the read-only path after the move.
        try SQLiteArchiveDatabase.verifyBackupFileIntegrity(at: finalDatabaseURL)
        // Recovered settings go ONLY to the fresh suite, via the same store
        // the app uses for that suite. Current settings are never written.
        // (The backend already forced automation off/paused in `staged.settings`.)
        do {
            try UserDefaultsSettingsStore(userDefaults: suiteDefaults).saveSettings(staged.settings)
        } catch {
            throw ProjectVaultRecoveryServiceError.ioFailed(
                "cannot write recovered settings to fresh suite: \(error)"
            )
        }
        completed = true
        return ProjectVaultRecoveredLibrary(
            settingsSuiteName: suiteName,
            supportDirectoryURL: supportDirectory,
            databaseURL: finalDatabaseURL,
            settings: staged.settings
        )
    }

    private static func isSymlink(at url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Same sanitization `AppComposition` applies to isolated suite directory
    /// names, so the recovered support directory matches the runtime layout.
    private static func sanitizedPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return sanitized.isEmpty ? "isolated" : sanitized
    }
}
