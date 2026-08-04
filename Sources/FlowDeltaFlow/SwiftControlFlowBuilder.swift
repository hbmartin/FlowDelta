import FlowDeltaCore
import Foundation
import OSLog

public enum ControlFlowBuilderError: Error, Equatable {
    case nodeLimitExceeded(limit: Int)
    case edgeLimitExceeded(limit: Int)
}

public struct SwiftControlFlowBuilder: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Flow")

    public init() {}

    public func build(
        for entity: SourceEntity,
        limits: AnalysisLimits = .default
    ) throws -> ControlFlowGraph {
        var builder = Builder(entity: entity, limits: limits)
        let graph = try builder.build()
        Self.logger.debug(
            "Built CFG for \(entity.qualifiedName, privacy: .public): \(graph.nodes.count) nodes, \(graph.edges.count) edges"
        )
        return graph
    }
}

private struct PendingExit {
    let nodeID: StableID
    let edgeKind: FlowEdgeKind
    let label: String?

    static func `fallthrough`(_ id: StableID) -> PendingExit {
        PendingExit(nodeID: id, edgeKind: .fallthrough, label: nil)
    }
}

private struct FlowContext {
    var breakTarget: StableID?
    var continueTarget: StableID?
    var errorTarget: StableID
    var activeDefers: [SyntaxNode] = []
}

private struct Builder {
    let entity: SourceEntity
    let limits: AnalysisLimits
    var nodes: [FlowNode] = []
    var edges: [FlowEdge] = []
    var sourceOrder = 0
    let entryID: StableID
    let exitID: StableID
    let errorExitID: StableID

    init(entity: SourceEntity, limits: AnalysisLimits) {
        self.entity = entity
        self.limits = limits
        entryID = StableID(namespace: "flow", components: [entity.id.rawValue, "entry"])
        exitID = StableID(namespace: "flow", components: [entity.id.rawValue, "exit"])
        errorExitID = StableID(namespace: "flow", components: [entity.id.rawValue, "error-exit"])
    }

    mutating func build() throws -> ControlFlowGraph {
        try appendNode(FlowNode(id: entryID, kind: .entry, label: "Entry", sourceOrder: nextOrder()))
        let executable = statements(in: entity.body)
        var context = FlowContext(errorTarget: errorExitID)
        var open = try lowerSequence(executable, incoming: [.fallthrough(entryID)], context: &context)
        open = try appendDeferredExecutions(to: open, defers: context.activeDefers, reason: "normal-exit")

        try appendNode(FlowNode(id: exitID, kind: .exit, label: "Exit", sourceOrder: nextOrder()))
        try connect(open, to: exitID)
        try appendNode(FlowNode(id: errorExitID, kind: .errorExit, label: "Error Exit", sourceOrder: nextOrder()))

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
        _ statements: [SyntaxNode],
        incoming: [PendingExit],
        context: inout FlowContext
    ) throws -> [PendingExit] {
        var open = incoming
        for statement in statements {
            open = try lower(statement, incoming: open, context: &context)
        }
        return open
    }

    mutating func lower(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: inout FlowContext
    ) throws -> [PendingExit] {
        switch statement.kind {
        case "if_statement":
            return try lowerIf(statement, incoming: incoming, context: context)
        case "guard_statement":
            return try lowerGuard(statement, incoming: incoming, context: context)
        case "switch_statement":
            return try lowerSwitch(statement, incoming: incoming, context: context)
        case "for_statement", "while_statement":
            return try lowerPreTestLoop(statement, incoming: incoming, context: context)
        case "repeat_while_statement":
            return try lowerRepeatLoop(statement, incoming: incoming, context: context)
        case "do_statement":
            return try lowerDoCatch(statement, incoming: incoming, context: context)
        case "defer_statement":
            let registration = try sourceNode(statement, kind: .deferBlock, label: "register \(compactLabel(statement.text))")
            try connect(incoming, to: registration.id)
            context.activeDefers.append(statement)
            return [.fallthrough(registration.id)]
        case "control_transfer_statement":
            return try lowerTransfer(statement, incoming: incoming, context: context)
        default:
            return try lowerSimple(statement, incoming: incoming, context: context)
        }
    }

    mutating func lowerSimple(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let node = try sourceNode(statement, kind: .basicBlock, label: compactLabel(statement.text))
        try connect(incoming, to: node.id)
        if containsPlainTry(statement.text) {
            var exceptional = [PendingExit.fallthrough(node.id)]
            exceptional = try appendDeferredExecutions(
                to: exceptional,
                defers: context.activeDefers,
                reason: "throwing-expression"
            )
            for exit in exceptional {
                try appendEdge(source: exit.nodeID, target: context.errorTarget, kind: .throwFlow, label: "throws")
            }
        }
        return [.fallthrough(node.id)]
    }

