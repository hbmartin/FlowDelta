# M3 design record

Started 2026-11-27 from FlowDelta `0.2.2` (plus the unreleased PR #3 fixes on `main`) on branch `codex/m2-closeout-m3`. M3 ships as `0.3.0`, together with the M2 host-API work, so GitX can show every feature in one integration.

## Scope

- A noise dial that hides formatting-only and cosmetic node changes without hiding rewrites.
- Concern grouping that splits a revision's entity changes into behavioral, refactoring and cosmetic groups and flags tangled commits.
- A walkthrough that steps through a revision's visible changes function by function, with template narration.
- Python and Go def-use, so data context and data slices cover all five languages.
- Export and CLI options for the three features. With no option set, the table, Markdown and Mermaid output is unchanged; JSON gains only the new optional fields.
- Native UI: a scope bar for the noise level and grouping, concern group rows in triage, and a walkthrough bar.

Out of scope: MCP hooks, the iPad-ready core audit, IndexStoreDB enrichment and XML export.

## Package boundary

FlowDeltaUI depends only on FlowDeltaCore and FlowDeltaLayout, so every decision the UI makes is a pure function in FlowDeltaCore: `FlowNoisePolicy`, `FlowNoiseFilter`, `FlowWalkthrough` and the concern model. Classification that needs syntax trees (noise levels, concern evidence, binding rules) lives in FlowDeltaAnalysis and FlowDeltaFlow and is stored in the report. New report fields are optional, so `0.2.x` JSON still decodes.

## Noise boundary

`FlowNodeDelta.noise: FlowNoiseLevel?` classifies a paired node whose kinds match:

1. **Formatting.** The token sequences of the old and new statement are equal once whitespace and comments are removed. Whitespace-only edits are already `retained`, because labels collapse whitespace; comment edits inside a statement were `modified`.
2. **Optional syntax.** The token sequences are equal once the language's optional tokens are removed: statement-ending `;`, a trailing `,` before a closing bracket, `self.`/`this.` receivers, and one pair of parentheses around a whole condition. Each language's table lives in `LanguageProfile.noise`.
3. **Rewrite.** The statements are equal under a token-provable rewrite: a compound assignment and its expansion (`a += b` and `a = a + b` for a single identifier `a`), or a commuted `==`/`!=` comparison.

Pairing also gets stricter. A pair whose labels are equal but whose tokens differ (an edit past the label's truncation point) is now `modified` instead of `retained`.

`FlowNoisePolicy` has three levels: `showAll`, `hideFormatting` (hides level 1) and `hideCosmetic` (hides levels 1 and 2). Level 3 is never hidden; it is marked "rewrite" so a reviewer can confirm it. `FlowNoiseFilter` applies a policy to a function delta:

- Hidden nodes display as `retained`.
- Causality links triggered by a hidden node are pruned, and an `affected` node left without links becomes `retained`.
- The filter reports how many nodes it hid, for a "N hidden — Show" link.

Hosts choose the default; GitX uses `hideCosmetic`.

## Concern boundary

`HeuristicConcernGrouper` (FlowDeltaAnalysis) fills `RevisionFlowDeltaReport.concerns: [FlowConcern]?`. It classifies every entity change that is not `unchanged`:

- **Cosmetic:** a modified callable whose changed nodes are all formatting or optional-syntax noise.
- **Refactoring:**
  - a moved or renamed entity whose structural digest is unchanged, or
  - a modified callable whose changed nodes are all rewrites.
- **Container:** a modified type whose tokens outside its member entities are unchanged. Every member change also modifies its type, so a container joins the group of its first behavioral member (or, failing that, the group of its first changed member) instead of merging its members' groups.
- **Behavioral:** everything else.

Behavioral entities are merged by union-find. The reasons for a merge, in order:

1. call-graph edges between changed entities;
2. a changed entity's new body naming another changed entity as a bare identifier (not a member after `.`, which calls cover, and not an argument label, keyword argument or assignment target before `:` or `=`), where a type's body counts only its own tokens;
3. for leftover singletons, the same file and the same containing type, where a type is in its own type.

Refactoring entities and cosmetic entities each form one group per revision, after the behavioral groups.

Groups are deterministic:

- Members are sorted by path and source order, and groups by their first member.
- Titles are templates: "`name`" for a single member, "`name` and N related changes" for more, and "Renames, moves and rewrites" and "Formatting and cosmetic changes" for the fixed groups.
- Each group records the `links` that merged it, with their reasons.
- A revision is **tangled** when it has two or more behavioral groups.

## Walkthrough boundary

`FlowWalkthrough` (FlowDeltaCore) turns a report and a noise policy into ordered steps.

- **Steps within a function.** A function's visible changed nodes (added, removed or modified, and not hidden by the policy) form chunks: connected components over the delta's control edges. `affected` nodes are context, not steps.
- **Step order within a function.** By the reverse postorder of each chunk's first node in the target graph (or the base graph for removals), then by source order.
- **Order across functions.** Functions follow triage order, so Next continues into the next function.
- **Narration** is a template built from the chunk's states, its first label and its classifications, plus the count of nodes it affects. For example: "Adds `guard items.isEmpty == false` — affects 3 nodes by control."

## Data-flow boundary

Python and Go def-use use AST binding rules from a per-language `LanguageProfile.binding` table, not regular expressions.

- **Anchoring.** Definitions are taken only from binding statements anchored at statement starts. Keyword arguments and struct-literal keys therefore never define.
- **Python** binds:
  - assignment and augmented-assignment targets, including tuples;
  - annotated assignments, `for` targets, `with … as`, `except … as` and walrus targets.

  Names in `global` and `nonlocal` statements are not local. Comprehensions and lambdas are scoped binders, so their variables don't leak.
- **Go** binds:
  - short variable declarations (`:=`), `var` specs, assignment targets and `range` clauses.

  `_` is not a symbol, and function literals are scoped binders.
- **Parameters** come from the AST as `SourceEntity.parameterNames`. This includes `*args` and `**kwargs`, Go grouped parameters, variadic parameters, receivers and named results. The old `qualifiedName` parsing stays as the fallback for Swift and TypeScript/JavaScript.
- **Header fields.** Condition and loop nodes record their header fields' syntax (`if x := f(); x > 0`, Go `for` clauses), so initializer definitions are not lost.

Every language then has data flow, so `SourceLanguage.supportsDataFlow` (added unreleased in this branch) is removed and the review summary always reports control + data context for analyzed files. The model stays per statement, so false edges remain possible; validation measures them on the audit corpus. Nodes after a loop carry the loop's syntax but run none of it, so they have no facts.

## Export and CLI boundary

`FlowDeltaExportOptions(noise:groupByConcern:includeWalkthrough:)`:

- The default options reproduce today's table, Markdown and Mermaid output exactly.
- `noise` applies the filter before counting and drawing nodes.
- `groupByConcern` orders the table and Markdown output by concern group and adds the tangled-commit note.
- `includeWalkthrough` appends the steps in table, Markdown and JSON output; JSON becomes a `FlowDeltaExportDocument` of the report and its walkthrough.

The CLI gains `--noise show-all|hide-formatting|hide-cosmetic`, `--group-by-concern` and `--walkthrough`.

## UI boundary

The review header becomes a Snow Leopard accessory bar holding:

- a noise pop-up;
- a Group by Concern checkbox;
- a "N hidden — Show" link that switches to `showAll`.

With grouping on, triage shows a group row above each group's members. A tangled revision shows a banner that offers to turn grouping on. The walkthrough bar shows ◀ ▶, "Step k of n", the narration and Done.

- **Behavior:** moving to a step selects its function, emphasizes its chunk, scrolls it into view, and announces the narration through VoiceOver. It respects Reduce Motion.
- **State:** `FlowReviewState` gains `noise`, `groupsByConcern` and `walkthroughStep`, reported through the delegate like the other fields.

## Verification plan

- Core and analysis unit tests cover every noise level and rule, every grouping reason and title, walkthrough chunking and order, and every Python and Go binding rule.
- Existing M2 expectations keep passing, apart from the two that pin Python and Go as control-flow only, which flip deliberately.
- An audit-corpus check counts data edges before and after, for Python and Go fixtures.
- Export tests prove the default output is unchanged, and cover each option.
- The CLI is smoke-tested with every flag and format.
- UI tests drive the scope bar, group rows, the banner, the walkthrough bar and the delegate state.
- The native reference snapshot is re-recorded deliberately; it no longer matched this host's rendering even before M3.
- Coverage stays at or above the 94.03% floor. The pinned SwiftFormat and strict SwiftLint pass.
- A clean exact-pin consumer build resolves `0.3.0`.
