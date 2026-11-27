import FlowDeltaCore
import Foundation
import OSLog

public struct SourceEntityExtractor: Sendable {
    private static let logger = Logger(subsystem: "com.hbmartin.FlowDelta", category: "Triage")

    public init() {}

    public func entities(in tree: SyntaxTree) -> [SourceEntity] {
        if tree.snapshot.language == .swift {
            return SwiftEntityExtractor().entities(in: tree)
        }
        var result: [SourceEntity] = []
        visit(
            tree.root,
            language: tree.snapshot.language,
            containers: [],
            insideCallable: false,
            path: tree.snapshot.path,
            result: &result
        )
        let sorted = result.sorted {
            ($0.path, $0.range.start, $0.qualifiedName) < ($1.path, $1.range.start, $1.qualifiedName)
        }
        Self.logger.debug(
            "Extracted \(sorted.count) \(tree.snapshot.language.displayName, privacy: .public) entities from \(tree.snapshot.path, privacy: .public)"
        )
        return sorted
    }

    private func visit(
        _ node: SyntaxNode,
        language: SourceLanguage,
        containers: [String],
        insideCallable: Bool,
        path: String,
        result: inout [SourceEntity]
    ) {
        if let declaration = declaration(
            for: node,
            language: language,
            containers: containers,
            insideCallable: insideCallable,
            path: path
        ) {
            result.append(declaration.entity)
            for child in node.children {
                visit(
                    child,
                    language: language,
                    containers: declaration.childContainers,
                    insideCallable: insideCallable || declaration.callable,
                    path: path,
                    result: &result
                )
            }
            return
        }
        for child in node.children {
            visit(
                child,
                language: language,
                containers: containers,
                insideCallable: insideCallable,
                path: path,
                result: &result
            )
        }
    }

    private func declaration(
        for node: SyntaxNode,
        language: SourceLanguage,
        containers: [String],
        insideCallable: Bool,
        path: String
    ) -> (entity: SourceEntity, childContainers: [String], callable: Bool)? {
        let classification = classify(node, language: language, containers: containers, insideCallable: insideCallable)
        guard let classification else { return nil }
        let nameNode = node.firstChild(fieldName: "name")
            ?? node.firstDescendant(kind: classification.identifierKind)
        let name = normalizedName(nameNode?.text) ?? classification.fallbackName
        let parameters = classification.callable ? parameterClause(in: node) : ""
        let receiver = language == .go && node.kind == "method_declaration"
            ? goReceiverType(in: node)
            : nil
        let qualifiedName = (containers + (receiver.map { [$0] } ?? []) + [name + parameters])
            .joined(separator: ".")
        let directBody = node.firstChild(fieldName: "body")
        let valueBody = node.firstChild(fieldName: "value")?.firstChild(fieldName: "body")
        let body = directBody ?? valueBody ?? node
        let entity = SourceEntity(
            id: StableID(
                namespace: "entity",
                components: [path, classification.kind.rawValue, qualifiedName, String(node.range.start.utf16Offset)]
            ),
            kind: classification.kind,
            name: name,
            qualifiedName: qualifiedName,
            path: path,
            range: node.range,
            body: body,
            parameterNames: classification.callable ? Self.parameterNames(in: node, language: language) : nil
        )
        var childContainers = containers
        if classification.container {
            childContainers.append(name)
        }
        return (entity, childContainers, classification.callable)
    }

    private func classify(
        _ node: SyntaxNode,
        language: SourceLanguage,
        containers: [String],
        insideCallable: Bool
    ) -> DeclarationClassification? {
        switch language {
        case .swift:
            nil
        case .typescript, .javascript:
            classifyTypeScriptOrJavaScript(node, containers: containers, insideCallable: insideCallable)
        case .python:
            classifyPython(node, containers: containers)
        case .go:
            classifyGo(node, containers: containers, insideCallable: insideCallable)
        }
    }

    private func classifyTypeScriptOrJavaScript(
        _ node: SyntaxNode,
        containers: [String],
        insideCallable: Bool
    ) -> DeclarationClassification? {
        switch node.kind {
        case "class_declaration", "abstract_class_declaration", "interface_declaration":
            return .type(identifier: "identifier")
        case "function_declaration", "generator_function_declaration":
            return .callable(kind: containers.isEmpty ? .function : .method, identifier: "identifier")
        case "method_definition", "method_signature":
            return .callable(kind: .method, identifier: "property_identifier")
        case "public_field_definition":
            return isFunctionValue(node)
                ? .callable(kind: .method, identifier: "property_identifier")
                : nil
        case "variable_declarator":
            if isFunctionValue(node) {
                return .callable(kind: containers.isEmpty ? .function : .method, identifier: "identifier")
            }
            return containers.isEmpty && !insideCallable ? .binding(identifier: "identifier") : nil
        default:
            return nil
        }
    }

