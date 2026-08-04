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
