# M3 implementation record

Date: 2026-11-27

M3 is assembled on `codex/m2-closeout-m3` against the design in `notes/012`. Milestone validation follows in `notes/014`.

## Analysis

- **Noise classification.** Paired nodes of the same kind get a `FlowNodeDelta.noise` level:
  - formatting, from equal tokens without whitespace and comments;
  - optional syntax, from each `LanguageProfile.noise` table;
  - token-provable rewrites: compound assignment and its expansion, and commuted `==`/`!=`.

  Equal labels with different tokens now pair as `modified`.
- **Concern grouping.** `HeuristicConcernGrouper` fills the optional `RevisionFlowDeltaReport.concerns`. Behavioral changes merge by union-find: call edges, then bare-identifier name references, then leftover singletons in the same file and type. Containers join their first behavioral member. One refactoring group and one cosmetic group follow. A revision with two or more behavioral groups is tangled.
- **Python and Go def-use.** `LanguageProfile.binding` rules, read from the syntax tree, cover assignment targets, declarations, aliases, scoped binders and Go's blank identifier. Condition and loop nodes read their headers. `SourceEntity.parameterNames` comes from declarations. `SourceLanguage.supportsDataFlow` is gone: every language has data flow.

## Core

- `FlowNoisePolicy` and `FlowNoiseFilter` apply a level to a delta:
  - hidden nodes display as retained;
  - their causality links are pruned;
  - the filter reports how many nodes it hid.
- `FlowWalkthrough` turns a report and a policy into steps. Each step is a connected group of the visible changed nodes, ordered by reverse postorder and then source order. Functions follow triage order. Narration is a template.
- `FlowTriage.sections(for:groupsByConcern:)` is the single triage order. It is shared by the review view and the table and Markdown export.
- `FlowReviewState` gains `noise`, `groupsByConcern` and `walkthroughStep`.

## Export and CLI

- `FlowDeltaExportOptions(noise:groupByConcern:includeWalkthrough:)`:
  - The default options reproduce the golden table, Mermaid and Markdown files exactly.
  - With the walkthrough included, JSON becomes a `FlowDeltaExportDocument`.
- The CLI gains `--noise`, `--group-by-concern` and `--walkthrough`, and reports version `0.3.0`.
- A smoke run over this branch found name references over-merging concern groups, so they now count only bare identifiers.

## Native review UI

- **Header controls.** The header, a Snow Leopard accessory bar, holds:
  - a small Noise pop-up (Show All, Hide Formatting, Hide Cosmetic);
  - a Group by Concern checkbox;
  - an inline "N hidden — Show" link;
  - a Walkthrough button.
- **Concern groups in triage.** With grouping on, each group gets a heading row ("`name` · Behavioral"). Heading rows are group rows: you can't select them, and keyboard selection skips them.
- **Banners.** A yellow banner names a tangled revision and offers Group by Concern. The walkthrough bar holds Previous, Next, "Step k of n", the narration and Done.
- **Walkthrough behavior.** Moving to a step:
  - selects its function;
  - emphasizes the step's nodes;
  - scrolls the first node into view, without animation when Reduce Motion is on;
  - announces the narration through VoiceOver.
- **Delegate state.** Changes to the noise level, grouping and step reach the delegate as `FlowReviewState` changes, caused by the user or the host.
- **Accessibility.** Every new control has a `FlowDelta.Review.*` identifier. Tab order runs from noise to grouping to walkthrough to triage, and then to the graph and source.
- **Appearance.** The Snow Leopard chrome is drawn in fixed light colors, and inside a Dark Mode host its system text colors turned white on light fills. The review view now adopts Aqua unless its host sets an appearance. Layer colors are resolved for each view's own appearance, and node labels use a fixed dark color. A dark palette is deferred.

## Authored verification

- Core tests cover:
  - noise levels and rules;
  - the filter's pruning and counts;
  - walkthrough chunking, order and narration;
  - triage sections.
- Analysis tests cover every grouping reason, title and tangled case, and every Python and Go binding rule. The two M2 tests that pinned Python and Go as control-only were flipped on purpose.
- Export golden files pin the default output, and option tests cover each flag.
- `FlowDeltaReviewM3Tests` drives:
  - the noise dial and hidden-count link;
  - grouping rows and the tangled banner;
  - a walkthrough with steps;
  - an empty walkthrough;
  - the new identifiers and tab order.
