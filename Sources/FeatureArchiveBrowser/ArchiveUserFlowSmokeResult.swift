#if DEBUG
import Foundation

public struct ArchiveUserFlowSmokeResult: Sendable, Equatable {
    let runs: [SmokeRun]
    public let smokeLog: [String: String]

    public var core: CoreFlowEvidence {
        guard let run = runs.first(where: { $0.id == .coreFlow }),
              case .coreFlow(let evidence) = run.evidence else {
            preconditionFailure("archive smoke harness must include core flow run")
        }
        return evidence
    }

    public var fixtureDiagnostics: FixtureDiagnosticsEvidence {
        guard let run = runs.first(where: { $0.id == .fixtureDiagnostics }),
              case .fixtureDiagnostics(let evidence) = run.evidence else {
            preconditionFailure("archive smoke harness must include fixture diagnostics run")
        }
        return evidence
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
}

public enum ArchiveUserFlowSmokeValidationError: Error, Equatable, Sendable {
    case evidenceIncomplete
    case dryRunLogMissing
}
#endif
