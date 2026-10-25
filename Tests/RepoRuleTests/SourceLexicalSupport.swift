import Foundation

/// Bounded test-only lexical support for source guards.
///
/// - `stripped(_:)` blanks comments and string literals (preserving newlines
///   for stable line numbers). `strippedCommentsOnly(_:)` blanks comments
///   only and retains string literals for literal-dependent guards.
/// - `focusablePairFailures(in:)` reports every `.focusable(...)` whose own
///   modifier chain lacks a valid `.focusEffectDisabled` in the SAME chain
///   (paired, either order). A chain is the contiguous `.modifier(...)` /
///   `.modifier { ... }` run; intervening modifiers and balanced closures are
///   allowed. A suppression on a sibling view does NOT satisfy the check.
///   Nested trailing closures and paren arguments are traversed as independent
///   chains (never borrowing outer or sibling suppression), so an unpaired
///   nested `.focusable()` still fails and outer suppression never covers it.
///   Valid suppression is a call with empty args or `true`. A chain with ANY
///   explicit `false`/unknown-arg suppression is conservatively rejected even
///   with another valid present; bare references do not count. No claim about
///   SwiftUI's last-modifier-wins without runtime evidence.
/// - `scrollViewBodies(in:)` returns brace bodies of `ScrollView` /
///   `ScrollView(...)` (not `ScrollViewReader`/`Proxy`) for nesting checks.
///   `inspectorContentScrollBodies(in:)` scopes to HubInspectorPage.body's
///   content column before `HubDesignSystem.Palette.separator` (whitespace
///   tolerant); inspector ScrollViews after the separator are excluded.
/// - Ownership helpers tie wrapper + type/name within one property declaration
///   anchored to the FIRST `var` and bound to its declaration (multiline
///   allowed, never crossing another `@`/`;`/`{`/`}` or a later `var`/`let`).
///   Only `var name: Type` and `var name = Type(` forms are reported.
///
/// Limits: not a Swift parser. Exotic modifiers (subscripts, multiple paren
/// groups) are out of scope. Unterminated comments/strings are blanked to end
/// (fail closed for pairing checks). Ownership reports only the two forms
/// above; other spellings are out of scope.
enum SourceLex {
    // MARK: - Stripping

    static func stripped(_ source: String) -> String {
        lex(source, blankStrings: true)
    }

    static func strippedCommentsOnly(_ source: String) -> String {
        lex(source, blankStrings: false)
    }

