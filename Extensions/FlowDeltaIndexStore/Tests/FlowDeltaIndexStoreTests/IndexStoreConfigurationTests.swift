import FlowDeltaCore
import FlowDeltaIndexStore
import Foundation
import IndexStoreDB
import XCTest

final class IndexStoreConfigurationTests: XCTestCase {
    func testEnvironmentConfigurationRequiresAllThreePaths() {
        XCTAssertNil(IndexStoreConfiguration(environment: [:]))
        XCTAssertNil(IndexStoreConfiguration(environment: [
            IndexStoreConfiguration.storePathEnvironmentKey: "/tmp/index/store"
        ]))

        let configuration = IndexStoreConfiguration(environment: [
            IndexStoreConfiguration.storePathEnvironmentKey: "/tmp/index/store",
            IndexStoreConfiguration.databasePathEnvironmentKey: "/tmp/index/database",
            IndexStoreConfiguration.libraryPathEnvironmentKey: "/tmp/libIndexStore.dylib"
        ])

        XCTAssertEqual(configuration?.storePath, "/tmp/index/store")
        XCTAssertEqual(configuration?.databasePath, "/tmp/index/database")
        XCTAssertEqual(configuration?.libraryPath, "/tmp/libIndexStore.dylib")
    }

    func testEnricherLoadsARealSwiftIndexAndMergesCalls() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDeltaIndexStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("index", isDirectory: true)
        let database = root.appendingPathComponent("database", isDirectory: true)
        let source = root.appendingPathComponent("Fixture.swift")
        let executable = root.appendingPathComponent("Fixture")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
        try Data("""
        func helper(_ value: Int) -> Int { value + 1 }
        func recursive(_ value: Int) -> Int { value == 0 ? 0 : recursive(value - 1) }
        func caller() { print(helper(41)); _ = recursive(2) }
        caller()
        """.utf8).write(to: source, options: .atomic)

