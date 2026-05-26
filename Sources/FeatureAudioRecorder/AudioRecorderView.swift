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
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 32)
            .frame(maxWidth: 640, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
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
            Button(viewModel.isRecording ? "Stop" : "Start Recording") {
                if viewModel.isRecording {
                    Task { await viewModel.stopRecording() }
                } else {
                    Task { await viewModel.startRecording() }
                }
            }
            .buttonStyle(.bordered)
            .tint(viewModel.isRecording ? .red : nil)
            .disabled(viewModel.recordingState == .stopping)

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

                Text("Audio Recorder needs system audio permission to capture your Mac's audio. Open Privacy & Security settings to allow access.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Open System Settings") {
                        openSystemSettingsPrivacy()
                    }
                    .buttonStyle(.bordered)

                    Button("Try Again") {
                        Task { await viewModel.requestPermission() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var saveConfirmationSection: some View {
        if viewModel.showSaveConfirmation, let url = viewModel.lastRecordedURL {
            HStack(spacing: 12) {
                Text("Recording saved")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)

                Button("Reveal") {
                    context.fileActions.revealInFinder(url)
                }
                .buttonStyle(.bordered)

                Button("Open") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func errorCard(for error: RecorderError) -> some View {
        let card = cardFor(error)
        StandardErrorCard(card: card)
    }

    private func cardFor(_ error: RecorderError) -> AppErrorCard {
        switch error {
        case .permissionDenied:
            return AppErrorCard(
                category: .permission,
                label: "Permission Required",
                icon: "lock.shield",
                body: "Audio Recorder needs system audio permission to capture your Mac's audio. Open Privacy & Security settings to allow access.",
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Open System Settings", style: .secondary, action: .openSystemSettings),
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

    private func openSystemSettingsPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }

    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
