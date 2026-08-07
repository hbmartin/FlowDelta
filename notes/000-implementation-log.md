# M0/M1 implementation log

Started: 2026-08-04

## Working agreements

- Implement in `/Volumes/ExtStor/FlowDelta`; GitX remains a consumer planned for M2.
- Keep milestone notes in this directory as implementation proceeds.
- Defer builds, validation, and tests until the end of each milestone.
- M0 has no screen-recording deliverable. Diagnostic stills and deterministic evidence replace it.
- The human reviewer timing exercise is a follow-up metric rather than a `0.1.0` release gate.

## M0 start

- Created branch `codex/m0-m1` from the clean research-only `main` branch.
- Established SwiftPM boundaries for Core, Parse, Match, Flow, Analysis, and Layout.
- Exact dependency choices: SwiftTreeSitter 0.25.0 and tree-sitter-swift's source-complete 0.7.3 release commit (`31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5`). The plain 0.7.3 tag omits generated `parser.c` and cannot build as an SPM dependency.
- M0 code will be written before the first milestone validation pass, per the requested workflow.
- Recorded the M0 identity, matcher, CFG, layout, and evidence contracts in `notes/001-m0-design.md`.
- Added the permanent 20-case matcher audit manifest and an exact `swift-syntax` old/new excerpt for the end-to-end gate.
- Added a reusable `FDFlowGraphView` AppKit/CALayer scene that consumes layout results and installs the three-phase transition plan.

## M0 validation gate

- M0 implementation completed before validation began.
- The gate covers debug and release compilation, all M0 tests, the 20-case audit manifest, the real-commit end-to-end excerpt, the 30-node p95 layout budget, and generation of a diagnostic PNG still (no screen recording).
- Gate passed: 22 XCTest cases and the release build succeeded. Detailed findings and evidence are in `notes/002-m0-validation.md`.

## M1 start

- M0 committed as `39d96d2` (`Implement M0 analysis and rendering spikes`).
- Recorded the Git, matched-delta, AppKit review, export/CLI, and deferred-gate contracts in `notes/003-m1-design.md`.
- Added exact package declarations for ArgumentParser 1.8.2, HighlightKit 0.3.0, and SnapshotTesting 1.19.4 without resolving or building them yet.
- Added offline real-history evidence for ten commits, including exact `swift-syntax` and `swift-nio` old/new excerpts that produce deterministic revision reports.
- Implemented the shell-free Git provider, raw and parsed unified-diff values, commit-scope entity matching, matched flow-node/edge projection, control-context causality, and micro-change classifications.
- Implemented deterministic table/JSON/Mermaid/Markdown exporters and the ArgumentParser `flowdelta` command.
- Implemented the Snow Leopard-inspired AppKit review surface, accessible layer-backed node views, delta-colored edges, HighlightKit source sync, forward slicing, and the reference macOS app.
- Added M1 Git/delta/export/CLI/UI tests, SnapshotTesting support, pinned lint/format configuration, a coverage ratchet, and macOS CI. Validation remains deferred until the milestone implementation is declared complete.

## M1 implementation complete

- Completed the full Git-to-review vertical slice and recorded the implementation inventory in `notes/005-m1-implementation.md`.
- Confirmed that GitX integration remains outside this package milestone and is deferred to M2.
- Declared implementation complete before resolving the new packages, compiling, formatting, linting, testing, measuring coverage, or generating the M1 diagnostic still. The deferred M1 validation gate begins after this point.

## M1 validation gate

- Resolved the exact package graph, including HighlightKit 0.3.0, only after the implementation-complete checkpoint.
- Fixed issues discovered by the gate in formatter/linter alignment, Swift 6 compilation, condition-subtree matching, Git rename evidence, native split-view constraints, and Xcode-sandboxed snapshot lookup.
- Gate passed with 48 XCTest cases, a release build, a real release-CLI smoke across every export format, a verified native snapshot, and 93.13% library line coverage.
- Ratcheted the four critical file floors to 95.42–97.57%. Full evidence is recorded in `notes/006-m1-validation.md`.
