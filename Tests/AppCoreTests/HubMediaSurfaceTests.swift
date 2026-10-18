@testable import AppCore
import AppKit
import SwiftUI
import XCTest

@MainActor
final class HubMediaSurfaceTests: XCTestCase {
    func testWaveformFixtureViewsHostWithoutCrash() throws {
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

    func testPlayedBarCountMatchesProgress() {
        func litBars(_ progress: Double) -> Int {
            (0..<16).filter { HubWaveformSurface.isBarPlayed(index: $0, count: 16, progress: progress) }.count
        }

        XCTAssertEqual(litBars(0), 0)
        XCTAssertEqual(litBars(0.0625), 1)
        XCTAssertEqual(litBars(0.5), 8)
        XCTAssertEqual(litBars(1.0), 16)
        XCTAssertEqual(litBars(.nan), 0)
        XCTAssertEqual(litBars(-1), 0)
    }

    func testMediaSurfaceSourceExposesRequiredStates() throws {
        let source = try String(
            contentsOfFile: "Sources/AppCore/Components/HubMediaSurfaces.swift",
            encoding: .utf8
        )

        [
            "public struct HubWaveformSurface",
            "HubWaveformSurfaceVariant",
            "rowStrip",
            "isEnabled",
            "onSeek",
            "HubMediaSurfaceFixtures",
            "archivePreviewPeaks",
            "meterPeaks",
        ].forEach { required in
            XCTAssertTrue(source.contains(required), "Missing media surface source: \(required)")
        }

        XCTAssertFalse(
            source.contains("DragGesture"),
            "Waveform is display-only; seek is the persistent Preview position slider."
        )
        XCTAssertFalse(
            source.contains("accessibilityAdjustableAction"),
            "VoiceOver seek is the persistent player slider, not the waveform."
        )
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