    mutating func lowerIf(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let condition = try sourceNode(
            statement,
            kind: .condition,
            label: "if \(conditionLabel(statement))",
            syntaxIDs: conditionSyntaxIDs(statement)
        )
        try connect(incoming, to: condition.id)
        let branches = statement.children.filter { $0.kind == "statements" || $0.kind == "if_statement" }

        var thenContext = context
        var thenExits = try lowerSequence(
            branches.first.map(statements(in:)) ?? [],
            incoming: [PendingExit(nodeID: condition.id, edgeKind: .conditionTrue, label: "true")],
            context: &thenContext
        )
        thenExits = try appendDeferredExecutions(
            to: thenExits,
            defers: Array(thenContext.activeDefers.dropFirst(context.activeDefers.count)),
            reason: "if-scope"
        )

        guard branches.count > 1 else {
            return thenExits + [PendingExit(nodeID: condition.id, edgeKind: .conditionFalse, label: "false")]
        }
        var elseContext = context
        var elseExits: [PendingExit]
        if branches[1].kind == "if_statement" {
            elseExits = try lower(
                branches[1],
                incoming: [PendingExit(nodeID: condition.id, edgeKind: .conditionFalse, label: "false")],
                context: &elseContext
            )
        } else {
            elseExits = try lowerSequence(
                statements(in: branches[1]),
                incoming: [PendingExit(nodeID: condition.id, edgeKind: .conditionFalse, label: "false")],
                context: &elseContext
            )
        }
        elseExits = try appendDeferredExecutions(
            to: elseExits,
            defers: Array(elseContext.activeDefers.dropFirst(context.activeDefers.count)),
            reason: "else-scope"
        )
        return thenExits + elseExits
    }

    mutating func lowerGuard(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let condition = try sourceNode(
            statement,
            kind: .condition,
            label: "guard \(conditionLabel(statement))",
            syntaxIDs: conditionSyntaxIDs(statement)
        )
        try connect(incoming, to: condition.id)
        guard let elseStatements = statement.children.first(where: { $0.kind == "statements" }) else {
            return [PendingExit(nodeID: condition.id, edgeKind: .conditionTrue, label: "passes")]
        }
        var elseContext = context
        var failure = try lowerSequence(
            statements(in: elseStatements),
            incoming: [PendingExit(nodeID: condition.id, edgeKind: .conditionFalse, label: "else")],
            context: &elseContext
        )
        failure = try appendDeferredExecutions(
            to: failure,
            defers: elseContext.activeDefers,
            reason: "guard-else"
        )
        for exit in failure {
            try appendEdge(source: exit.nodeID, target: exitID, kind: .returnFlow, label: "required exit")
        }
        return [PendingExit(nodeID: condition.id, edgeKind: .conditionTrue, label: "passes")]
    }

    mutating func lowerPreTestLoop(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let keyword = statement.kind == "for_statement" ? "for" : "while"
        let condition = try sourceNode(statement, kind: .condition, label: "\(keyword) \(conditionLabel(statement))")
        let join = try syntheticNode(role: "\(keyword)-exit", near: statement, label: "after \(keyword)")
        try connect(incoming, to: condition.id)
        try appendEdge(source: condition.id, target: join.id, kind: .conditionFalse, label: "done")

        var loopContext = context
        loopContext.breakTarget = join.id
        loopContext.continueTarget = condition.id
        let body = statement.children.first(where: { $0.kind == "statements" })
        var bodyExits = try lowerSequence(
            body.map(statements(in:)) ?? [],
            incoming: [PendingExit(nodeID: condition.id, edgeKind: .conditionTrue, label: "next")],
            context: &loopContext
        )
        bodyExits = try appendDeferredExecutions(
            to: bodyExits,
            defers: Array(loopContext.activeDefers.dropFirst(context.activeDefers.count)),
            reason: "loop-iteration"
        )
        for exit in bodyExits {
            try appendEdge(source: exit.nodeID, target: condition.id, kind: .loopBack, label: "repeat")
        }
        return [.fallthrough(join.id)]
    }

    mutating func lowerRepeatLoop(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let condition = try sourceNode(statement, kind: .condition, label: "while \(conditionLabel(statement))")
        let join = try syntheticNode(role: "repeat-exit", near: statement, label: "after repeat")
        let bodyAnchor = try syntheticNode(role: "repeat-body", near: statement, label: "repeat")
        try connect(incoming, to: bodyAnchor.id)
        var loopContext = context
        loopContext.breakTarget = join.id
        loopContext.continueTarget = condition.id
        let body = statement.children.first(where: { $0.kind == "statements" })
        var bodyExits = try lowerSequence(
            body.map(statements(in:)) ?? [],
            incoming: [.fallthrough(bodyAnchor.id)],
            context: &loopContext
        )
        bodyExits = try appendDeferredExecutions(
            to: bodyExits,
            defers: Array(loopContext.activeDefers.dropFirst(context.activeDefers.count)),
            reason: "repeat-iteration"
        )
        try connect(bodyExits, to: condition.id)
        try appendEdge(source: condition.id, target: bodyAnchor.id, kind: .loopBack, label: "true")
        try appendEdge(source: condition.id, target: join.id, kind: .conditionFalse, label: "false")
        return [.fallthrough(join.id)]
    }

