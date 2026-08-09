import FlowDeltaCore
import FlowDeltaParse
import Foundation
import OSLog

public struct SourceControlFlowBuilder: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Flow")

    public init() {}

    public func build(
        for entity: SourceEntity,
        language: SourceLanguage,
        limits: AnalysisLimits = .default
    ) throws -> ControlFlowGraph {
        if language == .swift {
            return try SwiftControlFlowBuilder().build(for: entity, limits: limits)
        }
        var builder = GenericControlFlowBuilder(
            entity: entity,
            profile: LanguageProfile.profile(for: language),
            limits: limits
        )
        let graph = try builder.build()
        Self.logger.debug(
            "Built \(language.displayName, privacy: .public) CFG for \(entity.qualifiedName, privacy: .public): \(graph.nodes.count) nodes, \(graph.edges.count) edges"
        )
        return graph
    }
}

private struct GenericPendingExit {
    let nodeID: StableID
    let edgeKind: FlowEdgeKind
    let label: String?

    static func open(_ id: StableID) -> GenericPendingExit {
        GenericPendingExit(nodeID: id, edgeKind: .fallthrough, label: nil)
    }
}

private struct GenericFlowContext {
    var breakTarget: StableID?
    var continueTarget: StableID?
}

private struct GenericControlFlowBuilder {
    let entity: SourceEntity
    let profile: LanguageProfile
    let limits: AnalysisLimits
    let entryID: StableID
    let exitID: StableID
    let errorExitID: StableID
    var nodes: [FlowNode] = []
    var edges: [FlowEdge] = []
    var sourceOrder = 0

    init(entity: SourceEntity, profile: LanguageProfile, limits: AnalysisLimits) {
        self.entity = entity
        self.profile = profile
        self.limits = limits
        entryID = StableID(namespace: "flow", components: [entity.id.rawValue, "entry"])
        exitID = StableID(namespace: "flow", components: [entity.id.rawValue, "exit"])
        errorExitID = StableID(namespace: "flow", components: [entity.id.rawValue, "error-exit"])
    }

    mutating func build() throws -> ControlFlowGraph {
        try appendNode(FlowNode(id: entryID, kind: .entry, label: "Entry", sourceOrder: nextOrder()))
        try appendNode(FlowNode(id: exitID, kind: .exit, label: "Exit", sourceOrder: Int.max - 1))
        try appendNode(FlowNode(id: errorExitID, kind: .errorExit, label: "Error Exit", sourceOrder: Int.max))
        var context = GenericFlowContext()
        let open = try lowerSequence(statements(in: entity.body), incoming: [.open(entryID)], context: &context)
        try connect(open, to: exitID)
        return ControlFlowGraph(
            entityID: entity.id,
            nodes: nodes,
            edges: edges,
            entryID: entryID,
            exitID: exitID,
            errorExitID: errorExitID
        )
    }

    mutating func lowerSequence(
        _ sequence: [SyntaxNode],
        incoming: [GenericPendingExit],
        context: inout GenericFlowContext
    ) throws -> [GenericPendingExit] {
        var open = incoming
        for statement in sequence where !open.isEmpty {
            open = try lower(statement, incoming: open, context: &context)
        }
        return open
    }

    mutating func lower(
        _ statement: SyntaxNode,
        incoming: [GenericPendingExit],
        context: inout GenericFlowContext
    ) throws -> [GenericPendingExit] {
        if profile.conditionKinds.contains(statement.kind) {
            return try lowerCondition(statement, incoming: incoming, context: context)
        }
        if profile.loopKinds.contains(statement.kind) {
            return try lowerLoop(statement, incoming: incoming, context: context)
        }
        if profile.switchKinds.contains(statement.kind) {
            return try lowerSwitch(statement, incoming: incoming, context: context)
        }
        if profile.tryKinds.contains(statement.kind) {
            return try lowerTry(statement, incoming: incoming, context: context)
        }
        if profile.returnKinds.contains(statement.kind) {
            return try lowerTransfer(statement, incoming: incoming, target: exitID, kind: .returnFlow)
        }
        if profile.throwKinds.contains(statement.kind) {
            return try lowerTransfer(statement, incoming: incoming, target: errorExitID, kind: .throwFlow)
        }
        if profile.breakKinds.contains(statement.kind) {
            return try lowerTransfer(
                statement,
                incoming: incoming,
                target: context.breakTarget,
                kind: .breakFlow
            )
        }
        if profile.continueKinds.contains(statement.kind) {
            return try lowerTransfer(
                statement,
                incoming: incoming,
                target: context.continueTarget,
                kind: .continueFlow
            )
        }
        if profile.statementContainers.contains(statement.kind) {
            return try lowerSequence(statements(in: statement), incoming: incoming, context: &context)
        }
        let node = try sourceNode(statement, kind: .basicBlock, label: compact(statement.text))
        try connect(incoming, to: node.id)
        return [.open(node.id)]
    }

