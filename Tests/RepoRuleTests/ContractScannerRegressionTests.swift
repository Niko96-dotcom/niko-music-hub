import AppCore
import XCTest

/// Regression snippets for the strengthened source guards.
///
/// Each test states what the ORIGINAL brittle guard did (count / textual
/// order / exact-string) and what the new scanner requires. Snippets are
/// inline strings so formatting variants (whitespace, comments, intervening
/// modifiers, balanced closures) are exercised without touching production.
/// Ownership cases use the SAME shared `SourceLex` predicates as the source
/// suites so they cannot diverge.
final class ContractScannerRegressionTests: XCTestCase {
    // MARK: - Helpers replicating the original brittle guards

    /// Original focusable guard: strip only full-line `//`, count lines.
    private func oldCountPasses(_ source: String) -> Bool {
        let lines: [String] = source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("//") ? "" : String(line)
        }
        let focusables = lines.filter { $0.contains(".focusable(") }.count
        let disabled = lines.filter { $0.contains(".focusEffectDisabled()") }.count
        return disabled >= focusables
    }

    /// Original layout guard: textual order (`ScrollView {` before `live`).
    private func oldOrderPasses(_ source: String) -> Bool {
        guard let bodyRange = source.range(of: "public var body: some View") else { return false }
        let content = String(source[bodyRange.lowerBound...])
        guard let scroll = content.range(of: "ScrollView {"),
              let live = content.range(of: "live") else { return false }
        return scroll.lowerBound < live.lowerBound
    }

    // MARK: - Focus: accepted formatting variants

    func testFocusableAcceptsSimplePair() {
        let snippet = #"Text("a").focusable().focusEffectDisabled()"#
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty)
    }

    func testFocusableAcceptsWhitespaceVariants() {
        let snippet = """
        Text("a")
            .focusable ( )
            .focusEffectDisabled ( )
        """
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "whitespace around ., name and () must be accepted")
    }

    func testFocusableAcceptsCommentBetweenModifiers() {
        let snippet = """
        Text("a")
            .focusable()
            // No system-blue ring; quiet ring is drawn by the component.
            .focusEffectDisabled()
        """
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "line comments between modifiers must be accepted")
    }

    func testFocusableAcceptsInterveningModifiers() {
        let snippet = """
        Button("x") { doit() }
            .buttonStyle(.plain)
            .focusable()
            .focused($isFocused)
            .onHover { _ in }
            .focusEffectDisabled()
            .overlay { Text("ring") }
        """
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "intervening modifiers must be accepted")
    }

    func testFocusableAcceptsBalancedClosureBetween() {
        let snippet = """
        Text("a")
            .focusable()
            .overlay {
                VStack {
                    Text("inner")
                }
            }
            .focusEffectDisabled()
        """
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "balanced closures between must be skipped, not end the chain")
    }

    func testFocusableAcceptsSuppressionBeforeFocusable() {
        let snippet = """
        Text("a")
            .focusEffectDisabled()
            .focusable()
        """
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "paired, either order: suppression before focusable must pass")
    }

    func testFocusableAcceptsTrueArgument() {
        let snippet = #"Text("a").focusable().focusEffectDisabled(true)"#
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "focusEffectDisabled(true) must pass")
    }

    func testFocusableAcceptsMultipleFocusablesWithOneSuppression() {
        let snippet = """
        Text("a")
            .focusable()
            .focusable()
            .focusEffectDisabled()
        """
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "one suppression covers focusables in the same chain")
    }

    // MARK: - Focus: sibling / spoof / arg rejections

    func testFocusableRejectsSiblingSuppressionWhenCountsMatch() {
        let sibling = """
        VStack {
            Text("a")
                .focusable()
            Text("b")
                .focusEffectDisabled()
        }
        """
        XCTAssertTrue(oldCountPasses(sibling), "precondition: old count guard passes the sibling snippet")
        XCTAssertFalse(
            SourceLex.focusablePairFailures(in: sibling).isEmpty,
            "sibling .focusEffectDisabled must NOT satisfy .focusable"
        )
    }

    func testFocusableRejectsLineCommentSpoof() {
        let snippet = """
        Text("a")
            .focusable() // .focusEffectDisabled()
        """
        XCTAssertTrue(oldCountPasses(snippet), "precondition: old guard counts the commented suppression")
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "commented suppression must not pair")
    }

    func testFocusableRejectsBlockCommentSpoof() {
        let snippet = """
        Text("a")
            .focusable()
            /* .focusEffectDisabled() */
        """
        XCTAssertTrue(oldCountPasses(snippet), "precondition: old guard counts the block-commented suppression")
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "block-commented suppression must not pair")
    }

    func testFocusableRejectsNestedBlockCommentSpoof() {
        let snippet = """
        Text("a")
            .focusable()
            /* outer /* .focusEffectDisabled() */ still outer */
        """
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "nested block-commented suppression must not pair")
    }

    func testFocusableRejectsStringLiteralSpoof() {
        let snippet = """
        Text("a")
            .focusable()
        Text(".focusEffectDisabled()")
        """
        XCTAssertTrue(oldCountPasses(snippet), "precondition: old guard counts the string literal")
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "string-literal suppression must not pair")
    }

    func testFocusableRejectsRawStringSpoof() {
        let snippet = """
        Text("a")
            .focusable()
        Text(#".focusEffectDisabled()"#)
        """
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "raw-string suppression must not pair")
    }

    func testFocusableRejectsFalseArgument() {
        let snippet = #"Text("a").focusable().focusEffectDisabled(false)"#
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "focusEffectDisabled(false) must not pair")
    }

    func testFocusableRejectsUnknownArgument() {
        let snippet = #"Text("a").focusable().focusEffectDisabled(isEnabled)"#
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "dynamic suppression arg must not pair")
    }

    func testFocusableRejectsBareReferenceWithoutCall() {
        let snippet = """
        Text("a")
            .focusable()
            .focusEffectDisabled
        """
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "bare reference without () is not a call")
    }

    func testFocusableRejectsNestedChildSuppression() {
        let snippet = """
        Text("a")
            .focusable()
            .overlay {
                Text("inner")
                    .focusEffectDisabled()
            }
        """
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "suppression inside a nested closure is a child, not the same chain")
    }

    func testFocusableRejectsBareFocusable() {
        let snippet = """
        Text("a")
            .focusable()
        """
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty)
    }

    func testFocusableRejectsNestedUnpairedFocusableInOverlay() {
        let snippet = """
        Text("outer").overlay {
            Text("inner").focusable()
        }
        """
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "unpaired nested focusable in overlay closure must fail")
    }

    func testFocusableAcceptsIndependentlyPairedNested() {
        let snippet = """
        Text("outer").overlay {
            Text("inner").focusable().focusEffectDisabled()
        }
        """
        XCTAssertTrue(SourceLex.focusablePairFailures(in: snippet).isEmpty, "independently paired nested chain must pass")
    }

    func testFocusableRejectsNestedWhenOuterSuppressionExists() {
        let snippet = """
        Text("outer").focusable().focusEffectDisabled().overlay {
            Text("inner").focusable()
        }
        """
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "outer suppression must not satisfy nested guard")
    }

    func testFocusableRejectsNestedUnpairedInBackground() {
        let snippet = #"Text("outer").background(content: Text("inner").focusable())"#
        XCTAssertFalse(SourceLex.focusablePairFailures(in: snippet).isEmpty, "unpaired nested focusable in background args must fail")
    }

    func testFocusableRejectsConflictingEmptyThenFalse() {
        let first = #"Text("a").focusable().focusEffectDisabled().focusEffectDisabled(false)"#
        XCTAssertFalse(SourceLex.focusablePairFailures(in: first).isEmpty, "valid + explicit false must conservatively fail")
        let second = #"Text("a").focusable().focusEffectDisabled(false).focusEffectDisabled()"#
        XCTAssertFalse(SourceLex.focusablePairFailures(in: second).isEmpty, "false + valid (reverse order) must conservatively fail")
    }

    func testFocusableRejectsConflictingTrueThenFalse() {
        let first = #"Text("a").focusable().focusEffectDisabled(true).focusEffectDisabled(false)"#
        XCTAssertFalse(SourceLex.focusablePairFailures(in: first).isEmpty, "true + false must conservatively fail")
        let second = #"Text("a").focusable().focusEffectDisabled(false).focusEffectDisabled(true)"#
        XCTAssertFalse(SourceLex.focusablePairFailures(in: second).isEmpty, "false + true (reverse order) must conservatively fail")
    }

    // MARK: - Layout: nesting, not order

    func testLayoutAcceptsLiveAndListNestedInScrollView() {
        let snippet = """
        public var body: some View {
            ScrollView {
                VStack {
                    live
                    list
                }
            }
        }
        """
        let bodies = SourceLex.inspectorContentScrollBodies(in: snippet)
        XCTAssertTrue(bodies.contains { SourceLex.containsWord($0, "live") && SourceLex.containsWord($0, "list") })
    }

    func testLayoutRejectsOrderedButUnnestedLiveList() {
        let snippet = """
        public var body: some View {
            ScrollView {
                Text("scroll")
            }
            live
            list
        }
        """
        XCTAssertTrue(oldOrderPasses(snippet), "precondition: old order guard passes unnested snippet")
        let bodies = SourceLex.inspectorContentScrollBodies(in: snippet)
        XCTAssertFalse(
            bodies.contains { SourceLex.containsWord($0, "live") && SourceLex.containsWord($0, "list") },
            "live/list outside the ScrollView body must fail nesting"
        )
    }

    func testLayoutRejectsLiveOutsideScrollView() {
        let snippet = """
        ScrollView {
            list
        }
        live
        """
        let bodies = SourceLex.inspectorContentScrollBodies(in: snippet)
        XCTAssertFalse(bodies.contains { SourceLex.containsWord($0, "live") && SourceLex.containsWord($0, "list") })
    }

    func testLayoutRejectsInspectorOnlyScrollAfterSeparator() {
        let snippet = """
        public var body: some View {
            VStack {
                header
                primary
            }
            HubDesignSystem.Palette.separator
            VStack {
                ScrollView {
                    VStack {
                        live
                        list
                    }
                }
            }
        }
        """
        let bodies = SourceLex.inspectorContentScrollBodies(in: snippet)
        XCTAssertFalse(
            bodies.contains { SourceLex.containsWord($0, "live") && SourceLex.containsWord($0, "list") },
            "live/list in the inspector ScrollView after the separator must not satisfy the content-column check"
        )
    }

    func testLayoutAcceptsContentAndInspectorScrolls() {
        let snippet = """
        public var body: some View {
            VStack {
                ScrollView {
                    VStack {
                        live
                        list
                    }
                }
            }
            HubDesignSystem . Palette . separator
            VStack {
                ScrollView {
                    inspector
                }
            }
        }
        """
        let bodies = SourceLex.inspectorContentScrollBodies(in: snippet)
        XCTAssertTrue(
            bodies.contains { SourceLex.containsWord($0, "live") && SourceLex.containsWord($0, "list") },
            "content-column live/list must pass even with an inspector ScrollView after a whitespace-tolerant separator"
        )
    }

    // MARK: - Ownership: same shared predicates as source suites

    func testOwnershipAcceptsRenamedObservedViewModel() {
        let snippet = "struct V: View { @ObservedObject var model: DownloaderViewModel }"
        XCTAssertTrue(SourceLex.declaresObservedObject(ofType: "DownloaderViewModel", in: SourceLex.stripped(snippet)))
    }

    func testOwnershipAcceptsSpacingVariants() {
        let snippet = "@ObservedObject   private   var   viewModel  :  DownloaderViewModel"
        XCTAssertTrue(SourceLex.declaresObservedObject(ofType: "DownloaderViewModel", in: SourceLex.stripped(snippet)))
    }

    func testOwnershipAcceptsMultilineWrapperVar() {
        let snippet = "@ObservedObject\n    private var\n        viewModel: DownloaderViewModel"
        XCTAssertTrue(SourceLex.declaresObservedObject(ofType: "DownloaderViewModel", in: SourceLex.stripped(snippet)))
    }

    func testOwnershipRejectsStateObjectOfSameTypeButAllowsUnrelated() {
        let same = "@StateObject private var model: DownloaderViewModel"
        XCTAssertTrue(SourceLex.declaresStateObject(ofType: "DownloaderViewModel", in: SourceLex.stripped(same)))
        let mixed = """
        @ObservedObject var viewModel: DownloaderViewModel
        @StateObject private var cache: BoardProjectionCache
        """
        let clean = SourceLex.stripped(mixed)
        XCTAssertTrue(SourceLex.declaresObservedObject(ofType: "DownloaderViewModel", in: clean))
        XCTAssertFalse(SourceLex.declaresStateObject(ofType: "DownloaderViewModel", in: clean))
        XCTAssertTrue(SourceLex.declaresStateObject(ofType: "BoardProjectionCache", in: clean))
    }

    func testOwnershipIgnoresCommentedObserved() {
        let snippet = "// @ObservedObject private var viewModel: DownloaderViewModel"
        XCTAssertFalse(SourceLex.declaresObservedObject(ofType: "DownloaderViewModel", in: SourceLex.stripped(snippet)))
    }

    func testOwnershipComputedShellSessionIsNotObservation() {
        let snippet = "private var shellSession: HubShellSession { composition.shellSession }"
        let clean = SourceLex.stripped(snippet)
        XCTAssertTrue(SourceLex.propertyDeclarations(in: clean).filter { $0.wrapper == "StateObject" || $0.wrapper == "ObservedObject" }.isEmpty)
    }

    func testOwnershipRejectsObservedShellSessionUnderAnyName() {
        let snippet = "@ObservedObject var session: HubShellSession"
        XCTAssertTrue(SourceLex.declaresObservedObject(ofType: "HubShellSession", in: SourceLex.stripped(snippet)))
    }

    func testOwnershipRejectsStateObjectInitWrappingViewModel() {
        let snippet = "_viewModel = StateObject(wrappedValue: DownloaderViewModel())"
        let clean = SourceLex.stripped(snippet)
        XCTAssertTrue(SourceLex.hasStateObjectInit(wrapping: "DownloaderViewModel", in: clean))
        XCTAssertTrue(SourceLex.hasUnderscoreStateObjectInit(for: ["viewModel"], in: clean))
        let direct = "self.viewModel = viewModel"
        XCTAssertFalse(SourceLex.hasStateObjectInit(wrapping: "DownloaderViewModel", in: SourceLex.stripped(direct)))
    }

    func testOwnershipStateObjectInitIgnoresUnrelatedAttributeBeforeObserved() {
        // Grok exact repro: a @StateObject ATTRIBUTE on an unrelated cache must
        // not read as constructing a StateObject wrapping the observed type.
        let snippet = """
        @StateObject private var cache = BoardProjectionCache()
        @ObservedObject private var viewModel: DownloaderViewModel
        """
        let clean = SourceLex.stripped(snippet)
        XCTAssertFalse(
            SourceLex.hasStateObjectInit(wrapping: "DownloaderViewModel", in: clean),
            "unrelated @StateObject attribute must not count as StateObject(wrappedValue: DownloaderViewModel)"
        )
        let direct = "_viewModel = StateObject(wrappedValue: DownloaderViewModel())"
        XCTAssertTrue(SourceLex.hasStateObjectInit(wrapping: "DownloaderViewModel", in: SourceLex.stripped(direct)))
    }

    func testOwnershipExactRegressionFullScreenStateFollowedByShellSession() {
        let snippet = """
        @StateObject private var fullScreenState = HubFullScreenState()
        private let composition: AppComposition
        private var shellSession: HubShellSession { composition.shellSession }
        """
        let clean = SourceLex.stripped(snippet)
        let decls = SourceLex.propertyDeclarations(in: clean)
        XCTAssertTrue(decls.contains { $0.wrapper == "StateObject" && $0.name == "fullScreenState" && $0.type == "HubFullScreenState" })
        XCTAssertFalse(decls.contains { $0.wrapper == "StateObject" && $0.type == "HubShellSession" }, "later typed declaration must not be attributed to the earlier @StateObject")
        XCTAssertFalse(decls.contains { ["StateObject", "ObservedObject", "State"].contains($0.wrapper) && $0.name == "shellSession" })
        XCTAssertEqual(
            SourceLex.unexpectedObservedTypes(in: clean, allowed: ["MenuBarExtraState", "AppAppearanceController", "HubFullScreenState"]),
            [],
            "exact app shape must not report StateObject:HubShellSession"
        )
        let initSnippet = "_menuBarExtra = StateObject(wrappedValue: composition.shellSession.menuBarExtra)"
        let initClean = SourceLex.stripped(initSnippet)
        XCTAssertTrue(SourceLex.propertyDeclarations(in: initClean).isEmpty, "StateObject init without @var must not be a property declaration")
        XCTAssertFalse(SourceLex.propertyDeclarations(in: initClean).contains { $0.name == "shellSession" })
    }

    func testOwnershipTypedFirstVarBoundsLaterDeclarations() {
        let snippet = """
        @StateObject private var foo: Foo
        private var bar: Bar { baz }
        """
        let clean = SourceLex.stripped(snippet)
        let decls = SourceLex.propertyDeclarations(in: clean)
        XCTAssertTrue(decls.contains { $0.wrapper == "StateObject" && $0.name == "foo" && $0.type == "Foo" })
        XCTAssertFalse(decls.contains { $0.type == "Bar" }, "later typed var must not be attributed to the earlier wrapper")
    }

    func testOwnershipInferredFirstVarBoundsLaterDeclarations() {
        let snippet = """
        @ObservedObject private var model = SomeModel()
        private let other: Other
        private var later: Later { thing }
        """
        let clean = SourceLex.stripped(snippet)
        let decls = SourceLex.propertyDeclarations(in: clean)
        XCTAssertTrue(decls.contains { $0.wrapper == "ObservedObject" && $0.name == "model" && $0.type == "SomeModel" })
        XCTAssertFalse(decls.contains { $0.type == "Later" })
    }

    func testOwnershipStorageArgumentExact() {
        XCTAssertTrue(SourceLex.hasCompositionDefaultAppStorage(in: ".defaultAppStorage(composition.userDefaults)"))
        XCTAssertTrue(SourceLex.hasCompositionDefaultAppStorage(in: ".defaultAppStorage( composition.userDefaults )"))
        XCTAssertFalse(SourceLex.hasCompositionDefaultAppStorage(in: ".defaultAppStorage(UserDefaults.standard)"))
        XCTAssertFalse(SourceLex.hasCompositionDefaultAppStorage(in: ".defaultAppStorage()"))
        XCTAssertTrue(SourceLex.hasHubChromeMaterialTitleInset(in: ".hubChromeMaterial(extendAboveBy: titleRowInset)"))
        XCTAssertFalse(SourceLex.hasHubChromeMaterialTitleInset(in: ".hubChromeMaterial()"))
    }
}