    mutating func lowerSwitch(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let condition = try sourceNode(statement, kind: .condition, label: "switch \(conditionLabel(statement))")
        let join = try syntheticNode(role: "switch-exit", near: statement, label: "after switch")
        try connect(incoming, to: condition.id)
        let entries = statement.children.filter { $0.kind == "switch_entry" }
        guard !entries.isEmpty else {
            try appendEdge(source: condition.id, target: join.id, kind: .conditionFalse, label: "no cases")
            return [.fallthrough(join.id)]
        }
        var caseNodes: [FlowNode] = []
        for entry in entries {
            let label = entry.text.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "case"
            caseNodes.append(try sourceNode(entry, kind: .switchCase, label: compactLabel(label)))
        }
        for caseNode in caseNodes {
            try appendEdge(source: condition.id, target: caseNode.id, kind: .switchCase, label: caseNode.label)
        }
        for (index, entry) in entries.enumerated() {
            var caseContext = context
            caseContext.breakTarget = join.id
            var caseExits = try lowerSequence(
                entry.children.first(where: { $0.kind == "statements" }).map(statements(in:)) ?? [],
                incoming: [.fallthrough(caseNodes[index].id)],
                context: &caseContext
            )
            caseExits = try appendDeferredExecutions(
                to: caseExits,
                defers: Array(caseContext.activeDefers.dropFirst(context.activeDefers.count)),
                reason: "switch-case"
            )
            let fallsThrough = entry.text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("fallthrough")
            let target = fallsThrough && index + 1 < caseNodes.count ? caseNodes[index + 1].id : join.id
            for exit in caseExits {
                try appendEdge(
                    source: exit.nodeID,
                    target: target,
                    kind: fallsThrough ? .fallthrough : .breakFlow,
                    label: fallsThrough ? "fallthrough" : nil
                )
            }
        }
        return [.fallthrough(join.id)]
    }

    mutating func lowerDoCatch(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let join = try syntheticNode(role: "do-exit", near: statement, label: "after do")
        let catches = statement.children.filter { $0.kind == "catch_block" }
        let dispatch = catches.isEmpty
            ? nil
            : try syntheticNode(role: "catch-dispatch", near: statement, label: "catch")
        var bodyContext = context
        bodyContext.errorTarget = dispatch?.id ?? context.errorTarget
        let bodyStatements = statement.children.first(where: { $0.kind == "statements" })
        var normalExits = try lowerSequence(
            bodyStatements.map(statements(in:)) ?? [],
            incoming: incoming,
            context: &bodyContext
        )
        normalExits = try appendDeferredExecutions(
            to: normalExits,
            defers: Array(bodyContext.activeDefers.dropFirst(context.activeDefers.count)),
            reason: "do-scope"
        )
        try connect(normalExits, to: join.id)

        if let dispatch {
            for catchNode in catches {
                let catchFlow = try sourceNode(catchNode, kind: .catchBlock, label: compactLabel(catchNode.text))
                try appendEdge(source: dispatch.id, target: catchFlow.id, kind: .catchFlow, label: "catch")
                var catchContext = context
                var catchExits = try lowerSequence(
                    catchNode.children.first(where: { $0.kind == "statements" }).map(statements(in:)) ?? [],
                    incoming: [.fallthrough(catchFlow.id)],
                    context: &catchContext
                )
                catchExits = try appendDeferredExecutions(
                    to: catchExits,
                    defers: Array(catchContext.activeDefers.dropFirst(context.activeDefers.count)),
                    reason: "catch-scope"
                )
                try connect(catchExits, to: join.id)
            }
        }
        return [.fallthrough(join.id)]
    }

