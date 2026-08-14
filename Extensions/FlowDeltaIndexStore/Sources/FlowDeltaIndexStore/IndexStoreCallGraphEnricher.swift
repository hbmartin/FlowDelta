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
        readonly: Bool = false
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

    public convenience init(configuration: IndexStoreConfiguration, readonly: Bool = false) throws {
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
        let internalNodes = graph.nodes.filter { !$0.external }
        let internalByCanonicalName = Dictionary(grouping: internalNodes) { canonicalName($0.name) }
        let internalBySimpleName = Dictionary(grouping: internalNodes) { simpleName($0.name) }
        var externalByCanonicalName = Dictionary(grouping: graph.nodes.filter(\.external)) {
            canonicalName($0.name)
        }
        var resolvedUSR: [String: StableID] = [:]

        func internalNode(at location: SymbolLocation) -> StableID? {
            let matches = internalNodes.filter { node in
                guard let path = node.path, let range = node.range else { return false }
                let indexedPath = URL(fileURLWithPath: location.path).resolvingSymlinksInPath().standardized.path
                let nodePath = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardized.path
                let pathMatches = indexedPath == nodePath || indexedPath.hasSuffix("/\(path)")
                let line = max(0, location.line - 1)
                return pathMatches && range.start.line <= line && line <= range.end.line
            }
            return matches.count == 1 ? matches.first?.id : nil
        }

        for path in sourceFiles.sorted() {
            for occurrence in database.symbolOccurrences(inFilePath: path)
                where occurrence.roles.contains(.definition) || occurrence.roles.contains(.declaration)
            {
                if let nodeID = internalNode(at: occurrence.location) {
                    resolvedUSR[occurrence.symbol.usr] = nodeID
                }
            }
        }

        func nodeID(for symbol: Symbol) -> StableID {
            if let existing = resolvedUSR[symbol.usr] {
                return existing
            }
            let definitions = database.occurrences(ofUSR: symbol.usr, roles: .definition)
                + database.occurrences(ofUSR: symbol.usr, roles: .declaration)
            for occurrence in definitions {
                if let match = internalNode(at: occurrence.location) {
                    resolvedUSR[symbol.usr] = match
                    return match
                }
            }
            let canonical = canonicalName(symbol.name)
            if let matches = internalByCanonicalName[canonical], matches.count == 1, let match = matches.first {
                resolvedUSR[symbol.usr] = match.id
                return match.id
            }
            let simple = simpleName(symbol.name)
            if let matches = internalBySimpleName[simple], matches.count == 1, let match = matches.first {
                resolvedUSR[symbol.usr] = match.id
                return match.id
            }
            if let existing = externalByCanonicalName[canonical]?.map(\.id).min() {
                resolvedUSR[symbol.usr] = existing
                return existing
            }
            let id = StableID(namespace: "indexstore-call-node", components: [symbol.usr])
            resolvedUSR[symbol.usr] = id
            let node = CallGraphNode(id: id, name: symbol.name, state: .retained, external: true)
            externalByCanonicalName[canonical, default: []].append(node)
            nodes[id] = node
            return id
        }

        for path in sourceFiles.sorted() {
            for occurrence in database.symbolOccurrences(inFilePath: path) where occurrence.roles.contains(.call) {
                guard let callerRelation = occurrence.relations.first(where: {
                    $0.roles.contains(.calledBy) || $0.roles.contains(.containedBy)
                }) else { continue }
                let caller = nodeID(for: callerRelation.symbol)
                let callee = nodeID(for: occurrence.symbol)
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

    private func canonicalName(_ name: String) -> String {
        name.filter { !$0.isWhitespace }
    }
}
