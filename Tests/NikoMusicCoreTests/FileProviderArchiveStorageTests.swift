import Darwin
import Foundation
import XCTest
@testable import NikoMusicCore

private actor StubFileProviderArchiveService: FileProviderArchiveServicing {
    enum Behavior: Sendable {
        case available
        case inspectionUnavailable
        case durabilityUnavailable
        case materializationUnavailable
        case evictionUnavailable
    }

    let behavior: Behavior
    let locality: ArchiveStorageLocality
    private(set) var inspectedRoots: [URL] = []
    private(set) var localityRequests: [(root: URL, expectedFiles: [URL])] = []
    private(set) var durabilityRoots: [URL] = []
    private(set) var materializationRequests: [(root: URL, expectedFiles: [URL])] = []
    private(set) var evictedRoots: [URL] = []

    init(
        _ behavior: Behavior = .available,
        locality: ArchiveStorageLocality = .fullyLocalCurrent
    ) {
        self.behavior = behavior
        self.locality = locality
    }

    func inspect(root: URL) throws {
        inspectedRoots.append(root)
        if behavior == .inspectionUnavailable {
            throw FileProviderArchiveStorageError.managerUnavailable
        }
    }

    func currentLocality(
        root: URL,
        expectedItems: [FileProviderExpectedItem]
    ) throws -> ArchiveStorageLocality {
        localityRequests.append((root, expectedItems.map(\.url)))
        if behavior == .inspectionUnavailable {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
        return locality
    }

    func waitForChanges(root: URL) throws {
        durabilityRoots.append(root)
        if behavior == .durabilityUnavailable {
            throw FileProviderArchiveStorageError.domainDisconnected
        }
    }

    func materialize(root: URL, expectedItems: [FileProviderExpectedItem]) throws {
        materializationRequests.append((root, expectedItems.map(\.url)))
        if behavior == .materializationUnavailable {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
    }

    func evict(root: URL) throws {
        evictedRoots.append(root)
        if behavior == .evictionUnavailable {
            throw FileProviderArchiveStorageError.managerUnavailable
        }
    }
}

final class FileProviderArchiveStorageTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/provider-root", isDirectory: true)

    func testAvailableProviderReportsPublicCapabilities() async throws {
        let service = StubFileProviderArchiveService()
        let storage = FileProviderArchiveStorage(root: root, service: service)

        let capabilities = try await storage.capabilities()

        XCTAssertEqual(
            capabilities,
            StorageCapabilities(
                waitsForDurability: true,
                supportsMaterialization: true,
                supportsEviction: true
            )
        )
        let inspectedRoots = await service.inspectedRoots
        XCTAssertEqual(inspectedRoots, [root.standardizedFileURL])
    }

    func testUnavailableProviderStatusFailsClosed() async {
        let storage = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService(.inspectionUnavailable)
        )

        do {
            _ = try await storage.capabilities()
            XCTFail("unavailable manager must not advertise provider capabilities")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .managerUnavailable)
        }
    }

    func testCurrentLocalityUsesProviderMetadataWithoutMaterializing() async throws {
        let service = StubFileProviderArchiveService(locality: .materializationRequired)
        let storage = FileProviderArchiveStorage(root: root, service: service)
        let manifest = VaultManifest(entries: [
            .init(
                relativePath: "Nested/Song.cpr",
                type: .regularFile,
                byteCount: 42,
                modifiedAt: .distantPast,
                sha256: "fixture"
            ),
            .init(
                relativePath: "Nested",
                type: .directory,
                byteCount: 0,
                modifiedAt: .distantPast,
                sha256: nil
            ),
        ])

        let locality = try await storage.currentLocality(at: root, manifest: manifest)
        let localityRequests = await service.localityRequests
        let materializationRequests = await service.materializationRequests

        XCTAssertEqual(locality, .materializationRequired)
        XCTAssertEqual(localityRequests.count, 1)
        XCTAssertEqual(localityRequests.first?.root, root.standardizedFileURL)
        XCTAssertEqual(
            localityRequests.first?.expectedFiles,
            [root.appendingPathComponent("Nested/Song.cpr").standardizedFileURL]
        )
        XCTAssertTrue(materializationRequests.isEmpty)
    }

    func testSystemLocalityCurrentForEveryExpectedFileIsFullyLocalCurrent() async throws {
        let expected = [
            FileProviderExpectedItem(
                url: root.appendingPathComponent("A.cpr"),
                expectedType: .regularFile,
                expectedByteCount: 42
            ),
            FileProviderExpectedItem(
                url: root.appendingPathComponent("Audio/take.wav"),
                expectedType: .regularFile,
                expectedByteCount: 42
            ),
        ]
        let coordinator = StubFileProviderMetadataCoordinator(
            metadataByPath: Dictionary(uniqueKeysWithValues: expected.map {
                ($0.url.path, .init(type: .regularFile, size: 42, status: .current))
            })
        )
        let downloader = StubFileProviderDownloader()
        let service = SystemFileProviderArchiveService(
            promisedMetadataCoordinator: coordinator,
            downloader: downloader
        )

        let locality = try await service.currentLocality(
            root: root,
            expectedItems: expected
        )

        XCTAssertEqual(locality, .fullyLocalCurrent)
        XCTAssertEqual(coordinator.requests.map(\.url), expected.map(\.url))
        XCTAssertTrue(coordinator.requests.allSatisfy {
            $0.options.contains(.immediatelyAvailableMetadataOnly)
        })
        XCTAssertTrue(downloader.requestedURLs.isEmpty)
    }

    func testSystemLocalityExpectedMissingFailsClosed() async throws {
        try await assertSystemLocalityFailsClosed(
            for: .init(type: nil, size: nil, status: .unknown)
        )
    }

    func testSystemLocalityNilStatusFailsClosed() async throws {
        try await assertSystemLocalityFailsClosed(
            for: .init(type: .regularFile, size: 42, status: .unknown)
        )
    }

    func testSystemLocalityDownloadedRequiresMaterialization() async throws {
        try await assertSystemLocalityRequiresMaterialization(for: .downloaded)
    }

    func testSystemLocalityNotDownloadedRequiresMaterialization() async throws {
        try await assertSystemLocalityRequiresMaterialization(for: .notDownloaded)
    }

    func testSystemLocalityMetadataErrorFailsClosed() async throws {
        let expected = root.appendingPathComponent("A.cpr")
        let coordinator = StubFileProviderMetadataCoordinator(
            metadataByPath: [:],
            failingPaths: [expected.path]
        )
        let service = SystemFileProviderArchiveService(promisedMetadataCoordinator: coordinator)

        do {
            _ = try await service.currentLocality(
                root: root,
                expectedItems: [
                    .init(url: expected, expectedType: .regularFile, expectedByteCount: 42),
                ]
            )
            XCTFail("metadata errors must not claim fully local bytes")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .lookupUnavailable)
        }
        XCTAssertEqual(coordinator.requests.map(\.url), [expected])
        XCTAssertTrue(coordinator.requests.allSatisfy {
            $0.options.contains(.immediatelyAvailableMetadataOnly)
        })
    }

    func testPromisedMetadataUsesMetadataOnlyCoordinatorAndPromisedValues() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("promised-metadata-\(UUID().uuidString)", isDirectory: true)
        let item = fixtureRoot.appendingPathComponent("Song.cpr")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        try Data(repeating: 0x2A, count: 42).write(to: item)
        let sdk = StubPromisedItemSDK(
            values: [
                .isRegularFileKey: true,
                .fileSizeKey: 42,
                .ubiquitousItemDownloadingStatusKey: URLUbiquitousItemDownloadingStatus.current,
            ]
        )
        let accessor = FoundationFileProviderPromisedItemAccessor(
            checkPromisedItemIsReachable: sdk.checkReachable,
            getPromisedItemResourceValue: sdk.resourceValue
        )
        let coordinator = FoundationFileProviderMetadataCoordinator(promisedItemAccessor: accessor)

        let metadata = try coordinator.metadata(
            at: item,
            options: [.immediatelyAvailableMetadataOnly]
        )

        XCTAssertEqual(
            metadata,
            FileProviderPromisedItemMetadata(
                type: .regularFile,
                size: 42,
                status: .current
            )
        )
        XCTAssertEqual(sdk.reachabilityURLs, [item])
        XCTAssertEqual(
            Set(sdk.requestedKeys),
            Set([
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemDownloadingErrorKey,
            ])
        )
    }

    func testCurrentLocalityRejectsSamePathSizeGrowthWithoutDownload() async throws {
        let item = FileProviderExpectedItem(
            url: root.appendingPathComponent("Song.cpr"),
            expectedType: .regularFile,
            expectedByteCount: 42
        )
        let coordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
            item.url.path: [.metadata(.init(type: .regularFile, size: 43, status: .current))],
        ])
        let downloader = StubFileProviderDownloader()
        let service = SystemFileProviderArchiveService(
            promisedMetadataCoordinator: coordinator,
            downloader: downloader
        )

        do {
            _ = try await service.currentLocality(root: root, expectedItems: [item])
            XCTFail("same-path size growth must fail before locality is trusted")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .expectedFileSizeMismatch(item.url, expected: 42, actual: 43))
        }
        XCTAssertTrue(downloader.requestedURLs.isEmpty)
    }

    func testCurrentLocalityRejectsRegularFileReplacedByDirectoryWithoutDownload() async throws {
        let item = FileProviderExpectedItem(
            url: root.appendingPathComponent("Song.cpr"),
            expectedType: .regularFile,
            expectedByteCount: 42
        )
        let coordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
            item.url.path: [.metadata(.init(type: .directory, size: nil, status: .current))],
        ])
        let downloader = StubFileProviderDownloader()
        let service = SystemFileProviderArchiveService(
            promisedMetadataCoordinator: coordinator,
            downloader: downloader
        )

        do {
            _ = try await service.currentLocality(root: root, expectedItems: [item])
            XCTFail("file-to-directory replacement must fail before locality is trusted")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .expectedItemMismatch)
        }
        XCTAssertTrue(downloader.requestedURLs.isEmpty)
    }

    func testMaterializePreflightsAllItemsBeforeLaterSizeDriftWithoutAnyDownload() async throws {
        let first = FileProviderExpectedItem(
            url: root.appendingPathComponent("First.cpr"),
            expectedType: .regularFile,
            expectedByteCount: 42
        )
        let later = FileProviderExpectedItem(
            url: root.appendingPathComponent("Later.wav"),
            expectedType: .regularFile,
            expectedByteCount: 84
        )
        let preflightCoordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
            first.url.path: [.metadata(.init(type: .regularFile, size: 42, status: .downloaded))],
            later.url.path: [.metadata(.init(type: .regularFile, size: 85, status: .current))],
        ])
        let preflightDownloader = StubFileProviderDownloader()
        let preflightService = SystemFileProviderArchiveService(
            promisedMetadataCoordinator: preflightCoordinator,
            downloader: preflightDownloader
        )

        await XCTAssertThrowsErrorAsync(
            try await preflightService.materialize(root: root, expectedItems: [first, later]),
            equals: FileProviderArchiveStorageError.expectedFileSizeMismatch(later.url, expected: 84, actual: 85)
        )
        XCTAssertTrue(preflightDownloader.requestedURLs.isEmpty)

        let pollingCoordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
            first.url.path: [
                .metadata(.init(type: .regularFile, size: 42, status: .downloaded)),
                .metadata(.init(type: .regularFile, size: 43, status: .current)),
            ],
        ])
        let pollingDownloader = StubFileProviderDownloader()
        let pollingService = SystemFileProviderArchiveService(
            pollPolicy: .init(
                timeout: .seconds(1),
                initialBackoff: .milliseconds(1),
                maximumBackoff: .milliseconds(1),
                maximumReadinessProbes: 2
            ),
            promisedMetadataCoordinator: pollingCoordinator,
            downloader: pollingDownloader
        )
        await XCTAssertThrowsErrorAsync(
            try await pollingService.materialize(root: root, expectedItems: [first]),
            equals: FileProviderArchiveStorageError.expectedFileSizeMismatch(first.url, expected: 42, actual: 43)
        )
        XCTAssertEqual(pollingDownloader.requestedURLs, [first.url])
    }

    func testMaterializePreflightsAllItemsBeforeLaterTypeDriftWithoutAnyDownload() async throws {
        let first = FileProviderExpectedItem(
            url: root.appendingPathComponent("First.cpr"),
            expectedType: .regularFile,
            expectedByteCount: 42
        )
        let later = FileProviderExpectedItem(
            url: root.appendingPathComponent("Later.wav"),
            expectedType: .regularFile,
            expectedByteCount: 84
        )
        let preflightCoordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
            first.url.path: [.metadata(.init(type: .regularFile, size: 42, status: .notDownloaded))],
            later.url.path: [.metadata(.init(type: .directory, size: nil, status: .current))],
        ])
        let preflightDownloader = StubFileProviderDownloader()
        let preflightService = SystemFileProviderArchiveService(
            promisedMetadataCoordinator: preflightCoordinator,
            downloader: preflightDownloader
        )

        await XCTAssertThrowsErrorAsync(
            try await preflightService.materialize(root: root, expectedItems: [first, later]),
            equals: FileProviderArchiveStorageError.expectedItemMismatch
        )
        XCTAssertTrue(preflightDownloader.requestedURLs.isEmpty)

        let pollingCoordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
            first.url.path: [
                .metadata(.init(type: .regularFile, size: 42, status: .notDownloaded)),
                .metadata(.init(type: .directory, size: nil, status: .current)),
            ],
        ])
        let pollingDownloader = StubFileProviderDownloader()
        let pollingService = SystemFileProviderArchiveService(
            pollPolicy: .init(
                timeout: .seconds(1),
                initialBackoff: .milliseconds(1),
                maximumBackoff: .milliseconds(1),
                maximumReadinessProbes: 2
            ),
            promisedMetadataCoordinator: pollingCoordinator,
            downloader: pollingDownloader
        )
        await XCTAssertThrowsErrorAsync(
            try await pollingService.materialize(root: root, expectedItems: [first]),
            equals: FileProviderArchiveStorageError.expectedItemMismatch
        )
        XCTAssertEqual(pollingDownloader.requestedURLs, [first.url])
    }

    func testPromisedMissingNilNegativeUnknownAndErrorFailClosedWithoutDownload() async throws {
        let item = FileProviderExpectedItem(
            url: root.appendingPathComponent("Song.cpr"),
            expectedType: .regularFile,
            expectedByteCount: 42
        )
        let cases: [SequencedPromisedMetadataCoordinator.Outcome] = [
            .failure(.lookupUnavailable),
            .metadata(.init(type: nil, size: 42, status: .current)),
            .metadata(.init(type: .regularFile, size: nil, status: .current)),
            .metadata(.init(type: .regularFile, size: -1, status: .current)),
            .metadata(.init(type: .regularFile, size: 42, status: .unknown)),
        ]

        for outcome in cases {
            let coordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
                item.url.path: [outcome],
            ])
            let downloader = StubFileProviderDownloader()
            let service = SystemFileProviderArchiveService(
                promisedMetadataCoordinator: coordinator,
                downloader: downloader
            )
            do {
                _ = try await service.currentLocality(root: root, expectedItems: [item])
                XCTFail("invalid promised metadata must fail closed: \(outcome)")
            } catch {}
            XCTAssertTrue(downloader.requestedURLs.isEmpty)
        }

        let pollingDriftCases: [(String, SequencedPromisedMetadataCoordinator.Outcome)] = [
            ("type", .metadata(.init(type: .directory, size: nil, status: .current))),
            ("size", .metadata(.init(type: .regularFile, size: 43, status: .current))),
            ("status", .metadata(.init(type: .regularFile, size: 42, status: .unknown))),
            ("error", .failure(.lookupUnavailable)),
        ]

        for (label, pollingOutcome) in pollingDriftCases {
            let pollingCoordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
                item.url.path: [
                    .metadata(.init(type: .regularFile, size: 42, status: .downloaded)),
                    pollingOutcome,
                ],
            ])
            let pollingDownloader = StubFileProviderDownloader()
            let pollingService = SystemFileProviderArchiveService(
                pollPolicy: .init(
                    timeout: .seconds(1),
                    initialBackoff: .milliseconds(1),
                    maximumBackoff: .milliseconds(1),
                    maximumReadinessProbes: 2
                ),
                promisedMetadataCoordinator: pollingCoordinator,
                downloader: pollingDownloader
            )
            do {
                try await pollingService.materialize(root: root, expectedItems: [item])
                XCTFail("polling \(label) drift must fail closed")
            } catch {}
            XCTAssertEqual(
                pollingDownloader.requestedURLs,
                [item.url],
                "polling \(label) drift must not request any extra or unexpected URL"
            )
        }
    }

    func testSystemManifestMaterializationStartsOnlyExpectedFilesAndNeverRootOrUnexpected() async throws {
        let expected = [
            FileProviderExpectedItem(
                url: root.appendingPathComponent("Expected/Song.cpr"),
                expectedType: .regularFile,
                expectedByteCount: 42
            ),
            FileProviderExpectedItem(
                url: root.appendingPathComponent("Expected/Audio/take.wav"),
                expectedType: .regularFile,
                expectedByteCount: 84
            ),
        ]
        let unexpected = root.appendingPathComponent("Unexpected/online-only.wav")
        let coordinator = SequencedPromisedMetadataCoordinator(outcomesByPath: [
            expected[0].url.path: [
                .metadata(.init(type: .regularFile, size: 42, status: .downloaded)),
                .metadata(.init(type: .regularFile, size: 42, status: .current)),
            ],
            expected[1].url.path: [
                .metadata(.init(type: .regularFile, size: 84, status: .notDownloaded)),
                .metadata(.init(type: .regularFile, size: 84, status: .current)),
            ],
        ])
        let downloader = StubFileProviderDownloader()
        let service = SystemFileProviderArchiveService(
            pollPolicy: .init(
                timeout: .seconds(1),
                initialBackoff: .milliseconds(1),
                maximumBackoff: .milliseconds(1),
                maximumReadinessProbes: 1
            ),
            promisedMetadataCoordinator: coordinator,
            downloader: downloader
        )

        try await service.materialize(root: root, expectedItems: expected)

        XCTAssertEqual(downloader.requestedURLs, expected.map(\.url))
        XCTAssertFalse(downloader.requestedURLs.contains(root))
        XCTAssertFalse(downloader.requestedURLs.contains(unexpected))
        XCTAssertEqual(
            coordinator.requests.map(\.url),
            expected.map(\.url) + expected.map(\.url),
            "materialization must validate every expected item before download and again while polling"
        )
        XCTAssertTrue(coordinator.requests.allSatisfy {
            $0.options.contains(.immediatelyAvailableMetadataOnly)
        })
    }

    private func assertSystemLocalityRequiresMaterialization(
        for status: FileProviderPromisedItemStatus
    ) async throws {
        let expected = root.appendingPathComponent("A.cpr")
        let coordinator = StubFileProviderMetadataCoordinator(
            metadataByPath: [
                expected.path: .init(type: .regularFile, size: 42, status: status),
            ]
        )
        let service = SystemFileProviderArchiveService(promisedMetadataCoordinator: coordinator)

        let locality = try await service.currentLocality(
            root: root,
            expectedItems: [
                .init(url: expected, expectedType: .regularFile, expectedByteCount: 42),
            ]
        )

        XCTAssertEqual(locality, .materializationRequired)
        XCTAssertEqual(coordinator.requests.map(\.url), [expected])
        XCTAssertTrue(coordinator.requests.allSatisfy {
            $0.options.contains(.immediatelyAvailableMetadataOnly)
        })
    }

    private func assertSystemLocalityFailsClosed(
        for metadata: FileProviderPromisedItemMetadata
    ) async throws {
        let expected = root.appendingPathComponent("A.cpr")
        let coordinator = StubFileProviderMetadataCoordinator(
            metadataByPath: [expected.path: metadata]
        )
        let service = SystemFileProviderArchiveService(promisedMetadataCoordinator: coordinator)

        do {
            _ = try await service.currentLocality(
                root: root,
                expectedItems: [
                    .init(url: expected, expectedType: .regularFile, expectedByteCount: 42),
                ]
            )
            XCTFail("invalid promised metadata must fail closed")
        } catch {
            XCTAssertNotNil(error as? FileProviderArchiveStorageError)
        }
        XCTAssertEqual(coordinator.requests.map(\.url), [expected])
        XCTAssertTrue(coordinator.requests.allSatisfy {
            $0.options.contains(.immediatelyAvailableMetadataOnly)
        })
    }

    func testDurabilityRequiresSuccessfulProviderBarrier() async throws {
        let service = StubFileProviderArchiveService()
        let storage = FileProviderArchiveStorage(root: root, service: service)

        let durability = try await storage.waitUntilDurable(root)
        let durabilityRoots = await service.durabilityRoots
        XCTAssertEqual(durability, .syncedToProvider)
        XCTAssertEqual(durabilityRoots, [root.standardizedFileURL])
    }

    func testAmbiguousDurabilityNeverClaimsProviderSync() async {
        let storage = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService(.durabilityUnavailable)
        )

        do {
            _ = try await storage.waitUntilDurable(root)
            XCTFail("ambiguous durability must fail closed")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .durabilityUnavailable)
        }
    }

    func testManifestBoundMaterializationRequestsOnlyExpectedFilesAndFailureIsVisible() async throws {
        let service = StubFileProviderArchiveService()
        let storage = FileProviderArchiveStorage(root: root, service: service)
        let manifest = VaultManifest(entries: [
            .init(
                relativePath: "Expected/Song.cpr",
                type: .regularFile,
                byteCount: 42,
                modifiedAt: .distantPast,
                sha256: "fixture"
            ),
        ])
        try await storage.materialize(root, manifest: manifest)
        let materializationRequests = await service.materializationRequests
        XCTAssertEqual(materializationRequests.count, 1)
        XCTAssertEqual(materializationRequests.first?.root, root.standardizedFileURL)
        XCTAssertEqual(
            materializationRequests.first?.expectedFiles,
            [root.appendingPathComponent("Expected/Song.cpr").standardizedFileURL]
        )
        XCTAssertFalse(
            materializationRequests.first?.expectedFiles.contains(
                root.appendingPathComponent("Unexpected/online-only.wav")
            ) ?? true,
            "an unexpected provider placeholder must never be requested"
        )

        let unavailable = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService(.materializationUnavailable)
        )
        do {
            try await unavailable.materialize(root, manifest: manifest)
            XCTFail("failed materialization must remain a restore failure")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .materializationUnavailable)
        }
    }

    func testEvictionFailureClearlyDegradesToUnsupported() async throws {
        let service = StubFileProviderArchiveService(.evictionUnavailable)
        let storage = FileProviderArchiveStorage(root: root, service: service)

        let result = try await storage.evictIfSupported(root)
        let evictedRoots = await service.evictedRoots
        XCTAssertEqual(result, .unsupported)
        XCTAssertEqual(evictedRoots, [root.standardizedFileURL])
    }

    func testSuccessfulEvictionReportsEvicted() async throws {
        let storage = FileProviderArchiveStorage(
            root: root,
            service: StubFileProviderArchiveService()
        )
        let result = try await storage.evictIfSupported(root)
        XCTAssertEqual(result, .evicted)
    }

    func testReadinessPollingUsesBoundedExponentialBackoff() async throws {
        let probe = PollOutcomeProbe(outcomes: [false, false, false, true])
        let sleeper = PollDelayRecorder()
        let policy = FileProviderPollPolicy(
            timeout: .seconds(10),
            initialBackoff: .milliseconds(250),
            maximumBackoff: .seconds(5),
            maximumReadinessProbes: 8
        )

        try await FileProviderReadinessPoller.pollUntilReady(
            policy: policy,
            probe: { _ in await probe.next() },
            sleep: { delay in await sleeper.record(delay) }
        )

        let probeCount = await probe.count
        let recordedDelays = await sleeper.delays
        XCTAssertEqual(probeCount, 4)
        XCTAssertEqual(recordedDelays, [.milliseconds(250), .milliseconds(500), .seconds(1)])
    }

    func testReadinessPollingFailsClosedAtProbeCapWithoutTightLooping() async {
        let probe = PollOutcomeProbe(outcomes: [])
        let policy = FileProviderPollPolicy(
            timeout: .seconds(10),
            initialBackoff: .milliseconds(1),
            maximumBackoff: .milliseconds(4),
            maximumReadinessProbes: 3
        )

        do {
            try await FileProviderReadinessPoller.pollUntilReady(
                policy: policy,
                probe: { _ in await probe.next() },
                sleep: { _ in }
            )
            XCTFail("pending provider state must not loop forever")
        } catch {
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .operationTimedOut)
        }
        let probeCount = await probe.count
        XCTAssertEqual(probeCount, 3)
    }

    func testProviderEnumerationStopsWhenTheOperationCanNoLongerContinue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<3 {
            try Data("fixture".utf8).write(to: root.appendingPathComponent("\(index).cpr"))
        }

        var continuationChecks = 0
        var visits = 0
        XCTAssertThrowsError(
            try SystemFileProviderArchiveService.forEachItem(
                fileManager: .default,
                at: root,
                keys: [.isRegularFileKey],
                shouldContinue: {
                    continuationChecks += 1
                    if continuationChecks >= 3 { throw FileProviderArchiveStorageError.operationTimedOut }
                }
            ) { _ in
                visits += 1
            }
        ) { error in
            XCTAssertEqual(error as? FileProviderArchiveStorageError, .operationTimedOut)
        }
        XCTAssertLessThan(visits, 3)
    }

    func testProviderDurabilityEnumerationIgnoresOnlyExactDSStoreMetadataFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("root metadata".utf8).write(to: root.appendingPathComponent(".DS_Store"))
        try Data("nested metadata".utf8).write(to: nested.appendingPathComponent(".DS_Store"))
        try Data("keep exact-prefix".utf8).write(to: root.appendingPathComponent(".DS_Store.keep"))
        try Data("keep exact-suffix".utf8).write(to: nested.appendingPathComponent("song.DS_Store"))
        try Data("project".utf8).write(to: nested.appendingPathComponent("Song.cpr"))
        var regularFileNames: [String] = []

        try SystemFileProviderArchiveService.forEachItem(
            fileManager: .default,
            at: root,
            keys: [.isRegularFileKey]
        ) { url in
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                regularFileNames.append(url.lastPathComponent)
            }
        }

        XCTAssertFalse(regularFileNames.contains(".DS_Store"))
        XCTAssertTrue(regularFileNames.contains(".DS_Store.keep"))
        XCTAssertTrue(regularFileNames.contains("song.DS_Store"))
        XCTAssertTrue(regularFileNames.contains("Song.cpr"))
    }

    func testSystemProviderEnumerationFailsClosedOnUnreadableSubtree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let blocked = root.appendingPathComponent("blocked", isDirectory: true)
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("hidden".utf8).write(to: blocked.appendingPathComponent("hidden.cpr"))
        defer {
            chmod(blocked.path, S_IRWXU)
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertEqual(chmod(blocked.path, 0), 0)

        XCTAssertThrowsError(
            try SystemFileProviderArchiveService.forEachItem(
                fileManager: .default,
                at: root,
                keys: [.isRegularFileKey]
            ) { _ in }
        )
    }
}

