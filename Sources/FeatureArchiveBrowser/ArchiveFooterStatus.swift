import Foundation

/// What the archive footer shows: at most one message and one warning.
///
/// A Project Vault message holds the footer until the next action message;
/// background messages never replace it. A new warning replaces the old one.
/// `text` is the message, then the warning, separated by one space.
struct ArchiveFooterStatus: Equatable {
    enum Source: Equatable {
        /// The result of something the person did. Always replaces the message
        /// and releases a Project Vault hold.
        case action
        /// Scan progress and results. Never replaces a Project Vault message.
        case background
        /// A Project Vault operation. Holds the footer until the next action message.
        case projectVault
    }

    struct Warning: Equatable {
        /// The family a warning belongs to, so code that resolves a condition
        /// clears only its own warning without reading the sentence.
        enum Kind: Equatable {
            case settings
            case rootAccess
            case projectVaultRead
            /// Unreadable or blocked song details; a repair replaces it.
            case songDetails
            /// Cleared only when another warning replaces it or the roots change.
            case other
        }

        let kind: Kind
        let text: String

        init(kind: Kind, text: String) {
            self.kind = kind
            self.text = text
        }

        /// A warning without a clear rule of its own. Song-details sentences
        /// reach the footer from many paths (scan, cache load, edits,
        /// collaborators), so they are recognized here by the copy that writes
        /// them and a repair can still replace them.
        init(_ text: String) {
            self.init(
                kind: SongMetadataIntegrityCopy.isIntegrityWarning(text) ? .songDetails : .other,
                text: text
            )
        }
    }

    private(set) var message: String?
    private(set) var warning: Warning?
    private var projectVaultHoldsMessage = false

    var text: String? {
        guard let warning else { return message }
        guard let message, !message.isEmpty else { return warning.text }
        return "\(message) \(warning.text)"
    }

    mutating func show(_ message: String?, from source: Source) {
        switch source {
        case .action:
            projectVaultHoldsMessage = false
        case .background:
            guard !projectVaultHoldsMessage else { return }
        case .projectVault:
            projectVaultHoldsMessage = true
        }
        self.message = message
    }

    mutating func raise(_ warning: Warning) {
        self.warning = warning
    }

    /// Clears the warning only when it is of this kind.
    mutating func resolve(_ kind: Warning.Kind) {
        guard warning?.kind == kind else { return }
        warning = nil
    }

    /// Clears any warning (root change).
    mutating func clearWarning() {
        warning = nil
    }

    /// Clears the message only while it is still exactly `message`; the
    /// Project Vault keeps the hold, as if it had cleared the message itself.
    mutating func withdraw(_ message: String) {
        guard self.message == message else { return }
        show(nil, from: .projectVault)
    }
}

// MARK: - Warnings with a clear rule

/// Each family that is cleared when its condition resolves writes its sentence
/// here, next to its kind.
extension ArchiveFooterStatus.Warning {
    static func rootAccess(rootName: String) -> Self {
        Self(kind: .rootAccess, text: "Archive root access could not be restored: \(rootName).")
    }

    static func settingsLoadFailed(_ error: any Error) -> Self {
        Self(kind: .settings, text: "Archive settings could not be loaded: \(error.localizedDescription)")
    }

    /// Settings that no longer decode get the write guard's sentence, as the
    /// archive's other refused writes do.
    static func settingsSaveFailed(_ error: any Error) -> Self {
        Self(
            kind: .settings,
            text: error is DecodingError
                ? ArchiveWriteGuardError.settingsUnreadable.localizedDescription
                : "Archive settings could not be saved: \(error.localizedDescription)"
        )
    }

    /// A refused archive write; unreadable settings clear with a settings repair.
    static func archiveWriteRefused(_ error: any Error) -> Self {
        if error as? ArchiveWriteGuardError == .settingsUnreadable {
            return Self(kind: .settings, text: error.localizedDescription)
        }
        return Self(error.localizedDescription)
    }

    static func projectVaultUnreadable(recordsOnly: Bool) -> Self {
        Self(
            kind: .projectVaultRead,
            text: recordsOnly
                ? "Some Project Vault records couldn't be read. They were left as they are."
                : "Project Vault status couldn't be read. Nothing was changed."
        )
    }
}
