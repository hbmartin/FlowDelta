# M2 semantic-release boundary correction

Date: 2026-08-04

GitX's first resolution of the exact 0.2.0 tag exposed a boundary that a local `../FlowDelta` package cannot exercise: SwiftPM rejects a semantic-versioned package when its manifest includes revision- or branch-based dependencies. The rejected graph contained tree-sitter-swift by revision and IndexStoreDB by revision, with IndexStoreDB itself selecting swift-lmdb's `main` branch.

The correction keeps the runtime contract while making the primary package eligible for an exact semantic pin:

- tree-sitter-swift uses its source-complete semantic prerelease tag `0.7.3-with-generated-files`, which identifies the same previously validated commit;
- optional IndexStoreDB enrichment moves to `Extensions/FlowDeltaIndexStore`, a separately resolved extension package whose unstable upstream graph no longer contaminates the core release;
- the default FlowDelta package and GitX integration retain deterministic syntax-derived call edges and syntax fallback;
- GitX does not link the optional extension until its upstream dependency graph offers a semantic release or a separately reviewed extension pin is adopted.

Version 0.2.0 remains an immutable record of the failed external-resolution attempt. The corrected package will be released as 0.2.1 only after the root and extension validation gates pass and a clean exact-pin consumer resolution succeeds.

## Correction validation

- Root dependency resolution selected only semantic versions, including tree-sitter-swift `0.7.3-with-generated-files`; IndexStoreDB and swift-lmdb are absent from the core graph.
- Root debug and release suites each passed all 66 tests, including the native snapshot; the standalone release build passed.
- The separate extension debug and release suites each passed all 3 tests, including compilation of a real Swift index and IndexStoreDB call-edge enrichment.
- Root Xcode coverage passed all 66 tests at 94.03% across 37 library files; the existing ratchet remains satisfied.
- Pinned SwiftFormat and strict SwiftLint passed across root and extension sources with zero violations.

The remaining pre-push gate is resolving and building a clean consumer against the final local 0.2.1 semantic tag, followed by the real GitX exact-pin resolution.