    private static func lex(_ source: String, blankStrings: Bool) -> String {
        var out = ""
        out.reserveCapacity(source.count)
        var i = source.startIndex
        let end = source.endIndex
        while i < end {
            let c = source[i]
            // Raw string start: hashes + " or """ .
            if c == "#" {
                var j = i
                var hashes = 0
                while j < end && source[j] == "#" {
                    hashes += 1
                    j = source.index(after: j)
                }
                if j < end && source[j] == "\"" {
                    let k1 = source.index(after: j)
                    let k2 = k1 < end ? source.index(after: k1) : end
                    let isTriple = k1 < end && source[k1] == "\"" && k2 < end && source[k2] == "\""
                    if blankStrings {
                        for _ in 0..<hashes { out.append(" ") }
                        out.append(" ")
                        if isTriple { out.append(" "); out.append(" ") }
                    } else {
                        for _ in 0..<hashes { out.append("#") }
                        out.append("\"")
                        if isTriple { out.append("\""); out.append("\"") }
                    }
                    var p = source.index(after: j)
                    if isTriple {
                        p = source.index(after: p)
                        if p < end { p = source.index(after: p) }
                    }
                    i = p
                    var closed = false
                    while i < end {
                        if source[i] == "\n" {
                            out.append("\n")
                            i = source.index(after: i)
                            continue
                        }
                        if source[i] == "\"" {
                            if isTriple {
                                let a = source.index(after: i)
                                let b = a < end ? source.index(after: a) : end
                                if a < end && source[a] == "\"" && b < end && source[b] == "\"" {
                                    var q = source.index(after: b)
                                    var ok = true
                                    for _ in 0..<hashes {
                                        if q < end && source[q] == "#" {
                                            q = source.index(after: q)
                                        } else { ok = false; break }
                                    }
                                    if ok {
                                        if blankStrings {
                                            out.append(" "); out.append(" "); out.append(" ")
                                            for _ in 0..<hashes { out.append(" ") }
                                        } else {
                                            out.append("\""); out.append("\""); out.append("\"")
                                            for _ in 0..<hashes { out.append("#") }
                                        }
                                        i = q
                                        closed = true
                                        break
                                    }
                                }
                            } else {
                                var q = source.index(after: i)
                                var ok = true
                                for _ in 0..<hashes {
                                    if q < end && source[q] == "#" {
                                        q = source.index(after: q)
                                    } else { ok = false; break }
                                }
                                if ok {
                                    if blankStrings {
                                        out.append(" ")
                                        for _ in 0..<hashes { out.append(" ") }
                                    } else {
                                        out.append("\"")
                                        for _ in 0..<hashes { out.append("#") }
                                    }
                                    i = q
                                    closed = true
                                    break
                                }
                            }
                        }
                        if blankStrings {
                            out.append(" ")
                        } else {
                            out.append(source[i])
                        }
                        i = source.index(after: i)
                    }
                    _ = closed
                    continue
                }
                out.append(c)
                i = source.index(after: i)
                continue
            }
            if c == "/" {
                let n = source.index(after: i)
                if n < end && source[n] == "/" {
                    out.append(" "); out.append(" ")
                    i = source.index(after: n)
                    while i < end && source[i] != "\n" {
                        out.append(" ")
                        i = source.index(after: i)
                    }
                    continue
                }
                if n < end && source[n] == "*" {
                    out.append(" "); out.append(" ")
                    i = source.index(after: n)
                    var depth = 1
                    while i < end && depth > 0 {
                        if source[i] == "\n" {
                            out.append("\n")
                            i = source.index(after: i)
                            continue
                        }
                        let m = source.index(after: i)
                        if source[i] == "/" && m < end && source[m] == "*" {
                            out.append(" "); out.append(" ")
                            i = source.index(after: m)
                            depth += 1
                            continue
                        }
                        if source[i] == "*" && m < end && source[m] == "/" {
                            out.append(" "); out.append(" ")
                            i = source.index(after: m)
                            depth -= 1
                            continue
                        }
                        out.append(" ")
                        i = source.index(after: i)
                    }
                    continue
                }
            }
            if c == "\"" {
                let n1 = source.index(after: i)
                let n2 = n1 < end ? source.index(after: n1) : end
                let isTriple = n1 < end && source[n1] == "\"" && n2 < end && source[n2] == "\""
                if isTriple {
                    if blankStrings { out.append(" "); out.append(" "); out.append(" ") }
                    else { out.append("\""); out.append("\""); out.append("\"") }
                    i = source.index(after: n2)
                    while i < end {
                        if source[i] == "\"" {
                            let a = source.index(after: i)
                            let b = a < end ? source.index(after: a) : end
                            if a < end && source[a] == "\"" && b < end && source[b] == "\"" {
                                if blankStrings { out.append(" "); out.append(" "); out.append(" ") }
                                else { out.append("\""); out.append("\""); out.append("\"") }
                                i = source.index(after: b)
                                break
                            }
                        }
                        if source[i] == "\n" { out.append("\n") }
                        else if blankStrings { out.append(" ") } else { out.append(source[i]) }
                        i = source.index(after: i)
                    }
                    continue
                }
                if blankStrings { out.append(" ") } else { out.append("\"") }
                i = source.index(after: i)
                var escaped = false
                while i < end {
                    let ch = source[i]
                    if ch == "\n" { break }
                    if escaped {
                        if blankStrings { out.append(" ") } else { out.append(ch) }
                        escaped = false
                        i = source.index(after: i)
                        continue
                    }
                    if ch == "\\" {
                        if blankStrings { out.append(" ") } else { out.append(ch) }
                        escaped = true
                        i = source.index(after: i)
                        continue
                    }
                    if ch == "\"" {
                        if blankStrings { out.append(" ") } else { out.append(ch) }
                        i = source.index(after: i)
                        break
                    }
                    if blankStrings { out.append(" ") } else { out.append(ch) }
                    i = source.index(after: i)
                }
                continue
            }
            out.append(c)
            i = source.index(after: i)
        }
        return out
    }