    mutating func lowerCondition(
        _ statement: SyntaxNode,
        incoming: [GenericPendingExit],
        context: GenericFlowContext
    ) throws -> [GenericPendingExit] {
        let conditionSyntax = statement.firstChild(fieldName: "condition")
            ?? statement.firstChild(fieldName: "predicate")
            ?? statement.children.first { !$0.isNamed || !profile.statementContainers.contains($0.kind) }
        let condition = try sourceNode(
            conditionSyntax ?? statement,
            kind: .condition,
            label: "if \(compact(conditionSyntax?.text ?? statement.text))"
        )
        try connect(incoming, to: condition.id)
        let consequence = statement.firstChild(fieldName: "consequence")
            ?? statement.firstChild(fieldName: "body")
            ?? statement.children.first { profile.statementContainers.contains($0.kind) }
        let alternative = statement.firstChild(fieldName: "alternative")
            ?? statement.children.drop(while: { $0.id != consequence?.id }).dropFirst().first {
                profile.statementContainers.contains($0.kind) || profile.conditionKinds.contains($0.kind)
            }
        var thenContext = context
        let thenExits = try lowerBranch(
            consequence,
            incoming: [GenericPendingExit(nodeID: condition.id, edgeKind: .conditionTrue, label: "true")],
            context: &thenContext
        )
        guard let alternative else {
            return thenExits + [GenericPendingExit(nodeID: condition.id, edgeKind: .conditionFalse, label: "false")]
        }
        var elseContext = context
        let elseExits = try lowerBranch(
            alternative,
            incoming: [GenericPendingExit(nodeID: condition.id, edgeKind: .conditionFalse, label: "false")],
            context: &elseContext
        )
        return thenExits + elseExits
    }

    mutating func lowerLoop(
        _ statement: SyntaxNode,
        incoming: [GenericPendingExit],
        context: GenericFlowContext
    ) throws -> [GenericPendingExit] {
        let conditionSyntax = statement.firstChild(fieldName: "condition")
            ?? statement.firstChild(fieldName: "clause")
            ?? statement.firstChild(fieldName: "left")
        let condition = try sourceNode(
            conditionSyntax ?? statement,
            kind: .condition,
            label: "loop \(compact(conditionSyntax?.text ?? statement.text))"
        )
        try connect(incoming, to: condition.id)
        let afterID = StableID(namespace: "flow", components: [statement.id.rawValue, "after-loop"])
        let body = statement.firstChild(fieldName: "body")
            ?? statement.children.first { profile.statementContainers.contains($0.kind) }
        var loopContext = context
        loopContext.breakTarget = afterID
        loopContext.continueTarget = condition.id
        let bodyExits = try lowerBranch(
            body,
            incoming: [GenericPendingExit(nodeID: condition.id, edgeKind: .conditionTrue, label: "body")],
            context: &loopContext
        )
        for bodyExit in bodyExits {
            try appendEdge(source: bodyExit.nodeID, target: condition.id, kind: .loopBack, label: "next")
        }
        let after = FlowNode(
            id: afterID,
            kind: .basicBlock,
            label: "after loop",
            sourceRanges: [statement.range],
            syntaxIDs: [statement.id],
            sourceOrder: nextOrder()
        )
        try appendNode(after)
        try appendEdge(source: condition.id, target: after.id, kind: .conditionFalse, label: "done")
        return [.open(after.id)]
    }

    mutating func lowerSwitch(
        _ statement: SyntaxNode,
        incoming: [GenericPendingExit],
        context: GenericFlowContext
    ) throws -> [GenericPendingExit] {
        let subject = statement.firstChild(fieldName: "value")
            ?? statement.firstChild(fieldName: "condition")
            ?? statement.firstChild(fieldName: "subject")
        let decision = try sourceNode(
            subject ?? statement,
            kind: .condition,
            label: "switch \(compact(subject?.text ?? statement.text))"
        )
        try connect(incoming, to: decision.id)
        let caseKinds: Set = [
            "switch_case", "switch_default", "case_clause", "default_clause", "expression_case", "type_case",
            "communication_case"
        ]
        let cases = statement.descendants.filter { caseKinds.contains($0.kind) }
        guard !cases.isEmpty else { return [.open(decision.id)] }
        var exits: [GenericPendingExit] = []
        for branch in cases {
            let caseNode = try sourceNode(branch, kind: .switchCase, label: compact(branch.text))
            try appendEdge(source: decision.id, target: caseNode.id, kind: .switchCase, label: compact(branch.text))
            var branchContext = context
            let branchStatements = statements(in: branch)
            exits += try lowerSequence(branchStatements, incoming: [.open(caseNode.id)], context: &branchContext)
        }
        return exits
    }

