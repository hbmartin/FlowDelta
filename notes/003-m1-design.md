# M1 Swift MVP design record

Date: 2026-08-04

## Deliverable

M1 turns the M0 foundations into one reviewable vertical slice:

`git revisions → Swift blobs → entity triage → AST edits → CFG pair → matched flow delta → native review view / CLI exports`

The supported input is a local Git repository and two commit-ish values. Only changed `.swift` files enter analysis. Every layer remains available through injected value inputs so embedders do not need to shell out to Git.

## Package boundaries

- `FlowDeltaGit`: `RevisionProvider` plus the default safe `/usr/bin/git` implementation.
- `FlowDeltaAnalysis`: revision orchestration and matched CFG-delta construction.
- `FlowDeltaExport`: deterministic table, JSON, Mermaid, and Markdown output.
- `FlowDeltaUI`: AppKit/CALayer graph and source-review views.
- `flowdelta`: ArgumentParser-based headless executable.
- `FlowDeltaReference`: small native macOS reference app and diagnostic host.

M1 adds exact pins for ArgumentParser 1.8.2, HighlightKit 0.3.0, and SnapshotTesting 1.19.4. HighlightKit owns Swift syntax coloring in the source pane; FlowDelta applies source-selection overlays after highlighting.

## Git boundary

The provider invokes Git without a shell and passes every argument separately. It canonicalizes revisions with `rev-parse`, reads NUL-delimited rename-aware name status, loads blobs with `git show <revision>:<path>`, and obtains zero-context diffs for anchoring. Standard error and exit status are preserved in typed errors. File-count and blob-size limits are checked before analysis.

## Matched flow delta

Syntax mappings project onto flow nodes through their syntax IDs. Entry, normal-exit, and error-exit nodes are paired explicitly; remaining source nodes are greedily paired by mapped-syntax overlap, then compatible kind/label fallback. Edge matching uses projected endpoints, edge kind, and label.

The node vocabulary is `added`, `removed`, `retained`, `modified`, and `affected`. In M1, `affected` means control context only: an otherwise retained downstream node is reachable from a modified condition. Each affected node records a control-basis causality link to its triggering condition. No data-flow claim is made.

## Native review surface

The reference view follows GitX's Snow Leopard-inspired AppKit vocabulary: a compact gradient header, source-list-style triage table, beveled controls, a native split view, a CALayer graph canvas, and an `NSTextView` source pane. Four-state coloring is always paired with labels/legend; affected nodes explicitly say “control context.”

Selecting a function renders one superimposed matched graph. Selecting a graph node highlights and scrolls its UTF-16 source range. Forward-slice focus traverses control edges and dims nodes outside the slice. Stable delta IDs drive the existing staged transition.

## Exports and CLI

The CLI default is a terminal triage table with per-function summaries. `--format json`, `mermaid`, or `markdown` selects a portable artifact, and `--output` writes it atomically. JSON uses sorted keys; Mermaid identifiers are stable-ID-derived and escaped; Markdown includes the triage executive summary before graph details.

## M1 gate (deferred until implementation completion)

- Git-provider integration tests in temporary repositories, including rename, add, delete, spaces, invalid revision, and blob limit.
- Delta invariants for all five states, control-basis causality, edge projection, and forward slice.
- Golden exporter and CLI tests.
- AppKit decision-level tests plus SnapshotTesting image baselines for the complete reference review view.
- Real-history snapshot corpus entries from `swift-syntax` and `swift-nio` provenance.
- Debug/release builds, full XCTest suite with coverage, strict pinned SwiftLint and SwiftFormat, and diagnostic PNG generation.

The informal reviewer timing exercise remains a post-release metric, not the M1 build gate.
