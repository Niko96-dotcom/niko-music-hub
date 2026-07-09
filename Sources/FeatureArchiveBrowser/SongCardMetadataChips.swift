import AppCore
import NikoMusicCore
import SwiftUI

struct SongCardMetadataChip: Identifiable, Equatable {
    let id: String
    let label: String
}

enum SongCardMetadataChipBuilder {
    static func chips(for song: Song, matchSummary: String?) -> [SongCardMetadataChip] {
        var chips: [SongCardMetadataChip] = []

        if let matchSummary, !matchSummary.isEmpty {
            chips.append(SongCardMetadataChip(id: "match", label: matchSummary))
        }

        if let cpr = song.effectiveLatestCPR {
            chips.append(SongCardMetadataChip(id: "cpr", label: "CPR \(relativeShort(cpr.modifiedAt))"))
            if let versionLabel = cprVersionLabel(cpr) {
                chips.append(SongCardMetadataChip(id: "cpr-version", label: versionLabel))
            }
        }

        if let previewRole = mainPreviewRoleLabel(for: song) {
            chips.append(SongCardMetadataChip(id: "preview-role", label: previewRole))
        }

        if song.hasStems {
            chips.append(SongCardMetadataChip(id: "stems", label: "Stems"))
        }

        if let collaborator = song.collaboratorNames.first {
            chips.append(SongCardMetadataChip(id: "collaborator", label: collaborator))
        }

        if song.mainPreviewCandidateID == nil {
            chips.append(SongCardMetadataChip(id: "no-preview", label: "No preview"))
        }

        return deduplicated(chips).prefix(4).map { $0 }
    }

    private static func mainPreviewRoleLabel(for song: Song) -> String? {
        guard let id = song.mainPreviewCandidateID,
              let candidate = song.previewCandidates.first(where: { $0.id == id }) else {
            return nil
        }
        switch candidate.folderRole {
        case .mixdown, .root:
            return "Mixdown"
        case .stems:
            return "Stems folder"
        case .other:
            switch candidate.detectedRole {
            case .mainMix, .master, .preview:
                return "Mixdown"
            case .instrumental:
                return "Instrumental"
            case .acapella:
                return "Acapella"
            case .stems:
                return "Stems"
            case .unknown:
                return nil
            }
        }
    }

    private static func cprVersionLabel(_ cpr: ProjectVersion) -> String? {
        guard let version = cpr.detectedVersionNumber else { return nil }
        return "v\(version)"
    }

    private static func relativeShort(_ date: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        if interval < 3_600 {
            return "\(max(1, Int(interval / 60)))m"
        }
        if interval < 86_400 {
            return "\(max(1, Int(interval / 3_600)))h"
        }
        if interval < 604_800 {
            return "\(max(1, Int(interval / 86_400)))d"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func deduplicated(_ chips: [SongCardMetadataChip]) -> [SongCardMetadataChip] {
        var seen = Set<String>()
        return chips.filter { chip in
            let key = chip.label.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}

struct SongCardMetadataChipRow: View {
    let chips: [SongCardMetadataChip]

    var body: some View {
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(chips) { chip in
                    Text(chip.label)
                        .font(HubDesignSystem.Typography.micro())
                        .foregroundStyle(HubDesignSystem.Palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(HubDesignSystem.Palette.textPrimary.opacity(0.06))
                        }
                        .lineLimit(1)
                }
            }
        }
    }
}
