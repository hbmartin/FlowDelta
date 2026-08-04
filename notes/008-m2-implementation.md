# M2 implementation record

Date: 2026-08-04

Implementation is assembled; milestone validation begins after this record.

## Language and analysis

- Added exact-pinned TypeScript/TSX, JavaScript, Python, and Go tree-sitter grammars behind the shared normalized syntax model.
- Added declarative language profiles, entity extraction, and statement-level CFG lowering for TS/JS, Python, and Go while retaining the higher-fidelity Swift builder.
- Git revision ingestion now admits all supported source extensions and retains per-file language identity.
- Added lexical intraprocedural def-use graphs for Swift and TS/JS, def-use edge deltas, data-basis causality, and backward slices over control plus data dependencies.
- Data edges render as a distinct dotted teal overlay and do not influence dominator/rank placement.

## Calls and presentation

- Added deterministic syntax-derived call-graph deltas and radius-limited caller/callee neighborhoods.
- Added optional IndexStoreDB enrichment behind `CallGraphEnriching`, with explicit environment configuration and syntax fallback.
- Added Delta, Before / After, and Calls presentation modes to the native review view.
- Added forward/backward slice direction and kept graph-to-source synchronization in delta, juxtaposed, and call modes.
- Extended JSON model output and Mermaid/Markdown evidence with data edges and basis labels.

## Host integration

- GitX development uses the sibling `../FlowDelta` package while implementing M2.
- The GitX adapter observes History selection and Flow-tab activation, selects the commit's first parent, cancels stale work, and renders package UI without changing the Objective-C History controller.
- `PBGitHistoryView.xib` now has a third native **Flow** tab and segmented-control item. Its index persists through the existing History preference.
- Empty, multiple-selection, working-state, root-commit, unavailable-repository, loading, cancellation, and failure states are represented by native status UI.

## Authored verification

- Representative Swift, TypeScript/TSX, JavaScript, Python, and Go parser/CFG tests.
- Def-use, data-causality, backward-slice, call-neighborhood, layout, exporter, and IndexStore configuration tests.
- Native juxtaposed/call/slice view tests.
- GitX adapter policy, real-nib Flow view, and selected-index persistence tests.

No tests, builds, formatters, linters, coverage commands, or UI validation were run before this implementation record, per the maintainer's milestone sequencing instruction.
