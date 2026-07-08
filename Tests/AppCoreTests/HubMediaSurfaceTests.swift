import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubMediaSurfaceTests: XCTestCase {
    func testTransportAndWaveformFixtureViewsHostWithoutCrash() throws {
        XCTAssertNoThrow(try hostMediaView(
            HubTransportBar(
                style: .full,
                title: "Lab Song v3 mix.wav",
                subtitle: "Main preview",
                isPlaying: true,
                currentTime: 42,
                duration: 180,
                markerProgress: 0.33,
                volumeLevel: 0.8,
                showsSkipControls: true,
                onPlayPause: {},
                onSeekBackward: {},
                onSeekForward: {},
                onSeek: { _ in }
            ),
            size: CGSize(width: 360, height: 96)
        ))

        XCTAssertNoThrow(try hostMediaView(
            HubTransportBar(
                style: .compact,
                title: "No preview",
                isPlaying: false,
                currentTime: 0,
                duration: 0,
                isEnabled: false,
                showsSurface: false,
                onPlayPause: {},
                onSeek: { _ in }
            ),
            size: CGSize(width: 220, height: 40)
        ))

        XCTAssertNoThrow(try hostMediaView(
            HubWaveformSurface(
                peaks: HubMediaSurfaceFixtures.archivePreviewPeaks,
                progress: 0.4,
                variant: .archivePreview,
                onSeek: { _ in }
            ),
            size: CGSize(width: 360, height: 92)
        ))

        XCTAssertNoThrow(try hostMediaView(
            HubWaveformSurface(
                peaks: HubMediaSurfaceFixtures.meterPeaks,
                progress: 0.7,
                variant: .meter
            ),
            size: CGSize(width: 240, height: 64)
        ))

        XCTAssertNoThrow(try hostMediaView(
            HubWaveformSurface(peaks: [], variant: .empty, isEnabled: false),
            size: CGSize(width: 240, height: 72)
        ))

        // Row strip must stay thin and unboxed — this is the surface that replaced the
        // delayed 72pt carded "ugly player" on archive song select.
        XCTAssertNoThrow(try hostMediaView(
            HubWaveformSurface(
                peaks: HubMediaSurfaceFixtures.archivePreviewPeaks,
                progress: 0,
                variant: .rowStrip,
                showsSurface: true,
                onSeek: { _ in }
            ),
            size: CGSize(width: 220, height: 22)
        ))
    }

    func testMediaSurfaceSourceExposesRequiredStates() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubMediaSurfaces.swift",
            encoding: .utf8
        )

        [
            "public struct HubTransportBar",
            "public struct HubWaveformSurface",
            "HubTransportBarStyle",
            "HubWaveformSurfaceVariant",
            "rowStrip",
            "isPlaying",
            "isEnabled",
            "markerProgress",
            "volumeLevel",
            "onSeek",
            "HubMediaSurfaceFixtures",
            "archivePreviewPeaks",
            "meterPeaks",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing media surface source: \(required)")
        }
    }
}

@MainActor
private func hostMediaView<V: View>(_ view: V, size: CGSize) throws {
    let controller = NSHostingController(rootView: view.frame(width: size.width, height: size.height))
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height)),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = controller.view
    controller.view.layoutSubtreeIfNeeded()
}
