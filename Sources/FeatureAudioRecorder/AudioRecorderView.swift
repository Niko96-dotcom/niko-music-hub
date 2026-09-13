import AppCore
import AppKit
import SwiftUI

public struct AudioRecorderView: View {
    let context: ToolContext
    @StateObject private var viewModel: AudioRecorderViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastPersistedMaxDurationMinutes: Int?

    public init(context: ToolContext, viewModel: AudioRecorderViewModel) {
        self.context = context
        _viewModel = StateObject(wrappedValue: viewModel)
        _lastPersistedMaxDurationMinutes = State(initialValue: viewModel.maxDurationMinutes)
    }

    public var body: some View {
        HubToolPage {
            saveConfirmationBanner
            header
            filenameDisplay
            timeDisplay
            // Reference rule: live surfaces are hidden at rest — the level
            // meter only appears while a recording is actually running.
            if viewModel.isRecording {
                meterSection
            }
            controlSection
            settingsSection
            recordingsSection
            errorSection
            permissionSection
            incompatibleSection
        }
        .onAppear {
            syncMaxDurationFromSettings()
            viewModel.onAppear()
        }
        .onChange(of: viewModel.maxDurationMinutes) { _, newValue in
            let normalized = RecordingDurationOptions.normalized(newValue)
            guard normalized != lastPersistedMaxDurationMinutes else { return }
            persistMaxDuration(minutes: newValue)
        }
        .task(id: viewModel.showSaveConfirmation) {
            guard viewModel.showSaveConfirmation else { return }
            try? await Task.sleep(for: .seconds(5))
            if viewModel.showSaveConfirmation {
                viewModel.dismissSaveConfirmation()
            }
        }
    }

    @ViewBuilder
    private var saveConfirmationBanner: some View {
        if viewModel.showSaveConfirmation, let url = viewModel.lastRecordedURL {
            VStack(alignment: .leading, spacing: HubDesignSystem.Spacing.inlineGap) {
                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    Label("Recording saved", systemImage: "checkmark.circle.fill")
                        .font(HubDesignSystem.Typography.body())
                        .foregroundStyle(HubDesignSystem.Colors.success)

                    Spacer(minLength: 8)

                    HubLabeledButton(
                        icon: "folder",
                        label: "Reveal",
                        style: .secondary
                    ) {
                        context.fileActions.revealInFinder(url)
                    }

                    HubLabeledButton(
                        icon: "arrow.up.forward.app",
                        label: "Open",
                        style: .secondary
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }

                if let warning = viewModel.handoffWarningMessage {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(HubDesignSystem.Typography.bodySmall())
                        .foregroundStyle(HubDesignSystem.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .selected)
            .frame(maxWidth: HubToolLayout.maxContentWidth)
        }
    }

    private var header: some View {
        ToolHeaderBlock(
            title: "Audio Recorder",
            statusText: statusText,
            statusColor: statusColor
        )
        .frame(maxWidth: HubToolLayout.maxContentWidth)
    }

    private var filenameDisplay: some View {
        Group {
            if viewModel.filenameOverride.isEmpty {
                Text("Recording \(Date().formatted(date: .complete, time: .omitted)).wav")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
            } else {
                Text(viewModel.filenameOverride)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textPrimary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: HubToolLayout.maxContentWidth)
    }

    private var meterSection: some View {
        HubWaveformSurface(
            peaks: meterPeaks,
            progress: Double(viewModel.currentLevel?.peak ?? 0),
            variant: .meter,
            isEnabled: viewModel.isRecording
        )
        .frame(maxWidth: HubToolLayout.maxContentWidth)
        .opacity(viewModel.isRecording ? 1 : 0.35)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: viewModel.currentLevel?.peak)
    }

    // Bare display type — a timer is not a bounded object, so no card (DS:
    // "cards only for bounded objects").
    private var timeDisplay: some View {
        Text(formatElapsedTime(viewModel.elapsedTime))
            .font(HubDesignSystem.Typography.display())
            .monospacedDigit()
            .foregroundStyle(viewModel.isRecording ? HubDesignSystem.Palette.textPrimary : HubDesignSystem.Palette.textTertiary)
            .padding(.vertical, 10)
            .frame(maxWidth: HubToolLayout.maxContentWidth)
    }

    private var controlSection: some View {
        Button {
            if viewModel.isCaptureActive {
                Task { await viewModel.stopRecording() }
            } else {
                Task { await viewModel.startRecording() }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isCaptureActive {
                    Circle()
                        .fill(HubDesignSystem.Palette.danger)
                        .frame(width: 10, height: 10)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: viewModel.isRecording
                        )
                }
                Label(
                    viewModel.isCaptureActive ? "Stop" : "Record",
                    systemImage: viewModel.isCaptureActive ? "stop.fill" : "record.circle"
                )
                .font(HubDesignSystem.Typography.body())
                .fontWeight(.semibold)
            }
            .foregroundStyle(HubDesignSystem.Palette.canvas)
            .frame(height: 34)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(viewModel.isCaptureActive ? HubDesignSystem.Palette.danger : HubDesignSystem.Palette.accent)
        }
        .disabled(viewModel.recordingState == .stopping)
        .accessibilityLabel(viewModel.isCaptureActive ? "Stop recording" : "Start recording")
        .padding(12)
    }

    // Quiet unboxed preference row — chips are already chips; a card around
    // them is box-in-box.
    private var settingsSection: some View {
        HStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Text("Max duration")
                .font(HubDesignSystem.Typography.caption())
                .foregroundStyle(HubDesignSystem.Palette.textTertiary)
            HubChoiceChips("Max Duration", selection: $viewModel.maxDurationMinutes, choices:
                RecordingDurationOptions.supportedMinutes.map { minutes in
                    .init(
                        minutes,
                        label: RecordingDurationOptions.chipLabel(for: minutes),
                        help: RecordingDurationOptions.label(for: minutes)
                    )
                }
            )
            .disabled(viewModel.isCaptureActive)
            .opacity(viewModel.isCaptureActive ? 0.45 : 1)
        }
        .frame(maxWidth: HubToolLayout.maxContentWidth)
    }