    mutating func lowerTry(
        _ statement: SyntaxNode,
        incoming: [GenericPendingExit],
        context: GenericFlowContext
    ) throws -> [GenericPendingExit] {
        let attempt = try sourceNode(statement, kind: .basicBlock, label: "try")
        try connect(incoming, to: attempt.id)
        var exits: [GenericPendingExit] = []
        if let body = statement.firstChild(fieldName: "body") {
            var bodyContext = context
            exits += try lowerBranch(body, incoming: [.open(attempt.id)], context: &bodyContext)
        }
        for clause in statement.children where profile.catchKinds.contains(clause.kind) {
            let catchNode = try sourceNode(clause, kind: .catchBlock, label: compact(clause.text))
            try appendEdge(source: attempt.id, target: catchNode.id, kind: .catchFlow, label: "error")
            var catchContext = context
            exits += try lowerSequence(statements(in: clause), incoming: [.open(catchNode.id)], context: &catchContext)
        }
        return exits.isEmpty ? [.open(attempt.id)] : exits
    }

    mutating func lowerTransfer(
        _ statement: SyntaxNode,
        incoming: [GenericPendingExit],
        target: StableID?,
        kind: FlowEdgeKind
    ) throws -> [GenericPendingExit] {
        let node = try sourceNode(statement, kind: .basicBlock, label: compact(statement.text))
        try connect(incoming, to: node.id)
        if let target {
            try appendEdge(source: node.id, target: target, kind: kind, label: nil)
            return []
        }
        return [.open(node.id)]
    }

    mutating func lowerBranch(
        _ node: SyntaxNode?,
        incoming: [GenericPendingExit],
        context: inout GenericFlowContext
    ) throws -> [GenericPendingExit] {
        guard let node else { return incoming }
        if profile.statementContainers.contains(node.kind) {
            return try lowerSequence(statements(in: node), incoming: incoming, context: &context)
        }
        return try lower(node, incoming: incoming, context: &context)
    }

    func statements(in node: SyntaxNode) -> [SyntaxNode] {
        let candidates = profile.statementContainers.contains(node.kind)
            ? node.children
            : node.children.first(where: { profile.statementContainers.contains($0.kind) })?.children ?? node.children
        return candidates.filter { child in
            child.isNamed && child.kind != "comment" && child.kind != "line_comment" && child.kind != "block_comment"
        }
    }

    mutating func sourceNode(_ syntax: SyntaxNode, kind: FlowNodeKind, label: String) throws -> FlowNode {
        let node = FlowNode(
            id: StableID(namespace: "flow", components: [entity.id.rawValue, syntax.id.rawValue, kind.rawValue]),
            kind: kind,
            label: label,
            sourceRanges: [syntax.range],
            syntaxIDs: [syntax.id],
            sourceOrder: nextOrder()
        )
        try appendNode(node)
        return node
    }

    mutating func connect(_ incoming: [GenericPendingExit], to target: StableID) throws {
        for exit in incoming {
            try appendEdge(source: exit.nodeID, target: target, kind: exit.edgeKind, label: exit.label)
        }
    }

    mutating func appendNode(_ node: FlowNode) throws {
        guard nodes.count < limits.maximumFlowNodesPerFunction else {
            throw ControlFlowBuilderError.nodeLimitExceeded(limit: limits.maximumFlowNodesPerFunction)
        }
        if !nodes.contains(where: { $0.id == node.id }) {
            nodes.append(node)
        }
    }

    mutating func appendEdge(source: StableID, target: StableID, kind: FlowEdgeKind, label: String?) throws {
        guard edges.count < limits.maximumFlowEdgesPerFunction else {
            throw ControlFlowBuilderError.edgeLimitExceeded(limit: limits.maximumFlowEdgesPerFunction)
        }
        let edge = FlowEdge(source: source, target: target, kind: kind, label: label)
        if !edges.contains(where: { $0.id == edge.id }) {
            edges.append(edge)
        }
    }

    mutating func nextOrder() -> Int {
        defer { sourceOrder += 1 }
        return sourceOrder
    }

    func compact(_ value: String) -> String {
        let compacted = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return compacted.count > 88 ? String(compacted.prefix(85)) + "…" : compacted
    }
}
