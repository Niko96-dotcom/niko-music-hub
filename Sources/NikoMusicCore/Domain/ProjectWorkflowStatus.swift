import Foundation

public enum ProjectWorkflowStatus: String, CaseIterable, Codable, Hashable, Sendable {
    case songstarterBeat = "songstarter_beat"
    case song = "song"
    case sessionProd = "session_prod"
    case prod = "prod"
    case waitingFeedback = "waiting_feedback"
    case feedbackTodo = "feedback_todo"
    case done = "done"

    public var displayTitle: String {
        switch self {
        case .songstarterBeat: "Songstarter/Beat"
        case .song: "Song"
        case .sessionProd: "Session Prod"
        case .prod: "Prod"
        case .waitingFeedback: "Waiting Feedback"
        case .feedbackTodo: "Feedback Todo"
        case .done: "Done"
        }
    }

    public var shortTitle: String {
        switch self {
        case .songstarterBeat: "Idea"
        case .song: "Song"
        case .sessionProd: "Session"
        case .prod: "Prod"
        case .waitingFeedback: "Waiting"
        case .feedbackTodo: "Todo"
        case .done: "Done"
        }
    }

    public var isIdea: Bool {
        self == .songstarterBeat
    }

    public var isTodo: Bool {
        switch self {
        case .song, .sessionProd, .prod, .feedbackTodo:
            return true
        case .songstarterBeat, .waitingFeedback, .done:
            return false
        }
    }

    public var isWaitingOnOthers: Bool {
        self == .waitingFeedback
    }

    public var searchableText: String {
        switch self {
        case .songstarterBeat: "songstarter beat idea starter"
        case .song: "song"
        case .sessionProd: "session prod session production"
        case .prod: "prod production demo"
        case .waitingFeedback: "waiting feedback waiting on others waiting on people"
        case .feedbackTodo: "feedback todo incorporate feedback to do"
        case .done: "done finished complete"
        }
    }
}
