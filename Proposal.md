# FlowDelta Proposal 

A Swift library for visualizing how a git commit (or any diff) changes a program's control flow and data flow.

---

## 1. Thesis and opportunity

- Structural diff engines (Difftastic, GumTree v4, SemanticDiff, sem, diffsitter) are mature — but all present as *text*.
- Code-graph visualizers (Understand, Sourcetrail fork, CRABViz, CodeLens, flowR) render CFGs/call graphs — but only for *one version*; none has a temporal delta view. No before/after CFG-diff plugin exists in the VS Code or JetBrains marketplaces.
- The only production-grade *matched-graph delta* visualizers are binary reverse-engineering tools (BinDiff, Diaphora, ghidriff).
- The only tools that draw flow diagrams *from diffs* today (CodeRabbit walkthroughs/Change Stack, swark, gitdiagram, Windsurf Codemaps) generate them with an LLM — probabilistically, with hallucination risk.
- In academia, post-2020, only DiffSeer (CG&A 2023) treats "visualize the difference between graph snapshots" as a first-class problem, and it's for generic weighted graphs, not programs. CFG-delta *computation* exists (JDiff, TransplantFix, SigmaDiff, dynamic-CFG commit representations) but is never rendered for developers.

**The goal:** a *deterministic*, analysis-derived, per-commit control/data-flow delta — rendered natively with the interaction vocabulary proven by BinDiff (matched graphs), GraphDiaries (staged transitions), and SemanticDiff (semantic-impact filtering) — fills the credibility gap that LLM-drawn diagrams can't, and the temporal gap that static visualizers never addressed.

**Market cautions absorbed into this plan:**
- CodeSee (codesee.io) shut down Feb 2024: repo-level auto-diagrams as a destination product didn't sustain a business. SemanticMerge died as a standalone. → Ship as an **embeddable library**, inside existing workflows (review, hbmartin/GitX app, CLI, agent/MCP), not a destination.
- GitHub's stack graphs were unshipped because per-language rule authoring was unmaintainable. → Keep the per-language surface *minimal and declarative*.
- Onboard-CLI's HN reception: a graph canvas that doesn't visibly show meaningful edges destroys credibility instantly. → The first demo must show real, correct flow edges changing.

---

## 2. Product definition

**What it is:** A Swift package, **FlowDelta**, that takes *(base revision, target revision)* — a commit, a PR range, or two arbitrary blobs — and produces, per changed function/method:

1. an **entity triage** (functions/types added / removed / modified / moved / renamed),
2. a **matched AST edit script** (insert/delete/update/move) for modified entities,
3. a **CFG delta**: basic blocks and control edges added/removed/changed, plus *affected-but-unedited* regions,
4. a **data-flow delta**: def-use edges added/removed within changed functions, with slice-scoped impact,
5. a **call-graph delta** for the changed neighborhood,
6. **Swift views** that render 1–5 with animated, source-anchored, progressively disclosed visualization,
7. **Supported exports**: JSON, XML, Mermaid, Markdown summary, and MCP tool surface for agents.

**Who it's for:**

A package for use in hbmartin/GitX to serve developers who are reviewing AI-generated or unfamiliar changes ("AI writes 5,000 lines in 5 minutes; I spend hours understanding them" — the CodeSee founder's motivation, now everyone's problem). The unit of review is the diff (GitHub commit-by-commit review, ReviewStack, jj/GitButler) — exactly the scope where flow-delta graphs stay small and tractable.

