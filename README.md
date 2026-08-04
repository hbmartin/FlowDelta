# FlowDelta

FlowDelta is a deterministic Swift library and CLI for explaining how a Git change alters program control flow. It parses Swift into a normalized syntax tree, matches declarations and syntax across revisions, constructs statement-level control-flow graphs, computes one matched graph delta, and renders the result with native AppKit.

The first release is intentionally Swift-only. Multi-language parsing, data-flow analysis, call graphs, and the GitX History integration are later milestones.

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
- `FlowDeltaAnalysis`: Swift analysis and matched revision delta.
- `FlowDeltaGit`: pluggable revision input with the default safe Git process provider.
- `FlowDeltaLayout`: deterministic CFG layout and staged transition values.
- `FlowDeltaUI`: AppKit graph/review/source views; no SwiftUI or WebKit.
- `FlowDeltaExport`: table, JSON, Mermaid, and Markdown rendering.

`FDFlowDeltaReviewView`, `FDFlowGraphView`, and `FDFlowSourceView` have Objective-C runtime names for thin host adapters. Package model APIs remain Swift-native.

## Trust and limits

Matching confidence is part of the model and exports. Nodes labeled `affected` in the Swift MVP mean **control context** only and carry a causality link to the changed condition. FlowDelta does not claim data-flow impact until the data-flow milestone.

Analysis has hard changed-file, blob, syntax-node, flow-node, and flow-edge limits. A file or function can degrade to diagnostics while the remainder of the report stays usable.

See [PLAN.md](PLAN.md) for the current architecture, milestone status, and release gate. Implementation decisions and validation evidence are recorded in [notes](notes/).

## Development

```sh
swift test
swift build -c release
scripts/run_pinned_tool.sh swiftformat --lint .
scripts/run_pinned_tool.sh swiftlint lint --strict
```

Coverage is enforced from an Xcode result bundle with `scripts/check_coverage.py <result.xcresult>` and ratcheted with `--record-improvements`.

## Requirements

- Swift 6.2 or newer
- macOS 15 or newer
- arm64

FlowDelta is licensed under LGPL-3.0. Linking it into a GPLv2-only application is formally incompatible according to the FSF; embedders make that decision for their own distribution.
