import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaFlow
@testable import FlowDeltaParse
import XCTest

final class SyntaxDefUseTests: XCTestCase {
    func testPythonBindingRulesFollowAssignmentsLoopsAliasesAndScopes() throws {
        let edges = try dataEdges(path: "cart.py", language: .python, text: """
        def total(self, items, *args, scale=2, **kwargs):
            global counter
            count = 0
            for index, item in enumerate(items):
                count += item * scale
            with open(self.path) as handle:
                data = handle.read()
            try:
                value = int(data)
            except ValueError as error:
                value = len(error.args)
            if (size := len(args)) > 1:
                count = size
            squares = [n * n for n in items if n > count]
            report(key=count, other=value)
            counter = count
            print(counter)
            return squares, kwargs, f"{value}"
        """)
        for (symbol, definition, use) in [
            ("item", "loop index, item", "count += item * scale"),
            ("count", "count = 0", "count += item * scale"),
            ("count", "count += item * scale", "squares = ["),
            ("scale", "Entry", "count += item * scale"),
            ("self", "Entry", "with open(self.path)"),
            ("data", "with open(self.path)", "value = int(data)"),
            ("error", "except ValueError as error", "value = len(error.args)"),
            ("args", "Entry", "if (size := len(args)) > 1"),
            ("size", "if (size := len(args)) > 1", "count = size"),
            ("items", "Entry", "squares = ["),
            ("value", "value = int(data)", "report(key=count, other=value)"),
            ("kwargs", "Entry", "return squares"),
            ("value", "value = len(error.args)", "return squares")
        ] {
            XCTAssertTrue(edges.contains { $0.matches(symbol, definition, use) }, "\(symbol): \(definition) → \(use)")
        }
        let symbols = Set(edges.map(\.symbol))
        XCTAssertTrue(symbols.isDisjoint(with: ["counter", "n", "key", "other", "index", "handle"]), "\(symbols)")
    }

    func testGoBindingRulesFollowShortDeclarationsRangesHeadersAndClosures() throws {
        let edges = try dataEdges(path: "cart.go", language: .go, text: """
        func (c *Cart) Total(ctx context.Context, a, b int, xs ...int) (sum int, err error) {
            total, _ := c.compute(ctx)
            var x, y int = a, b
            for i, v := range xs {
                total += v * i
            }
            if n := len(xs); n > x {
                y = n
            }
            item := Item{Count: total, Name: y}
            fn := func(k int) int { inner := k + total; return inner }
            sum = fn(item.Count)
            switch z := x + y; z {
            case b:
                err = nil
            }
            return
        }
        """)
        for (symbol, definition, use) in [
            ("c", "Entry", "total, _ := c.compute(ctx)"),
            ("ctx", "Entry", "total, _ := c.compute(ctx)"),
            ("a", "Entry", "var x, y int = a, b"),
            ("b", "Entry", "case b"),
            ("xs", "Entry", "loop for i, v := range xs"),
            ("i", "loop for i, v := range xs", "total += v * i"),
            ("v", "loop for i, v := range xs", "total += v * i"),
            ("total", "total, _ := c.compute(ctx)", "total += v * i"),
            ("total", "total += v * i", "fn := func(k int)"),
            ("xs", "Entry", "if n > x"),
            ("x", "var x, y int = a, b", "if n > x"),
            ("n", "if n > x", "y = n"),
            ("y", "y = n", "item := Item{"),
            ("item", "item := Item{", "sum = fn(item.Count)"),
            ("fn", "fn := func(k int)", "sum = fn(item.Count)"),
            ("y", "y = n", "switch z")
        ] {
            XCTAssertTrue(edges.contains { $0.matches(symbol, definition, use) }, "\(symbol): \(definition) → \(use)")
        }
        let symbols = Set(edges.map(\.symbol))
        XCTAssertTrue(symbols.isDisjoint(with: ["_", "Count", "Name", "k", "inner", "int"]), "\(symbols)")
    }

    func testPythonScopesReadAndWriteTheEnclosingFunctionWhereTheLanguageSays() throws {
        let edges = try dataEdges(path: "scope.py", language: .python, function: "outer", text: """
        def outer(seed, xs, x):
            limit = 1
            def inner():
                global limit
                return limit
            fn = lambda value=seed: value
            same = [xs for xs in xs]
            items = [(last := n) for n in (x,)]
            x: int
            return limit, fn, same, items, last, x
        """)
        for (symbol, definition, use) in [
            ("limit", "limit = 1", "return limit"),
            ("seed", "Entry", "fn = lambda"),
            ("xs", "Entry", "same = ["),
            ("x", "Entry", "items = ["),
            ("last", "items = [", "return limit"),
            ("x", "Entry", "return limit")
        ] {
            XCTAssertTrue(edges.contains { $0.matches(symbol, definition, use) }, "\(symbol): \(definition) → \(use)")
        }
        XCTAssertFalse(edges.contains { $0.matches("x", "x: int", "return") }, "An annotation alone writes nothing")
        let symbols = Set(edges.map(\.symbol))
        XCTAssertTrue(symbols.isDisjoint(with: ["value", "n"]), "\(symbols)")
    }