Secondary: app developers embedding change visualization (git clients, code review tools, education), and agents consuming the JSON/XML output as compressed change context (Sourcegraph's data: structured context cuts agent tool calls 96→5).

**Platforms:** macOS-first (full pipeline incl. `git` CLI and IndexStoreDB); the core is platform-neutral pure Swift so iPadOS/visionOS surfaces work with injected inputs (libgit2 or pre-computed diffs). No server, no telemetry — all analysis local.

**Explicit non-goals (v1):**
- Not a merge tool (Mergiraf owns that; we borrow its architecture instead).
- No formal equivalence checking (SymDiff/ARDiff-class). EquiBench/CETBench show LLMs can't do it reliably either. We *classify and display*; we don't prove. A `SemanticOracle` protocol leaves the door open.
- No runtime tracing (AppMap's lane) — static first; a trace-overlay protocol can come later.
- No SwiftUI. The package must be backwards compatible with Objective-C based views in order to support hbmartin/GitX.

Future v2: A whole-repo "map." For v1, task-scoped slices beat whole-repo maps (Windsurf Codemaps lesson); the diff **is** the scope. But in v2 we may want to support additional comprehensive views.

---

## 3. Architecture

Layered pipeline, lazy at every stage — the Mergiraf/Difftastic doctrine: **cheap pass first, expensive analysis only where needed, hard resource limits with graceful fallback at every level.** The UI is "never loading" (Onboard-CLI): each layer's output is renderable before the next layer finishes.

```
                     ┌────────────────────────────────────────────────┐
 git commit / PR ──▶ │ L0  Input        unified diff + old/new blobs  │
                     ├────────────────────────────────────────────────┤
                     │ L1  Parse        tree-sitter CSTs (all langs)  │
                     │                  + SwiftSyntax enrich (Swift)  │
                     ├────────────────────────────────────────────────┤
                     │ L2  Triage       entity-level add/del/mod/move │
                     ├────────────────────────────────────────────────┤
                     │ L3  Match        GumTree-style AST matching    │  (lazy, per modified entity)
                     ├────────────────────────────────────────────────┤
                     │ L4  Flow         CFG + def-use construction    │  (lazy, per matched entity)
                     ├────────────────────────────────────────────────┤
                     │ L5  Delta        matched-graph diff + classify │
                     ├────────────────────────────────────────────────┤
                     │ L6  Present      layout, Swift views         │
                     ├────────────────────────────────────────────────┤
                     │ L7  Interop      JSON / Mermaid / MD / MCP     │
                     └────────────────────────────────────────────────┘
```

### L0 — Input

- Core API takes pure values: `(oldBlob, newBlob, unifiedDiff?, language)` per file — git access is **pluggable** behind a `RevisionProvider` protocol. May assume hbmartin/objective-git 
- macOS default uses hbmartin/objective-git . Also an option for shells out to `git` (`git show`, `git diff -U0 --no-color`); zero dependencies, sandbox-friendly via `Process`. SwiftGit2 is dormant (last release 2019) — avoid; (see also Working Copy's path).
- Unified diff parser: ~200 lines, vendor/own it (`tornikegomareli/gitdiff` is the reference; also Sourcegraph's `go-diff` as a spec). Consider the interface in hbmartin/gitx since that is the primary implementation surface. Hunks are used for *anchoring and prioritization*, never as the analysis substrate.

### L1 — Parse

- **Spine: SwiftTreeSitter (ChimeHQ)** — the only credible multi-language path in a Swift app (active, v0.10.0 Mar 2026; incremental, error-tolerant, S-expression queries; 50+ grammars distributed as SPM packages). This is the same substrate as Difftastic, Mergiraf, GitHub code-nav, sem — the industry has converged.
- **Normalized tree IR:** parse into our own `SyntaxTree` value type (kind, range, children, token text) independent of tree-sitter node types — Difftastic's uniform s-expression abstraction is what makes multi-language diffing tractable, and it decouples us from grammar churn.
- **Swift enrichment (optional trait):** SwiftSyntax (603.x) for full-fidelity Swift when present — better node kinds, trivia handling, macro awareness. tree-sitter-swift (alex-pinkus) remains the uniform fallback.
- Error tolerance is a feature: diffs frequently contain non-compiling states; tree-sitter's error recovery (plus Difftastic-style parse-error budgets) keeps the pipeline alive mid-edit. This is also why we do **not** build on SIL/compilation (see §5).

### L2 — Entity triage

- Extract named declarations (functions, methods, types, top-level bindings) via per-language S-expression query files — the same `.scm` mechanism editors already use.
- Match old↔new entity sets with **sem's tiered cascade** (fast, explainable): ① exact qualified-name match → ② structural hash match ignoring whitespace/comments (catches moves/renames with identical bodies) → ③ fuzzy token-overlap >80% (catches rename+edit). Record tier as **match confidence**.
- Output: the triage table — the "executive summary above any graph" (ghidriff lesson) and the entry point of the whole UI. Cross-file moves are first-class (commit-level differencing — RefactoringMiner's differentiator).

### L3 — Structural match (lazy, per modified entity)

- A Swift port of **GumTree classic** (greedy top-down isomorphic-subtree anchoring + bottom-up Dice-coefficient matching), which Mergiraf has already proven is portable and productionizable outside Java. Emit Chawathe edit scripts: **insert / delete / update / move** — the standard vocabulary.
- Known base-layer risk: published matchers mis-map 20–36% of file revisions (Fan et al., ICSE 2021), and matcher hyperparameters matter (DAT, TSE 2023). Mitigations: match *within* triaged entity pairs only (smaller, better-conditioned inputs than whole files); expose per-mapping confidence; validate against the **RefactoringMiner AST-mapping benchmark** (TOSEM 2025 — 800 bug-fix + 188 refactoring commits) before trusting any tuning.
- Optional refactoring-awareness pass (rename/extract-method detection informing matches) is a v2 lever with proven precision gains (Alikhanifard & Tsantalis).

### L4 — Flow construction (lazy, per matched entity)

**This layer is the library's core original IP — no Swift CFG library exists for *any* language.**

- **CFG from CST:** a per-language visitor lowering our normalized tree to statement-level basic blocks + edges (branch, loop, back-edge, exception/early-exit). The established recipe is Joern's `CfgCreator` as replicated by tree-climber (Python/C) and COMEX (Java/C#). C-family languages share most logic; each language contributes a small declarative mapping (which node kinds open branches, which are jumps/returns/throws). Keep this surface *data-shaped* (tree-sitter-graph-style) to dodge the stack-graphs maintenance death. 
- **Data flow:** intra-procedural def-use chains from scope analysis (tree-sitter `locals.scm` queries + per-language binding rules). Reaching-definitions on statement-level blocks is cheap at function scale. Interprocedural dependence (SDG) is explicitly deferred.
- **Call edges:** syntactic call-site extraction (name-based, always available) with **precise enrichment when available**: IndexStoreDB for Swift/ObjC/C++ on macOS (Periphery's proven recipe: index store for edges + syntax tree for structure), LSP `callHierarchy` via ChimeHQ LanguageClient for anything with a server. Copy Sourcegraph's degradation pattern verbatim: *precise where indexed, search-based fallback everywhere, labeled as such.*
- **Swift precision ladder (future v2):** AST-level CFG (always) → IndexStoreDB refs (built projects) → SIL parsing for basic-block-exact CFGs (SWAN proves feasibility and documents the toolchain-tracking pain; treat as an experimental backend, never the default — it requires compiling code and breaks on exactly the mid-edit states we must handle).

### L5 — Delta computation and classification

- **Model the delta as one matched graph pair, not two graphs** (BinDiff's central lesson: the matching *is* the diff). Project L3's AST correspondences onto CFG nodes (each basic block knows its AST statements → block correspondence falls out; JDiff's hammock matching is the fallback for structurally shuffled functions).
- Node/edge states: `added / removed / retained / modified`, plus the state that differentiates this tool — **`affected`: textually unchanged but semantically re-contexted** (its guarding condition changed, its reaching definitions changed, a dominator was inserted, its call target rebindds). This is SemanticDiff's "third highlight category" proposal + Horwitz's semantically-changed-vs-textually-changed partition, realized on a graph. Each `affected` node carries a **causality link** to the triggering change (trigger→effect tracing).
- **Match confidence as a first-class channel** (BinDiff/Diaphora): similarity is a spectrum; encode it, don't binarize it.
- **Change classification:** label deltas with a micro-change taxonomy (guard inserted, condition strengthened/weakened, early return added, branch removed, loop transformed, error path added…) built on ChangeDistiller's change-type taxonomy + the ICSME 2024 micro-changes catalog. These labels are the human-readable layer between edit scripts and pixels ("this edge exists because a guard was added").
- **Noise policy — the SemanticDiff Level dial:** Level 1 (formatting) always filtered; Level 2 (optional tokens) filtered by default; Level 3 (provable equivalences) *shown but de-emphasized*, never hidden — `for`→`while` proves reviewers still want to see behavior-preserving rewrites. Filtering must be visible and reversible ("N cosmetic changes hidden") — trust dies the first time the tool hides something that mattered.
- **Slicing:** forward slice from any changed node (potentially-affected downstream), backward slice to root cause — over control+data edges within the function, extending across call edges where precise data exists. Both reports flagged slice-scoped focus as *the single most valuable interaction*.
- LLM adapters (optional, protocol-based, off by default): natural-language labels for nodes/deltas and impact narration. Deterministic core, probabilistic garnish — calibrated by the literature (LLMs good at labeling/narration; unreliable at equivalence and slicing).

### L6 — Presentation (the differentiator)

**Layout.**
- **Layered (Sugiyama) layout via elk-swift** (Luki Labs' pure-Swift ELK port, 2026) — CFGs need top-down flow, not force-direction. Follow **CFGConf's domain conventions** (VISSOFT 2022): downward edges, distinct back-edge routing, loop contours, linear block order.
- **Layout stability across the delta:** stable node identity (deterministic content+position hashes, Onboard-CLI-style) drives everything; unchanged nodes are layout anchors; the delta relayouts *around* them. An unstable layout erases the value of a precise diff (VEIL, Code Flows, both reports' gap #2).
- Force-directed (Grape/ForceSimulation) is reserved for the call-graph "constellation" overview only.
- elk-swift is new and lightly proven — it gets a dedicated validation spike (M0). We expect the need to for and extend the port ourselves.

**Views (progressive disclosure, overview → drill):**
1. **Commit overview** — triage table + change-kind summary (ChangePrism's two-level General/Detailed design), grouped by concern when a commit is tangled (untangling literature: concern clusters over control/data-dependency graphs are a free grouping dimension; heuristic first, pluggable later).
2. **Call-graph neighborhood** — changed entities in their caller/callee context, radius-limited (Onboard-CLI), grouped by file (CRABViz), delta-colored.
3. **Function flow delta** — the centerpiece. Default **superimposed**: one merged CFG with per-node/edge delta states — right for the small graphs a single function yields. **Juxtaposed** synchronized before/after with correspondence linking (BinDiff-style click-to-counterpart) for large/restructured functions. Auto-select by delta size; user can override (Gleicher's comparison taxonomy: superposition / juxtaposition / explicit encoding — we use all three deliberately).
4. **Source pane, always co-present** — graphs orient, text confirms (Diaphora lesson). Every node/edge anchors to source ranges; hover/selection syncs bidirectionally (the canonical AST-diff interaction, GumTree webdiff). Rendering: Neon + SwiftTreeSitter over a read-only text view (macOS); Runestone (iPadOS). Minimap + on-demand context expansion (SemanticDiff UX). Consider also hbmartin/HighlightKit.
5. **Walkthrough mode** — narrated stepping through the delta in causal/execution order, camera following, one change-chunk at a time. Grounded in CodeSee's cognitive case (working memory ≈ 4 chunks; paths beat maps) and CodeRabbit's narrative-layer ordering. The full graph is the diploma, not the textbook.

**Encoding.**
- Four semantic categories: added / removed / retained / **affected** — affected gets its own hue (not red/green), the visual channel no shipping tool has. Confidence via saturation/stroke style. Micro-change labels as terse, hunk-anchored glyphs — empirical review studies (TSE 2026) show concise, anchored annotations are what drive reviewer action; global dashboards don't. (Build the actual palette with the dataviz skill / accessibility validation at implementation time.)
- **Staged animated transitions** (GraphDiaries, the controlled-study winner): stage 1 removals fade with halos (~300ms) → stage 2 survivors slide to new layout (~600ms, slow-in/slow-out) → stage 3 additions fade in (~300ms). User-scrubbed, not autoplay (Lee et al., TVCG 2021: interactive time navigation beats animation for change tasks).

**Rendering tech.**
- Community-standard hybrid:  `Canvas` for edges (immediate-mode, one draw pass) + **individual views for nodes** (hit-testing, context menus, accessibility) + custom `Layout` conformance wrapping elk-swift output + `matchedGeometryEffect` keyed on stable block IDs for the before/after morph.
- Metal is a deliberate non-goal until profiling proves need. (Be sure the architecture supports a possible Metal migration in the future.) Per-function CFGs are small (tens of nodes) — the scale problem lives in the call-graph view, which is radius-limited by design.

### Future v2: L7 — Interop

- **JSON schema** for the full delta model (CFGConf's JSON spec is prior art for shape) — the contract for embedding, testing, and caching.
- **XML schema** - equivalent to JSON for agents that prefer to read XML.
- **Mermaid export** (flowcharts with delta classes) — commodity rendering everywhere, incl. PR comments; CodeRabbit normalized reviewers seeing Mermaid in PRs.
- **Markdown commit report** — triage table + per-entity summaries + embedded diagrams; ghidriff's "social diffing" artifact.
- **MCP hooks** Thie library exposes ready hooks e.g. `flow_delta`, `impact_slice`, `entity_triage` — sem and diffsitter show agents adopt structural-diff MCP tools quickly; codebadger (2026) is the blueprint for LLM-queries-the-same-graph-the-UI-renders. The visualization and the agent context are the same model. The MCP server itself is the responsibility of the app in which this is embedded.

---

## 4. Package structure (SPM)

| Target | Contents | Depends on |
|---|---|---|
| `FlowDeltaCore` | Graph IR, `SyntaxTree`, edit scripts, delta model, classification taxonomy. Pure Sendable values, zero deps. | — |
| `FlowDeltaParse` | tree-sitter adapters, per-language `.scm` queries + CFG mapping rules; optional SwiftSyntax trait. | Core, SwiftTreeSitter |
| `FlowDeltaMatch` | Tiered entity matcher; GumTree-port tree matcher. | Core |
| `FlowDeltaFlow` | CFG/def-use builders, slicing; IndexStoreDB/LSP enrichment (macOS). | Core, Parse |
| `FlowDeltaGit` | `RevisionProvider`; git-CLI provider; unified diff parser. | Core |
| `FlowDeltaLayout` | elk-swift wrapper, CFGConf conventions, stability anchoring. | Core, elk-swift |
| `FlowDeltaUI` | Views: triage, call-graph, flow delta, source pane, walkthrough. | Core, Layout |
| `FlowDeltaExport` | JSON, XML, Mermaid, Markdown | Core |
| `FlowDeltaApp` (example) | Reference macOS app: open repo → pick commit → explore. | everything |

Dependency policy: Core/Match/Export have zero third-party dependencies; every integration point (git, index, LLM, layout) sits behind a protocol.

---

## 5. Key design decisions and rationale

| Decision | Choice | Why (evidence) |
|---|---|---|
| Parsing spine | tree-sitter, not SwiftSyntax/compilers | Only multi-language path in Swift; error-tolerant for mid-edit states; industry convergence (Difftastic, Mergiraf, GumTree v4, sem, GitHub). SwiftSyntax = Swift-only enrichment trait. Consider that we should also non-Swift enrichment for common ecosystems (e.g. TypeScript, Python, Rust, go-lang). |
| Analysis level | AST-level CFG, not IR/SIL | Diffs contain non-compiling code; SIL/compilation requires buildable targets and per-toolchain chasing (SWAN's documented pain). AST-level CFGs are diff-friendly and bounded work per language. v2 will have SIL (optional precision backend) later. Architect to support multi-language tool chains in the future. |
| Delta model | One matched graph pair + confidence spectrum | BinDiff: the matching *is* the diff; similarity is not binary. |
| The 4th color | `affected` (unchanged-but-recontexted) as first-class state with causality links | SemanticDiff's proposed-but-unshipped third category; Horwitz's semantic/textual partition; Sourcegraph's "diff-only tools produce diff-quality comments." This is the headline feature. |
| Determinism | Analysis-derived graphs; LLMs only as optional labeling adapters | CodeRabbit proves demand for flow diagrams from diffs but generates them probabilistically; EquiBench/slicing evals show LLMs unreliable for edges/equivalence, good at narration. Deterministic delta = the credibility differentiator. Support evidence bundle exports so a user can interact with these in their own LLM's. |
| Performance doctrine | Lazy per-entity escalation + textual fallback | Mergiraf fast mode; Difftastic graph/byte limits; flowR's ~100ms/file bar; Onboard-CLI streaming (flat memory) precedent. |
| Layout | Layered/Sugiyama (elk-swift) with stability anchors; force-directed only for overview | CFGs read top-down (CFGConf, VEIL); mental-map preservation is gap #2 in the literature; Grape is wrong for CFGs but right for constellations. |
| Language rollout | Swift first, then TS/JS, Python, Go, Rust — each = query files + small CFG mapping | Per-language maintenance killed stack graphs; declarative surface + shared C-family logic caps the cost. Swift-first is also publishable novelty (academic Swift analysis ≈ SWAN alone). |
| Distribution | Library; embed in workflows | CodeSee/SemanticMerge deaths; difit's zero-install wedge; review is consolidating into IDE/agent vendors — be the infrastructure. |

---

## 6. Roadmap

**M0 — De-risk spikes (2–3 weeks)**
- Spike A: elk-swift renders a 30-node CFG with CFGConf conventions in Canvas at 60fps, incl. matchedGeometryEffect morph between two layouts. Fallback decision point.
- Spike B: tree-sitter → normalized tree → statement-level CFG for one real Swift function (guard/if/switch/loop/defer/throws). Validates the CFG-from-CST recipe.
- Spike C: GumTree-port prototype on 20 real commit pairs; sanity-check mappings by hand.
- Exit criteria: all three demos work end-to-end on one hand-picked commit; a screen recording exists (the "visible edges" credibility test).

**M1 — Swift-only MVP (6–8 weeks)**
- L0–L6 for Swift: commit in → triage table → per-function superimposed CFG delta with 4-state coloring, staged transitions, source pane sync, forward-slice highlight.
- Reference macOS app; JSON export; snapshot-test corpus of real commits (swift-syntax, swift-nio histories).
- Acceptance: a reviewer can answer "what does this commit change about this function's control flow?" faster than with `git diff` on 10 benchmark commits (informal timing study, Hanam/SEMCIA-style task framing).

**M2 — Multi-language + data flow (6–8 weeks)**
- TS/JS, Python, Go mappings; def-use deltas + backward slicing; call-graph neighborhood view with IndexStoreDB enrichment for Swift; juxtaposed mode; walkthrough mode v1.
- Validate matcher against the RefactoringMiner benchmark; publish accuracy numbers (trust through measurement).

**M3 — Interop + polish (4–6 weeks)**
- XML/Mermaid/Markdown export, MCP server hooks, difit-style `swift run` local review flow; noise-level dial UI; tangled-commit grouping heuristic; iPad-ready core audit.
- Full codebase navigation view

**Later / research lane:** SIL precision backend; interprocedural SDG slices; refactoring-aware matching; trace overlay (AppMap-style); ProbeGen-style counterexample adapter; visionOS constellation view.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| elk-swift immaturity (v1.0.0, tiny community) | High | M0 spike; expect to fork and extend port (BeautifulMermaid proves it's usable in production) |
| AST matching errors (20–36% in the wild) poison everything above | High | Match within triaged entities; confidence surfaced honestly in UI; benchmark-driven tuning (DAT); never claim certainty the matcher doesn't have. |
| Per-language maintenance creep | High | Declarative mappings; 5 launch languages; shared C-family lowering; refuse languages without committed grammar maintenance. |
| Layout instability breaks mental map | Medium | Stable IDs, anchored relayout, staged transitions; test: unchanged functions must produce pixel-identical layouts across commits. |
| Noise/trust failure (hiding something that mattered) | Medium | Level dial defaults conservative; filtering always visible + reversible; de-emphasize, don't delete, for Level 3. |
| Scale blowups (generated files, 5k-line functions) | Medium | Hard limits per layer with labeled fallbacks (Difftastic doctrine); lazy per-entity computation; triage always works even when graphs don't. |
| Perf ceiling on large call graphs | Low | Radius-limited neighborhoods by design; Canvas hybrid; Metal only if profiling demands. |

---

## 8. Evaluation plan

- **Latency budgets:** <200ms per changed file for parse+triage (flowR bar); <1s to first CFG delta on a typical commit; every stage cancellable.
- **Correctness:** matcher precision/recall vs. RefactoringMiner AST-mapping benchmark; CFG builder golden-file tests per language construct; delta invariants (e.g., no `retained` node whose source text changed) as property tests over real repo histories.
- **Human effectiveness:** task-based study design per SEMCIA (the only precedent showing dependency views *can* fail users — measure task completion time/accuracy on review tasks, not preference): "which inputs now take the error path?", "what else is affected by this edit?" vs. plain diff baseline.
- **Dogfood metric:** the tool reviews its own PRs from M1 onward.

---

## 9. Assumptions and Requirements

- No javascript, java, etc libraries used, Swift ports only. We will need to create our own ports of some of the things cited above.
- Isolated smaller packages are preferable to a monolith. This speeds up compilation, improves testability, and enables other re-use.
- Swift 6.2 implementation.
- Minimum version supported is macOS 15 Sequoia
- We will modify hbmartin/HighlightKit and hbmartin/objective-git as needed
- Over 90% unit test and integration coverage
- Screenshot testing required
- Use pointfreeco style patterns where useful
- SwiftPM distribution (no Carthage, no CocoaPods)
- Must implement strict rules for SwiftLint and SwiftFormat
- If a build system is needed use mise
- LGPL license

---

## 10. Source index (for citation follow-up)

Synthesized 2026-07-19 from: the prior-art corpus in this repo (two deep-research reports, Mergiraf architecture, Diff/AST, CodeSee, CodeVisualizer, Emerge, Onboard-CLI), targeted web research on the 2024–2026 tool landscape, an academic literature sweep (2020–2026) via paper-search MCP, and a survey of the Swift ecosystem building blocks.

Key external references gathered in this pass:

- SemanticDiff blog (vs-difftastic; language-aware-diff-highlight; language-aware-diff-how-far)
- Difftastic manual
- Mergiraf/LWN
- GumTree v4
- sem (ataraxy-labs)
- RefactoringMiner AST-diff (TOSEM 2025) + benchmark
- HyperAST/HyperDiff
- BinDiff/Diaphora/ghidriff
- DiffSeer (CG&A 2023)
- CFGConf (VISSOFT 2022)
- GraphDiaries (TVCG 2014)
- Lee et al. (TVCG 2021)
- ChangePrism (VISSOFT 2025)
- micro-changes (ICSME 2024)
- ColaUntangle/HD-GNN (untangling)
- PASDA/ProbeGen/EquiBench (semantic limits)
- SWAN (Swift/SIL)
- Joern CPG / tree-climber / COMEX (CFG-from-CST)
- CodeRabbit Change Stack
- Windsurf Codemaps
- Sourcegraph SCIP + "why coding agents fail" + AI code review
- CodeSee shutdown/GitKraken
- SwiftTreeSitter/Neon
- swift-syntax 603
- IndexStoreDB/Periphery
- elk-swift/BeautifulMermaid
- Grape/ForceSimulation
- Runestone/CodeEditSourceEditor
- tornikegomareli/gitdiff.
