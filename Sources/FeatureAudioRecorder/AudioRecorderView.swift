import AppCore
import FeatureAudioConverter
import SwiftUI

public struct AudioRecorderView: View {
    let context: ToolContext
    @StateObject private var viewModel: AudioRecorderViewModel

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
            VStack(alignment: .leading, spacing: 24) {
                header
                filenameDisplay
                meterSection
                timeDisplay
                controlSection
                settingsSection
                errorSection
                permissionSection
                incompatibleSection
                saveConfirmationSection
            }
            .hubToolContentPadding()
            .frame(maxWidth: 640, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Audio Recorder", systemImage: "waveform.circle")
                .font(.system(size: 16, weight: .semibold))

            Text(statusText)
                .font(.system(size: 13))
                .foregroundStyle(statusColor)
        }
    }

    private var filenameDisplay: some View {
        VStack(alignment: .leading, spacing: 4) {
            if viewModel.filenameOverride.isEmpty {
                Text("Recording \(Date().formatted(date: .complete, time: .omitted)).wav")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(viewModel.filenameOverride)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var meterSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.thinMaterial)
                .frame(height: 12)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    if let level = viewModel.currentLevel {
                        Rectangle()
                            .fill(meterColor(for: level.peak))
                            .frame(width: CGFloat(level.peak) * geometry.size.width)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
        }
        .opacity(viewModel.isRecording ? 1.0 : 0.0)
    }

    private var timeDisplay: some View {
        Text(formatElapsedTime(viewModel.elapsedTime))
            .font(.system(size: 32, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(viewModel.isRecording ? .primary : .secondary)
    }

    private var controlSection: some View {
        HStack(spacing: 12) {
            Button {
                if viewModel.isRecording {
                    Task { await viewModel.stopRecording() }
                } else {
                    Task { await viewModel.startRecording() }
                }
            } label: {
                Label(
                    viewModel.isRecording ? "Stop" : "Record",
                    systemImage: viewModel.isRecording ? "stop.fill" : "record.circle"
                )
            }
            .buttonStyle(.bordered)
            .tint(viewModel.isRecording ? .red : nil)
            .disabled(viewModel.recordingState == .stopping)
            .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")

            if viewModel.isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
                    .opacity(viewModel.isRecording ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.isRecording)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Max Duration")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

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
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if case .error(let error) = viewModel.recordingState {
            errorCard(for: error)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if viewModel.recordingState == .permissionNeeded {
            VStack(alignment: .leading, spacing: 12) {
                Label("Permission Required", systemImage: "lock.shield")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)

                Text("Audio Recorder captures your Mac's system audio (not your microphone). In System Settings, enable Niko Music Hub under Screen & System Audio Recording.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    HubIconButton(
                        systemImage: "lock.shield",
                        accessibilityLabel: "Open system audio recording settings",
                        help: "Open Screen & System Audio Recording in System Settings"
                    ) {
                        SystemPrivacySettings.openSystemAudioRecordingSettings()
                    }

                    HubIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Try again",
                        help: "Request recording permission again",
                        prominent: true
                    ) {
                        Task { await viewModel.requestPermission() }
                    }
                }
            }
            .padding(12)
            .hubGlassCard()
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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .hubGlassCard()
        }
    }

    @ViewBuilder
    private var saveConfirmationSection: some View {
        if viewModel.showSaveConfirmation, let url = viewModel.lastRecordedURL {
            HStack(spacing: 12) {
                Text("Recording saved")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)

                HubIconButton(
                    systemImage: "folder",
                    accessibilityLabel: "Reveal in Finder",
                    help: "Show recording in Finder"
                ) {
                    context.fileActions.revealInFinder(url)
                }

                HubIconButton(
                    systemImage: "arrow.up.forward.app",
                    accessibilityLabel: "Open recording",
                    help: "Open recording file"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            return .orange
        case .recording, .stopping:
            return .green
        case .error:
            return .red
        }
    }

    private func meterColor(for peak: Float) -> Color {
        if peak > 0.9 {
            return .red
        } else if peak > 0.7 {
            return .yellow
        } else {
            return .green
        }
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
