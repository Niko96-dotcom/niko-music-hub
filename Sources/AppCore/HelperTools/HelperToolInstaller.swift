import CryptoKit
import Darwin
import Foundation

public enum HelperToolBundle: String, CaseIterable, Sendable, Identifiable {
    case downloadAndConvert
    case stemSeparation

    public var id: String {
        rawValue
    }

    public var tools: [HelperTool] {
        switch self {
        case .downloadAndConvert:
            [.ytDlp, .ffmpeg, .ffprobe]
        case .stemSeparation:
            [.demucsMlx]
        }
    }

    public var title: String {
        switch self {
        case .downloadAndConvert:
            "Download & Convert"
        case .stemSeparation:
            "Stem Separation"
        }
    }

    public var detail: String {
        switch self {
        case .downloadAndConvert:
            "yt-dlp and FFmpeg · about 100 MB"
        case .stemSeparation:
            "demucs-mlx and its model · about 1 GB"
        }
    }
}

public struct HelperInstallProgress: Equatable, Sendable {
    public var phase: String
    public var fractionCompleted: Double?

    public init(phase: String, fractionCompleted: Double? = nil) {
        self.phase = phase
        self.fractionCompleted = fractionCompleted
    }
}

public enum HelperInstallError: LocalizedError, Equatable, Sendable {
    case downloadFailed(String)
    case checksumMismatch(file: String)
    case extractFailed(String)
    case setupFailed(String)
    case verificationFailed(String)
    /// A download that is not what its publisher released: a bad signature, another key, or a release too old.
    case untrustedRelease(String)

    public var errorDescription: String? {
        switch self {
        case let .downloadFailed(detail):
            if detail.isEmpty {
                "Could not download the helper tools. Check your internet connection and try again."
            } else {
                "Could not download \(detail). Check your internet connection and try again."
            }
        case let .checksumMismatch(file):
            "The downloaded \(file) file was damaged. Try again."
        case let .extractFailed(detail):
            if detail.isEmpty {
                "Could not unpack the downloaded tools. Try again."
            } else {
                "Could not unpack \(detail). Try again."
            }
        case let .setupFailed(detail):
            if detail.isEmpty {
                "Could not set up the helper tools. Try again."
            } else {
                "Could not set up \(detail). Try again."
            }
        case let .verificationFailed(detail):
            if detail.isEmpty {
                "Could not verify the installed tools. Try again."
            } else {
                "Could not verify \(detail). Try again."
            }
        case let .untrustedRelease(detail):
            "The install stopped: \(detail). If this happens again, update Niko Music Hub."
        }
    }
}

public enum HelperToolDownloadSources {
    /// The newest yt-dlp release as GitHub's API names it; the installer then downloads that release's files.
    public static let ytDlpLatestRelease: URL = URL(
        string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    )!

    public static func ytDlpReleaseFile(_ name: String, tag: String) -> URL {
        URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\(tag)/\(name)")!
    }


    public static let pythonVersion = "3.12"
    public static let warmupModel = "htdemucs_ft"
}

/// One download that an install accepts only with exactly this SHA-256.
public struct PinnedDownload: Equatable, Sendable {
    public let url: URL
    public let sha256: String

    public init(url: URL, sha256: String) {
        self.url = url
        self.sha256 = sha256
    }
}

/// What an install trusts: the exact builds it accepts, and the key yt-dlp releases must be signed with. The
/// checksums come from the app, not from the server that serves the files, so a build that changed on the host
/// fails the install. `HelperToolPins.release` (HelperToolPins.swift) holds the shipped values; tests pass their own.
public struct HelperToolPins: Equatable, Sendable {
    public var ffmpeg: PinnedDownload
    public var ffprobe: PinnedDownload
    public var uv: PinnedDownload
    /// demucs-mlx and every package it needs, each with one exact version and the SHA-256 of each of its files
    /// (`uv pip install --require-hashes`). The model weights are pinned by the hashes inside demucs-mlx.
    public var demucsRequirements: String
    /// yt-dlp follows the newest release, so it has no pinned hash: its checksum list must carry this key's signature.
    public var ytDlpSigningKey: YtDlpSigningKey

    public init(
        ffmpeg: PinnedDownload,
        ffprobe: PinnedDownload,
        uv: PinnedDownload,
        demucsRequirements: String,
        ytDlpSigningKey: YtDlpSigningKey
    ) {
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.uv = uv
        self.demucsRequirements = demucsRequirements
        self.ytDlpSigningKey = ytDlpSigningKey
    }
}