    /// Latest finished recordings, each a draggable card — drop one straight into a DAW.
    private var recordingsSection: some View {
        ToolOutputShelf(
            title: "Recordings",
            items: viewModel.recentRecordings,
            subtitle: recordingSubtitle,
            onReveal: { item in
                context.fileActions.revealInFinder(item.fileURL)
            }
        )
        .frame(maxWidth: HubToolLayout.maxContentWidth)
    }

    private func recordingSubtitle(for item: OutputInboxItem) -> String? {
        var parts: [String] = []
        if let durationText = item.metadata["duration"], let duration = TimeInterval(durationText) {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            parts.append(String(format: "%d:%02d", minutes, seconds))
        }
        parts.append(HubRelativeTime.string(for: item.createdAt))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var errorSection: some View {
        if case .error(let error) = viewModel.recordingState {
            errorCard(for: error)
                .frame(maxWidth: HubToolLayout.maxContentWidth)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if viewModel.recordingState == .permissionNeeded {
            VStack(alignment: .leading, spacing: 12) {
                Label("Permission Required", systemImage: "lock.shield")
                    .font(HubDesignSystem.Typography.sectionTitle())
                    .foregroundStyle(HubDesignSystem.Colors.danger)

                Text("Audio Recorder captures your Mac's system audio (not your microphone). In System Settings, enable Niko Music Hub under Screen & System Audio Recording.")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: HubDesignSystem.Spacing.controlGap) {
                    HubLabeledButton(
                        icon: "lock.shield",
                        label: "Open Settings",
                        style: .secondary
                    ) {
                        SystemPrivacySettings.openSystemAudioRecordingSettings()
                    }

                    HubLabeledButton(
                        icon: "arrow.clockwise",
                        label: "Try Again",
                        style: .primary
                    ) {
                        Task { await viewModel.requestPermission() }
                    }
                }
            }
            .padding(12)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .warning)
            .frame(maxWidth: HubToolLayout.maxContentWidth)
        }
    }

