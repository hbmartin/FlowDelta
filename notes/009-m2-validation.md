# M2 validation record

Date: 2026-08-04

Result: **FlowDelta package gate passed; GitX consumer gate follows the published 0.2.0 tag**

Validation began only after `notes/008-m2-implementation.md` declared implementation complete.

## Package results

- Debug: `swift test` passed all 69 XCTest cases.
- Release: `swift test -c release` passed all 69 XCTest cases; `swift build -c release` passed.
- Xcode coverage: `FlowDeltaM2Coverage4.xcresult` passed all 69 cases with no product runtime warnings.
- Coverage: `scripts/check_coverage.py` passed at **94.03% across 38 library files**, up from 93.13%; `--record-improvements` raised the overall floor and the four tracked file floors.
- Style: pinned SwiftFormat 0.62.1 lint passed; pinned SwiftLint 0.63.2 strict passed with zero violations.
- Native UI: the reference snapshot passed after exercising Delta, Before / After, Calls, forward/backward slices, and call-to-source synchronization.
- Diagnostic still: `notes/artifacts/m2-reference-review.png` was inspected at original resolution. The updated snapshot is checked in beside the UI tests. No screen recording was made.
- Git/index integration: real repositories covered all supported extensions, rename/add/delete, spaces, limits, invalid revisions, invalid UTF-8 metadata/blobs, and a real Swift compiler index consumed through IndexStoreDB.
- CLI: release `flowdelta` reported 0.2.0 and produced structurally checked table, JSON, Mermaid, and Markdown artifacts for the real `39d96d2..b5bdacf` history range. The 390 MB temporary smoke directory was deleted after validation.

The Xcode 27 beta runner emitted its own IDE log-store and launch-session diagnostic warnings. The result bundle passed, and no warning originated from FlowDelta runtime behavior.

## GitX gate

GitX development used the sibling `../FlowDelta` checkout as required. After this package is committed, pushed, and tagged 0.2.0, the consumer project will switch to an exact remote 0.2.0 pin and run its correctness/UI plans, pinned style tools, analyzer and coverage baselines, supported sanitizer checks, final app refresh, and native Flow-tab screenshot.
