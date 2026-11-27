@testable import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaParse
import XCTest

final class FlowNoiseClassifierTests: XCTestCase {
    func testSwiftNodesAreClassifiedByTheNoiseTheirChangeAmountsTo() throws {
        let nodes = try changedNodes(
            old: """
            func total(a: Int, b: Int) -> Int {
                var sum = a /* start */ + b
                sum = sum + 1;
                self.log(sum)
                if (sum > 10) { return sum }
                if limit == sum { return 0 }
                return sum * 2
            }
            """,
            new: """
            func total(a: Int, b: Int) -> Int {
                var sum = a + b
                sum += 1
                log(sum)
                if sum > 10 { return sum }
                if sum == limit { return 0 }
                return sum * 3
            }
            """,
            path: "Total.swift",
            language: .swift
        )
        XCTAssertEqual(nodes["var sum = a + b"]?.noise, .formatting)
        XCTAssertEqual(nodes["log(sum)"]?.noise, .optionalSyntax)
        XCTAssertEqual(nodes["if sum > 10"]?.noise, .optionalSyntax)
        XCTAssertEqual(nodes["sum += 1"]?.noise, .rewrite)
        XCTAssertEqual(nodes["if sum == limit"]?.noise, .rewrite)
        XCTAssertEqual(nodes["return sum * 3"]?.state, .modified)
        XCTAssertNil(nodes["return sum * 3"]?.noise)
        XCTAssertTrue(nodes.values.allSatisfy { $0.state == .modified || $0.noise == nil })
    }

    func testTypeScriptDropsSemicolonsAndThisButPythonKeepsSelf() throws {
        let script = try changedNodes(
            old: "function run(items) {\n  this.reset();\n  const count = items.length;\n  return count + 1;\n}\n",
            new: "function run(items) {\n  reset()\n  const count = items.length\n  return count + 2\n}\n",
            path: "run.ts",
            language: .typescript
        )
        XCTAssertEqual(script["reset()"]?.noise, .optionalSyntax)
        XCTAssertEqual(script["const count = items.length"]?.noise, .optionalSyntax)
        XCTAssertNil(script["return count + 2"]?.noise)

        let python = try changedNodes(
            old: "def run(self, items):\n    self.reset()\n    return len(items)\n",
            new: "def run(self, items):\n    reset()\n    return len(items) + 1\n",
            path: "run.py",
            language: .python
        )
        XCTAssertEqual(python["reset()"]?.state, .modified)
        XCTAssertNil(python["reset()"]?.noise, "Python's self. is how an attribute is reached")
    }

    func testAnEditPastTheLabelsTruncationPointIsAModification() throws {
        let prefix = "let message = [" + (1 ... 40).map { "\"item\($0)\"" }.joined(separator: ", ")
        let nodes = try analyze(
            old: "func make() -> [String] {\n    \(prefix), \"old\"]\n    return message\n}\n",
            new: "func make() -> [String] {\n    \(prefix), \"new\"]\n    return message\n}\n",
            path: "Make.swift",
            language: .swift
        ).functionDeltas.first?.nodes ?? []
        let statement = try XCTUnwrap(nodes.first { $0.new?.label.hasPrefix("let message") == true })
        XCTAssertEqual(statement.old?.label, statement.new?.label, "Both labels are truncated before the edit")
        XCTAssertEqual(statement.state, .modified)
        XCTAssertNil(statement.noise)
    }

