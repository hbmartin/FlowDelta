# M0 design record

Date: 2026-08-04

## Scope

M0 proves the three risky foundations needed by the Swift-only MVP:

1. Swift source can be normalized from tree-sitter into a package-owned, UTF-8/UTF-16-aware syntax model and lowered to a useful statement-level CFG.
2. Entity and syntax matching are deterministic, confidence-bearing, and auditable against real commit pairs.
3. A small CFG can be laid out deterministically, preserve stable anchors between revisions, and provide a staged transition model suitable for Core Animation.

The milestone deliberately excludes git revision loading, delta classification, exporters, CLI, and AppKit presentation. Those belong to M1.

## Stable identity

- Syntax IDs combine the source path, normalized node kind, UTF-16 range, and grammar field. Revision identity is deliberately excluded so unchanged nodes keep identity across revisions.
- Entity IDs combine path, entity kind, overload-qualified name, and declaration start offset.
- Flow-node IDs combine entity and syntax identity; synthetic nodes add a deterministic role.
- Edge IDs combine source, target, edge kind, and label.
- Hashes use the package-owned deterministic digest rather than Swift's process-randomized `Hasher`.

Source offsets are retained in both UTF-8 and UTF-16 coordinates so tree-sitter byte ranges can round-trip to AppKit text storage without guessing.

## Matching

Entity triage uses the explainable cascade established in the product plan:

1. exact qualified name,
2. structural digest,
3. fuzzy token Dice similarity at or above 0.80.

Callable qualified names include their normalized parameter clause so overloads do not collapse into one identity bucket. Structural digests include normalized leaf text and omit comment contents; this preserves semantic token differences while ignoring formatting and comment-only edits.

Within a matched entity, the GumTree-style pass anchors unique identical subtrees and then applies bottom-up Dice matching. Every mapping carries its tier and score, and no downstream layer may silently promote a heuristic mapping to certainty.

## CFG contract

The Swift lowering covers sequential statements, `if`/`else`, `guard`, `switch`, pre-test and repeat loops, `do`/`catch`, `defer`, `return`, `throw`, `break`, and `continue`. Plain `try` conservatively creates an exceptional edge; `try?` and `try!` do not. Unsupported or recovered syntax stays visible as a basic block instead of aborting the file analysis.

Hard node and edge limits fail only the affected function and produce a diagnostic at the analysis boundary.

## Layout and transition contract

The layout identifies back edges from dominance, ranks the remaining graph downward, orders siblings by source position, and routes back edges in dedicated outside lanes. Stable IDs permit unchanged nodes to supply anchor positions in the target layout.

Transition planning is data-only and staged:

1. fade removed nodes and edges,
2. move retained nodes,
3. reveal added nodes and edges.

AppKit/CALayer rendering consumes this contract in M1.

## Evidence planned for the milestone gate

- unit tests for identity, ranges, Codable round trips, matcher tiers, edit operations, CFG constructs, resource limits, layout determinism, anchors, and transition phases;
- a permanent, provenance-recorded set of twenty real Swift function pairs from `swift-syntax` and `swift-nio`;
- an end-to-end representative pair that passes through parse, triage, match, CFG, and layout;
- a 30-node layout performance test with a 16.67 ms target per layout on the supported arm64/macOS 15 baseline.

Per the working agreement, none of this validation is executed until the M0 implementation is complete.
