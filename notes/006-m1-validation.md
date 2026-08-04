# M1 validation record

Date: 2026-08-04

Result: **passed**

Validation began only after `notes/005-m1-implementation.md` declared implementation complete.

## Automated gate

- Pinned SwiftFormat 0.62.1 formatted the package and then passed in lint mode.
- Pinned SwiftLint 0.63.2 passed with `--strict` and zero violations.
- `swift test` passed 48 XCTest cases across Core, Analysis, Layout, Git, Export, CLI, and UI targets.
- `swift test -c release` passed the same 48 XCTest cases under optimization.
- The native reference snapshot passed from its bundled hermetic baseline under both SwiftPM and Xcode's test sandbox.
- `swift build -c release` completed successfully for the libraries, `flowdelta`, and `FlowDeltaReference`.
- Xcode's `FlowDelta-Package` scheme passed with code coverage enabled in `build/FlowDeltaCoverageFinal2.xcresult`.
- `scripts/check_coverage.py` measured 93.13% line coverage across 29 FlowDelta library files.

The coverage ratchet was raised after the green run:

| Scope | Floor |
| --- | ---: |
| Overall library | 93.13% |
| `FlowDeltaAnalyzer.swift` | 95.97% |
| `MatchedFlowDeltaBuilder.swift` | 95.75% |
| `GitCLIRevisionProvider.swift` | 97.57% |
| `FlowDeltaReviewView.swift` | 95.42% |

Xcode beta emitted IDE log-store and launch-session diagnostic warnings while returning a successful test result; no product or XCTest failure accompanied them.

## Integration evidence

- Temporary Git repositories exercised modification, rename, addition, deletion, paths containing spaces, invalid revisions, changed-file limits, blob limits, and a missing repository.
- Analysis covered all five node states, matched edge invariants, commit-scope cross-file moves, control-basis causality, micro-change classification, syntax/flow resource degradation, and exact SwiftSyntax/SwiftNIO revision fixtures.
- The optimized `flowdelta` binary analyzed a real two-commit temporary repository. Its default table rendered, JSON parsed with `jq`, and Mermaid and Markdown contained the expected stable graph/report markers.
- The temporary CLI smoke repository was moved to the user's Trash after validation.

## Native visual evidence

The current diagnostic still is `notes/artifacts/m1-reference-review.png`. It was inspected at original resolution and shows:

- Snow Leopard-inspired gradient chrome and source-list triage;
- a visible native graph/source split with scrollable graph content;
- added, removed, modified, and control-context affected legend semantics;
- delta-colored nodes and edges;
- HighlightKit-rendered target source;
- the Forward Slice control;
- no Auto Layout conflict warnings during the verified snapshot run.

The checked-in baseline is `Tests/FlowDeltaUITests/__Snapshots__/FlowDeltaReviewViewTests/testReviewViewMatchesNativeReferenceSnapshot.1.png`. No screen recording is part of the milestone.

## Gate conclusion

M1 meets the package release gate. The informal reviewer timing exercise remains the post-release follow-up recorded in `notes/004-review-timing-follow-up.md`; GitX integration remains M2.
