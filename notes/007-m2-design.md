# M2 design record

Started 2026-08-04 from FlowDelta `0.1.0` on branch `codex/m2`.

## Scope

- Extend revision ingestion and statement-level CFG construction from Swift to TypeScript/JavaScript, Python, and Go.
- Add def-use edges, data-context `affected` causality, and backward slicing for Swift and TypeScript/JavaScript.
- Add a radius-limited call-graph neighborhood and a juxtaposed before/after graph presentation.
- Ship the native GitX History **Flow** tab through the external package boundary in ADRs 0007 and 0008.

## Package and language boundary

`FlowDeltaParse` owns a declarative `LanguageProfile` for grammar node names, entity declarations, control constructs, and binding syntax. The generic tree-sitter lowering keeps the per-language handwritten surface bounded. Swift retains its existing specialized builder where it provides higher fidelity; the shared builder covers TS/JS, Python, and Go.

Grammar packages are exact pinned to the last source-complete releases that use the same `ChimeHQ/SwiftTreeSitter` package identity as FlowDelta:

- tree-sitter-javascript `0.23.1`
- tree-sitter-typescript `0.23.2`
- tree-sitter-python `0.23.6`
- tree-sitter-go `0.23.4`

IndexStoreDB is pinned to revision `c993f4fb4f321fae1945e96a2377742f24e132f4`. Its manifest selects `swift-lmdb` from `main`; SwiftPM rejects an attempted top-level revision override as two incompatible revision requirements, so the transitive requirement remains package-owned.

## Data-flow boundary

Def-use analysis is intraprocedural and lexical in M2. It binds local declarations, parameters, assignments, and identifier uses to CFG blocks. Edges retain the symbol name and source/target block identities. Changed def-use edges can mark retained blocks as `affected` with the explicit `.data` basis. Backward slicing traverses incoming control and data dependencies.

## Call-graph boundary

The base call graph is deterministic and source-derived. Swift enrichment is isolated behind a protocol so IndexStoreDB symbols can augment, but never replace, source-derived evidence. Neighborhood projection is radius limited and stable-ID sorted. Hosts opt into an existing index with `FLOWDELTA_INDEXSTORE_PATH`, `FLOWDELTA_INDEXDATABASE_PATH`, and `FLOWDELTA_LIBINDEXSTORE_PATH`; missing or failed enrichment preserves the syntax-derived graph.

## GitX integration boundary

GitX will exact-pin the released FlowDelta package and link only the products required by `FlowDeltaAdapters.swift`. A XIB-instantiated Swift adapter owns the package review view, observes the History controller's selected commit, chooses the first parent as the base revision, cancels stale analysis, and renders errors/empty states natively. No Objective-C controller edit is required.

## Verification plan

Test execution is deferred until the complete M2 implementation boundary per the maintainer's instruction. Tests will cover representative and malformed language constructs, data-flow and slice invariants, call-graph radius behavior, adapter state decisions, History tab persistence/wiring, and the launched UI diagnostic screenshot. Final verification will include package and GitX correctness plans with coverage, GitX UI plan, pinned formatting/lint, relevant Thread Sanitizer coverage for cancellation/task state, and the stable Debug app at `build/GitX.app`.
