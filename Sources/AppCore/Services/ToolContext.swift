import Foundation

public struct ToolContext: Sendable {
    public let registeredToolCount: Int
    public let settingsStore: any SettingsStore
    public let outputInboxStore: any OutputInboxStore
    public let jobRunner: any JobRunning
    public let fileActions: any FileActions
    public let diagnostics: any Diagnostics

    public init(
        registeredToolCount: Int,
        settingsStore: any SettingsStore,
        outputInboxStore: any OutputInboxStore,
        jobRunner: any JobRunning,
        fileActions: any FileActions,
        diagnostics: any Diagnostics
    ) {
        self.registeredToolCount = registeredToolCount
        self.settingsStore = settingsStore
        self.outputInboxStore = outputInboxStore
        self.jobRunner = jobRunner
        self.fileActions = fileActions
        self.diagnostics = diagnostics
    }
}
