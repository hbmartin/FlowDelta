import FlowDeltaCore
import FlowDeltaParse
import XCTest

/// An entity's declaration header is what a rename keeps: its tokens outside its name, body and comments.
final class DeclarationHeaderTests: XCTestCase {
    func testThePythonHeaderKeepsKeywordsParametersAndExactLiterals() throws {
        let header = try declarationHeader(
            "async def run(x=\" a \",  # the default\n        y=2) -> int:\n    return x\n",
            path: "a.py",
            language: .python
        )
        XCTAssertEqual(header, ["async", "def", "(", "x", "=", "\" a \"", ",", "y", "=", "2", ")", "->", "int", ":"])
    }

    func testTheSwiftHeaderHoldsModifiersAndEffectsButNotTheNameOrBody() throws {
        let header = try XCTUnwrap(try declarationHeader(
            "public func read(_ value: Int) async throws -> Int {\n    return value\n}\n",
            path: "A.swift",
            language: .swift
        ))
        for token in ["public", "func", "async", "throws", "->"] {
            XCTAssertTrue(header.contains(token), "\(token) in \(header)")
        }
        XCTAssertFalse(header.contains("read"), "A rename keeps the header")
        XCTAssertFalse(header.contains("return"), "The body is not part of the header")
        XCTAssertEqual(
            try declarationHeader("let limit = 10\n", path: "A.swift", language: .swift),
            [],
            "A binding is its own body"
        )
    }

    func testAScriptFunctionValueKeepsItsArrowAndAsync() throws {
        let header = try XCTUnwrap(try declarationHeader(
            "const load = async (id) => {\n  return id\n}\n",
            path: "a.ts",
            language: .typescript
        ))
        XCTAssertTrue(header.contains("async"), "\(header)")
        XCTAssertTrue(header.contains("=>"), "\(header)")
        XCTAssertFalse(header.contains("load"), "\(header)")
    }

    func testAnUnknownHeaderMatchesAnyHeader() {
        func entity(_ header: [String]?) -> SourceEntity {
            let location = SourceLocation(utf8Offset: 0, utf16Offset: 0, line: 0, utf16Column: 0)
            let range = SourceRange(start: location, end: location)
            return SourceEntity(
                id: StableID(rawValue: "f"),
                kind: .function,
                name: "f",
                qualifiedName: "f()",
                path: "a.py",
                range: range,
                body: SyntaxNode(id: StableID(rawValue: "b"), kind: "block", range: range, text: ""),
                declarationHeader: header
            )
        }
        XCTAssertTrue(entity(nil).hasSameDeclarationHeader(as: entity(["async", "def"])))
        XCTAssertTrue(entity(["def"]).hasSameDeclarationHeader(as: entity(nil)))
        XCTAssertTrue(entity(["def"]).hasSameDeclarationHeader(as: entity(["def"])))
        XCTAssertFalse(entity(["def"]).hasSameDeclarationHeader(as: entity(["async", "def"])))
    }

    private func declarationHeader(_ text: String, path: String, language: SourceLanguage) throws -> [String]? {
        let snapshot = SourceSnapshot(path: path, revision: RevisionIdentity("r"), language: language, text: text)
        let tree = try SourceSyntaxParser().parse(snapshot)
        let entities = language == .swift
            ? SwiftEntityExtractor().entities(in: tree)
            : SourceEntityExtractor().entities(in: tree)
        return try XCTUnwrap(entities.first, "\(entities)").declarationHeader
    }
}
