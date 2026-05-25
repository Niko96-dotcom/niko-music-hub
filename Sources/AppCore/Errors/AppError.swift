import Foundation

public enum AppErrorCategory: String, CaseIterable {
    case permission
    case helperTool
    case conversionFile
    case inputURL
}

public struct AppErrorCard {
    public let category: AppErrorCategory
    public let label: String
    public let icon: String
    public let body: String
    public let recoveryActions: [RecoveryAction]

    public struct RecoveryAction {
        public let label: String
        public let style: ActionStyle
        public enum ActionStyle { case primary, secondary, destructive }
        public let action: RecoveryActionType

        public init(label: String, style: ActionStyle, action: RecoveryActionType) {
            self.label = label
            self.style = style
            self.action = action
        }
    }

    public enum RecoveryActionType {
        case openSystemSettings
        case tryAgain
        case chooseToolPath
        case revealInFinder
        case openTerminal
        case dismiss
    }

    public init(
        category: AppErrorCategory,
        label: String,
        icon: String,
        body: String,
        recoveryActions: [RecoveryAction]
    ) {
        self.category = category
        self.label = label
        self.icon = icon
        self.body = body
        self.recoveryActions = recoveryActions
    }
}