    private func classifyPython(
        _ node: SyntaxNode,
        containers: [String]
    ) -> DeclarationClassification? {
        switch node.kind {
        case "class_definition":
            .type(identifier: "identifier")
        case "function_definition":
            .callable(kind: containers.isEmpty ? .function : .method, identifier: "identifier")
        default:
            nil
        }
    }

    private func classifyGo(
        _ node: SyntaxNode,
        containers: [String],
        insideCallable: Bool
    ) -> DeclarationClassification? {
        switch node.kind {
        case "function_declaration":
            .callable(kind: .function, identifier: "identifier")
        case "method_declaration":
            .callable(kind: .method, identifier: "field_identifier")
        case "type_spec":
            .type(identifier: "type_identifier")
        case "var_spec" where containers.isEmpty && !insideCallable,
             "const_spec" where containers.isEmpty && !insideCallable:
            .binding(identifier: "identifier")
        default:
            nil
        }
    }

    private func isFunctionValue(_ node: SyntaxNode) -> Bool {
        let kind = node.firstChild(fieldName: "value")?.kind
        return kind == "arrow_function" || kind == "function_expression"
    }

    private func parameterClause(in declaration: SyntaxNode) -> String {
        let parameter = declaration.firstChild(fieldName: "parameters")
            ?? declaration.children.first { $0.kind.contains("parameter") }
        guard let parameter else { return "()" }
        return parameter.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Receiver, parameter and named-result names for the languages whose data flow reads syntax.
    static func parameterNames(in declaration: SyntaxNode, language: SourceLanguage) -> [String]? {
        guard let rules = LanguageProfile.profile(for: language).binding else { return nil }
        let lists = ["receiver", "parameters", "result"].compactMap { declaration.firstChild(fieldName: $0) }
        var names: [String] = []
        for list in lists where list.kind.contains("parameter") {
            for parameter in list.children where parameter.isNamed {
                names += parameterNames(declaredBy: parameter, rules: rules)
            }
        }
        return names.filter { !rules.ignoredNames.contains($0) }
    }

    private static func parameterNames(declaredBy parameter: SyntaxNode, rules: LanguageBindingRules) -> [String] {
        if rules.identifierKinds.contains(parameter.kind) {
            return [parameter.text]
        }
        let named = parameter.children.filter { $0.fieldName == "name" && rules.identifierKinds.contains($0.kind) }
        if !named.isEmpty {
            return named.map(\.text)
        }
        /// `*args`, `**kwargs` and `name: type`: the first identifier outside the type and default.
        func first(_ node: SyntaxNode) -> String? {
            for child in node.children where child.fieldName != "type" && child.fieldName != "value" {
                if rules.identifierKinds.contains(child.kind) {
                    return child.text
                }
                if let found = first(child) {
                    return found
                }
            }
            return nil
        }
        return first(parameter).map { [$0] } ?? []
    }

    private func goReceiverType(in declaration: SyntaxNode) -> String? {
        guard let receiver = declaration.firstChild(fieldName: "receiver") else { return nil }
        let text = receiver.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        let components = text.split(whereSeparator: { $0.isWhitespace })
        guard let type = components.last else { return nil }
        return normalizedName(String(type))
    }

    private func normalizedName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct DeclarationClassification {
    let kind: EntityKind
    let callable: Bool
    let container: Bool
    let identifierKind: String
    let fallbackName: String

    static func type(identifier: String) -> DeclarationClassification {
        DeclarationClassification(
            kind: .type,
            callable: false,
            container: true,
            identifierKind: identifier,
            fallbackName: "<anonymous type>"
        )
    }

    static func callable(kind: EntityKind, identifier: String) -> DeclarationClassification {
        DeclarationClassification(
            kind: kind,
            callable: true,
            container: false,
            identifierKind: identifier,
            fallbackName: "<anonymous function>"
        )
    }

    static func binding(identifier: String) -> DeclarationClassification {
        DeclarationClassification(
            kind: .topLevelBinding,
            callable: false,
            container: false,
            identifierKind: identifier,
            fallbackName: "<binding>"
        )
    }
}
