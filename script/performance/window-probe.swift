import CoreGraphics
import Darwin
import Foundation

// Launch probe for a running app: milliseconds from the process's start to its first on-screen window,
// then the process's CPU use in 250 ms steps until it has been quiet for one second (or the timeout).
// Needs no Accessibility or Screen Recording permission: it reads only window owner, layer and bounds.
//
//   window-probe <pid> [timeoutSeconds]
//
// One JSON object on stdout.

guard CommandLine.arguments.count >= 2, let pid = pid_t(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-probe <pid> [timeoutSeconds]\n".utf8))
    exit(64)
}
let timeout = Double(CommandLine.arguments.dropFirst(2).first ?? "") ?? 60

func processStart(_ pid: pid_t) -> Date? {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
}

func cpuSeconds(_ pid: pid_t) -> Double? {
    var info = proc_taskinfo()
    let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
    guard size == Int32(MemoryLayout<proc_taskinfo>.size) else { return nil }
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let nanoseconds = Double(info.pti_total_user + info.pti_total_system) * Double(timebase.numer) / Double(timebase.denom)
    return nanoseconds / 1e9
}

func residentMiB(_ pid: pid_t) -> Double? {
    var info = proc_taskinfo()
    let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
    return size == Int32(MemoryLayout<proc_taskinfo>.size) ? Double(info.pti_resident_size) / 1_048_576 : nil
}

func hasWindow(_ pid: pid_t) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
    return list.contains { window in
        guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
              (window[kCGWindowLayer as String] as? Int) == 0,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double else { return false }
        return width > 300 && height > 300
    }
}

guard let started = processStart(pid) else {
    FileHandle.standardError.write(Data("no such process \(pid)\n".utf8))
    exit(1)
}
var firstWindowMilliseconds: Double?
var samples: [[String: Double]] = []
var lastCPU = cpuSeconds(pid) ?? 0
var lastTick = Date()
var quietSince: Date?
var settledMilliseconds: Double?
let deadline = Date().addingTimeInterval(timeout)
var nextSample = Date()
while Date() < deadline {
    if firstWindowMilliseconds == nil, hasWindow(pid) {
        firstWindowMilliseconds = Date().timeIntervalSince(started) * 1000
    }
    if Date() >= nextSample {
        guard let cpu = cpuSeconds(pid) else { break }
        let now = Date()
        let busy = (cpu - lastCPU) / max(0.001, now.timeIntervalSince(lastTick))
        samples.append(["t_ms": now.timeIntervalSince(started) * 1000, "cpu_cores": busy, "rss_mib": residentMiB(pid) ?? 0])
        lastCPU = cpu
        lastTick = now
        nextSample = now.addingTimeInterval(0.25)
        if firstWindowMilliseconds != nil {
            if busy < 0.15 {
                quietSince = quietSince ?? now
                if now.timeIntervalSince(quietSince!) >= 1.0 {
                    settledMilliseconds = quietSince!.timeIntervalSince(started) * 1000
                    break
                }
            } else {
                quietSince = nil
            }
        }
    }
    usleep(5_000)
}
let totalCPU = cpuSeconds(pid) ?? 0
let result: [String: Any] = [
    "first_window_ms": firstWindowMilliseconds as Any? ?? NSNull(),
    "settled_ms": settledMilliseconds as Any? ?? NSNull(),
    "process_cpu_seconds": totalCPU,
    "samples": samples,
]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
