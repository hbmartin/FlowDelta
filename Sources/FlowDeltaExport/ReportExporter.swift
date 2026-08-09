import FlowDeltaCore
import Foundation

public enum FlowDeltaExportFormat: String, Codable, CaseIterable, Sendable {
    case table
    case json
    case mermaid
    case markdown
}

public enum FlowDeltaExportError: Error, Equatable {
    case stringEncoding
}

public struct FlowDeltaReportExporter: Sendable {
    public init() {}

    public func render(
        _ report: RevisionFlowDeltaReport,
        format: FlowDeltaExportFormat
    ) throws -> String {
        switch format {
        case .table:
            table(report)
        case .json:
            try json(report)
        case .mermaid:
            mermaid(report)
        case .markdown:
            markdown(report)
        }
    }

    public func json(_ report: RevisionFlowDeltaReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        guard let value = String(data: data, encoding: .utf8) else {
            throw FlowDeltaExportError.stringEncoding
        }
        return value + "\n"
    }

    public func table(_ report: RevisionFlowDeltaReport) -> String {
        var rows: [[String]] = [["CHANGE", "ENTITY", "PATH", "CONFIDENCE"]]
        for file in report.files {
            for change in file.entityChanges {
                let entity = change.new ?? change.old
                rows.append([
                    change.kind.rawValue.uppercased(),
                    entity?.qualifiedName ?? "<unknown>",
                    entity?.path ?? file.path,
                    confidenceLabel(change.confidence)
                ])
            }
        }
        let widths = rows[0].indices.map { column in
            rows.map { $0[column].count }.max() ?? 0
        }
        var lines = rows.enumerated().map { index, row in
            let rendered = row.enumerated().map { column, value in
                value.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
            if index == 0 {
                return rendered + "\n" + widths.map { String(repeating: "-", count: $0) }.joined(separator: "  ")
            }
            return rendered
        }
        lines.append("")
        lines.append(summary(report))
        for function in report.functionDeltas where function.nodes.contains(where: { $0.state != .retained }) {
            let classifications = function.classifications.map(\.humanReadable).joined(separator: ", ")
            lines.append(
                "• \(function.displayName): "
                    + stateSummary(function)
                    + (classifications.isEmpty ? "" : " • \(classifications)")
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func mermaid(_ report: RevisionFlowDeltaReport) -> String {
        var lines = ["flowchart TD"]
        for function in report.functionDeltas {
            let graph = ExportGraph(function)
            let functionID = mermaidID(function.id)
            lines.append("  subgraph \(functionID)[\"\(escapeMermaid(function.displayName))\"]")
            for node in graph.nodes {
                let shape = node.node.kind == .condition ? "{\"\(escapeMermaid(node.node.label))\"}" : "[\"\(escapeMermaid(node.node.label))\"]"
                lines.append("    \(mermaidID(node.id))\(shape):::\(node.state.rawValue)")
            }
            for edge in graph.edges {
                let label = edge.edge.label.map { "|\"\(escapeMermaid($0))\"|" } ?? ""
                let connector = edge.edge.kind == .dataDependency ? "-.->" : "-->"
                lines.append(
                    "    \(mermaidID(edge.source)) \(connector)\(label) \(mermaidID(edge.target))"
                )
            }
            lines.append("  end")
        }
        lines.append(contentsOf: [
            "  classDef added fill:#d8ecd0,stroke:#3f7d3b,color:#172515",
            "  classDef removed fill:#f2d1ca,stroke:#9d4036,color:#351512",
            "  classDef modified fill:#f6e6a9,stroke:#a17b16,color:#382c08",
            "  classDef affected fill:#ded5ef,stroke:#72539a,color:#261b35",
            "  classDef retained fill:#dce7f1,stroke:#6b7e91,color:#202830"
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    public func markdown(_ report: RevisionFlowDeltaReport) -> String {
        var lines = [
            "# FlowDelta report",
            "",
            "`\(report.base.value)` → `\(report.target.value)`",
            "",
            summary(report),
            "",
            "## Entity triage",
            "",
            "| Change | Entity | Path | Confidence |",
            "| --- | --- | --- | --- |"
        ]
        for file in report.files {
            for change in file.entityChanges {
                let entity = change.new ?? change.old
                lines.append(
                    "| \(change.kind.rawValue) | `\(escapeMarkdown(entity?.qualifiedName ?? "<unknown>"))` | `\(escapeMarkdown(entity?.path ?? file.path))` | \(confidenceLabel(change.confidence)) |"
                )
            }
        }
        lines.append(contentsOf: ["", "## Control-flow delta", "", "```mermaid"])
        lines.append(contentsOf: mermaid(report).split(separator: "\n").map(String.init))
        lines.append("```")
        lines.append("")
        let bases = Set(report.functionDeltas.flatMap { delta in
            delta.nodes.flatMap { $0.causality.map(\.basis.rawValue) }
        }).sorted()
        if !bases.isEmpty {
            lines.append("Affected nodes in this report use the **\(bases.joined(separator: " + ")) context** basis.")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func summary(_ report: RevisionFlowDeltaReport) -> String {
        "Summary: \(report.files.count) source file(s), \(report.count(of: .added)) added, \(report.count(of: .removed)) removed, \(report.count(of: .modified)) modified, \(report.count(of: .moved)) moved, \(report.count(of: .renamed)) renamed."
    }

    private func stateSummary(_ function: FunctionFlowDelta) -> String {
        [DeltaState.added, .removed, .modified, .affected]
            .map { "\(function.count(of: $0)) \($0.rawValue)" }
            .joined(separator: ", ")
    }

    private func confidenceLabel(_ confidence: MatchConfidence?) -> String {
        guard let confidence else { return "—" }
        return "\(confidence.tier.rawValue) \(Int((confidence.score * 100).rounded()))%"
    }

    private func mermaidID(_ id: StableID) -> String {
        "fd_" + String(StableDigest.fnv1a64(id.rawValue), radix: 16)
    }

    private func escapeMermaid(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func escapeMarkdown(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "`", with: "\\`")
    }
}

private extension FlowChangeClassification {
    var humanReadable: String {
        switch self {
        case .guardInserted: "guard inserted"
        case .conditionChanged: "condition changed"
        case .earlyReturnAdded: "early return added"
        case .branchAdded: "branch added"
        case .branchRemoved: "branch removed"
        case .loopChanged: "loop changed"
        case .errorPathAdded: "error path added"
        }
    }
}

private struct ExportNode {
    let id: StableID
    let node: FlowNode
    let state: DeltaState
}

private struct ExportEdge {
    let source: StableID
    let target: StableID
    let edge: FlowEdge
}

private struct ExportGraph {
    let nodes: [ExportNode]
    let edges: [ExportEdge]

    init(_ delta: FunctionFlowDelta) {
        var oldToDelta: [StableID: StableID] = [:]
        var newToDelta: [StableID: StableID] = [:]
        nodes = delta.nodes.compactMap { nodeDelta in
            if let old = nodeDelta.old {
                oldToDelta[old.id] = nodeDelta.id
            }
            if let new = nodeDelta.new {
                newToDelta[new.id] = nodeDelta.id
            }
            guard let node = nodeDelta.new ?? nodeDelta.old else { return nil }
            return ExportNode(id: nodeDelta.id, node: node, state: nodeDelta.state)
        }.sorted { ($0.node.sourceOrder, $0.id) < ($1.node.sourceOrder, $1.id) }
        var projectedEdges: [ExportEdge] = delta.edges.compactMap { edgeDelta in
            guard let edge = edgeDelta.new ?? edgeDelta.old else { return nil }
            let mapping = edgeDelta.new == nil ? oldToDelta : newToDelta
            guard let source = mapping[edge.source], let target = mapping[edge.target] else { return nil }
            return ExportEdge(source: source, target: target, edge: edge)
        }
        projectedEdges += (delta.dataFlow?.edges ?? []).compactMap { edgeDelta in
            guard let edge = edgeDelta.new ?? edgeDelta.old else { return nil }
            let mapping = edgeDelta.new == nil ? oldToDelta : newToDelta
            guard let source = mapping[edge.definition], let target = mapping[edge.use] else { return nil }
            return ExportEdge(
                source: source,
                target: target,
                edge: FlowEdge(
                    id: edgeDelta.id,
                    source: edge.definition,
                    target: edge.use,
                    kind: .dataDependency,
                    label: edge.symbol
                )
            )
        }
        edges = projectedEdges.sorted { ($0.source, $0.target, $0.edge.id) < ($1.source, $1.target, $1.edge.id) }
    }
}
