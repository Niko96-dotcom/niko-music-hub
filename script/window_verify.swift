#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO

struct Options {
    var appName = "NikoMusicHub"
    var binaryPath: String?
    var windowTitle = "Niko Music Hub"
    var minWidth = 400
    var minHeight = 300
    var checkVisible = false
    var capturePath: String?
    var blankCheck = false
}

func usage() {
    fputs(
        """
        usage: window_verify.swift [options]
          --app-name NAME           process name for pgrep (default: NikoMusicHub)
          --binary-path PATH        verify ps command starts with PATH
          --window-title TITLE      required window name match (default: Niko Music Hub)
          --min-width N             minimum window width (default: 400)
          --min-height N            minimum window height (default: 300)
          --check-visible           exit 0 if matching window exists, else 1
          --capture PATH            write PNG of matched window; exit 1 if not found
          --blank-check             with --capture: fail if PNG missing or smaller than min size

        Exit codes:
          0 success
          1 window not found / capture failed / blank-check failed / binary mismatch
          2 AX/Quartz window APIs unavailable
          3 binary path mismatch (--binary-path only)

        """,
        stderr
    )
}

func parseOptions(_ args: [String]) throws -> Options {
    var options = Options()
    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--app-name":
            index += 1
            guard index < args.count else { throw ValidationError("missing value for --app-name") }
            options.appName = args[index]
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
            options.checkVisible = true
        case "--capture":
            index += 1
            guard index < args.count else { throw ValidationError("missing value for --capture") }
            options.capturePath = args[index]
        case "--blank-check":
            options.blankCheck = true
        case "-h", "--help":
            usage()
            exit(0)
        default:
            throw ValidationError("unknown argument: \(arg)")
        }
        index += 1
    }
    if !options.checkVisible && options.capturePath == nil {
        throw ValidationError("one of --check-visible or --capture is required")
    }
    return options
}

struct ValidationError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
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

func processCommand(pid: pid_t) -> String? {
    let result = runCommand("/bin/ps", ["-p", String(pid), "-o", "command="])
    guard result.status == 0 else { return nil }
    return result.output
}

func windowList() -> [[String: Any]]? {
    guard let raw = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    return raw
}

func bounds(from window: [String: Any]) -> (width: Double, height: Double)? {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else { return nil }
    guard let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double else {
        return nil
    }
    return (width, height)
}

func windowName(from window: [String: Any]) -> String {
    window[kCGWindowName as String] as? String ?? ""
}

func ownerPID(from window: [String: Any]) -> pid_t? {
    if let pid = window[kCGWindowOwnerPID as String] as? Int32 {
        return pid
    }
    if let pid = window[kCGWindowOwnerPID as String] as? Int {
        return pid_t(pid)
    }
    return nil
}

func windowNumber(from window: [String: Any]) -> CGWindowID? {
    if let number = window[kCGWindowNumber as String] as? Int {
        return CGWindowID(number)
    }
    if let number = window[kCGWindowNumber as String] as? UInt32 {
        return number
    }
    return nil
}

func findMatchingWindow(
    pid: pid_t,
    options: Options
) -> (windowID: CGWindowID, width: Double, height: Double)? {
    guard let windows = windowList() else { return nil }
    for window in windows {
        guard ownerPID(from: window) == pid else { continue }
        guard windowName(from: window) == options.windowTitle else { continue }
        guard let size = bounds(from: window) else { continue }
        guard size.width >= Double(options.minWidth), size.height >= Double(options.minHeight) else {
            continue
        }
        guard let windowID = windowNumber(from: window) else { continue }
        return (windowID, size.width, size.height)
    }
    return nil
}

func captureWindow(windowID: CGWindowID, to path: String) -> Bool {
    let result = runCommand("/usr/sbin/screencapture", ["-l", String(windowID), "-x", path])
    guard result.status == 0 else { return false }
    return FileManager.default.fileExists(atPath: path)
}

func imageDimensions(at path: String) -> (width: Int, height: Int)? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
        return nil
    }
    return (width, height)
}

func blankCheckPassed(path: String, options: Options) -> Bool {
    guard let dimensions = imageDimensions(at: path) else { return false }
    return dimensions.width >= options.minWidth && dimensions.height >= options.minHeight
}

do {
    let options = try parseOptions(CommandLine.arguments)

    guard windowList() != nil else {
        fputs("AX/window check unavailable: CGWindowListCopyWindowInfo failed\n", stderr)
        exit(2)
    }

    guard let pid = newestPID(for: options.appName) else {
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

    guard let match = findMatchingWindow(pid: pid, options: options) else {
        fputs(
            "matching window not found for pid \(pid) title=\(options.windowTitle) min=\(options.minWidth)x\(options.minHeight)\n",
            stderr
        )
        exit(1)
    }

    if options.checkVisible {
        print("visible window ok: pid=\(pid) \(Int(match.width))x\(Int(match.height))")
        exit(0)
    }

    if let capturePath = options.capturePath {
        guard captureWindow(windowID: match.windowID, to: capturePath) else {
            fputs("screencapture failed for window \(match.windowID)\n", stderr)
            exit(1)
        }
        if options.blankCheck, !blankCheckPassed(path: capturePath, options: options) {
            fputs("blank-check failed: \(capturePath) missing or below minimum size\n", stderr)
            exit(1)
        }
        print(capturePath)
        exit(0)
    }

    exit(0)
} catch let error as ValidationError {
    fputs("\(error.message)\n", stderr)
    usage()
    exit(2)
} catch {
    fputs("\(error)\n", stderr)
    exit(2)
}
