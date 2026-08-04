import FlowDeltaCore
import FlowDeltaIndexStore
import Foundation
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
        let enricher = try IndexStoreCallGraphEnricher(configuration: configuration, readonly: false)

        let enriched = try enricher.enrich(graph, sourceFiles: [source.path])

        XCTAssertTrue(enriched.edges.contains { $0.caller == caller && $0.callee == helper })
        XCTAssertTrue(enriched.edges.contains { $0.caller == caller && $0.callee == recursive })
        XCTAssertEqual(enriched.edges.filter { $0.id == existingEdge.id }.count, 1)
        XCTAssertFalse(enriched.nodes.contains { $0.name == "recursive" && $0.external })
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
}