    mutating func lowerTransfer(
        _ statement: SyntaxNode,
        incoming: [PendingExit],
        context: FlowContext
    ) throws -> [PendingExit] {
        let text = statement.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = try sourceNode(statement, kind: .basicBlock, label: compactLabel(text))
        try connect(incoming, to: node.id)
        let target: StableID
        let edgeKind: FlowEdgeKind
        let reason: String
        if text.hasPrefix("throw") {
            target = context.errorTarget
            edgeKind = .throwFlow
            reason = "throw"
        } else if text.hasPrefix("return") || text.hasPrefix("yield") {
            target = exitID
            edgeKind = .returnFlow
            reason = "return"
        } else if text.hasPrefix("break") {
            target = context.breakTarget ?? exitID
            edgeKind = .breakFlow
            reason = "break"
        } else if text.hasPrefix("continue") {
            target = context.continueTarget ?? exitID
            edgeKind = .continueFlow
            reason = "continue"
        } else {
            return [.fallthrough(node.id)]
        }
        let deferred = try appendDeferredExecutions(
            to: [.fallthrough(node.id)],
            defers: context.activeDefers,
            reason: reason
        )
        for exit in deferred {
            try appendEdge(source: exit.nodeID, target: target, kind: edgeKind, label: reason)
        }
        return []
    }

    mutating func appendDeferredExecutions(
        to exits: [PendingExit],
        defers: [SyntaxNode],
        reason: String
    ) throws -> [PendingExit] {
        guard !defers.isEmpty else { return exits }
        var result: [PendingExit] = []
        for pending in exits {
            var previous = pending
            for deferred in defers.reversed() {
                let id = StableID(
                    namespace: "flow",
                    components: [entity.id.rawValue, deferred.id.rawValue, reason, previous.nodeID.rawValue]
                )
                let node = FlowNode(
                    id: id,
                    kind: .deferBlock,
                    label: "defer \(compactLabel(deferred.text))",
                    sourceRanges: [deferred.range],
                    syntaxIDs: [deferred.id],
                    sourceOrder: nextOrder()
                )
                try appendNode(node)
                try appendEdge(
                    source: previous.nodeID,
                    target: node.id,
                    kind: .deferredFlow,
                    label: reason
                )
                previous = .fallthrough(node.id)
            }
            result.append(previous)
        }
        return result
    }

    mutating func sourceNode(
        _ syntax: SyntaxNode,
        kind: FlowNodeKind,
        label: String,
        syntaxIDs: [StableID]? = nil
    ) throws -> FlowNode {
        let node = FlowNode(
            id: StableID(namespace: "flow", components: [entity.id.rawValue, syntax.id.rawValue, kind.rawValue]),
            kind: kind,
            label: label,
            sourceRanges: [syntax.range],
            syntaxIDs: syntaxIDs ?? [syntax.id],
            sourceOrder: nextOrder()
        )
        try appendNode(node)
        return node
    }

    mutating func syntheticNode(role: String, near syntax: SyntaxNode, label: String) throws -> FlowNode {
        let node = FlowNode(
            id: StableID(namespace: "flow", components: [entity.id.rawValue, syntax.id.rawValue, role]),
            kind: .basicBlock,
            label: label,
            sourceOrder: nextOrder()
        )
        try appendNode(node)
        return node
    }

    mutating func appendNode(_ node: FlowNode) throws {
        guard nodes.count < limits.maximumFlowNodesPerFunction else {
            throw ControlFlowBuilderError.nodeLimitExceeded(limit: limits.maximumFlowNodesPerFunction)
        }
        if !nodes.contains(where: { $0.id == node.id }) {
            nodes.append(node)
        }
    }

    mutating func connect(_ incoming: [PendingExit], to target: StableID) throws {
        for pending in incoming {
            try appendEdge(
                source: pending.nodeID,
                target: target,
                kind: pending.edgeKind,
                label: pending.label
            )
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

    func statements(in node: SyntaxNode) -> [SyntaxNode] {
        if node.kind == "statements" {
            return node.children.filter { $0.isNamed && $0.kind != "comment" }
        }
        if let statements = node.children.first(where: { $0.kind == "statements" }) {
            return self.statements(in: statements)
        }
        return node.children.filter { $0.isNamed && $0.kind != "comment" }
    }

    func conditionLabel(_ node: SyntaxNode) -> String {
        let values = node.children.filter { $0.fieldName == "condition" || $0.fieldName == "expr" || $0.fieldName == "collection" }
        if !values.isEmpty {
            return compactLabel(values.map(\.text).joined(separator: ", "))
        }
        let firstLine = node.text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? node.text
        return compactLabel(firstLine)
    }

    func conditionSyntaxIDs(_ node: SyntaxNode) -> [StableID] {
        let values = node.children.filter { $0.fieldName == "condition" || $0.fieldName == "expr" || $0.fieldName == "collection" }
        return values.isEmpty ? [node.id] : values.map(\.id)
    }

    func compactLabel(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return collapsed.count > 120 ? String(collapsed.prefix(117)) + "…" : collapsed
    }

    func containsPlainTry(_ text: String) -> Bool {
        text.range(of: #"\btry\s"#, options: .regularExpression) != nil
            && text.range(of: #"\btry[!?]"#, options: .regularExpression) == nil
    }
}