private final class StubFileProviderMetadataCoordinator: FileProviderPromisedMetadataCoordinating, @unchecked Sendable {
    struct Request {
        let url: URL
        let options: NSFileCoordinator.ReadingOptions
    }

    private let lock = NSLock()
    private let metadataByPath: [String: FileProviderPromisedItemMetadata]
    private let failingPaths: Set<String>
    private var storedRequests: [Request] = []

    init(
        metadataByPath: [String: FileProviderPromisedItemMetadata],
        failingPaths: Set<String> = []
    ) {
        self.metadataByPath = metadataByPath
        self.failingPaths = failingPaths
    }

    var requests: [Request] { lock.withLock { storedRequests } }

    func metadata(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions
    ) throws -> FileProviderPromisedItemMetadata {
        lock.withLock { storedRequests.append(.init(url: url, options: options)) }
        if failingPaths.contains(url.path) {
            throw FileProviderArchiveStorageError.lookupUnavailable
        }
        return metadataByPath[url.path] ?? .init(type: nil, size: nil, status: .unknown)
    }
}

private final class StubFileProviderDownloader: FileProviderDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequestedURLs: [URL] = []

    var requestedURLs: [URL] { lock.withLock { storedRequestedURLs } }

    func startDownloading(at url: URL) throws {
        lock.withLock { storedRequestedURLs.append(url) }
    }
}

