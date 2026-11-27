import FlowDeltaCore
import Foundation
import OSLog

public struct SwiftEntityExtractor: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Triage")

    public init() {}

    public func entities(in tree: SyntaxTree) -> [SourceEntity] {
        var result: [SourceEntity] = []
        visit(tree.root, containers: [], insideCallable: false, path: tree.snapshot.path, result: &result)
        let sorted = result.sorted { ($0.path, $0.range.start, $0.qualifiedName) < (
            $1.path,
            $1.range.start,
            $1.qualifiedName
        ) }
        Self.logger.debug("Extracted \(sorted.count) Swift entities from \(tree.snapshot.path, privacy: .public)")
        return sorted
    }

    private func visit(
        _ node: SyntaxNode,
        containers: [String],
        insideCallable: Bool,
        path: String,
        result: inout [SourceEntity]
    ) {
        if let declaration = declaration(
            for: node,
            containers: containers,
            insideCallable: insideCallable,
            path: path
        ) {
            result.append(declaration.entity)
            let childIsInsideCallable = insideCallable || Self.isCallable(declaration.entity.kind)
            for child in node.children {
                visit(
                    child,
                    containers: declaration.childContainers,
                    insideCallable: childIsInsideCallable,
                    path: path,
                    result: &result
                )
            }
            return
        }

        for child in node.children {
            visit(child, containers: containers, insideCallable: insideCallable, path: path, result: &result)
        }
    }

    private func declaration(
        for node: SyntaxNode,
        containers: [String],
        insideCallable: Bool,
        path: String
    ) -> (entity: SourceEntity, childContainers: [String])? {
        let kind: EntityKind
        let name: String
        var childContainers = containers

        switch node.kind {
        case "class_declaration":
            name = normalizedName(node.firstChild(fieldName: "name")?.text) ?? "<anonymous type>"
            let declarationKind = node.firstChild(fieldName: "declaration_kind")?.text ?? "type"
            kind = declarationKind == "extension" ? .typeExtension : .type
            childContainers.append(name)
        case "protocol_declaration":
            name = normalizedName(node.firstChild(fieldName: "name")?.text) ?? "<anonymous protocol>"
            kind = .type
            childContainers.append(name)
        case "function_declaration", "protocol_function_declaration":
            name = normalizedName(node.firstChild(fieldName: "name")?.text) ?? "<anonymous function>"
            kind = containers.isEmpty ? .function : .method
        case "init_declaration":
            name = "init"
            kind = .initializer
        case "deinit_declaration":
            name = "deinit"
            kind = .deinitializer
        case "subscript_declaration":
            name = "subscript"
            kind = .subscriptDeclaration
        case "operator_declaration":
            name = normalizedName(node.firstChild(fieldName: "name")?.text)
                ?? normalizedName(node.children.first(where: { $0.kind.contains("operator") })?.text)
                ?? "operator"
            kind = .operatorDeclaration
        case "property_declaration" where containers.isEmpty && !insideCallable:
            guard let identifier = node.firstDescendant(kind: "simple_identifier") else { return nil }
            name = normalizedName(identifier.text) ?? "<binding>"
            kind = .topLevelBinding
        default:
            return nil
        }

        let callableSuffix: String = switch kind {
        case .function, .method, .initializer, .subscriptDeclaration, .operatorDeclaration:
            parameterClause(in: node) ?? "()"
        case .type, .typeExtension, .deinitializer, .topLevelBinding:
            ""
        }
        let qualifiedName = (containers + [name + callableSuffix]).joined(separator: ".")
        let body = node.firstChild(fieldName: "body") ?? node
        let entity = SourceEntity(
            id: StableID(
                namespace: "entity",
                components: [path, kind.rawValue, qualifiedName, String(node.range.start.utf16Offset)]
            ),
            kind: kind,
            name: name,
            qualifiedName: qualifiedName,
            path: path,
            range: node.range,
            body: body,
            declarationHeader: DeclarationHeader.tokens(
                of: node,
                name: node.firstChild(fieldName: "name"),
                body: body,
                rules: LanguageProfile.profile(for: .swift).noise
            )
        )
        return (entity, childContainers)
    }

    private func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isCallable(_ kind: EntityKind) -> Bool {
        switch kind {
        case .function, .method, .initializer, .deinitializer, .subscriptDeclaration, .operatorDeclaration:
            true
        case .type, .typeExtension, .topLevelBinding:
            false
        }
    }

    private func parameterClause(in declaration: SyntaxNode) -> String? {
        let candidates = declaration.children.filter { child in
            child.fieldName != "body" &&
                (child.kind.contains("parameter") || child.fieldName?.contains("parameter") == true)
        }
        guard !candidates.isEmpty else { return nil }
        let parameters = candidates.map { parameter in
            parameter.text
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
        }
        return "(\(parameters.joined(separator: ",")))"
    }
}
