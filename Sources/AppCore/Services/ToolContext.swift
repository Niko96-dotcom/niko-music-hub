import Foundation

public struct PersistenceIssue: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var message: String

    public init(id: String, title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}

public struct ToolContext: Sendable {
    public let registeredToolCount: Int
    public let settingsStore: any SettingsStore
    public let preferences: any PreferenceStore
    public let outputInboxStore: any OutputInboxStore
    public let jobRunner: any JobRunning
    public let fileActions: any FileActions
    public let launchAtLogin: any LaunchAtLoginControlling
    public let diagnostics: any Diagnostics
    public let persistenceIssues: [PersistenceIssue]
    public let jobStatusCenter: ShellJobStatusCenter

    public init(
        registeredToolCount: Int,
        settingsStore: any SettingsStore,
        preferences: any PreferenceStore = UserDefaultsPreferenceStore(),
        outputInboxStore: any OutputInboxStore,
        jobRunner: any JobRunning,
        fileActions: any FileActions,
        launchAtLogin: any LaunchAtLoginControlling = NoopLaunchAtLoginController(),
        diagnostics: any Diagnostics,
        persistenceIssues: [PersistenceIssue] = [],
        jobStatusCenter: ShellJobStatusCenter? = nil
    ) {
        self.registeredToolCount = registeredToolCount
        self.settingsStore = settingsStore
        self.preferences = preferences
        self.outputInboxStore = outputInboxStore
        self.jobRunner = jobRunner
        self.fileActions = fileActions
        self.launchAtLogin = launchAtLogin
        self.diagnostics = diagnostics
        self.persistenceIssues = persistenceIssues
        self.jobStatusCenter = jobStatusCenter ?? ShellJobStatusCenter(jobRunner: jobRunner)
    }
}