    func testOptionalSyntaxRules() {
        let swift = LanguageProfile.profile(for: .swift).noise
        func stripped(_ tokens: [String], condition: Bool = false) -> [String] {
            FlowNoiseClassifier.withoutOptionalSyntax(tokens, rules: swift, isCondition: condition)
        }
        XCTAssertEqual(stripped(["f", "(", "a", ",", ")"]), ["f", "(", "a", ")"])
        XCTAssertEqual(stripped(["[", "a", ",", "b", "]"]), ["[", "a", ",", "b", "]"])
        XCTAssertEqual(
            stripped(["self", ".", "x", "=", "other", ".", "self", ".", "y"]),
            ["x", "=", "other", ".", "self", ".", "y"]
        )
        XCTAssertEqual(stripped(["self"]), ["self"], "A bare receiver is kept")
        XCTAssertEqual(
            stripped(["(", "a", ")", "&&", "(", "b", ")"], condition: true),
            ["(", "a", ")", "&&", "(", "b", ")"]
        )
        XCTAssertEqual(stripped(["(", "a", "&&", "b", ")"], condition: true), ["a", "&&", "b"])
        XCTAssertEqual(
            stripped(["(", "a", "&&", "b", ")"]),
            ["(", "a", "&&", "b", ")"],
            "Only conditions lose their parentheses"
        )
    }

    func testRewriteRulesOnlyAcceptTokenProvableEquivalences() {
        let swift = LanguageProfile.profile(for: .swift).noise
        func level(_ old: [String], _ new: [String]) -> FlowNoiseLevel? {
            FlowNoiseClassifier.level(old: old, new: new, rules: swift, isCondition: false)
        }
        XCTAssertEqual(
            level(["a", "=", "a", "-", "(", "b", "+", "c", ")"], ["a", "-=", "(", "b", "+", "c", ")"]),
            .rewrite
        )
        XCTAssertNil(
            level(["a", "=", "a", "-", "b", "+", "c"], ["a", "-=", "b", "+", "c"]),
            "a -= b + c is not a = a - b + c"
        )
        XCTAssertNil(level(["a", "=", "b", "+", "1"], ["a", "+=", "1"]))
        XCTAssertEqual(level(["x", "!==", "y"], ["y", "!==", "x"]), .rewrite)
        XCTAssertNil(level(["x", "<", "y"], ["y", "<", "x"]))
        XCTAssertNil(level(["x", "==", "y", "+", "1"], ["y", "+", "1", "==", "x"]), "Only a lone comparison commutes")
        XCTAssertEqual(level(["a"], ["a"]), .formatting)
        XCTAssertEqual(FlowNoiseClassifier.tokens(of: SyntaxNode.leaf("  x  "), comments: []), ["x"])
    }

    func testEveryLanguageHasNoiseRules() {
        for language in SourceLanguage.allCases {
            XCTAssertTrue(LanguageProfile.profile(for: language).noise.commentKinds.contains("comment"), "\(language)")
        }
        XCTAssertTrue(LanguageProfile.profile(for: .python).noise.optionalReceivers.isEmpty)
        XCTAssertTrue(LanguageProfile.profile(for: .go).noise.optionalReceivers.isEmpty)
    }

    // MARK: Helpers

    /// The changed nodes keyed by their new label.
    private func changedNodes(
        old: String,
        new: String,
        path: String,
        language: SourceLanguage
    ) throws -> [String: FlowNodeDelta] {
        let nodes = try analyze(old: old, new: new, path: path, language: language).functionDeltas.flatMap(\.nodes)
        return Dictionary(
            nodes.compactMap { node in node.new.map { ($0.label, node) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func analyze(
        old: String,
        new: String,
        path: String,
        language: SourceLanguage
    ) throws -> RevisionFlowDeltaReport {
        let base = RevisionIdentity("base")
        let target = RevisionIdentity("target")
        return try FlowDeltaAnalyzer().analyze(RevisionComparison(base: base, target: target, files: [FileComparison(
            old: SourceSnapshot(path: path, revision: base, language: language, text: old),
            new: SourceSnapshot(path: path, revision: target, language: language, text: new)
        )]))
    }
}

private extension SyntaxNode {
    static func leaf(_ text: String) -> SyntaxNode {
        let location = SourceLocation(utf8Offset: 0, utf16Offset: 0, line: 0, utf16Column: 0)
        return SyntaxNode(
            id: StableID(rawValue: "leaf"),
            kind: "identifier",
            range: SourceRange(start: location, end: location),
            text: text,
            children: []
        )
    }
}