private final class StubPromisedItemSDK: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [URLResourceKey: Any]
    private var storedReachabilityURLs: [URL] = []
    private var storedRequestedKeys: [URLResourceKey] = []

    init(values: [URLResourceKey: Any]) {
        self.values = values
    }

    var reachabilityURLs: [URL] { lock.withLock { storedReachabilityURLs } }
    var requestedKeys: [URLResourceKey] { lock.withLock { storedRequestedKeys } }

    func checkReachable(_ url: URL) throws {
        lock.withLock { storedReachabilityURLs.append(url) }
    }

    func resourceValue(_ url: URL, _ key: URLResourceKey) throws -> Any? {
        lock.withLock { storedRequestedKeys.append(key) }
        return values[key]
    }
}

private final class SequencedPromisedMetadataCoordinator: FileProviderPromisedMetadataCoordinating, @unchecked Sendable {
    enum Outcome: Sendable, CustomStringConvertible {
        case metadata(FileProviderPromisedItemMetadata)
        case failure(FileProviderArchiveStorageError)

        var description: String {
            switch self {
            case .metadata(let metadata): "metadata(\(metadata))"
            case .failure(let error): "failure(\(error))"
            }
        }
    }

    struct Request {
        let url: URL
        let options: NSFileCoordinator.ReadingOptions
    }

