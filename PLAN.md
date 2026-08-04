# FlowDelta implementation plan

FlowDelta is a standalone Swift package and CLI that deterministically explains how a Git change alters program control flow. It is developed and released from `hbmartin/FlowDelta`; GitX is one future consumer and will exact-pin releases through the boundary described by GitX ADR 0007.

This file is the package-local implementation source of truth. `Proposal.md` and `docs/` retain the research record and longer product rationale.

## Product contract

Given a base revision and target revision, FlowDelta produces:

1. entity triage for added, removed, modified, moved, renamed, and unchanged declarations;
2. confidence-bearing syntax correspondence and insert/delete/update/move edits;
3. statement-level control-flow graphs for changed Swift callables;
4. a matched graph delta with added, removed, retained, modified, and affected nodes;
5. native AppKit review views and portable table, JSON, Mermaid, and Markdown artifacts.

`affected` is always basis-labeled. M1 supports control context only. Data-flow and call-graph claims do not enter the product until their analyses exist.

## Architecture

| Layer | Target | Responsibility |
| --- | --- | --- |
| Input | `FlowDeltaGit` | Pluggable `RevisionProvider`; default shell-free Git process provider |
| Parse | `FlowDeltaParse` | tree-sitter Swift → normalized package-owned IR |
| Triage/match | `FlowDeltaMatch` | entity cascade and GumTree-style syntax mapping |
| Flow | `FlowDeltaFlow` | bounded Swift statement-level CFG lowering |
| Delta | `FlowDeltaAnalysis` | revision orchestration, CFG projection, control-context causality |
| Layout | `FlowDeltaLayout` | deterministic dominator-anchored ranks and back-edge lanes |
| Present | `FlowDeltaUI` | AppKit, accessible layer-backed node views, Core Animation, highlighted source |
| Interop | `FlowDeltaExport`, `flowdelta` | table/JSON/Mermaid/Markdown and CLI |

The pipeline escalates lazily from cheap triage to function analysis. Hard file, blob, syntax, node, and edge limits degrade the affected scope instead of taking down the whole report.

## Stable and matched identity

- IDs use package-owned deterministic hashing, never Swift's randomized `Hasher`.
- Revision-independent syntax IDs preserve unchanged positions across revisions.
- Entity matching runs exact overload-qualified name, structural body hash, then token Dice ≥ 0.80.
- Syntax matching runs unique identical-subtree anchors, bottom-up Dice, then conservative unique-child alignment.
- Flow correspondence projects syntax mappings; every heuristic mapping retains its confidence.
- Presentation and animation use matched delta IDs, so one graph—not two unrelated pictures—is the diff.

## Swift CFG scope

M1 lowers sequential statements, `if`/`else`, `guard`, `switch`, `for`, `while`, `repeat`, `do`/`catch`, `defer`, `return`, `throw`, `break`, `continue`, and conservative plain-`try` exception edges. `try?` and `try!` do not create speculative exceptional paths.

tree-sitter recovery stays visible as basic blocks. The known tree-sitter-swift 0.7.3 `defer` grammar gap is normalized from its unambiguous call-expression representation.

## Presentation contract

The native surface follows GitX ADR 0008 without integrating into GitX during M1:

- AppKit only; no SwiftUI or WebKit;
- `FDFlowDeltaReviewView`, `FDFlowGraphView`, and `FDFlowSourceView` are Objective-C-runtime-visible classes;
- `CAShapeLayer` edges and accessible, layer-backed node views;
- deterministic superimposed graph with five model states and four change colors;
- explicit staged fade → move → reveal animations;
- HighlightKit 0.3.0 source coloring, graph selection → UTF-16 source selection;
- forward control-slice focus;
- Snow Leopard-inspired hierarchy and control treatment.

GitX's third History **Flow** tab remains M2. GitX will use a thin app-target adapter and may inject an ObjectiveGit-backed revision provider. FlowDelta itself does not depend on ObjectiveGit.

## Milestones

### M0 — de-risk foundations (complete)

- Normalized Swift parsing, entity/matcher prototype, CFG lowering, layout, CALayer rendering, and staged transition.
- Twenty-entry hand-audit seed from `swift-syntax` and `swift-nio`.
- 30-node single-frame layout gate and diagnostic PNG.
- Evidence: `notes/002-m0-validation.md`.

### M1 — Swift-only MVP (complete)

- Commit in → triage → per-function matched CFG delta.
- Control-context `affected` with causality.
- Native review/source view, staged transitions, and forward slice.
- `flowdelta` table/JSON/Mermaid/Markdown output.
- Reference macOS app and real-history/snapshot corpus.
- Package-owned ≥90% coverage ratchet, pinned lint/format, and CI.

Evidence: `notes/006-m1-validation.md`.

The human review timing exercise is a follow-up dogfood metric, not a release gate.

### M2 — multi-language, data flow, and GitX

- TypeScript/JavaScript, Python, and Go CFG mappings.
- Swift and TypeScript/JavaScript def-use deltas, data-context affected state, and backward slices.
- Call-graph neighborhood and IndexStoreDB enrichment.
- GitX History Flow tab through exact-pinned package and thin adapter.

### M3 — depth and polish

- Walkthrough mode, remaining language binding rules, noise dial, concern grouping, MCP hooks, and iPad-ready core audit.

## M1 release gate

- All tests pass in debug and release configurations.
- Real Git repository integration covers modification, rename, addition, deletion, spaces, invalid revision, and limits.
- Export and CLI artifacts are deterministic and parseable.
- Native reference snapshots pass and a current diagnostic still is attached; no screen recording is required.
- Pinned SwiftFormat and strict SwiftLint pass.
- Library line coverage is at least 90%, enforced and ratcheted by `scripts/check_coverage.py`.
- `0.1.0` is tagged only after the gate is green; consumers exact-pin that tag.

## Constraints and accepted risks

- Swift 6.2, macOS 15+, arm64, SwiftPM.
- No JavaScript runtime, server, telemetry, SwiftUI, WebKit, ObjectiveGit, SwiftSyntax, IndexStoreDB, or ELK dependency in M1.
- AST matching is heuristic; confidence is never hidden.
- Generated/very large inputs are bounded and diagnostically skipped.
- FlowDelta is LGPL-3.0. Combining it with GPLv2-only GitX is formally incompatible according to the FSF and is a knowingly accepted embedder decision documented in both repositories.
