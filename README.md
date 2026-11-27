# FlowDelta

FlowDelta is a deterministic Swift library and CLI for explaining how a Git change alters program control and data flow. It parses Swift, TypeScript/JavaScript, Python, and Go into normalized syntax trees; matches declarations and syntax across revisions; constructs statement-level control-flow graphs; and renders matched graph deltas with native AppKit.

Swift and TypeScript/JavaScript also include lexical intraprocedural def-use deltas, explicitly basis-labeled data-context impact, and backward slicing. Source-derived call neighborhoods are always available and can be enriched for Swift by the separately resolved IndexStoreDB extension.

## Quick start

```sh
swift build
swift run flowdelta -C /path/to/repository BASE_REVISION HEAD
swift run flowdelta -C /path/to/repository --format markdown -o flow-report.md BASE_REVISION HEAD
swift run FlowDeltaReference
```

The default CLI output is an entity triage table followed by per-function flow summaries. `--format json`, `mermaid`, and `markdown` produce portable evidence artifacts.

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

Matching confidence is part of the model and exports. Nodes labeled `affected` carry causality links whose basis is explicitly `control`, `data`, or both. Data-flow claims are limited to Swift and TypeScript/JavaScript in M2; Python and Go remain control-flow only.

Analysis has hard changed-file, blob, syntax-node, flow-node, and flow-edge limits. A file or function can degrade to diagnostics while the remainder of the report stays usable. Only an exceeded limit is reported as `resourceLimit`; any other failure to analyze a file is `internalInvariant`.

Analysis and revision loading are cancellable. Cancelling the task that runs `FlowDeltaAnalyzer.analyze` stops it at the next file, entity, or function, and cancelling `GitCLIRevisionProvider.comparison` terminates the running `git` process. Both then throw `CancellationError`, so hosts should treat that error as "superseded" rather than as a failure.

See [PLAN.md](PLAN.md) for the current architecture, milestone status, and release gate. Implementation decisions and validation evidence are recorded in [notes](notes/).

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