    func testGoReadsNamedResultsMapKeysAndCapturesBeforeALocalDeclaration() throws {
        let edges = try dataEdges(path: "scope.go", language: .go, text: """
        func outer(x int, k string) (n int) {
            n = 7
            counts := map[string]int{k: 1}
            point := Point{X: x}
            fn := func() int { x := x + 1; return x }
            use(counts, point, fn)
            return
        }
        """)
        for (symbol, definition, use) in [
            ("n", "n = 7", "return"),
            ("k", "Entry", "counts := map"),
            ("x", "Entry", "point := Point"),
            ("x", "Entry", "fn := func()")
        ] {
            XCTAssertTrue(edges.contains { $0.matches(symbol, definition, use) }, "\(symbol): \(definition) → \(use)")
        }
        XCTAssertFalse(edges.contains { $0.symbol == "X" }, "A struct field label is not a variable")
    }

    func testGoParameterNamesFallBackToTheDeclarationWithoutSyntaxMetadata() throws {
        func edges(_ text: String) throws -> [DataFlowEdge] {
            let snapshot = SourceSnapshot(path: "a.go", revision: RevisionIdentity("r"), language: .go, text: text)
            let parsed = try XCTUnwrap(
                SourceEntityExtractor().entities(in: SourceSyntaxParser().parse(snapshot)).first { $0.kind != .type }
            )
            let entity = SourceEntity(
                id: parsed.id,
                kind: parsed.kind,
                name: parsed.name,
                qualifiedName: parsed.qualifiedName,
                path: parsed.path,
                range: parsed.range,
                body: parsed.body
            )
            let graph = try SourceControlFlowBuilder().build(for: entity, language: .go)
            return try XCTUnwrap(DefUseBuilder().build(for: entity, graph: graph, language: .go)).edges
        }
        let named = try edges("func scale(n int, a, b float64) float64 {\n\treturn float64(n) * a * b\n}\n")
        XCTAssertEqual(Set(named.map(\.symbol)), ["n", "a", "b"])
        let unnamed = try edges("func scale(int, float64) float64 {\n\treturn 1\n}\n")
        XCTAssertTrue(unnamed.isEmpty, "Unnamed Go parameters are types")
    }

    func testParameterNamesComeFromTheDeclarationForPythonAndGo() throws {
        func parameters(_ text: String, _ path: String, _ language: SourceLanguage) throws -> [String]? {
            let snapshot = SourceSnapshot(path: path, revision: RevisionIdentity("r"), language: language, text: text)
            let tree = try SourceSyntaxParser().parse(snapshot)
            return SourceEntityExtractor().entities(in: tree).first { $0.kind != .type }?.parameterNames
        }
        XCTAssertEqual(
            try parameters("def run(self, a: int, *rest, b=1, c: str = \"\", **options):\n    pass\n", "a.py", .python),
            ["self", "a", "rest", "b", "c", "options"]
        )
        XCTAssertEqual(
            try parameters(
                "func (s *Server) Serve(ctx context.Context, a, b int, rest ...string) (n int, err error) {\n}\n",
                "a.go",
                .go
            ),
            ["s", "ctx", "a", "b", "rest", "n", "err"]
        )
        XCTAssertEqual(try parameters("func run(int, string) {\n}\n", "a.go", .go), [])
        XCTAssertEqual(try parameters("func (_ Server) Run(_ int) {\n}\n", "a.go", .go), [])
        XCTAssertNil(try parameters("func run(a: Int) {\n}\n", "a.swift", .swift))
        XCTAssertNil(LanguageProfile.profile(for: .typescript).binding)
    }

    // MARK: Helpers

    private struct Edge {
        let symbol: String
        let definition: String
        let use: String

        func matches(_ symbol: String, _ definition: String, _ use: String) -> Bool {
            self.symbol == symbol && self.definition.hasPrefix(definition) && self.use.hasPrefix(use)
        }
    }

    private func dataEdges(
        path: String,
        language: SourceLanguage,
        function name: String? = nil,
        text: String
    ) throws -> [Edge] {
        let target = RevisionIdentity("target")
        let report = try FlowDeltaAnalyzer().analyze(RevisionComparison(
            base: RevisionIdentity("base"),
            target: target,
            files: [FileComparison(
                old: nil,
                new: SourceSnapshot(path: path, revision: target, language: language, text: text)
            )]
        ))
        let function = try XCTUnwrap(report.functionDeltas.first { delta in
            name.map { delta.entityChange.new?.name == $0 } ?? true
        })
        let graph = try XCTUnwrap(function.dataFlow?.newGraph)
        let flow = try XCTUnwrap(function.newGraph)
        let labels = Dictionary(uniqueKeysWithValues: flow.nodes.map { (
            $0.id,
            $0.label.replacingOccurrences(of: "\n", with: " ")
        ) })
        return graph.edges.map { Edge(
            symbol: $0.symbol,
            definition: labels[$0.definition] ?? "",
            use: labels[$0.use] ?? ""
        ) }
    }
}
