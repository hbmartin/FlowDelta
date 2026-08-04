# M1 implementation completion record

Date: 2026-08-04

M1 implementation is complete. Validation was intentionally deferred until this record, in accordance with the milestone working agreement.

## Implemented vertical slice

- `FlowDeltaGit` resolves revisions with a shell-free `/usr/bin/git` process boundary, reads rename-aware NUL-delimited changes, loads Swift blobs, retains a zero-context unified diff, and enforces file/blob limits.
- `FlowDeltaAnalysis` performs commit-scope entity matching, builds per-function matched CFG deltas, projects syntax edits onto nodes and edges, records control-basis causality, and emits micro-change classifications.
- `FlowDeltaExport` provides deterministic table, JSON, Mermaid, and Markdown artifacts.
- `flowdelta` exposes the revision analyzer through ArgumentParser, with repository, format, and atomic output options.
- `FlowDeltaUI` provides the Snow Leopard-inspired native review surface: triage, a superimposed matched graph, delta-colored nodes and edges, HighlightKit-backed source rendering, selection synchronization, staged transitions, and forward-slice focus.
- `FlowDeltaReference` hosts the complete review surface as a native macOS executable.

## Evidence prepared for the gate

- Temporary-repository Git cases cover modification, rename, addition, deletion, paths containing spaces, invalid revisions, and size limits.
- Analysis cases cover every delta state, edge projection, control-only affected causality, invariants, classifications, commit triage, and cross-file moves.
- Exact SwiftSyntax and SwiftNIO fixture pairs plus the ten-entry revision corpus exercise deterministic real-history reports.
- Export and CLI tests cover stable parseable artifacts and argument behavior.
- AppKit decision tests cover graph accessibility, source synchronization, selection, slicing, and the full reference-review snapshot.
- Package-owned pinned format/lint configuration, a 90% coverage ratchet, and macOS CI encode the release gate.

## Deliberate boundaries

- GitX consumption remains M2 work; M1 does not modify or pin the package into GitX.
- `affected` means control context only. M1 makes no data-flow or call-graph claim.
- The reviewer timing exercise remains post-release follow-up. The visual artifact for this milestone is a diagnostic still, with no screen recording.

## Next action

Run the complete deferred M1 gate once: dependency resolution, format/lint, debug and release builds, tests, snapshots, CLI integration, coverage enforcement, and diagnostic-still inspection. Any issues found belong to the validation/fix loop and will be recorded separately.