    // MARK: - Words / regex

    static func containsWord(_ haystack: String, _ word: String) -> Bool {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }

    static func matchesRegex(_ haystack: String, pattern: String) -> Bool {
        haystack.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Focus pairing (paired, either order)

    private struct ChainMod {
        let name: String
        let argsContent: String?
        let hasParen: Bool
        let dotIndex: String.Index
        let endIndex: String.Index
        let nested: [String]
    }

    static func focusablePairFailures(in source: String) -> [String] {
        let clean = stripped(source)
        return focusablePairFailures(inClean: clean)
    }

    private static func focusablePairFailures(inClean clean: String) -> [String] {
        let localLines = clean.components(separatedBy: "\n")
        var failures: [String] = []
        for chain in modifierChains(in: clean) {
            let focusables = chain.filter { $0.name == "focusable" && $0.hasParen }
            if focusables.isEmpty { continue }
            let hasValid = chain.contains {
                $0.name == "focusEffectDisabled" && $0.hasParen && isValidSuppressionArgs($0.argsContent)
            }
            // Conservative: any explicit false/unknown-arg suppression rejects the
            // chain even with another valid present. No last-modifier-wins claim.
            let hasInvalid = chain.contains {
                $0.name == "focusEffectDisabled" && $0.hasParen && !isValidSuppressionArgs($0.argsContent)
            }
            if !hasValid || hasInvalid {
                for f in focusables {
                    let line = clean.prefix(upTo: f.dotIndex).filter { $0 == "\n" }.count + 1
                    let excerpt: String = {
                        if line >= 1 && line <= localLines.count {
                            return localLines[line - 1].trimmingCharacters(in: .whitespaces)
                        }
                        return ""
                    }()
                    failures.append("line \(line): .focusable without .focusEffectDisabled in same chain (\(excerpt))")
                }
            }
        }
        // Traverse nested closures/arguments as independent chains, never
        // borrowing outer or sibling suppression.
        for nested in nestedModifierContents(in: clean) {
            failures += focusablePairFailures(inClean: nested)
        }
        return failures
    }

    private static func isValidSuppressionArgs(_ args: String?) -> Bool {
        guard let args else { return false }
        let t = args.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "true"
    }

    private static func nestedModifierContents(in clean: String) -> [String] {
        var out: [String] = []
        var idx = clean.startIndex
        while idx < clean.endIndex {
            guard clean[idx] == "." else {
                idx = clean.index(after: idx)
                continue
            }
            guard let mod = parseModifier(at: idx, in: clean) else {
                idx = clean.index(after: idx)
                continue
            }
            out += mod.nested
            idx = mod.endIndex
            if idx == mod.dotIndex { idx = clean.index(after: idx) }
        }
        return out
    }

    private static func modifierChains(in clean: String) -> [[ChainMod]] {
        var chains: [[ChainMod]] = []
        var current: [ChainMod] = []
        var currentEnd: String.Index?
        var idx = clean.startIndex
        while idx < clean.endIndex {
            guard clean[idx] == "." else {
                idx = clean.index(after: idx)
                continue
            }
            guard let mod = parseModifier(at: idx, in: clean) else {
                idx = clean.index(after: idx)
                continue
            }
            if let end = currentEnd, !current.isEmpty {
                let gap = clean[end..<mod.dotIndex]
                if gap.allSatisfy({ $0.isWhitespace }) {
                    current.append(mod)
                } else {
                    chains.append(current)
                    current = [mod]
                }
            } else if current.isEmpty {
                current = [mod]
            } else {
                chains.append(current)
                current = [mod]
            }
            currentEnd = mod.endIndex
            idx = mod.endIndex
            if idx == mod.dotIndex { idx = clean.index(after: idx) }
        }
        if !current.isEmpty { chains.append(current) }
        return chains
    }

    private static func parseModifier(at dot: String.Index, in clean: String) -> ChainMod? {
        var j = clean.index(after: dot)
        while j < clean.endIndex && clean[j].isWhitespace { j = clean.index(after: j) }
        guard j < clean.endIndex && (clean[j].isLetter || clean[j] == "_") else { return nil }
        var k = j
        while k < clean.endIndex && (clean[k].isLetter || clean[k].isNumber || clean[k] == "_") {
            k = clean.index(after: k)
        }
        let name = String(clean[j..<k])
        var m = k
        while m < clean.endIndex && clean[m].isWhitespace { m = clean.index(after: m) }
        var hasParen = false
        var args: String? = nil
        var end = k
        var nested: [String] = []
        if m < clean.endIndex && clean[m] == "(" {
            hasParen = true
            guard let after = indexAfterMatchingParen(in: clean, openAt: m) else {
                return ChainMod(name: name, argsContent: "", hasParen: true, dotIndex: dot, endIndex: clean.endIndex, nested: [])
            }
            let innerStart = clean.index(after: m)
            let innerEnd = clean.index(before: after)
            if innerStart <= innerEnd {
                args = String(clean[innerStart..<innerEnd])
            } else {
                args = ""
            }
            if let args, args.contains(".") {
                nested.append(args)
            }
            end = after
            var t = end
            while t < clean.endIndex && clean[t].isWhitespace { t = clean.index(after: t) }
            end = t
            // Trailing closures belong to this modifier; their contents are skipped
            // for chaining but collected as independent nested chains.
            while true {
                var u = end
                while u < clean.endIndex && clean[u].isWhitespace { u = clean.index(after: u) }
                guard u < clean.endIndex && clean[u] == "{" else { break }
                guard let afterBrace = indexAfterMatchingBrace(in: clean, openAt: u) else {
                    end = clean.endIndex
                    break
                }
                let innerStart = clean.index(after: u)
                let innerEnd = clean.index(before: afterBrace)
                if innerStart <= innerEnd {
                    nested.append(String(clean[innerStart..<innerEnd]))
                } else {
                    nested.append("")
                }
                end = afterBrace
            }
        } else {
            // Bare `.name` without call: only trailing closures could follow.
            var t = m
            var sawBrace = false
            while true {
                var u = t
                while u < clean.endIndex && clean[u].isWhitespace { u = clean.index(after: u) }
                guard u < clean.endIndex && clean[u] == "{" else { break }
                guard let afterBrace = indexAfterMatchingBrace(in: clean, openAt: u) else {
                    t = clean.endIndex
                    break
                }
                let innerStart = clean.index(after: u)
                let innerEnd = clean.index(before: afterBrace)
                if innerStart <= innerEnd {
                    nested.append(String(clean[innerStart..<innerEnd]))
                } else {
                    nested.append("")
                }
                t = afterBrace
                sawBrace = true
            }
            if sawBrace { end = t } else { end = k }
        }
        return ChainMod(name: name, argsContent: args, hasParen: hasParen, dotIndex: dot, endIndex: end, nested: nested)
    }

    // MARK: - ScrollView nesting

    static func scrollViewBodies(in source: String) -> [String] {
        let clean = stripped(source)
        var bodies: [String] = []
        var idx = clean.startIndex
        while idx < clean.endIndex {
            guard let found = clean[idx...].range(of: "ScrollView") else { break }
            let start = found.lowerBound
            let afterName = found.upperBound
            let beforeOK: Bool = {
                if start == clean.startIndex { return true }
                let b = clean.index(before: start)
                let ch = clean[b]
                return !(ch.isLetter || ch.isNumber || ch == "_")
            }()
            let afterOK: Bool = {
                if afterName == clean.endIndex { return true }
                let ch = clean[afterName]
                return !(ch.isLetter || ch.isNumber || ch == "_")
            }()
            if !beforeOK || !afterOK {
                idx = afterName
                continue
            }
            var j = afterName
            while j < clean.endIndex && clean[j].isWhitespace { j = clean.index(after: j) }
            if j < clean.endIndex && clean[j] == "(" {
                guard let after = indexAfterMatchingParen(in: clean, openAt: j) else {
                    idx = clean.index(after: j)
                    continue
                }
                j = after
                while j < clean.endIndex && clean[j].isWhitespace { j = clean.index(after: j) }
            }
            guard j < clean.endIndex && clean[j] == "{" else {
                if j < clean.endIndex { idx = clean.index(after: j) } else { idx = j }
                continue
            }
            guard let afterBrace = indexAfterMatchingBrace(in: clean, openAt: j) else {
                idx = clean.index(after: j)
                continue
            }
            let bodyStart = clean.index(after: j)
            let bracePos = clean.index(before: afterBrace)
            if bodyStart <= bracePos {
                bodies.append(String(clean[bodyStart..<bracePos]))
            } else {
                bodies.append("")
            }
            idx = afterBrace
        }
        return bodies
    }

    /// Content-column ScrollView bodies for HubInspectorPage.body: ScrollViews
    /// before `HubDesignSystem.Palette.separator` (whitespace tolerant).
    /// Inspector ScrollViews after the separator are excluded. Shared by source
    /// suites and regression fixtures.
    static func inspectorContentScrollBodies(in source: String) -> [String] {
        let clean = stripped(source)
        let region = contentColumnRegion(in: clean)
        return scrollViewBodies(in: String(region))
    }

    private static func contentColumnRegion(in clean: String) -> Substring {
        let bodyStart: String.Index = {
            if let r = clean.range(of: "\\bvar\\s+body\\b", options: .regularExpression) {
                return r.lowerBound
            }
            return clean.startIndex
        }()
        let afterBody = clean[bodyStart...]
        if let sep = afterBody.range(of: "HubDesignSystem\\s*\\.\\s*Palette\\s*\\.\\s*separator", options: .regularExpression) {
            return clean[bodyStart..<sep.lowerBound]
        }
        return clean[bodyStart...]
    }

    // MARK: - Ownership (shared predicates)

    struct PropertyDecl {
        let wrapper: String
        let name: String
        let type: String
    }

    static func propertyDeclarations(in strippedText: String) -> [PropertyDecl] {
        var out: [PropertyDecl] = []
        var search = strippedText.startIndex
        while search < strippedText.endIndex {
            guard let at = strippedText[search...].firstIndex(of: "@") else { break }
            var w = strippedText.index(after: at)
            while w < strippedText.endIndex && strippedText[w].isWhitespace { w = strippedText.index(after: w) }
            guard w < strippedText.endIndex && (strippedText[w].isLetter || strippedText[w] == "_") else {
                search = strippedText.index(after: at)
                continue
            }
            var wEnd = w
            while wEnd < strippedText.endIndex && (strippedText[wEnd].isLetter || strippedText[wEnd].isNumber || strippedText[wEnd] == "_") {
                wEnd = strippedText.index(after: wEnd)
            }
            let wrapper = String(strippedText[w..<wEnd])
            let nextAt: String.Index = {
                if let n = strippedText[wEnd...].firstIndex(of: "@") { return n }
                return strippedText.endIndex
            }()
            var sliceEnd = nextAt
            for stop in [";", "{", "}"] {
                if let r = strippedText[wEnd..<nextAt].range(of: stop), r.lowerBound < sliceEnd {
                    sliceEnd = r.lowerBound
                }
            }
            var slice = String(strippedText[wEnd..<sliceEnd])
            if slice.count > 500 { slice = String(slice.prefix(500)) }
            if let varRange = slice.range(of: "\\bvar\\b", options: .regularExpression) {
                let prefix = String(slice[slice.startIndex..<varRange.lowerBound])
                let blocked = prefix.range(of: "\\b(func|struct|class|enum|let)\\b", options: .regularExpression) != nil
                if !blocked {
                    let tail = String(slice[varRange.lowerBound...])
                    // Anchor to the FIRST var and bind to its declaration: only a
                    // leading `var ...` may match, so a later typed declaration
                    // cannot satisfy an earlier inferred one.
                    if let m = tail.range(of: "\\Avar\\s+(\\w+)\\s*:\\s*(\\w+)", options: .regularExpression) {
                        let cap = String(tail[m])
                        let parts = cap.components(separatedBy: CharacterSet(charactersIn: ": \t\n")).filter { !$0.isEmpty && $0 != "var" }
                        if parts.count >= 2 {
                            out.append(PropertyDecl(wrapper: wrapper, name: parts[0], type: parts[1]))
                        }
                    } else if let m2 = tail.range(of: "\\Avar\\s+(\\w+)\\s*=\\s*(\\w+)\\s*\\(", options: .regularExpression) {
                        let cap = String(tail[m2])
                        let toks = cap.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && $0 != "var" }
                        if toks.count >= 2 {
                            out.append(PropertyDecl(wrapper: wrapper, name: toks[0], type: toks[1]))
                        }
                    }
                }
            }
            search = wEnd
        }
        return out
    }

