import Foundation

/// A fixed pattern compiled once and shared.
///
/// `String.range(of:options: .regularExpression)` and `replacingOccurrences(of:with:options: .regularExpression)`
/// compile their pattern on every call, and the small system cache behind them thrashes once a code path
/// cycles through more patterns than it holds. Filename classification runs these per file and per song, so
/// the compile cost dominated a launch on a large archive. `NSRegularExpression` is immutable and safe to
/// share across the concurrent scans and cache loads, and a match over the whole string returns what the
/// string APIs return.
struct CompiledRegex: @unchecked Sendable {
    private let expression: NSRegularExpression

    /// `pattern` is always a literal in this module; an invalid one fails in every test run that touches it.
    init(_ pattern: String, caseInsensitive: Bool = false) {
        do {
            expression = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Invalid regular expression \(pattern): \(error)")
        }
    }

    func firstMatchRange(in string: String) -> Range<String.Index>? {
        guard let match = expression.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) else {
            return nil
        }
        return Range(match.range, in: string)
    }

    func hasMatch(in string: String) -> Bool {
        expression.firstMatch(in: string, options: [], range: NSRange(string.startIndex..., in: string)) != nil
    }

    func replacingMatches(in string: String, with template: String) -> String {
        expression.stringByReplacingMatches(
            in: string,
            options: [],
            range: NSRange(string.startIndex..., in: string),
            withTemplate: template
        )
    }

    /// Every match in order; capture group ranges are available through the result.
    func matches(in string: String) -> [NSTextCheckingResult] {
        expression.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
    }
}
