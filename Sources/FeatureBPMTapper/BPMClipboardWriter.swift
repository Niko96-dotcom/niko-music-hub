import AppKit
import Foundation

public protocol BPMClipboardWriting: Sendable {
    func copyPlainNumber(_ value: String)
}

public struct PasteboardBPMClipboard: BPMClipboardWriting, @unchecked Sendable {
    public init() {}

    public func copyPlainNumber(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

public struct NoOpBPMClipboard: BPMClipboardWriting {
    public init() {}

    public func copyPlainNumber(_ value: String) {}
}
