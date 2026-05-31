import Foundation

public struct ArchiveUserFlowSmokeResult: Sendable, Equatable {
    let runs: [SmokeRun]
    public let smokeLog: [String: String]

    public var core: CoreFlowEvidence {
        evidence(.coreFlow, as: CoreFlowEvidence.self)
    }

    public var fixtureDiagnostics: FixtureDiagnosticsEvidence {
        evidence(.fixtureDiagnostics, as: FixtureDiagnosticsEvidence.self)
    }

    init(runs: [SmokeRun]) {
        self.runs = runs
        var log: [String: String] = [:]
        for run in runs {
            run.appendLog(into: &log)
        }
        log["dry_run"] = "true"
        smokeLog = log
    }

    public func validateForE2ESmoke(dryRunOpen: Bool) throws {
        guard SmokeSuiteValidation.allRunsValid(runs) else {
            throw ArchiveUserFlowSmokeValidationError.evidenceIncomplete
        }
        if dryRunOpen, !core.satisfiesDryRunOpenEvidence() {
            throw ArchiveUserFlowSmokeValidationError.dryRunLogMissing
        }
    }

    private func evidence<T>(_ id: SmokeRunID, as type: T.Type) -> T {
        guard let run = runs.first(where: { $0.id == id }) else {
            fatalError("missing smoke run: \(id)")
        }
        switch run.evidence {
        case .coreFlow(let evidence) where T.self == CoreFlowEvidence.self:
            return evidence as! T
        case .fixtureDiagnostics(let evidence) where T.self == FixtureDiagnosticsEvidence.self:
            return evidence as! T
        default:
            fatalError("unexpected evidence type for \(id)")
        }
    }
}

public enum ArchiveUserFlowSmokeValidationError: Error, Equatable, Sendable {
    case evidenceIncomplete
    case dryRunLogMissing
}
