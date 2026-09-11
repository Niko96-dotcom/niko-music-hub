import Foundation
@testable import FeatureArchiveBrowser
import XCTest

@MainActor
final class ArchiveMiniPlayerMetadataCacheTests: XCTestCase {
    func testFreshBindHidesPrimedMetadataUntilAsyncValidation() async throws {
        ArchivePreviewPlayer.clearMetadataCaches()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-cache-bind-\(UUID().uuidString).wav")
        defer {
            ArchivePreviewPlayer.clearMetadataCaches()
            try? FileManager.default.removeItem(at: url)
        }

        try makeMono16BitWAV(seconds: 12, loudBurstAt: 8, at: url)
        let primingPlayer = ArchivePreviewPlayer()
        primingPlayer.toggle(at: url)
        _ = try await waitForHook(on: primingPlayer)
        primingPlayer.forceStop()

        let freshPlayer = ArchivePreviewPlayer()
        freshPlayer.bind(url: url)

        XCTAssertNil(freshPlayer.hookTime)
        XCTAssertEqual(freshPlayer.duration, 0)
        XCTAssertEqual(freshPlayer.currentTime, 0)
    }

    func testSamePathOverwriteDoesNotSeekFromStaleHookOnImmediatePlay() async throws {
        ArchivePreviewPlayer.clearMetadataCaches()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-cache-overwrite-\(UUID().uuidString).wav")
        defer {
            ArchivePreviewPlayer.clearMetadataCaches()
            try? FileManager.default.removeItem(at: url)
        }

        try makeMono16BitWAV(seconds: 12, loudBurstAt: 8, at: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000)],
            ofItemAtPath: url.path
        )

        let firstPlayer = ArchivePreviewPlayer()
        firstPlayer.toggle(at: url)
        let staleHook = try await waitForHook(on: firstPlayer)
        XCTAssertGreaterThan(staleHook, 5)
        firstPlayer.forceStop()

        // Keep the path stable while replacing the file with a much shorter render.
        // The date is deliberately distinct, so the cache must be revalidated before
        // first play can use any old hook/duration value.
        try makeMono16BitWAV(seconds: 1, loudBurstAt: 0, at: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_010)],
            ofItemAtPath: url.path
        )

        let replacementPlayer = ArchivePreviewPlayer()
        replacementPlayer.prefetch(url: url)
        replacementPlayer.toggle(at: url)

        XCTAssertEqual(
            replacementPlayer.currentTime,
            0,
            accuracy: 0.001,
            "Immediate play must not synchronously seek using a stale same-path cache entry"
        )
        replacementPlayer.forceStop()
    }

    func testLateValidatedCachedHookSeeksForTheStillActivePlayRequest() async throws {
        ArchivePreviewPlayer.clearMetadataCaches()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-cache-late-hook-\(UUID().uuidString).wav")
        defer {
            ArchivePreviewPlayer.clearMetadataCaches()
            try? FileManager.default.removeItem(at: url)
        }

        try makeMono16BitWAV(seconds: 12, loudBurstAt: 8, at: url)
        let primingPlayer = ArchivePreviewPlayer()
        primingPlayer.toggle(at: url)
        let cachedHook = try await waitForHook(on: primingPlayer)
        XCTAssertGreaterThan(cachedHook, 5)
        primingPlayer.forceStop()

        let revision = try XCTUnwrap(
            try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )
        // prepare() validates the cache once without seeking. The next validation, triggered
        // by play, is held until playback is demonstrably past the old 0.35 s cutoff.
        let revisions = RevisionGate(responses: [revision], delayedCall: 2)
        let player = ArchivePreviewPlayer(metadataRevisionLoader: { _ in
            await revisions.load()
        })
        player.prepare(url: url)
        let preparedHook = try await waitForHook(on: player)
        XCTAssertEqual(preparedHook, cachedHook, accuracy: 0.001)

        player.toggle(at: url)
        await revisions.waitUntilDelayedCall()
        _ = try await waitForCurrentTime(on: player, atLeast: 0.5)

        await revisions.releaseDelayedResponse(revision)
        _ = try await waitForCurrentTime(on: player, atLeast: cachedHook - 0.1)
        XCTAssertGreaterThan(
            player.currentTime,
            cachedHook - 0.1,
            "A valid hook that finishes validating after playback advances must still serve this play request"
        )
        player.forceStop()
    }

    func testLateValidatedCachedHookDoesNotSeekAfterPause() async throws {
        ArchivePreviewPlayer.clearMetadataCaches()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-cache-paused-hook-\(UUID().uuidString).wav")
        defer {
            ArchivePreviewPlayer.clearMetadataCaches()
            try? FileManager.default.removeItem(at: url)
        }

        try makeMono16BitWAV(seconds: 12, loudBurstAt: 8, at: url)
        let primingPlayer = ArchivePreviewPlayer()
        primingPlayer.toggle(at: url)
        let cachedHook = try await waitForHook(on: primingPlayer)
        primingPlayer.forceStop()

        let revision = try XCTUnwrap(
            try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )
        let revisions = RevisionGate(responses: [revision], delayedCall: 2)
        let player = ArchivePreviewPlayer(metadataRevisionLoader: { _ in
            await revisions.load()
        })
        player.prepare(url: url)
        _ = try await waitForHook(on: player)

        player.toggle(at: url)
        await revisions.waitUntilDelayedCall()
        // This is intentionally before the revision gate is released. The pending hook must
        // not surprise-seek after the user has paused, even if AVPlayer was still buffering.
        player.toggle(at: url)
        await revisions.releaseDelayedResponse(revision)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertLessThan(
            player.currentTime,
            cachedHook - 1,
            "A paused transport must not receive a late hook seek"
        )
        player.forceStop()
    }

    func testUnknownRevisionDoesNotExposePrimedMetadata() async throws {
        ArchivePreviewPlayer.clearMetadataCaches()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-cache-unknown-revision-\(UUID().uuidString).wav")
        defer {
            ArchivePreviewPlayer.clearMetadataCaches()
            try? FileManager.default.removeItem(at: url)
        }

        try makeMono16BitWAV(seconds: 12, loudBurstAt: 8, at: url)
        let primingPlayer = ArchivePreviewPlayer()
        primingPlayer.toggle(at: url)
        _ = try await waitForHook(on: primingPlayer)
        primingPlayer.forceStop()

        let revisions = RevisionGate(responses: [])
        let player = ArchivePreviewPlayer(metadataRevisionLoader: { _ in
            await revisions.load()
        })
        player.toggle(at: url)
        try await waitForRevisionCalls(on: revisions, atLeast: 1)

        XCTAssertNil(player.hookTime)
        XCTAssertEqual(player.duration, 0)
        player.forceStop()
    }

    func testChangedRevisionAfterAnalysisDiscardsNewHookBeforeCacheCommit() async throws {
        ArchivePreviewPlayer.clearMetadataCaches()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-cache-revision-race-\(UUID().uuidString).wav")
        defer {
            ArchivePreviewPlayer.clearMetadataCaches()
            try? FileManager.default.removeItem(at: url)
        }

        try makeMono16BitWAV(seconds: 12, loudBurstAt: 8, at: url)
        let revision = try XCTUnwrap(
            try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )

        // Prime duration only, so the model has to perform a fresh hook analysis during play.
        let durationPrimer = ArchivePreviewPlayer()
        durationPrimer.prefetch(url: url)
        _ = try await waitForDuration(on: durationPrimer)
        durationPrimer.forceStop()

        // The first request validates cached duration. The second starts fresh hook analysis;
        // its post-analysis revision read is delayed and then reports a replacement render.
        let replacementRevision = revision.addingTimeInterval(1)
        let revisions = RevisionGate(responses: [revision, revision], delayedCall: 3)
        let player = ArchivePreviewPlayer(metadataRevisionLoader: { _ in
            await revisions.load()
        })
        player.prepare(url: url)
        _ = try await waitForDuration(on: player)

        player.toggle(at: url)
        await revisions.waitUntilDelayedCall()
        XCTAssertNil(
            player.hookTime,
            "Fresh hook output must stay private until its post-analysis revision check passes"
        )

        await revisions.releaseDelayedResponse(replacementRevision)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(player.hookTime)
        let revisionCallCount = await revisions.callCount()
        XCTAssertEqual(
            revisionCallCount,
            3,
            "A changed revision discards the in-flight result instead of committing or retrying it"
        )
        player.forceStop()
    }

    private func waitForHook(
        on player: ArchivePreviewPlayer,
        attempts: Int = 150
    ) async throws -> Double {
        for _ in 0..<attempts {
            if let hook = player.hookTime {
                return hook
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(
            domain: "ArchiveMiniPlayerMetadataCacheTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for preview hook analysis"]
        )
    }

    private func waitForDuration(
        on player: ArchivePreviewPlayer,
        attempts: Int = 150
    ) async throws -> Double {
        for _ in 0..<attempts {
            if player.duration > 0 {
                return player.duration
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(
            domain: "ArchiveMiniPlayerMetadataCacheTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for preview duration metadata"]
        )
    }

    private func waitForCurrentTime(
        on player: ArchivePreviewPlayer,
        atLeast minimum: Double,
        attempts: Int = 200
    ) async throws -> Double {
        for _ in 0..<attempts {
            if player.currentTime >= minimum {
                return player.currentTime
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(
            domain: "ArchiveMiniPlayerMetadataCacheTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for preview playback progress"]
        )
    }

    private func waitForRevisionCalls(
        on revisions: RevisionGate,
        atLeast minimum: Int,
        attempts: Int = 150
    ) async throws {
        for _ in 0..<attempts {
            if await revisions.callCount() >= minimum {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(
            domain: "ArchiveMiniPlayerMetadataCacheTests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for metadata revision validation"]
        )
    }

    private func makeMono16BitWAV(seconds: Int, loudBurstAt: Int, at url: URL) throws {
        let sampleRate = 8_000
        let totalSamples = seconds * sampleRate
        var samples = Array(repeating: Int16(0), count: totalSamples)
        let burstStart = max(0, min(totalSamples, loudBurstAt * sampleRate))
        let burstEnd = min(totalSamples, burstStart + sampleRate)
        for index in burstStart..<burstEnd {
            samples[index] = index.isMultiple(of: 2) ? 1_000 : -1_000
        }

        var data = Data()
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign = channelCount * bitsPerSample / 8
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let audioByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        let riffByteCount = UInt32(36) + audioByteCount

        func appendASCII(_ string: String) { data.append(contentsOf: string.utf8) }
        func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendLittleEndian(riffByteCount)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendLittleEndian(UInt32(16))
        appendLittleEndian(UInt16(1))
        appendLittleEndian(channelCount)
        appendLittleEndian(UInt32(sampleRate))
        appendLittleEndian(byteRate)
        appendLittleEndian(blockAlign)
        appendLittleEndian(bitsPerSample)
        appendASCII("data")
        appendLittleEndian(audioByteCount)
        for sample in samples {
            appendLittleEndian(UInt16(bitPattern: sample))
        }

        try data.write(to: url, options: .atomic)
    }
}

private actor RevisionGate {
    private let responses: [Date?]
    private let delayedCall: Int?
    private var calls = 0
    private var delayedRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var delayedResponse: CheckedContinuation<Date?, Never>?

    init(responses: [Date?], delayedCall: Int? = nil) {
        self.responses = responses
        self.delayedCall = delayedCall
    }

    func load() async -> Date? {
        calls += 1
        let call = calls
        if delayedCall == call {
            let waiters = delayedRequestWaiters
            delayedRequestWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            return await withCheckedContinuation { continuation in
                delayedResponse = continuation
            }
        }
        guard !responses.isEmpty else { return nil }
        return responses[min(call - 1, responses.count - 1)]
    }

    func callCount() -> Int {
        calls
    }

    func waitUntilDelayedCall() async {
        guard let delayedCall else { return }
        guard calls < delayedCall else { return }
        await withCheckedContinuation { continuation in
            delayedRequestWaiters.append(continuation)
        }
    }

    func releaseDelayedResponse(_ revision: Date?) {
        let response = delayedResponse
        delayedResponse = nil
        response?.resume(returning: revision)
    }
}
