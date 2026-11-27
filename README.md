# FlowDelta

FlowDelta is a deterministic Swift library and CLI for explaining how a Git change alters program control and data flow. It parses Swift, TypeScript/JavaScript, Python, and Go into normalized syntax trees; matches declarations and syntax across revisions; constructs statement-level control-flow graphs; and renders matched graph deltas with native AppKit.

Every language also includes intraprocedural def-use deltas, explicitly basis-labeled data-context impact, and backward slicing. Swift and TypeScript/JavaScript read definitions and uses lexically; Python and Go read them from syntax-tree binding rules. Source-derived call neighborhoods are always available and can be enriched for Swift by the separately resolved IndexStoreDB extension.

## Quick start

```sh
swift build
swift run flowdelta -C /path/to/repository BASE_REVISION HEAD
swift run flowdelta -C /path/to/repository --format markdown -o flow-report.md BASE_REVISION HEAD
swift run FlowDeltaReference
```

The default CLI output is an entity triage table followed by per-function flow summaries. `--format json`, `mermaid`, and `markdown` produce portable evidence artifacts.

Three options shape a review; without them the table, Mermaid, and Markdown output is unchanged:

- `--noise hide-formatting|hide-cosmetic` shows formatting-only (and, for `hide-cosmetic`, optional-syntax) node changes as retained and says how many it hid. Equivalent rewrites such as `a += b` for `a = a + b` are never hidden.
- `--group-by-concern` orders the triage by concern group (behavioral groups joined by calls, name references, and shared types; then renames, moves, and rewrites; then cosmetic changes) and notes a tangled revision that mixes behavioral concerns.
- `--walkthrough` appends ordered review steps with narration to table, Markdown, and JSON output. JSON then becomes `{"report": …, "walkthrough": […]}`.

Libraries get the same choices through `FlowDeltaExportOptions`, and the pure `FlowNoiseFilter`, `FlowWalkthrough`, and `RevisionFlowDeltaReport.concerns` APIs.

## Libraries

- `FlowDeltaCore`: source, entity, syntax, CFG, delta, diagnostic, and report values.
- `FlowDeltaAnalysis`: multi-language analysis, matched revision deltas, data causality, and source-derived call graphs.
- `FlowDeltaGit`: pluggable revision input with the default safe Git process provider.
- `FlowDeltaLayout`: deterministic CFG layout and staged transition values.
- `FlowDeltaUI`: AppKit graph/review/source views; no SwiftUI or WebKit.
- `FlowDeltaExport`: table, JSON, Mermaid, and Markdown rendering.
- `Extensions/FlowDeltaIndexStore`: optional precise Swift call-edge enrichment from an existing IndexStoreDB index. It is a separate package so IndexStoreDB's revision-based dependency graph does not prevent exact semantic pins of the core package.

`FDFlowDeltaReviewView`, `FDFlowGraphView`, and `FDFlowSourceView` have Objective-C runtime names for thin host adapters. Package model APIs remain Swift-native.

## Trust and limits

Matching confidence is part of the model and exports. Nodes labeled `affected` carry causality links whose basis is explicitly `control`, `data`, or both. Def-use is per statement and intraprocedural: it does not follow aliasing, fields or calls, and a Python name declared `global` or `nonlocal` is not treated as local.

Analysis has hard changed-file, blob, syntax-node, flow-node, and flow-edge limits. A file or function can degrade to diagnostics while the remainder of the report stays usable. Only an exceeded limit is reported as `resourceLimit`; any other failure to analyze a file is `internalInvariant`.

Analysis and revision loading are cancellable. Cancelling the task that runs `FlowDeltaAnalyzer.analyze` stops it at the next file, entity, or function, and cancelling `GitCLIRevisionProvider.comparison` terminates the running `git` process. Both then throw `CancellationError`, so hosts should treat that error as "superseded" rather than as a failure.

See [PLAN.md](PLAN.md) for the current architecture, milestone status, and release gate. Implementation decisions and validation evidence are recorded in [notes](notes/).

## Embedding