public actor HelperToolInstaller {
    private let locator: HelperToolLocator
    private let pins: HelperToolPins
    private let downloader: any HelperDownloading
    private let processRunner: any StreamingExternalProcessRunning
    /// The person's home: the warm-up puts the model where later runs read it (`~/.cache/demucs-mlx`).
    private let homeDirectory: URL
    private let fileManager: FileManager
    /// Staging names of attempts still running. Installs can interleave at
    /// suspension points (a cancelled attempt still unwinds while its
    /// replacement runs), so sweeps skip every folder a live attempt owns.
    private var activeAttempts: Set<String> = []

    public init(
        locator: HelperToolLocator,
        pins: HelperToolPins = .release,
        downloader: any HelperDownloading = URLSessionHelperDownloader(),
        processRunner: any StreamingExternalProcessRunning,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.locator = locator
        self.pins = pins
        self.downloader = downloader
        self.processRunner = processRunner
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public func install(
        _ bundle: HelperToolBundle,
        progress: @escaping @Sendable (HelperInstallProgress) -> Void
    ) async throws {
        // Killed or crashed attempts never ran their cleanup.
        removeAbandonedAttempts(in: locator.managedRoot.appendingPathComponent(".staging", isDirectory: true))
        switch bundle {
        case .downloadAndConvert:
            try await installDownloadAndConvert(progress: progress)
        case .stemSeparation:
            try await installStemSeparation(progress: progress)
        }
    }

    public nonisolated func isInstalled(_ bundle: HelperToolBundle) -> Bool {
        bundle.tools.allSatisfy { tool in
            HelperExecutableValidation.validate(url: locator.managedExecutableURL(for: tool)) == nil
        }
    }

    // MARK: - Download & Convert

    private func installDownloadAndConvert(
        progress: @escaping @Sendable (HelperInstallProgress) -> Void
    ) async throws {
        let staging = freshStagingDirectory()
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: staging)
            activeAttempts.remove(staging.lastPathComponent)
        }
        let stagingBin = staging.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: stagingBin, withIntermediateDirectories: true)

        // Weighted steps keep fractions non-decreasing across sub-progress.
        let ytEnd = 0.34
        let ffmpegEnd = 0.62
        let ffprobeEnd = 0.90

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Downloading yt-dlp", fractionCompleted: 0.0))

        // One release tag for all three files, so the list, its signature and the binary belong together.
        let ytTag = try await latestYtDlpTag()
        try Task.checkCancellation()
        let sumsStaged = staging.appendingPathComponent("SHA2-256SUMS", isDirectory: false)
        let signatureStaged = staging.appendingPathComponent("SHA2-256SUMS.sig", isDirectory: false)
        _ = try await downloader.download(
            HelperToolDownloadSources.ytDlpReleaseFile("SHA2-256SUMS", tag: ytTag), to: sumsStaged
        ) { _ in }
        _ = try await downloader.download(
            HelperToolDownloadSources.ytDlpReleaseFile("SHA2-256SUMS.sig", tag: ytTag), to: signatureStaged
        ) { _ in }
        try Task.checkCancellation()
        let sums = try Data(contentsOf: sumsStaged)
        try pins.ytDlpSigningKey.verify(signature: try Data(contentsOf: signatureStaged), of: sums)
        let ytExpected = try expectedYtDlpHash(from: String(decoding: sums, as: UTF8.self))
        let ytStaged = staging.appendingPathComponent("yt-dlp_macos", isDirectory: false)
        _ = try await downloader.download(
            HelperToolDownloadSources.ytDlpReleaseFile("yt-dlp_macos", tag: ytTag),
            to: ytStaged
        ) { value in
            let sub = value ?? 0
            progress(HelperInstallProgress(
                phase: "Downloading yt-dlp",
                fractionCompleted: ytEnd * min(max(sub, 0), 1)
            ))
        }
        try Task.checkCancellation()
        try verifyFile(at: ytStaged, expectedHex: ytExpected, displayName: HelperTool.ytDlp.displayName)
        try Task.checkCancellation()
        try installExecutable(
            from: ytStaged,
            to: stagingBin.appendingPathComponent(HelperTool.ytDlp.executableName, isDirectory: false)
        )

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Downloading FFmpeg", fractionCompleted: ytEnd))
        let ffmpegZipStaged = staging.appendingPathComponent("ffmpeg.zip", isDirectory: false)
        _ = try await downloader.download(pins.ffmpeg.url, to: ffmpegZipStaged) { value in
            let sub = value ?? 0
            progress(HelperInstallProgress(
                phase: "Downloading FFmpeg",
                fractionCompleted: ytEnd + (ffmpegEnd - ytEnd) * min(max(sub, 0), 1)
            ))
        }
        try Task.checkCancellation()
        try verifyFile(at: ffmpegZipStaged, expectedHex: pins.ffmpeg.sha256, displayName: "FFmpeg")
        try Task.checkCancellation()
        let ffmpegUnzipDir = staging.appendingPathComponent("unzipped-ffmpeg", isDirectory: true)
        try fileManager.createDirectory(at: ffmpegUnzipDir, withIntermediateDirectories: true)
        let ffmpegDittoResult = try await processRunner.run(ExternalProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", ffmpegZipStaged.path, ffmpegUnzipDir.path],
            timeoutSeconds: 120
        ))
        if ffmpegDittoResult.exitCode != 0 {
            throw HelperInstallError.extractFailed(verificationDetail(
                tool: "FFmpeg",
                standardError: ffmpegDittoResult.standardError
            ))
        }
        try Task.checkCancellation()
        let ffmpegExtracted = ffmpegUnzipDir.appendingPathComponent("ffmpeg", isDirectory: false)
        guard fileManager.fileExists(atPath: ffmpegExtracted.path) else {
            throw HelperInstallError.extractFailed("FFmpeg")
        }
        try installExecutable(
            from: ffmpegExtracted,
            to: stagingBin.appendingPathComponent(HelperTool.ffmpeg.executableName, isDirectory: false)
        )

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Downloading ffprobe", fractionCompleted: ffmpegEnd))
        let ffprobeZipStaged = staging.appendingPathComponent("ffprobe.zip", isDirectory: false)
        _ = try await downloader.download(pins.ffprobe.url, to: ffprobeZipStaged) { value in
            let sub = value ?? 0
            progress(HelperInstallProgress(
                phase: "Downloading ffprobe",
                fractionCompleted: ffmpegEnd + (ffprobeEnd - ffmpegEnd) * min(max(sub, 0), 1)
            ))
        }
        try Task.checkCancellation()
        try verifyFile(at: ffprobeZipStaged, expectedHex: pins.ffprobe.sha256, displayName: "ffprobe")
        try Task.checkCancellation()
        let ffprobeUnzipDir = staging.appendingPathComponent("unzipped-ffprobe", isDirectory: true)
        try fileManager.createDirectory(at: ffprobeUnzipDir, withIntermediateDirectories: true)
        let ffprobeDittoResult = try await processRunner.run(ExternalProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", ffprobeZipStaged.path, ffprobeUnzipDir.path],
            timeoutSeconds: 120
        ))
        if ffprobeDittoResult.exitCode != 0 {
            throw HelperInstallError.extractFailed(verificationDetail(
                tool: "ffprobe",
                standardError: ffprobeDittoResult.standardError
            ))
        }
        try Task.checkCancellation()
        let ffprobeExtracted = ffprobeUnzipDir.appendingPathComponent("ffprobe", isDirectory: false)
        guard fileManager.fileExists(atPath: ffprobeExtracted.path) else {
            throw HelperInstallError.extractFailed("ffprobe")
        }
        try installExecutable(
            from: ffprobeExtracted,
            to: stagingBin.appendingPathComponent(HelperTool.ffprobe.executableName, isDirectory: false)
        )

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Checking tools", fractionCompleted: ffprobeEnd))
        let ytBin = stagingBin.appendingPathComponent(HelperTool.ytDlp.executableName, isDirectory: false)
        let ytResult = try await processRunner.run(ExternalProcessRequest(
            executableURL: ytBin,
            arguments: ["--version"],
            timeoutSeconds: 120
        ))
        if ytResult.exitCode != 0 {
            throw HelperInstallError.verificationFailed(verificationDetail(
                tool: "yt-dlp",
                standardError: ytResult.standardError
            ))
        }
        try Task.checkCancellation()
        let ffmpegBin = stagingBin.appendingPathComponent(HelperTool.ffmpeg.executableName, isDirectory: false)
        let ffmpegResult = try await processRunner.run(ExternalProcessRequest(
            executableURL: ffmpegBin,
            arguments: ["-version"],
            timeoutSeconds: 30
        ))
        if ffmpegResult.exitCode != 0 {
            throw HelperInstallError.verificationFailed(verificationDetail(
                tool: "FFmpeg",
                standardError: ffmpegResult.standardError
            ))
        }
        try Task.checkCancellation()
        let ffprobeBin = stagingBin.appendingPathComponent(HelperTool.ffprobe.executableName, isDirectory: false)
        let ffprobeResult = try await processRunner.run(ExternalProcessRequest(
            executableURL: ffprobeBin,
            arguments: ["-version"],
            timeoutSeconds: 30
        ))
        if ffprobeResult.exitCode != 0 {
            throw HelperInstallError.verificationFailed(verificationDetail(
                tool: "ffprobe",
                standardError: ffprobeResult.standardError
            ))
        }

        try Task.checkCancellation()
        // Publish only after every check passed; nothing in managedBinDirectory
        // was touched before this point.
        try installExecutable(
            from: stagingBin.appendingPathComponent(HelperTool.ytDlp.executableName, isDirectory: false),
            to: locator.managedExecutableURL(for: .ytDlp)
        )
        try installExecutable(
            from: stagingBin.appendingPathComponent(HelperTool.ffmpeg.executableName, isDirectory: false),
            to: locator.managedExecutableURL(for: .ffmpeg)
        )
        try installExecutable(
            from: stagingBin.appendingPathComponent(HelperTool.ffprobe.executableName, isDirectory: false),
            to: locator.managedExecutableURL(for: .ffprobe)
        )

        progress(HelperInstallProgress(phase: "Done", fractionCompleted: 1))
    }

    // MARK: - Stem Separation

    private func installStemSeparation(
        progress: @escaping @Sendable (HelperInstallProgress) -> Void
    ) async throws {
        let staging = freshStagingDirectory()
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: staging)
            activeAttempts.remove(staging.lastPathComponent)
        }

        let uvDownloadEnd = 0.10
        let demucsInstallFraction = 0.10
        let warmupFraction = 0.70
        let cleanupFraction = 0.95

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Downloading the setup helper", fractionCompleted: 0.0))

        let uvArchiveStaged = staging.appendingPathComponent("uv.tar.gz", isDirectory: false)
        _ = try await downloader.download(pins.uv.url, to: uvArchiveStaged) { value in
            let sub = value ?? 0
            progress(HelperInstallProgress(
                phase: "Downloading the setup helper",
                fractionCompleted: uvDownloadEnd * min(max(sub, 0), 1)
            ))
        }
        try Task.checkCancellation()
        try verifyFile(at: uvArchiveStaged, expectedHex: pins.uv.sha256, displayName: "uv")
        try Task.checkCancellation()

        let uvExtractDir = staging.appendingPathComponent("uv", isDirectory: true)
        try fileManager.createDirectory(at: uvExtractDir, withIntermediateDirectories: true)
        let tarResult = try await processRunner.run(ExternalProcessRequest(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", uvArchiveStaged.path, "-C", uvExtractDir.path],
            timeoutSeconds: 120
        ))
        if tarResult.exitCode != 0 {
            throw HelperInstallError.extractFailed(verificationDetail(
                tool: "uv",
                standardError: tarResult.standardError
            ))
        }
        try Task.checkCancellation()
        let uvSource = uvExtractDir
            .appendingPathComponent("uv-aarch64-apple-darwin", isDirectory: true)
            .appendingPathComponent("uv", isDirectory: false)
        guard fileManager.fileExists(atPath: uvSource.path) else {
            throw HelperInstallError.extractFailed("uv")
        }
        let uvDestination = locator.managedRoot
            .appendingPathComponent("uv", isDirectory: true)
            .appendingPathComponent("uv", isDirectory: false)
        try installExecutable(from: uvSource, to: uvDestination)

        try Task.checkCancellation()
        progress(HelperInstallProgress(
            phase: "Installing demucs-mlx (this can take a few minutes)",
            fractionCompleted: demucsInstallFraction
        ))

        let home = homeDirectory.path
        // A virtual environment holds absolute interpreter paths, so keep each
        // attempt at its permanent path and publish its entry point only when
        // preparation succeeds. A late cancelled writer cannot touch live tools.
        let attemptRoot = locator.managedRoot.appendingPathComponent("uv-tools")
            .appendingPathComponent(staging.lastPathComponent, isDirectory: true)
        let venv = attemptRoot.appendingPathComponent("venv", isDirectory: true)
        let attemptBin = venv.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: attemptRoot, withIntermediateDirectories: true)
        var published = false
        defer {
            if !published { try? fileManager.removeItem(at: attemptRoot) }
        }
        let uvEnvironment: [String: String] = [
            "HOME": home,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "UV_PYTHON_INSTALL_DIR": attemptRoot.appendingPathComponent("python").path,
            "UV_CACHE_DIR": attemptRoot.appendingPathComponent("cache").path,
            "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_NO_CONFIG": "1",
        ]
        let requirements = staging.appendingPathComponent("demucs-requirements.txt", isDirectory: false)
        try Data(pins.demucsRequirements.utf8).write(to: requirements)
        let venvRequest = ExternalProcessRequest(
            executableURL: uvDestination,
            arguments: ["venv", "--python", HelperToolDownloadSources.pythonVersion, venv.path],
            environment: uvEnvironment,
            timeoutSeconds: 600
        )
        // Every package and file must match the pinned lock; nothing is built from source.
        let installRequest = ExternalProcessRequest(
            executableURL: uvDestination,
            arguments: [
                "pip", "install", "--python", attemptBin.appendingPathComponent("python").path,
                "--require-hashes", "--no-build", "-r", requirements.path,
            ],
            environment: uvEnvironment,
            timeoutSeconds: 1800
        )
        for request in [venvRequest, installRequest] {
            let uvResult = try await processRunner.run(
                request,
                onStandardOutput: { _ in },
                onStandardError: { _ in }
            )
            if uvResult.exitCode != 0 {
                let lines = uvResult.standardError
                    .split(separator: "\n")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                // Keep the last 20 lines for context; the message carries the last one.
                let tail = Array(lines.suffix(20))
                let last = tail.last ?? "(no details)"
                throw HelperInstallError.setupFailed("demucs-mlx: \(last)")
            }
            try Task.checkCancellation()
        }

        let demucsBin = attemptBin.appendingPathComponent(HelperTool.demucsMlx.executableName)
        guard fileManager.isExecutableFile(atPath: demucsBin.path) else {
            throw HelperInstallError.setupFailed("demucs-mlx")
        }

        progress(HelperInstallProgress(
            phase: "Preparing the separation model",
            fractionCompleted: warmupFraction
        ))

        let wavURL = staging.appendingPathComponent("silence.wav", isDirectory: false)
        try silentWAVData().write(to: wavURL)
        let warmupOut = attemptRoot.appendingPathComponent("warmup-out", isDirectory: true)
        // Same HOME the app uses later, so the prepared model lands in the cache
        // demucs-mlx reads on real runs (~/.cache/demucs-mlx).
        let warmupEnvironment = [
            "HOME": home,
            "PATH": "\(attemptBin.path):\(locator.managedBinDirectory.path):/usr/bin:/bin",
        ]
        let warmupRequest = ExternalProcessRequest(
            executableURL: demucsBin,
            arguments: [
                wavURL.path,
                "--out", warmupOut.path,
                "-n", HelperToolDownloadSources.warmupModel,
                "--prefetch-tracks", "0",
                "--write-workers", "1",
            ],
            environment: warmupEnvironment,
            timeoutSeconds: 1800
        )
        let warmupResult = try await processRunner.run(warmupRequest)
        if warmupResult.exitCode != 0 {
            throw HelperInstallError.verificationFailed(verificationDetail(
                tool: "demucs-mlx",
                standardError: warmupResult.standardError
            ))
        }

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Cleaning up", fractionCompleted: cleanupFraction))
        try? fileManager.removeItem(at: attemptRoot.appendingPathComponent("cache"))
        try? fileManager.removeItem(at: warmupOut)
        try Task.checkCancellation()
        let entryPoint = staging.appendingPathComponent(HelperTool.demucsMlx.executableName)
        try fileManager.createSymbolicLink(at: entryPoint, withDestinationURL: demucsBin)
        try installExecutable(from: entryPoint, to: locator.managedExecutableURL(for: .demucsMlx))
        published = true
        // The entry point no longer reaches earlier environments.
        removeAbandonedAttempts(in: attemptRoot.deletingLastPathComponent())

        progress(HelperInstallProgress(phase: "Done", fractionCompleted: 1))
    }

    // MARK: - Helpers

    private func freshStagingDirectory() -> URL {
        let name = UUID().uuidString
        activeAttempts.insert(name)
        return locator.managedRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    /// Removes every attempt folder in `directory` that no live attempt owns.
    private func removeAbandonedAttempts(in directory: URL) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where !activeAttempts.contains(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// The newest yt-dlp release tag. A tag that is not a release date is refused, and so is a release older than
    /// the one YouTube needs: an old release is still validly signed, so the date stops a downgrade.
    private func latestYtDlpTag() async throws -> String {
        struct Release: Decodable {
            let tagName: String
            enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
        }
        let text = try await downloader.fetchText(HelperToolDownloadSources.ytDlpLatestRelease)
        guard let tag = try? JSONDecoder().decode(Release.self, from: Data(text.utf8)).tagName else {
            throw HelperInstallError.downloadFailed("yt-dlp: unreadable release information")
        }
        guard tag.range(of: #"^20[0-9]{2}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$"#, options: .regularExpression) != nil else {
            throw HelperInstallError.untrustedRelease("yt-dlp: unexpected release name")
        }
        let floor = YtDlpVersionPolicy.youtubeCompatibilityFloor
        guard let date = YtDlpVersionPolicy.parseVersionDate(tag),
              let floorDate = YtDlpVersionPolicy.parseVersionDate(floor),
              date >= floorDate
        else {
            throw HelperInstallError.untrustedRelease("yt-dlp \(tag) is older than \(floor)")
        }
        return tag
    }

    private func expectedYtDlpHash(from text: String) throws -> String {
        for rawLine in text.split(separator: "\n") {
            let parts = rawLine.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2 else { continue }
            var filename = String(parts.last!)
            if filename.hasPrefix("*") {
                filename.removeFirst()
            }
            if filename == "yt-dlp_macos" {
                return String(parts.first!)
            }
        }
        throw HelperInstallError.downloadFailed("yt-dlp checksums: entry for yt-dlp_macos not found")
    }

    private func sha256HexOfFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func verifyFile(at url: URL, expectedHex: String, displayName: String) throws {
        let actual = try sha256HexOfFile(at: url)
        if actual.lowercased() != expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            throw HelperInstallError.checksumMismatch(file: displayName)
        }
    }

    private func installExecutable(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        removeQuarantine(at: source)
        // POSIX rename atomically replaces an existing regular file on the same
        // volume; staging lives under the managed root so this holds. The existing
        // destination is never deleted before the replacement is in place.
        if rename(source.path, destination.path) != 0 {
            let renameErrno = errno
            guard renameErrno == EXDEV else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(renameErrno))
            }
            let tempName = destination.lastPathComponent + ".nmh-new-" + UUID().uuidString
            let tempURL = destination.deletingLastPathComponent().appendingPathComponent(tempName)
            do {
                try fileManager.copyItem(at: source, to: tempURL)
                if rename(tempURL.path, destination.path) != 0 {
                    let secondErrno = errno
                    try? fileManager.removeItem(at: tempURL)
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(secondErrno))
                }
            } catch {
                try? fileManager.removeItem(at: tempURL)
                throw error
            }
        }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        removeQuarantine(at: destination)
    }

    private func removeQuarantine(at url: URL) {
        url.path.withCString { pathPointer in
            "com.apple.quarantine".withCString { namePointer in
                _ = removexattr(pathPointer, namePointer, 0)
            }
        }
    }

    private func verificationDetail(tool: String, standardError: String) -> String {
        let first = standardError
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let first, !first.isEmpty else {
            return tool
        }
        return "\(tool): \(first)"
    }

    private func silentWAVData() -> Data {
        // 1 second of 44.1 kHz 16-bit stereo silence.
        let sampleRate: UInt32 = 44_100
        let channels: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let frames = sampleRate
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = UInt32(frames) * UInt32(blockAlign)

        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        appendUInt32LE(&data, 36 + dataSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        appendUInt32LE(&data, 16)
        appendUInt16LE(&data, 1) // PCM
        appendUInt16LE(&data, channels)
        appendUInt32LE(&data, sampleRate)
        appendUInt32LE(&data, byteRate)
        appendUInt16LE(&data, blockAlign)
        appendUInt16LE(&data, bitsPerSample)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        appendUInt32LE(&data, dataSize)
        data.append(contentsOf: repeatElement(UInt8(0), count: Int(dataSize)))
        return data
    }

    private func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