    static func declaresObservedObject(ofType type: String, in strippedText: String) -> Bool {
        propertyDeclarations(in: strippedText).contains { $0.wrapper == "ObservedObject" && $0.type == type }
    }

    static func declaresStateObject(ofType type: String, in strippedText: String) -> Bool {
        propertyDeclarations(in: strippedText).contains { $0.wrapper == "StateObject" && $0.type == type }
    }

    static func observedPropertyNames(ofType type: String, in strippedText: String) -> [String] {
        propertyDeclarations(in: strippedText).filter { $0.wrapper == "ObservedObject" && $0.type == type }.map { $0.name }
    }

    static func hasStateObjectInit(wrapping type: String, in strippedText: String) -> Bool {
        let pattern = "\\bStateObject\\s*\\(\\s*wrappedValue\\s*:\\s*" + NSRegularExpression.escapedPattern(for: type) + "\\b"
        return strippedText.range(of: pattern, options: .regularExpression) != nil
    }

    static func hasUnderscoreStateObjectInit(for names: [String], in strippedText: String) -> Bool {
        for n in names {
            let pattern = "_\\s*" + NSRegularExpression.escapedPattern(for: n) + "\\s*=\\s*StateObject\\b"
            if strippedText.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }

    static func unexpectedObservedTypes(in strippedText: String, allowed: Set<String>) -> [String] {
        let watched: Set<String> = ["StateObject", "ObservedObject", "State", "EnvironmentObject"]
        return propertyDeclarations(in: strippedText)
            .filter { watched.contains($0.wrapper) && !allowed.contains($0.type) }
            .map { "\($0.wrapper):\($0.type)" }
    }

    static func hasCompositionDefaultAppStorage(in text: String) -> Bool {
        text.range(of: "\\.defaultAppStorage\\s*\\(\\s*composition\\.userDefaults\\s*\\)", options: .regularExpression) != nil
    }

    static func hasHubChromeMaterialTitleInset(in text: String) -> Bool {
        text.range(of: "\\.hubChromeMaterial\\s*\\(\\s*extendAboveBy\\s*:\\s*titleRowInset\\s*\\)", options: .regularExpression) != nil
    }

    // MARK: - Bracket matching (same-type depth; stripped text has no strings/comments)

    private static func indexAfterMatchingParen(in s: String, openAt: String.Index) -> String.Index? {
        guard openAt < s.endIndex && s[openAt] == "(" else { return nil }
        var depth = 0
        var i = openAt
        while i < s.endIndex {
            if s[i] == "(" { depth += 1 }
            else if s[i] == ")" {
                depth -= 1
                if depth == 0 { return s.index(after: i) }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func indexAfterMatchingBrace(in s: String, openAt: String.Index) -> String.Index? {
        guard openAt < s.endIndex && s[openAt] == "{" else { return nil }
        var depth = 0
        var i = openAt
        while i < s.endIndex {
            if s[i] == "{" { depth += 1 }
            else if s[i] == "}" {
                depth -= 1
                if depth == 0 { return s.index(after: i) }
            }
            i = s.index(after: i)
        }
        return nil
    }
}
