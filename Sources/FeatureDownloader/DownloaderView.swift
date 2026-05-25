import AppCore
import AppKit
import SwiftUI

public struct DownloaderView: View {
    let context: ToolContext

    @StateObject private var viewModel: DownloaderViewModel
    @FocusState private var downloaderFocused: Bool

    public init(
        context: ToolContext,
        viewModel: DownloaderViewModel
    ) {
        self.context = context
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                urlInput
                if viewModel.downloadState == .readyToDownload || viewModel.downloadState == .downloading {
                    trustInfo
                }
                if viewModel.downloadState == .downloading {
                    progressSection
                    logArea
                }
                if case let .failed(message) = viewModel.downloadState {
                    errorSection(message: message)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 56)
            .frame(minWidth: 320, idealWidth: 640, maxWidth: 720, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($downloaderFocused)
        .onAppear { downloaderFocused = true }
        .onKeyPress(.escape) {
            if !viewModel.urlText.isEmpty {
                viewModel.clearInput()
            }
            return .handled
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(DownloaderCopy.toolLabel, systemImage: "arrow.down.circle")
                .font(.system(size: 16, weight: .semibold))

            Text(headerStatus)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    private var headerStatus: String {
        switch viewModel.downloadState {
        case .idle:
            return DownloaderCopy.urlPlaceholder
        case .checkingURL:
            return DownloaderCopy.checkingURL
        case .readyToDownload:
            return viewModel.statusMessage ?? DownloaderCopy.readyToDownload
        case .downloading:
            return viewModel.statusMessage ?? DownloaderCopy.downloading
        case .completed:
            return DownloaderCopy.downloadComplete
        case let .failed(message):
            return message
        }
    }

    private var urlInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(DownloaderCopy.urlPlaceholder, text: $viewModel.urlText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.urlText) { _, _ in
                    viewModel.urlTextDidChange()
                }

            HStack {
                if let fileName = viewModel.detectedFileName {
                    Text(fileName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                downloadButton
                clearButton
            }
        }
    }

    @ViewBuilder
    private var downloadButton: some View {
        Button(DownloaderCopy.download) {
            viewModel.startDownload()
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.downloadState != .readyToDownload)
    }

    private var clearButton: some View {
        Button(DownloaderCopy.clear) {
            viewModel.clearInput()
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.downloadState == .downloading)
    }

    private var trustInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(DownloaderCopy.sourceLabel):")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(viewModel.urlText)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Text("\(DownloaderCopy.destinationLabel):")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(viewModel.outputFolder.path)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(DownloaderCopy.trustNotice)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: viewModel.progress)
                .frame(maxWidth: 320)
                .tint(Color.accentColor)

            Text("\(Int(viewModel.progress * 100))% complete")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var logArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.logEntries, id: \.self) { entry in
                        Text(entry)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func errorSection(message: String) -> some View {
        let card = Self.errorCard(for: message)
        return StandardErrorCard(card: card) { action in
            if action == .tryAgain {
                viewModel.retryAfterFailure()
            }
        }
    }

    private static func errorCard(for message: String) -> AppErrorCard {
        let lower = message.lowercased()
        if lower.contains("yt-dlp is required") || lower.contains("yt-dlp path") || lower.contains("outdated") {
            return AppErrorCard(
                category: .helperTool,
                label: "yt-dlp Not Found",
                icon: "tool.badge.xmark",
                body: message,
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Open Terminal", style: .primary, action: .openTerminal),
                    AppErrorCard.RecoveryAction(label: "Retry", style: .secondary, action: .tryAgain)
                ]
            )
        }
        if lower.contains("error:") || lower.contains("unsupported") || lower.contains("video unavailable") {
            return AppErrorCard(
                category: .inputURL,
                label: "URL Not Supported",
                icon: "link.badge.plus",
                body: message,
                recoveryActions: [
                    AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
                ]
            )
        }
        return AppErrorCard(
            category: .conversionFile,
            label: "Download Failed",
            icon: "arrow.down.circle.badge.xmark",
            body: message,
            recoveryActions: [
                AppErrorCard.RecoveryAction(label: "Retry", style: .primary, action: .tryAgain)
            ]
        )
    }
}