        let swiftCompiler = try run("/usr/bin/xcrun", arguments: ["--find", "swiftc"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sdk = try run("/usr/bin/xcrun", arguments: ["--sdk", "macosx", "--show-sdk-path"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let architecture = try run("/usr/bin/uname", arguments: ["-m"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let library = URL(fileURLWithPath: swiftCompiler)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib/libIndexStore.dylib")
        try run(swiftCompiler, arguments: [
            "-sdk", sdk,
            "-target", "\(architecture)-apple-macos15.0",
            "-index-store-path", store.path,
            "-module-name", "Fixture",
            source.path,
            "-o", executable.path
        ])

        let caller = StableID(namespace: "test", components: ["caller"])
        let helper = StableID(namespace: "test", components: ["helper"])
        let recursive = StableID(namespace: "test", components: ["recursive"])
        let existingEdge = CallGraphEdge(caller: caller, callee: helper, state: .retained)
        let graph = CallGraph(
            nodes: [
                CallGraphNode(id: caller, name: "Fixture.caller()", state: .retained),
                CallGraphNode(id: helper, name: "helper(_:)", state: .retained),
                CallGraphNode(id: recursive, name: "recursive(_:)", state: .retained),
                CallGraphNode(
                    id: StableID(namespace: "test", components: ["print"]),
                    name: "print(_:separator:terminator:)",
                    state: .retained,
                    external: true
                )
            ],
            edges: [existingEdge]
        )
        let configuration = IndexStoreConfiguration(
            storePath: store.path,
            databasePath: database.path,
            libraryPath: library.path
        )
        let enricher = try IndexStoreCallGraphEnricher(configuration: configuration)

        let enriched = try enricher.enrich(graph, sourceFiles: [source.path])

        XCTAssertTrue(enriched.edges.contains { $0.caller == caller && $0.callee == helper })
        XCTAssertTrue(enriched.edges.contains { $0.caller == caller && $0.callee == recursive })
        XCTAssertEqual(enriched.edges.filter { $0.id == existingEdge.id }.count, 1)
        XCTAssertFalse(enriched.nodes.contains { $0.name == "recursive" && $0.external })
    }

    func testEnricherUsesUSRDefinitionLocationsToDistinguishOverloads() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDeltaIndexStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("index", isDirectory: true)
        let database = root.appendingPathComponent("database", isDirectory: true)
        let source = root.appendingPathComponent("Overloads.swift")
        let executable = root.appendingPathComponent("Overloads")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try Data("""
        func helper(_ value: Int) -> Int { value + 1 }
        func helper(_ value: String) -> String { value + "!" }
        func caller() { print(helper(41)) }
        caller()
        """.utf8).write(to: source, options: .atomic)

        let swiftCompiler = try run("/usr/bin/xcrun", arguments: ["--find", "swiftc"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sdk = try run("/usr/bin/xcrun", arguments: ["--sdk", "macosx", "--show-sdk-path"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let architecture = try run("/usr/bin/uname", arguments: ["-m"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let library = URL(fileURLWithPath: swiftCompiler)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib/libIndexStore.dylib")
        try run(swiftCompiler, arguments: [
            "-sdk", sdk,
            "-target", "\(architecture)-apple-macos15.0",
            "-index-store-path", store.path,
            "-module-name", "Overloads",
            source.path,
            "-o", executable.path
        ])

        let integer = StableID(namespace: "test", components: ["helper-int"])
        let string = StableID(namespace: "test", components: ["helper-string"])
        let caller = StableID(namespace: "test", components: ["caller"])
        let graph = CallGraph(
            nodes: [
                CallGraphNode(
                    id: integer,
                    name: "helper(_ value: Int)",
                    path: source.path,
                    range: sourceRange(line: 0),
                    state: .retained
                ),
                CallGraphNode(
                    id: string,
                    name: "helper(_ value: String)",
                    path: source.path,
                    range: sourceRange(line: 1),
                    state: .retained
                ),
                CallGraphNode(
                    id: caller,
                    name: "caller()",
                    path: source.path,
                    range: sourceRange(line: 2),
                    state: .retained
                )
            ],
            edges: []
        )
        let indexLibrary = try IndexStoreLibrary(dylibPath: library.path)
        let indexDatabase = try IndexStoreDB(
            storePath: store.path,
            databasePath: database.path,
            library: indexLibrary,
            waitUntilDoneInitializing: true,
            readonly: false
        )
        let indexedSummary = indexDatabase.symbolOccurrences(inFilePath: source.path).map {
            "\($0.symbol.name) \($0.roles) \($0.location.path):\($0.location.line)"
        }
        let enricher = IndexStoreCallGraphEnricher(database: indexDatabase)

        let enriched = try enricher.enrich(graph, sourceFiles: [source.path])

        XCTAssertTrue(
            enriched.edges.contains { $0.caller == caller && $0.callee == integer },
            "Index: \(indexedSummary) • Nodes: \(enriched.nodes) • Edges: \(enriched.edges)"
        )
        XCTAssertFalse(enriched.edges.contains { $0.caller == caller && $0.callee == string })
    }

    func testEnricherToleratesCollidingExternalSimpleNames() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowDeltaIndexStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("index", isDirectory: true)
        let database = root.appendingPathComponent("database", isDirectory: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)

        let swiftCompiler = try run("/usr/bin/xcrun", arguments: ["--find", "swiftc"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let library = URL(fileURLWithPath: swiftCompiler)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("lib/libIndexStore.dylib")

        let first = StableID(namespace: "test", components: ["ModuleA.foo"])
        let second = StableID(namespace: "test", components: ["ModuleB.foo"])
        let graph = CallGraph(
            nodes: [
                CallGraphNode(id: first, name: "ModuleA.foo()", state: .retained, external: true),
                CallGraphNode(id: second, name: "ModuleB.foo()", state: .retained, external: true)
            ],
            edges: []
        )
        let enricher = try IndexStoreCallGraphEnricher(
            storePath: store.path,
            databasePath: database.path,
            libraryPath: library.path,
            readonly: false
        )

        let enriched = try enricher.enrich(graph, sourceFiles: [])

        XCTAssertEqual(Set(enriched.nodes.map(\.id)), [first, second])
        XCTAssertTrue(enriched.edges.isEmpty)
    }

    func testEnricherReportsInvalidIndexStoreLibrary() {
        XCTAssertThrowsError(try IndexStoreCallGraphEnricher(
            storePath: "/tmp/missing-index",
            databasePath: "/tmp/missing-database",
            libraryPath: "/tmp/missing-libIndexStore.dylib"
        ))
    }

    @discardableResult
    private func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "IndexStoreConfigurationTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: String(data: errorData, encoding: .utf8) ?? "<non-UTF-8 error>"
                ]
            )
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private func sourceRange(line: Int) -> SourceRange {
        SourceRange(
            start: SourceLocation(utf8Offset: 0, utf16Offset: 0, line: line, utf16Column: 0),
            end: SourceLocation(utf8Offset: 1, utf16Offset: 1, line: line, utf16Column: 1)
        )
    }
}
