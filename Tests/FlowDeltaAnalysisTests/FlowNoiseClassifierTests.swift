@testable import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaParse
import XCTest

final class FlowNoiseClassifierTests: XCTestCase {
    func testSemicolonsInLiteralsAndEmptyStatementsStayVisible() throws {
        for (path, language) in [("view.jsx", SourceLanguage.javascript), ("view.tsx", .typescript)] {
            try assertVisibleBehavior(
                old: "function View() { return <p>;</p>; }",
                new: "function View() { return <p></p>; }",
                path: path,
                language: language
            )
        }
        try assertVisibleBehavior(
            old: "function make(ready, work) { return () => { if (ready); work(); }; }",
            new: "function make(ready, work) { return () => { if (ready) work(); }; }",
            path: "make.js",
            language: .javascript
        )
        try assertVisibleBehavior(
            old: "function make(value) { return () => { return\nvalue; }; }",
            new: "function make(value) { return () => { return value; }; }",
            path: "make.js",
            language: .javascript
        )
    }

    func testAnOptionalTerminatorDoesNotMakeReorderedControlFlowCosmetic() throws {
        let report = try analyze(
            old: "function run() { first(); second(); }",
            new: "function run() { second(); first() }",
            path: "run.js",
            language: .javascript
        )
        let function = try XCTUnwrap(report.functionDeltas.first)
        XCTAssertTrue(function.nodes.contains { $0.noise == .optionalSyntax })
        XCTAssertTrue(function.edges.contains { $0.state != .retained })
        XCTAssertEqual(report.concerns?.map(\.kind), [.behavioral])
    }

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
        XCTAssertEqual(nodes["log(sum)"]?.state, .modified)
        XCTAssertNil(nodes["log(sum)"]?.noise, "self.log and log can name different functions")
        XCTAssertEqual(nodes["if sum > 10"]?.noise, .optionalSyntax)
        XCTAssertEqual(nodes["sum += 1"]?.noise, .rewrite)
        XCTAssertEqual(nodes["if sum == limit"]?.noise, .rewrite)
        XCTAssertEqual(nodes["return sum * 3"]?.state, .modified)
        XCTAssertNil(nodes["return sum * 3"]?.noise)
        XCTAssertTrue(nodes.values.allSatisfy { $0.state == .modified || $0.noise == nil })
    }

    func testScriptsDropSemicolonsButKeepThisAndPythonKeepsSelf() throws {
        let script = try changedNodes(
            old: "function run(items) {\n  this.reset();\n  const count = items.length;\n  return count + 1;\n}\n",
            new: "function run(items) {\n  reset()\n  const count = items.length\n  return count + 2\n}\n",
            path: "run.ts",
            language: .typescript
        )
        XCTAssertEqual(script["reset()"]?.state, .modified)
        XCTAssertNil(script["reset()"]?.noise, "this.reset() calls a member; reset() resolves a lexical binding")
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

    func testSwiftSelfStaysBecauseALocalNameCanShadowAProperty() throws {
        let nodes = try changedNodes(
            old: "struct Box {\n    var x = 1\n    func read(_ x: Int) -> Int {\n        return self.x\n    }\n}\n",
            new: "struct Box {\n    var x = 1\n    func read(_ x: Int) -> Int {\n        return x\n    }\n}\n",
            path: "Box.swift",
            language: .swift
        )
        XCTAssertEqual(nodes["return x"]?.state, .modified)
        XCTAssertNil(nodes["return x"]?.noise, "The parameter x shadows the property self.x")
    }

    func testJSXTextComparesAsItRenders() throws {
        func noise(_ old: String, _ new: String, path: String, language: SourceLanguage) throws -> FlowNoiseLevel? {
            let nodes = try changedNodes(old: old, new: new, path: path, language: language)
            let node = try XCTUnwrap(nodes.values.first { $0.new?.label.hasPrefix("return") == true }, "\(nodes.keys)")
            XCTAssertEqual(node.state, .modified)
            return node.noise
        }
        func component(_ markup: String) -> String {
            "function View() {\n  return \(markup)\n}\n"
        }
        XCTAssertNil(
            try noise(component("<pre> a </pre>"), component("<pre>a</pre>"), path: "a.jsx", language: .javascript),
            "Spaces inside a line of JSX text render"
        )
        XCTAssertNil(try noise(
            component("<p>Total: {n}</p>"),
            component("<p>Total:{n}</p>"),
            path: "a.tsx",
            language: .typescript
        ))
        let reindented = try changedNodes(
            old: component("<p>\n      Hello   world\n    </p>"),
            new: component("<p>\n  Hello   world\n</p>"),
            path: "a.jsx",
            language: .javascript
        )
        XCTAssertEqual(
            reindented.values.first { $0.new?.label.hasPrefix("return") == true }?.state,
            .retained,
            "Whitespace touching a line break does not render"
        )
        XCTAssertEqual(
            try noise(component("<p>Hi</p>;"), component("<p>Hi</p>"), path: "a.tsx", language: .typescript),
            .optionalSyntax
        )
        XCTAssertEqual(FlowNoiseClassifier.renderedJSXText("\n  one  \n\t two\n  "), "one two")
        XCTAssertEqual(FlowNoiseClassifier.renderedJSXText(" a "), " a ")
        XCTAssertEqual(FlowNoiseClassifier.renderedJSXText("\n   \n"), "")
        XCTAssertEqual(FlowNoiseClassifier.renderedJSXText("a\r\nb"), "a b")
    }

    func testCommasThatChangeAValueAreNeverOptional() throws {
        func noise(_ old: String, _ new: String, path: String, language: SourceLanguage) throws -> FlowNoiseLevel? {
            let nodes = try changedNodes(old: old, new: new, path: path, language: language)
            let node = try XCTUnwrap(nodes.values.first { $0.new?.label.hasPrefix("return") == true }, "\(nodes.keys)")
            XCTAssertEqual(node.state, .modified)
            return node.noise
        }
        func python(_ value: String) -> String {
            "def make(value, other, items, key):\n    return \(value)\n"
        }
        func script(_ value: String) -> String {
            "function make(a) {\n  return \(value)\n}\n"
        }
        XCTAssertNil(
            try noise(python("(value,)"), python("(value)"), path: "a.py", language: .python),
            "A singleton tuple"
        )
        XCTAssertNil(try noise(python("items[key,]"), python("items[key]"), path: "a.py", language: .python))
        XCTAssertEqual(
            try noise(python("(value, other,)"), python("(value, other)"), path: "a.py", language: .python),
            .optionalSyntax
        )
        XCTAssertEqual(
            try noise(python("len(items,)"), python("len(items)"), path: "a.py", language: .python),
            .optionalSyntax
        )
        XCTAssertEqual(
            try noise(python("[value,]"), python("[value]"), path: "a.py", language: .python),
            .optionalSyntax
        )
        XCTAssertNil(try noise(script("[,]"), script("[]"), path: "a.js", language: .javascript), "An array hole")
        XCTAssertNil(try noise(script("[a,,]"), script("[a,]"), path: "a.js", language: .javascript))
        XCTAssertEqual(try noise(script("[a,]"), script("[a]"), path: "a.js", language: .javascript), .optionalSyntax)
    }

    func testStringLiteralsCompareExactly() throws {
        func noise(_ old: String, _ new: String, path: String, language: SourceLanguage) throws -> FlowNoiseLevel? {
            let nodes = try changedNodes(old: old, new: new, path: path, language: language)
            let node = try XCTUnwrap(nodes.values.first { $0.new?.label.hasPrefix("return") == true }, "\(nodes.keys)")
            XCTAssertEqual(node.state, .modified)
            return node.noise
        }
        func script(_ value: String) -> String {
            "function label() {\n  return \(value)\n}\n"
        }
        XCTAssertNil(try noise(script("\" a \""), script("\"a\""), path: "a.js", language: .javascript))
        XCTAssertNil(try noise(script("\";\""), script("\"\""), path: "a.ts", language: .typescript))
        XCTAssertNil(try noise(script("`a ${b}`"), script("`a  ${b}`"), path: "a.js", language: .javascript))
        XCTAssertEqual(
            try noise(script("\"a\";"), script("\"a\""), path: "a.js", language: .javascript),
            .optionalSyntax
        )
        XCTAssertNil(try noise(
            "func label() -> String {\n    return \"a  b\"\n}\n",
            "func label() -> String {\n    return \"a b\"\n}\n",
            path: "A.swift",
            language: .swift
        ))
        XCTAssertNil(try noise(
            "def label():\n    return 'x;'\n",
            "def label():\n    return 'x'\n",
            path: "a.py",
            language: .python
        ))
        XCTAssertNil(try noise(
            "package a\n\nfunc label() string {\n\treturn \" a \"\n}\n",
            "package a\n\nfunc label() string {\n\treturn \"a\"\n}\n",
            path: "a.go",
            language: .go
        ))
        let commentedGo = try noise(
            "package a\n\nfunc label(n int) string {\n\tn++\n\treturn /* raw */ `a`\n}\n",
            "package a\n\nfunc label(n int) string {\n\tn--\n\treturn `a`\n}\n",
            path: "a.go",
            language: .go
        )
        XCTAssertEqual(commentedGo, .formatting, "Text around a literal is still formatting")
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
        // No built-in language has an optional receiver; a host's own rules still can.
        let swift = LanguageNoiseRules(
            commentKinds: ["comment"],
            optionalTokens: [";"],
            optionalReceivers: ["self"],
            allowsTrailingCommas: true
        )
        func stripped(_ tokens: [String], condition: Bool = false) -> [String] {
            FlowNoiseClassifier.withoutOptionalSyntax(
                tokens.map { FlowNoiseClassifier.Token($0) },
                rules: swift,
                isCondition: condition
            ).map(\.text)
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
            FlowNoiseClassifier.level(
                old: old.map { FlowNoiseClassifier.Token($0) },
                new: new.map { FlowNoiseClassifier.Token($0) },
                rules: swift,
                isCondition: false
            )
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
        XCTAssertEqual(FlowNoiseClassifier.tokens(of: SyntaxNode.leaf("  x  "), rules: swift).map(\.text), ["x"])
    }

    func testEveryLanguageHasNoiseRules() {
        for language in SourceLanguage.allCases {
            XCTAssertTrue(LanguageProfile.profile(for: language).noise.commentKinds.contains("comment"), "\(language)")
        }
        for language in SourceLanguage.allCases {
            XCTAssertTrue(LanguageProfile.profile(for: language).noise.optionalReceivers.isEmpty, "\(language)")
        }
        XCTAssertTrue(LanguageProfile.profile(for: .javascript).noise.literalKinds.contains("jsx_text"))
        XCTAssertTrue(LanguageProfile.profile(for: .typescript).noise.literalKinds.contains("jsx_text"))
        for language in SourceLanguage.allCases {
            XCTAssertFalse(LanguageProfile.profile(for: language).noise.literalKinds.isEmpty, "\(language)")
        }
        XCTAssertEqual(
            LanguageProfile.profile(for: .python).noise.singletonTupleKinds,
            ["tuple", "tuple_pattern", "subscript"]
        )
    }

    // MARK: Helpers

    private func assertVisibleBehavior(
        old: String,
        new: String,
        path: String,
        language: SourceLanguage
    ) throws {
        let report = try analyze(old: old, new: new, path: path, language: language)
        let filtered = FlowNoiseFilter.apply(.hideCosmetic, to: report)
        XCTAssertTrue(filtered.functionDeltas.flatMap(\.nodes).contains { $0.state == .modified && $0.noise == nil })
        XCTAssertEqual(report.concerns?.map(\.kind), [.behavioral])
        XCTAssertFalse(FlowWalkthrough.steps(for: report, policy: .hideCosmetic).isEmpty)
    }

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