    @ViewBuilder
    private var incompatibleSection: some View {
        if case .incompatibleMacOS(let version) = viewModel.recordingState {
            VStack(alignment: .leading, spacing: 12) {
                Label("macOS Too Old", systemImage: "laptopcomputer")
                    .font(HubDesignSystem.Typography.sectionTitle())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)

                Text("Audio Recorder requires macOS 14.2 or later. Current version: \(version). Please upgrade macOS or use an external audio interface.")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(HubDesignSystem.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .hubCard(cornerRadius: HubDesignSystem.Radius.row, state: .disabled)
            .frame(maxWidth: HubToolLayout.maxContentWidth)
        }
    }

    @ViewBuilder
    private func errorCard(for error: RecorderError) -> some View {
        let card = cardFor(error)
        StandardErrorCard(card: card) { action in
            switch action {
            case .tryAgain:
                Task { await viewModel.startRecording() }
            case .openSystemSettings:
                SystemPrivacySettings.openSystemAudioRecordingSettings()
            default:
                break
            }
        }
    }

    private func cardFor(_ error: RecorderError) -> AppErrorCard {
        switch error {
        case .permissionDenied:
            return AppErrorCard(
                category: .permission,
                label: "Permission Required",
                icon: "lock.shield",
                body: "Audio Recorder captures your Mac's system audio (not your microphone). In System Settings, enable Niko Music Hub under Screen & System Audio Recording.",
                recoveryActions: [
                    AppErrorCard.RecoveryAction(
                        label: "Open System Audio Recording Settings",
                        style: .secondary,
                        action: .openSystemSettings
                    ),
                    AppErrorCard.RecoveryAction(label: "Try Again", style: .primary, action: .tryAgain)
                ]
            )
        case .permissionRestricted:
            return AppErrorCard(
                category: .permission,
                label: "Recording Restricted",
                icon: "exclamationmark.shield",
                body: "System audio recording is restricted on this device (MDM or parental controls).",
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "OK", style: .secondary, action: .dismiss)
                ]
            )
        case .apiError(let message):
            return AppErrorCard(
                category: .permission,
                label: "Audio Capture Failed",
                icon: "waveform.badge.xmark",
                body: message,
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Open System Settings", style: .secondary, action: .openSystemSettings),
                    AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
                ]
            )
        case .writeError:
            return AppErrorCard(
                category: .conversionFile,
                label: "Could Not Save Recording",
                icon: "externaldrive.badge.xmark",
                body: "Check available disk space. The output folder may be full or on a read-only volume.",
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Check Disk Space", style: .secondary, action: .revealInFinder),
                    AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
                ]
            )
        case .verificationFailed:
            return AppErrorCard(
                category: .conversionFile,
                label: "Recording Verification Failed",
                icon: "checkmark.shield",
                body: "The recorded file could not be verified. It may be corrupted.",
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
                ]
            )
        case .noAudioCaptured:
            return AppErrorCard(
                category: .conversionFile,
                label: "No Audio Captured",
                icon: "waveform.badge.exclamationmark",
                body: "macOS did not deliver any audio frames to the recorder. Check that Screen & System Audio Recording permission is granted for Niko Music Hub, then retry.",
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Open System Audio Recording Settings", style: .secondary, action: .openSystemSettings),
                    AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
                ]
            )
        case .incompatibleMacOS(let minimum, let current):
            return AppErrorCard(
                category: .permission,
                label: "macOS Too Old",
                icon: "laptopcomputer",
                body: "Audio Recorder requires macOS \(minimum) or later. Current version: \(current). Please upgrade macOS or use an external audio interface.",
                recoveryActions: []
            )
        }
    }

    private var statusText: String {
        switch viewModel.recordingState {
        case .idle:
            return "Ready to record"
        case .permissionNeeded:
            return "Permission required"
        case .incompatibleMacOS(let version):
            return "macOS \(version) not supported"
        case .starting:
            return "Starting…"
        case .recording:
            return "Recording..."
        case .reconnecting:
            return "Reconnecting audio…"
        case .stopping:
            return "Stopping..."
        case .error(let error):
            return error.localizedDescription
        }
    }

    private var statusColor: Color {
        switch viewModel.recordingState {
        case .idle:
            return HubDesignSystem.Palette.textSecondary
        case .permissionNeeded, .incompatibleMacOS:
            return HubDesignSystem.Colors.warning
        case .starting, .reconnecting:
            return HubDesignSystem.Colors.warning
        case .recording, .stopping:
            return HubDesignSystem.Colors.success
        case .error:
            return HubDesignSystem.Colors.danger
        }
    }

    private var meterPeaks: [Double] {
        let peak = Double(viewModel.currentLevel?.peak ?? 0)
        guard peak > 0 else {
            return HubMediaSurfaceFixtures.meterPeaks.map { $0 * 0.08 }
        }
        return HubMediaSurfaceFixtures.meterPeaks.enumerated().map { index, value in
            let pulse = 0.62 + (Double(index % 4) * 0.11)
            return min(max(value * peak * pulse, 0.03), 1)
        }
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func persistMaxDuration(minutes: Int) {
        let normalized = RecordingDurationOptions.normalized(minutes)
        let previous = lastPersistedMaxDurationMinutes ?? normalized
        do {
            try context.settingsStore.updateSettings { settings in
                settings.maxRecordingDurationMinutes = normalized
            }
            lastPersistedMaxDurationMinutes = normalized
        } catch {
            context.diagnostics.log(.error, "Failed to persist max recording duration: \(error)")
            viewModel.maxDurationMinutes = previous
        }
    }

    private func syncMaxDurationFromSettings() {
        let settings = (try? context.settingsStore.loadSettings()) ?? .default
        let normalized = RecordingDurationOptions.normalized(settings.maxRecordingDurationMinutes)
        guard viewModel.maxDurationMinutes != normalized else { return }
        viewModel.maxDurationMinutes = normalized
        lastPersistedMaxDurationMinutes = normalized
    }
}
