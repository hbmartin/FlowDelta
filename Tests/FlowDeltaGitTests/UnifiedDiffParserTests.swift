import FlowDeltaGit
import XCTest

final class UnifiedDiffParserTests: XCTestCase {
    func testParsesMultipleHunksAndPathsWithSpaces() throws {
        let value = """
        diff --git a/Sources/Old Name.swift b/Sources/New Name.swift
        --- a/Sources/Old Name.swift
        +++ b/Sources/New Name.swift
        @@ -2,2 +2,3 @@ func value() {
         unchanged()
        -old()
        +new()
        +added()
        @@ -10 +11,0 @@
        -removed()
        """
        let patch = try XCTUnwrap(UnifiedDiffParser().parse(value).first)

        XCTAssertEqual(patch.oldPath, "Sources/Old Name.swift")
        XCTAssertEqual(patch.newPath, "Sources/New Name.swift")
        XCTAssertEqual(patch.hunks.count, 2)
        XCTAssertEqual(patch.hunks[0].oldLines.start, 2)
        XCTAssertEqual(patch.hunks[0].newLines.count, 3)
        XCTAssertEqual(patch.hunks[0].context, "func value() {")
        XCTAssertEqual(patch.hunks[1].newLines.count, 0)
    }

    func testParsesAddedFileDevNull() throws {
        let value = """
        diff --git a/Added.swift b/Added.swift
        --- /dev/null
        +++ b/Added.swift
        @@ -0,0 +1 @@
        +func added() {}
        """
        let patch = try XCTUnwrap(UnifiedDiffParser().parse(value).first)

        XCTAssertNil(patch.oldPath)
        XCTAssertEqual(patch.newPath, "Added.swift")
        XCTAssertEqual(patch.hunks[0].oldLines, .init(start: 0, count: 0))
    }

    func testRejectsMalformedHunkHeader() {
        XCTAssertThrowsError(try UnifiedDiffParser().parse("@@ nonsense @@")) { error in
            XCTAssertEqual(error as? UnifiedDiffParserError, .malformedHunkHeader("@@ nonsense @@"))
        }
    }
}
