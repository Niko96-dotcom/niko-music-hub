#!/usr/bin/env swift
import ApplicationServices
import CoreGraphics
import Foundation
enum ProbeMode {
    case checkVisible
    case capture(path: String, minBytes: Int)
    case axDump
}

struct Options {
    var appName = "NikoMusicHub"
    var pid: pid_t?
    var binaryPath: String?
    var windowTitle = "Niko Music Hub"
    var minWidth = 400
    var minHeight = 300
    var mode: ProbeMode = .checkVisible
}

func usage() {
    fputs(
        """
        usage: ui_probe.swift [options]
          --app-name NAME              process name when --pid is omitted (default: NikoMusicHub)
          --pid N                      target process (overrides --app-name; also reads NIKO_MUSIC_HUB_AX_PID)
          --binary-path PATH           require ps command to start with PATH
          --window-title TITLE         required window name (default: Niko Music Hub)
          --min-width N                minimum window width in points (default: 400)
          --min-height N               minimum window height in points (default: 300)
          --check-visible              exit 0 when a matching window exists
          --capture PATH               write PNG of matched window to PATH
          --require-nonempty-capture   with --capture: fail if file is missing or smaller than --min-capture-bytes
          --min-capture-bytes N        minimum PNG size for --require-nonempty-capture (default: 4096)
          --ax-dump                    print accessibility tree for the target pid

        Exit codes:
          0 success
          1 window/process/capture/binary mismatch failure
          2 APIs unavailable or invalid arguments
          3 binary path mismatch (--binary-path only)

        """,
        stderr
    )
}

struct ValidationError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

func parseOptions(_ args: [String]) throws -> Options {
    var options = Options()
    var minCaptureBytes = 4096
    var requireNonemptyCapture = false
    var sawMode = false

    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--app-name":
            index += 1
            guard index < args.count else { throw ValidationError("missing value for --app-name") }
            options.appName = args[index]
        case "--pid":
            index += 1
            guard index < args.count, let value = Int32(args[index]) else {
                throw ValidationError("invalid --pid")
            }
            options.pid = value
        case "--binary-path":
            index += 1
            guard index < args.count else { throw ValidationError("missing value for --binary-path") }
            options.binaryPath = args[index]
        case "--window-title":
            index += 1
            guard index < args.count else { throw ValidationError("missing value for --window-title") }
            options.windowTitle = args[index]
        case "--min-width":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                throw ValidationError("invalid --min-width")
            }
            options.minWidth = value
        case "--min-height":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                throw ValidationError("invalid --min-height")
            }
            options.minHeight = value
        case "--check-visible":
            options.mode = .checkVisible
            sawMode = true
        case "--capture":
            index += 1
            guard index < args.count else { throw ValidationError("missing value for --capture") }
            options.mode = .capture(path: args[index], minBytes: minCaptureBytes)
            sawMode = true
        case "--require-nonempty-capture":
            requireNonemptyCapture = true
        case "--min-capture-bytes":
            index += 1
            guard index < args.count, let value = Int(args[index]), value > 0 else {
                throw ValidationError("invalid --min-capture-bytes")
            }
            minCaptureBytes = value
        case "--ax-dump":
            options.mode = .axDump
            sawMode = true
        case "-h", "--help":
            usage()
            exit(0)
        default:
            throw ValidationError("unknown argument: \(arg)")
        }
        index += 1
    }

    if case .capture(let path, _) = options.mode {
        options.mode = .capture(path: path, minBytes: requireNonemptyCapture ? minCaptureBytes : 0)
    } else if requireNonemptyCapture {
        throw ValidationError("--require-nonempty-capture requires --capture")
    }

    if !sawMode {
        throw ValidationError("one of --check-visible, --capture, or --ax-dump is required")
    }
    return options
}

@discardableResult
func runCommand(_ launchPath: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (127, "")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
}

func newestPID(for appName: String) -> pid_t? {
    let result = runCommand("/usr/bin/pgrep", ["-x", appName])
    guard result.status == 0, !result.output.isEmpty else { return nil }
    let pids = result.output.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
    return pids.max()
}

func resolvePID(options: Options) -> pid_t? {
    if let pid = options.pid {
        return pid
    }
    if let envPID = ProcessInfo.processInfo.environment["NIKO_MUSIC_HUB_AX_PID"],
       let pid = pid_t(envPID)
    {
        return pid
    }
    return newestPID(for: options.appName)
}

