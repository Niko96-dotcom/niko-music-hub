import AppCore
import AppKit
import SwiftUI

public struct AudioRecorderView: View {
    let context: ToolContext
    @StateObject private var viewModel: AudioRecorderViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(context: ToolContext) {
        self.context = context

        let capturePort = CoreAudioTapAdapter()
        let useCase = RecordSystemAudioUseCase(capturePort: capturePort)
        let outputURL = ((try? context.settingsStore.loadSettings()) ?? .default).outputFolder.url
        let outputInboxStore = context.outputInboxStore

        _viewModel = StateObject(wrappedValue: AudioRecorderViewModel(
            capturePort: capturePort,
            useCase: useCase,
            outputURL: outputURL,
            outputInboxStore: outputInboxStore
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: HubDesignSystem.Spacing.section) {
                saveConfirmationBanner
                header
                filenameDisplay
                timeDisplay
                meterSection
                controlSection
                settingsSection
                errorSection
                permissionSection
                incompatibleSection
            }
            .hubToolContentPadding()
            .frame(maxWidth: HubToolLayout.maxContentWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(HubDesignSystem.Colors.success.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
            .frame(maxWidth: 560)
        }
    }

    private var header: some View {
        VStack(spacing: HubDesignSystem.Spacing.inlineGap) {
            Text("Audio Recorder")
                .font(HubDesignSystem.Typography.screenTitle())

            Text(statusText)
                .font(HubDesignSystem.Typography.body())
                .foregroundStyle(statusColor)
        }
        .frame(maxWidth: 560)
    }

    private var filenameDisplay: some View {
        Group {
            if viewModel.filenameOverride.isEmpty {
                Text("Recording \(Date().formatted(date: .complete, time: .omitted)).wav")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.filenameOverride)
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.primary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
    }

    private var meterSection: some View {
        GeometryReader { geometry in
            let peak = viewModel.currentLevel?.peak ?? 0
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 8)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(meterGradient(for: peak))
                    .frame(width: max(0, CGFloat(peak) * geometry.size.width), height: 8)
            }
        }
        .frame(height: 8)
        .frame(maxWidth: 560)
        .shadow(
            color: viewModel.isRecording ? HubDesignSystem.Colors.success.opacity(0.3) : .clear,
            radius: 4
        )
        .opacity(viewModel.isRecording ? 1 : 0.35)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: viewModel.currentLevel?.peak)
    }

    private var timeDisplay: some View {
        Text(formatElapsedTime(viewModel.elapsedTime))
            .font(HubDesignSystem.Typography.display())
            .monospacedDigit()
            .foregroundStyle(viewModel.isRecording ? .primary : .tertiary)
            .frame(maxWidth: 560)
    }

    private var controlSection: some View {
        Button {
            if viewModel.isRecording {
                Task { await viewModel.stopRecording() }
            } else {
                Task { await viewModel.startRecording() }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isRecording {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: viewModel.isRecording
                        )
                }
                Label(
                    viewModel.isRecording ? "Stop" : "Record",
                    systemImage: viewModel.isRecording ? "stop.fill" : "record.circle"
                )
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.red)
        .disabled(viewModel.recordingState == .stopping)
        .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
    }

    private var settingsSection: some View {
        VStack(spacing: HubDesignSystem.Spacing.controlGap) {
            Picker("Max Duration", selection: $viewModel.maxDurationMinutes) {
                Text("5 min").tag(5)
                Text("10 min").tag(10)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("60 min").tag(60)
                Text("Unlimited").tag(0)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isRecording)
            .frame(maxWidth: 560)
        }
        .padding(.top, HubDesignSystem.Spacing.section)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var errorSection: some View {
        if case .error(let error) = viewModel.recordingState {
            errorCard(for: error)
                .frame(maxWidth: 560)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if viewModel.recordingState == .permissionNeeded {
            VStack(alignment: .leading, spacing: 12) {
                Label("Permission Required", systemImage: "lock.shield")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HubDesignSystem.Colors.danger)

                Text("Audio Recorder captures your Mac's system audio (not your microphone). In System Settings, enable Niko Music Hub under Screen & System Audio Recording.")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.secondary)
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
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
            .frame(maxWidth: 560)
        }
    }

    @ViewBuilder
    private var incompatibleSection: some View {
        if case .incompatibleMacOS(let version) = viewModel.recordingState {
            VStack(alignment: .leading, spacing: 12) {
                Label("macOS Too Old", systemImage: "laptopcomputer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Audio Recorder requires macOS 14.2 or later. Current version: \(version). Please upgrade macOS or use an external audio interface.")
                    .font(HubDesignSystem.Typography.bodySmall())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: HubDesignSystem.Radius.row, style: .continuous))
            .frame(maxWidth: 560)
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
        case .recording:
            return "Recording..."
        case .stopping:
            return "Stopping..."
        case .error(let error):
            return error.localizedDescription
        }
    }

    private var statusColor: Color {
        switch viewModel.recordingState {
        case .idle:
            return .secondary
        case .permissionNeeded, .incompatibleMacOS:
            return HubDesignSystem.Colors.warning
        case .recording, .stopping:
            return HubDesignSystem.Colors.success
        case .error:
            return HubDesignSystem.Colors.danger
        }
    }

    private func meterGradient(for peak: Float) -> LinearGradient {
        let colors: [Color]
        if peak > 0.9 {
            colors = [HubDesignSystem.Colors.warning, HubDesignSystem.Colors.danger]
        } else if peak > 0.7 {
            colors = [HubDesignSystem.Colors.success, HubDesignSystem.Colors.warning]
        } else {
            colors = [HubDesignSystem.Colors.success, HubDesignSystem.Colors.success.opacity(0.85)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
