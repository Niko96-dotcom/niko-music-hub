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
            "demucs-mlx and its model · about 1.2 GB"
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
        }
    }
}

public enum HelperToolDownloadSources {
    public static let ffmpegHost = "ffmpeg.martin-riedl.de"
    public static let ytDlpBinary: URL = URL(
        string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
    )!
    public static let ytDlpChecksums: URL = URL(
        string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"
    )!
    public static let ffmpegZip: URL = URL(
        string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
    )!
    public static let ffprobeZip: URL = URL(
        string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffprobe.zip"
    )!
    public static let uvArchive: URL = URL(
        string: "https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz"
    )!
    public static let uvChecksum: URL = URL(string: uvArchive.absoluteString + ".sha256")!

    public static let demucsPackageSpec = "demucs-mlx[convert]"
    public static let pythonVersion = "3.12"
    public static let warmupModel = "htdemucs_ft"
}

public actor HelperToolInstaller {
    private let locator: HelperToolLocator
    private let downloader: any HelperDownloading
    private let processRunner: any StreamingExternalProcessRunning
    private let fileManager: FileManager

    public init(
        locator: HelperToolLocator,
        downloader: any HelperDownloading = URLSessionHelperDownloader(),
        processRunner: any StreamingExternalProcessRunning = FoundationExternalProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.locator = locator
        self.downloader = downloader
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    public func install(
        _ bundle: HelperToolBundle,
        progress: @escaping @Sendable (HelperInstallProgress) -> Void
    ) async throws {
        switch bundle {
        case .downloadAndConvert:
            try await installDownloadAndConvert(progress: progress)
        case .stemSeparation:
            try await installStemSeparation(progress: progress)
        }
    }

    public nonisolated func isInstalled(_ bundle: HelperToolBundle) -> Bool {
        let manager = FileManager()
        return bundle.tools.allSatisfy { tool in
            manager.isExecutableFile(atPath: locator.managedExecutableURL(for: tool).path)
        }
    }

    // MARK: - Download & Convert

    private func installDownloadAndConvert(
        progress: @escaping @Sendable (HelperInstallProgress) -> Void
    ) async throws {
        let staging = freshStagingDirectory()
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let stagingBin = staging.appendingPathComponent("bin", isDirectory: true)
        try fileManager.createDirectory(at: stagingBin, withIntermediateDirectories: true)

        // Weighted steps keep fractions non-decreasing across sub-progress.
        let ytEnd = 0.34
        let ffmpegEnd = 0.62
        let ffprobeEnd = 0.90

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Downloading yt-dlp", fractionCompleted: 0.0))

        let checksumsText = try await downloader.fetchText(HelperToolDownloadSources.ytDlpChecksums)
        try Task.checkCancellation()
        let ytExpected = try expectedYtDlpHash(from: checksumsText)
        let ytStaged = staging.appendingPathComponent("yt-dlp_macos", isDirectory: false)
        _ = try await downloader.download(
            HelperToolDownloadSources.ytDlpBinary,
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
        let ffmpegFinal = try await downloader.download(
            HelperToolDownloadSources.ffmpegZip,
            to: ffmpegZipStaged
        ) { value in
            let sub = value ?? 0
            progress(HelperInstallProgress(
                phase: "Downloading FFmpeg",
                fractionCompleted: ytEnd + (ffmpegEnd - ytEnd) * min(max(sub, 0), 1)
            ))
        }
        try Task.checkCancellation()
        try validateFFmpegHost(ffmpegFinal, tool: "FFmpeg")
        let ffmpegChecksumText = try await downloader.fetchText(checksumURL(for: ffmpegFinal))
        let ffmpegExpected = try firstChecksumToken(from: ffmpegChecksumText, context: "FFmpeg")
        try verifyFile(at: ffmpegZipStaged, expectedHex: ffmpegExpected, displayName: "FFmpeg")
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
        let ffprobeFinal = try await downloader.download(
            HelperToolDownloadSources.ffprobeZip,
            to: ffprobeZipStaged
        ) { value in
            let sub = value ?? 0
            progress(HelperInstallProgress(
                phase: "Downloading ffprobe",
                fractionCompleted: ffmpegEnd + (ffprobeEnd - ffmpegEnd) * min(max(sub, 0), 1)
            ))
        }
        try Task.checkCancellation()
        try validateFFmpegHost(ffprobeFinal, tool: "ffprobe")
        let ffprobeChecksumText = try await downloader.fetchText(checksumURL(for: ffprobeFinal))
        let ffprobeExpected = try firstChecksumToken(from: ffprobeChecksumText, context: "ffprobe")
        try verifyFile(at: ffprobeZipStaged, expectedHex: ffprobeExpected, displayName: "ffprobe")
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
        defer { try? fileManager.removeItem(at: staging) }

        let uvDownloadEnd = 0.10
        let demucsInstallFraction = 0.10
        let warmupFraction = 0.70
        let cleanupFraction = 0.95

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Downloading the setup helper", fractionCompleted: 0.0))

        let uvArchiveStaged = staging.appendingPathComponent("uv.tar.gz", isDirectory: false)
        _ = try await downloader.download(
            HelperToolDownloadSources.uvArchive,
            to: uvArchiveStaged
        ) { value in
            let sub = value ?? 0
            progress(HelperInstallProgress(
                phase: "Downloading the setup helper",
                fractionCompleted: uvDownloadEnd * min(max(sub, 0), 1)
            ))
        }
        try Task.checkCancellation()
        let uvChecksumText = try await downloader.fetchText(HelperToolDownloadSources.uvChecksum)
        let uvExpected = try firstChecksumToken(from: uvChecksumText, context: "uv")
        try verifyFile(at: uvArchiveStaged, expectedHex: uvExpected, displayName: "uv")
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

        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        // Record pre-existing state so a failed run never deletes a working tool,
        // but still cleans a stray link this run may have left behind.
        let demucsBinURL = locator.managedExecutableURL(for: .demucsMlx)
        let demucsExistedBeforeRun = fileManager.fileExists(atPath: demucsBinURL.path)
        let uvEnvironment: [String: String] = [
            "HOME": home,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "UV_TOOL_DIR": locator.managedRoot.appendingPathComponent("uv-tools").path,
            "UV_TOOL_BIN_DIR": locator.managedBinDirectory.path,
            "UV_PYTHON_INSTALL_DIR": locator.managedRoot.appendingPathComponent("python").path,
            "UV_CACHE_DIR": locator.managedRoot.appendingPathComponent("uv-cache").path,
            "UV_PYTHON_PREFERENCE": "only-managed",
            "UV_NO_CONFIG": "1",
        ]
        let uvRequest = ExternalProcessRequest(
            executableURL: uvDestination,
            arguments: [
                "tool", "install", "--upgrade", "--python",
                HelperToolDownloadSources.pythonVersion,
                HelperToolDownloadSources.demucsPackageSpec,
            ],
            environment: uvEnvironment,
            timeoutSeconds: 1800
        )
        let uvResult = try await processRunner.run(
            uvRequest,
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
            if !demucsExistedBeforeRun {
                try? fileManager.removeItem(at: demucsBinURL)
            }
            throw HelperInstallError.setupFailed("demucs-mlx: \(last)")
        }

        try Task.checkCancellation()
        let demucsBin = locator.managedExecutableURL(for: .demucsMlx)
        guard fileManager.isExecutableFile(atPath: demucsBin.path) else {
            if !demucsExistedBeforeRun {
                try? fileManager.removeItem(at: demucsBinURL)
            }
            throw HelperInstallError.setupFailed("demucs-mlx")
        }

        progress(HelperInstallProgress(
            phase: "Preparing the separation model",
            fractionCompleted: warmupFraction
        ))

        let wavURL = staging.appendingPathComponent("silence.wav", isDirectory: false)
        try silentWAVData().write(to: wavURL)
        let warmupOut = staging.appendingPathComponent("warmup-out", isDirectory: true)
        // Same HOME the app uses later, so the prepared model lands in the cache
        // demucs-mlx reads on real runs (~/.cache/demucs-mlx).
        let warmupEnvironment = [
            "HOME": home,
            "PATH": "\(locator.managedBinDirectory.path):/usr/bin:/bin",
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
        let warmupResult: ExternalProcessResult
        do {
            warmupResult = try await processRunner.run(warmupRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if !demucsExistedBeforeRun {
                try? fileManager.removeItem(at: demucsBinURL)
            }
            throw error
        }
        if warmupResult.exitCode != 0 {
            if !demucsExistedBeforeRun {
                try? fileManager.removeItem(at: demucsBinURL)
            }
            throw HelperInstallError.verificationFailed(verificationDetail(
                tool: "demucs-mlx",
                standardError: warmupResult.standardError
            ))
        }

        try Task.checkCancellation()
        progress(HelperInstallProgress(phase: "Cleaning up", fractionCompleted: cleanupFraction))
        try? fileManager.removeItem(at: locator.managedRoot.appendingPathComponent("uv-cache"))

        progress(HelperInstallProgress(phase: "Done", fractionCompleted: 1))
    }

    // MARK: - Helpers

    private func freshStagingDirectory() -> URL {
        locator.managedRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func checksumURL(for finalURL: URL) -> URL {
        URL(string: finalURL.absoluteString + ".sha256")!
    }

    private func validateFFmpegHost(_ finalURL: URL, tool: String) throws {
        guard finalURL.scheme == "https",
              finalURL.host == HelperToolDownloadSources.ffmpegHost
        else {
            let host = finalURL.host ?? finalURL.absoluteString
            throw HelperInstallError.downloadFailed("\(tool): unexpected download host \(host)")
        }
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

    private func firstChecksumToken(from text: String, context: String) throws -> String {
        guard let token = text.split(whereSeparator: \.isWhitespace).first.map(String.init),
              !token.isEmpty
        else {
            throw HelperInstallError.downloadFailed("\(context) checksum: unreadable response")
        }
        return token
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