func processCommand(pid: pid_t) -> String? {
    let result = runCommand("/bin/ps", ["-p", String(pid), "-o", "command="])
    guard result.status == 0 else { return nil }
    return result.output
}

func intValue(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
}

func doubleValue(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
}

func windowList() -> [[String: Any]]? {
    CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]
}

func bounds(from window: [String: Any]) -> (width: Double, height: Double)? {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = doubleValue(bounds["Width"]),
          let height = doubleValue(bounds["Height"])
    else {
        return nil
    }
    return (width, height)
}

func findMatchingWindow(
    pid: pid_t,
    options: Options,
    windows: [[String: Any]]
) -> (windowID: CGWindowID, width: Double, height: Double)? {
    for window in windows {
        guard intValue(window[kCGWindowOwnerPID as String]) == Int(pid) else { continue }
        let name = window[kCGWindowName as String] as? String ?? ""
        guard name == options.windowTitle else { continue }
        guard let size = bounds(from: window) else { continue }
        guard size.width >= Double(options.minWidth), size.height >= Double(options.minHeight) else {
            continue
        }
        guard let windowID = intValue(window[kCGWindowNumber as String]) else { continue }
        return (CGWindowID(windowID), size.width, size.height)
    }
    return nil
}

func captureWindow(windowID: CGWindowID, to path: String) -> Bool {
    let result = runCommand("/usr/sbin/screencapture", ["-l", String(windowID), "-x", path])
    guard result.status == 0 else { return false }
    return FileManager.default.fileExists(atPath: path)
}

func captureMeetsMinimumBytes(path: String, minBytes: Int) -> Bool {
    guard minBytes > 0 else { return true }
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? NSNumber
    else {
        return false
    }
    return size.intValue >= minBytes
}

func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success, let value else { return "" }
    return String(describing: value)
}

func axChildren(of element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard result == .success, let array = value as? [AXUIElement] else { return [] }
    return array
}

func dumpAX(_ element: AXUIElement, depth: Int) {
    guard depth <= 6 else { return }

    let role = stringAttribute(element, kAXRoleAttribute)
    let title = stringAttribute(element, kAXTitleAttribute)
    let value = stringAttribute(element, kAXValueAttribute)

    if !title.isEmpty || !value.isEmpty {
        print("\(String(repeating: "  ", count: depth))\(role) title=\(title) value=\(value)")
    }

    for child in axChildren(of: element) {
        dumpAX(child, depth: depth + 1)
    }
}

do {
    let options = try parseOptions(CommandLine.arguments)
    guard let pid = resolvePID(options: options) else {
        fputs("process not running: \(options.appName)\n", stderr)
        exit(1)
    }

    if let binaryPath = options.binaryPath {
        guard let command = processCommand(pid: pid) else {
            fputs("could not read process command for pid \(pid)\n", stderr)
            exit(1)
        }
        if !command.hasPrefix(binaryPath) {
            fputs("process command does not start with \(binaryPath)\n", stderr)
            exit(3)
        }
    }

    switch options.mode {
    case .axDump:
        dumpAX(AXUIElementCreateApplication(pid), depth: 0)
        exit(0)

    case .checkVisible, .capture:
        guard let windows = windowList() else {
            fputs("window check unavailable: CGWindowListCopyWindowInfo failed\n", stderr)
            exit(2)
        }

        guard let match = findMatchingWindow(pid: pid, options: options, windows: windows) else {
            fputs(
                "matching window not found for pid \(pid) title=\(options.windowTitle) min=\(options.minWidth)x\(options.minHeight)\n",
                stderr
            )
            exit(1)
        }

        switch options.mode {
        case .checkVisible:
            print("visible window ok: pid=\(pid) \(Int(match.width))x\(Int(match.height))")
            exit(0)
        case .capture(let path, let minBytes):
            guard captureWindow(windowID: match.windowID, to: path) else {
                fputs("screencapture failed for window \(match.windowID)\n", stderr)
                exit(1)
            }
            if !captureMeetsMinimumBytes(path: path, minBytes: minBytes) {
                fputs(
                    "capture failed: \(path) missing or smaller than \(minBytes) bytes\n",
                    stderr
                )
                exit(1)
            }
            print(path)
            exit(0)
        case .axDump:
            fatalError("unreachable")
        }
    }
} catch let error as ValidationError {
    fputs("\(error.message)\n", stderr)
    usage()
    exit(2)
} catch {
    fputs("\(error)\n", stderr)
    exit(2)
}
