import FlowDeltaCore
import Foundation
import IndexStoreDB
import OSLog

public struct IndexStoreConfiguration: Equatable, Sendable {
    public static let storePathEnvironmentKey = "FLOWDELTA_INDEXSTORE_PATH"
    public static let databasePathEnvironmentKey = "FLOWDELTA_INDEXDATABASE_PATH"
    public static let libraryPathEnvironmentKey = "FLOWDELTA_LIBINDEXSTORE_PATH"

    public let storePath: String
    public let databasePath: String
    public let libraryPath: String

    public init(storePath: String, databasePath: String, libraryPath: String) {
        self.storePath = storePath
        self.databasePath = databasePath
        self.libraryPath = libraryPath
    }

    public init?(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let storePath = environment[Self.storePathEnvironmentKey],
              let databasePath = environment[Self.databasePathEnvironmentKey],
              let libraryPath = environment[Self.libraryPathEnvironmentKey],
              !storePath.isEmpty,
              !databasePath.isEmpty,
              !libraryPath.isEmpty
        else { return nil }
        self.init(storePath: storePath, databasePath: databasePath, libraryPath: libraryPath)
    }
}

public final class IndexStoreCallGraphEnricher: CallGraphEnriching, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "IndexStore")
    private let database: IndexStoreDB
    private let library: IndexStoreLibrary?
    private let lock = NSLock()

    public init(database: IndexStoreDB) {
        self.database = database
        library = nil
    }

    public init(
        storePath: String,
        databasePath: String,
        libraryPath: String,
        readonly: Bool = true
    ) throws {
        let library = try IndexStoreLibrary(dylibPath: libraryPath)
        self.library = library
        database = try IndexStoreDB(
            storePath: storePath,
            databasePath: databasePath,
            library: library,
            waitUntilDoneInitializing: true,
            readonly: readonly
        )
    }

    public convenience init(configuration: IndexStoreConfiguration, readonly: Bool = true) throws {
        try self.init(
            storePath: configuration.storePath,
            databasePath: configuration.databasePath,
            libraryPath: configuration.libraryPath,
            readonly: readonly
        )
    }

    public func enrich(_ graph: CallGraph, sourceFiles: [String]) throws -> CallGraph {
        lock.lock()
        defer { lock.unlock() }
        var nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        var edges = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
        let internalByName = Dictionary(grouping: graph.nodes.filter { !$0.external }) { simpleName($0.name) }
        var externalByName = Dictionary(uniqueKeysWithValues: graph.nodes.filter(\.external).map {
            (simpleName($0.name), $0.id)
        })

        func nodeID(named name: String) -> StableID {
            let simple = simpleName(name)
            if let matches = internalByName[simple], matches.count == 1, let match = matches.first {
                return match.id
            }
            if let existing = externalByName[simple] {
                return existing
            }
            let id = StableID(namespace: "indexstore-call-node", components: [simple])
            externalByName[simple] = id
            nodes[id] = CallGraphNode(id: id, name: simple, state: .retained, external: true)
            return id
        }

        for path in sourceFiles.sorted() {
            for occurrence in database.symbolOccurrences(inFilePath: path) where occurrence.roles.contains(.call) {
                guard let callerRelation = occurrence.relations.first(where: {
                    $0.roles.contains(.calledBy) || $0.roles.contains(.containedBy)
                }) else { continue }
                let caller = nodeID(named: callerRelation.symbol.name)
                let callee = nodeID(named: occurrence.symbol.name)
                guard caller != callee else { continue }
                let edge = CallGraphEdge(caller: caller, callee: callee, state: .retained)
                edges[edge.id] = edges[edge.id] ?? edge
            }
        }
        let enriched = CallGraph(nodes: Array(nodes.values), edges: Array(edges.values))
        Self.logger.notice(
            "IndexStoreDB enriched call graph from \(sourceFiles.count) files to \(enriched.nodes.count) nodes and \(enriched.edges.count) edges"
        )
        return enriched
    }

    private func simpleName(_ name: String) -> String {
        let withoutParameters = name.split(separator: "(", maxSplits: 1).first.map(String.init) ?? name
        return withoutParameters.split(separator: ".").last.map(String.init) ?? withoutParameters
    }
}