    private let lock = NSLock()
    private var outcomesByPath: [String: [Outcome]]
    private var storedRequests: [Request] = []

    init(outcomesByPath: [String: [Outcome]]) {
        self.outcomesByPath = outcomesByPath
    }

    var requests: [Request] { lock.withLock { storedRequests } }

    func metadata(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions
    ) throws -> FileProviderPromisedItemMetadata {
        try lock.withLock {
            storedRequests.append(.init(url: url, options: options))
            guard var outcomes = outcomesByPath[url.path], !outcomes.isEmpty else {
                throw FileProviderArchiveStorageError.lookupUnavailable
            }
            let outcome = outcomes.count == 1 ? outcomes[0] : outcomes.removeFirst()
            outcomesByPath[url.path] = outcomes
            switch outcome {
            case .metadata(let metadata): return metadata
            case .failure(let error): throw error
            }
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    equals expected: FileProviderArchiveStorageError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? FileProviderArchiveStorageError, expected, file: file, line: line)
    }
}

private actor PollOutcomeProbe {
    private var outcomes: [Bool]
    private(set) var count = 0

    init(outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func next() -> Bool {
        count += 1
        return outcomes.isEmpty ? false : outcomes.removeFirst()
    }
}

private actor PollDelayRecorder {
    private(set) var delays: [Duration] = []

    func record(_ delay: Duration) {
        delays.append(delay)
    }
}
