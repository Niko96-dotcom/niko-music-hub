// Times a full read-only scan of one archive root with 1, 2, 4 and 8 folder workers, interleaved,
// and prints the median per worker count plus the limit the scanner picks for that volume.
// The scanner only reads; nothing is written to the archive. Use it on the real archive disk to
// check `ScanWorkerBudget.volumeLimit` (for example a spinning external disk).
//   script/benchmark_scan_workers.sh <archive-root> [--runs N]
import Foundation
@testable import NikoMusicCore

@main
struct ScanWorkers {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            print("usage: benchmark_scan_workers.sh <archive-root> [--runs N]")
            exit(64)
        }
        let root = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
        let runs = arguments.firstIndex(of: "--runs").map { Int(arguments[$0 + 1]) ?? 3 } ?? 3
        let workerCounts = [1, 2, 4, 8]
        print("root \(root.path)")
        print("volume limit \(ScanWorkerBudget.volumeLimit(for: root)) (interactive budget \(ScanWorkerBudget.interactive.maximumWorkers), background \(ScanWorkerBudget.background.maximumWorkers))")
        var samples: [Int: [Double]] = [:]
        var songs = 0
        // Warm-up so the first measured run does not pay for a cold metadata cache alone.
        songs = try scan(root, workers: 8).songs.count
        print("songs \(songs)")
        for run in 1...runs {
            for workers in (run % 2 == 0 ? workerCounts.reversed() : workerCounts) {
                let start = ContinuousClock.now
                _ = try scan(root, workers: workers)
                let elapsed = start.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                samples[workers, default: []].append(seconds)
                print(String(format: "run %d workers %d: %.2f s", run, workers, seconds))
            }
        }
        for workers in workerCounts {
            let sorted = samples[workers, default: []].sorted()
            let median = sorted[sorted.count / 2]
            print(String(format: "median workers %d: %.2f s (min %.2f, max %.2f)", workers, median, sorted.first!, sorted.last!))
        }
    }

    static func scan(_ root: URL, workers: Int) throws -> ScanResult {
        var scanner = MusicArchiveScanner()
        scanner.workerLimitOverride = workers
        return try scanner.scan(roots: [root])
    }
}
