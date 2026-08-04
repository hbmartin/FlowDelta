import FlowDeltaAnalysis
import FlowDeltaCore
import FlowDeltaFlow
@testable import FlowDeltaParse
import XCTest

final class ParserAndFlowTests: XCTestCase {
    func testSourceIndexPreservesUTF8AndUTF16Coordinates() {
        let text = "a🙂\nβ"
        let index = SourceIndex(text)
        let emoji = index.sourceRange(NSRange(location: 1, length: 2))
        let beta = index.sourceRange(NSRange(location: 4, length: 1))

        XCTAssertEqual(emoji.start.utf8Offset, 1)
        XCTAssertEqual(emoji.end.utf8Offset, 5)
        XCTAssertEqual(emoji.start.utf16Offset, 1)
        XCTAssertEqual(emoji.end.utf16Offset, 3)
        XCTAssertEqual(beta.start.line, 1)
        XCTAssertEqual(beta.start.utf16Column, 0)
    }

    func testExtractorDistinguishesOverloads() throws {
        let source = """
        struct Service {
            func load(value: Int) { print(value) }
            func load(value: String) { print(value) }
        }
        """
        let tree = try SwiftSyntaxParser().parse(snapshot(source))
        let methods = SwiftEntityExtractor().entities(in: tree).filter { $0.kind == .method }

        XCTAssertEqual(methods.count, 2)
        XCTAssertEqual(Set(methods.map(\.qualifiedName)).count, 2)
        XCTAssertEqual(Set(methods.map(\.id)).count, 2)
    }

    func testUnchangedSyntaxKeepsIdentityAcrossRevisions() throws {
        let source = "func stable(_ value: Int) -> Int { value + 1 }"
        let parser = SwiftSyntaxParser()
        let first = try parser.parse(snapshot(source, revision: "base"))
        let second = try parser.parse(snapshot(source, revision: "target"))

        XCTAssertEqual(first.root.id, second.root.id)
        XCTAssertEqual(first.root.descendants.map(\.id), second.root.descendants.map(\.id))
    }

    func testRepresentativeSwiftFunctionLowersMajorControlConstructs() throws {
        let source = try fixture("RepresentativeFlow")
        let analysis = try SwiftSourceAnalyzer().analyze(snapshot(source))
        let graph = try XCTUnwrap(analysis.graphs.values.first)
        let kinds = Set(graph.edges.map(\.kind))

        XCTAssertTrue(graph.nodes.contains { $0.kind == .condition })
        XCTAssertTrue(graph.nodes.contains { $0.kind == .switchCase })
        XCTAssertTrue(graph.nodes.contains { $0.kind == .catchBlock })
        XCTAssertTrue(
            graph.nodes.contains { $0.kind == .deferBlock },
            analysis.tree.root.descendants
                .filter { $0.text.contains("defer") }
                .map { "\($0.kind)=\($0.text)" }
                .joined(separator: " | ")
        )
        XCTAssertTrue(kinds.contains(.conditionTrue))
        XCTAssertTrue(kinds.contains(.conditionFalse))
        XCTAssertTrue(kinds.contains(.loopBack))
        XCTAssertTrue(kinds.contains(.continueFlow))
        XCTAssertTrue(kinds.contains(.breakFlow))
        XCTAssertTrue(kinds.contains(.returnFlow))
        XCTAssertTrue(kinds.contains(.throwFlow))
        XCTAssertTrue(kinds.contains(.deferredFlow))
        XCTAssertTrue(kinds.contains(.catchFlow))
    }

    func testRecoveredSyntaxProducesDiagnosticInsteadOfAborting() throws {
        let source = "func unfinished(_ value: Int) { let result = value + ; return }"
        let analysis = try SwiftSourceAnalyzer().analyze(snapshot(source))

        XCTAssertFalse(analysis.entities.isEmpty)
        XCTAssertTrue(analysis.diagnostics.contains { $0.code == .partialParse })
    }

    func testPerFunctionResourceLimitDegradesToDiagnostic() throws {
        let source = "func limited() { one(); two(); three(); four() }"
        let limits = AnalysisLimits(maximumFlowNodesPerFunction: 3)
        let analysis = try SwiftSourceAnalyzer().analyze(snapshot(source), limits: limits)

        XCTAssertTrue(analysis.graphs.isEmpty)
        XCTAssertTrue(analysis.diagnostics.contains { $0.code == .resourceLimit })
    }
}