`FlowDeltaReviewView` (`FDFlowDeltaReviewView` in Objective-C) is the review a host embeds. Call `display(_:)` with a `RevisionFlowDeltaReport`, then drive it with `setPresentation(_:)` (delta, before/after, calls), `setSlice(_:)` (forward, backward, or nil), `selectTriageRow(_:)` and `selectGraphNode(withStableID:)`. `state` reports the presentation, slice, selected function and selected node.

Set `delegate` to a `FlowDeltaReviewViewDelegate` to hear each state change once, after it renders, with its cause: `.user` for controls, the triage list, the graph, node menus and keys, and `.host` for API calls and `display(_:)`. Persist preferences only for `.user` changes. The delegate can also append items to graph node context menus. Copy Label and Copy Location write to `pasteboard` (the general pasteboard by default).

`setNoise(_:)` hides formatting or all cosmetic node changes (`hiddenNoiseCount` says how many), `setGroupsByConcern(_:)` groups triage by concern, and `startWalkthrough()`, `showNextWalkthroughStep()`, `showPreviousWalkthroughStep()` and `endWalkthrough()` drive the walkthrough. `state` includes the noise level, grouping and walkthrough step, so a host can persist them like the presentation and slice.

The review view draws Snow Leopard chrome in fixed light colors, so it adopts the Aqua appearance even inside a Dark Mode window. A host that sets `appearance` itself replaces this.

Node context menus offer Show Source, Forward or Backward Slice from Here and Clear Slice (delta presentation only), Copy Label and Copy Location, and Review Function for call nodes. In the focused graph, the arrow keys, Home and End move between nodes, Return shows the selected node's source, Space toggles its slice, and Escape clears the slice. Tab moves from the triage list to the graph and then the source.

Accessibility identifiers:

| Identifier | Element |
|---|---|
| `FlowDelta.Review` | The review view |
| `FlowDelta.Review.Revisions`, `.Summary` | Header labels |
| `FlowDelta.Review.Triage` | Triage table |
| `FlowDelta.Review.Function` | Selected function label |
| `FlowDelta.Review.Presentation` | Delta / Before & After / Calls control |
| `FlowDelta.Review.Slice`, `.SliceDirection` | Slice checkbox and direction control |
| `FlowDelta.Review.Graph`, `.ComparisonGraph` | Main graph and, in before/after, the target graph |
| `FlowDelta.Review.Source` | Source text view |
| `FlowDelta.Review.Noise`, `.HiddenNoise` | Noise pop-up and the "N hidden — Show" link |
| `FlowDelta.Review.GroupByConcern` | Group by Concern checkbox |
| `FlowDelta.Review.TangledBanner`, `.TangledBanner.Message`, `.TangledBanner.Group` | Tangled revision banner, its message and its Group by Concern button |
| `FlowDelta.Review.Walkthrough` | Walkthrough button |
| `FlowDelta.Review.WalkthroughBar`, `.Walkthrough.Previous`, `.Walkthrough.Next`, `.Walkthrough.Step`, `.Walkthrough.Narration`, `.Walkthrough.Done` | Walkthrough bar and its controls |
| `FlowDelta.Review.NodeMenu.<command>` | Node context menu items, e.g. `forwardSlice` |
| node stable ID | Each graph node (an accessibility button) |

## Development

```sh
swift test
swift build -c release
swift test --package-path Extensions/FlowDeltaIndexStore
scripts/run_pinned_tool.sh swiftformat --lint .
scripts/run_pinned_tool.sh swiftlint lint --strict
```

Coverage is enforced from an Xcode result bundle with `scripts/check_coverage.py <result.xcresult>` and ratcheted with `--record-improvements`.

IndexStoreDB enrichment is optional and degrades to source-derived call edges. Consumers that deliberately adopt `Extensions/FlowDeltaIndexStore` configure an existing Swift index with `FLOWDELTA_INDEXSTORE_PATH`, a writable `FLOWDELTA_INDEXDATABASE_PATH`, and the active toolchain's `FLOWDELTA_LIBINDEXSTORE_PATH`.

## Requirements

- Swift 6.2 or newer
- macOS 15 or newer
- arm64

FlowDelta is licensed under LGPL-3.0. Linking it into a GPLv2-only application is formally incompatible according to the FSF; embedders make that decision for their own distribution.
