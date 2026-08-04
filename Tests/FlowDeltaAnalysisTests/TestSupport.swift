import FlowDeltaCore
import Foundation

enum FixtureError: Error {
    case missing(String)
}

func fixture(_ name: String, extension fileExtension: String = "swift") throws -> String {
    guard let url = Bundle.module.url(
        forResource: name,
        withExtension: fileExtension,
        subdirectory: "Fixtures"
    )
    else {
        throw FixtureError.missing("\(name).\(fileExtension)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

func snapshot(_ text: String, path: String = "Fixture.swift", revision: String = "fixture") -> SourceSnapshot {
    SourceSnapshot(path: path, revision: RevisionIdentity(revision), language: .swift, text: text)
}
