# Research Findings — State of the Art for Control/Data-Flow Diff Visualization

*Compiled 2026-07 as the research record behind [`../PLAN.md`](../PLAN.md) (the FlowDelta design plan). Sources: the local prior-art corpus in this repo, deep-dives on the six requested URLs, web research on the 2024–2026 tool landscape, an academic sweep (2020–2026) via paper-search MCP across Semantic Scholar / DBLP / OpenAlex / CrossRef / arXiv, and a survey of Swift ecosystem building blocks.*

---

## Contents

1. [Headline conclusions](#1-headline-conclusions)
2. [Local prior-art corpus](#2-local-prior-art-corpus)
3. [URL deep-dives: SemanticDiff, Onboard-CLI, Sourcegraph](#3-url-deep-dives)
4. [Tool landscape 2024–2026](#4-tool-landscape-2024-2026)
5. [Academic literature 2020–2026](#5-academic-literature-2020-2026)
6. [Swift ecosystem building blocks](#6-swift-ecosystem-building-blocks)
7. [Cross-cutting synthesis](#7-cross-cutting-synthesis)

---

## 1. Headline conclusions

**The gap is confirmed and still open.** No tool — commercial, open-source, or academic — visualizes source-level control/data-flow *deltas* per commit:

- Structural diff engines (Difftastic, GumTree v4, SemanticDiff, sem, diffsitter) are mature — but all present as *text*.
- Code-graph visualizers (Understand, Sourcetrail fork, CRABViz, CodeLens, flowR) render CFGs/call graphs — but only for *one version*. No before/after CFG-diff plugin exists in the VS Code or JetBrains marketplaces.
- The only production-grade *matched-graph delta* visualizers are binary reverse-engineering tools (BinDiff, Diaphora, ghidriff).
- The only tools drawing flow diagrams *from diffs* (CodeRabbit, swark, gitdiagram, Windsurf Codemaps) generate them with an LLM — probabilistically.
- In academia post-2020, only DiffSeer (CG&A 2023) treats "visualize the difference between graph snapshots" as a first-class problem — for generic weighted graphs, not programs. CFG-delta *computation* exists (JDiff, TransplantFix, SigmaDiff) but is never rendered for developers.
- JetBrains still has no semantic diff (long-open YouTrack issues IJPL-99523, IJPL-103251); GitHub has none for source code, and its stack graphs project was unshipped.

---

## 2. Local prior-art corpus

Summary of what the files in this repo establish (full detail in the files themselves).

### Deep-research reports (`deep-research-report (4).md`, `compass_artifact…md`)

Both independently conclude: the field splits into (1) mature AST/tree differencing (Chawathe 1996 → ChangeDistiller → GumTree ASE 2014 → MTDIFF → GumTree-2024 scalable revision), (2) scientifically deep but research-grade semantic/dependence differencing (Horwitz PLDI 1990, Jackson & Ladd Semantic Diff, JDiff/ECFG, PDG/SDG, DSE, SymDiff, ARDiff, DiffKemp), and (3) mature InfoVis graph-diff techniques rarely applied to programs (GraphDiaries staged transitions, AniMatrix, Code Flows, Gleicher's comparison taxonomy, Beck et al. dynamic-graph survey). The best-developed CFG-delta visualizers are binary tools (BinDiff/BinHunt).

Recommended pipeline (both reports): GumTree-style AST matching for correspondence → lift to PDG/SDG → graph delta → render with staged transitions + add/remove/change color encoding; slice-scoped focus is "the single most valuable interaction." Identified gaps: end-to-end integration, stable layout/identity, evaluation realism, benchmark fragmentation, uncertainty representation. Caveat: AST-matching accuracy is an unsolved base layer (20–36% mapping errors per Fan et al., ICSE 2021).

### Mergiraf architecture (`Architecture - Mergiraf.pdf`, mergiraf.org)

Structured git merge driver (Rust, spork lineage). Pipeline: tree-sitter parses base/left/right → GumTree classic matches all three pairs → **class mapping** (equivalence classes of matched nodes with a "leader" per class = node identity across revisions) → trees encoded as Parent-Child-Successor (PCS) triples → changesets merged as quadruplet sets with inconsistency elimination → merged tree rebuilt (ExactTree / Conflict / LineBasedMerge / MixedTree node types) → delete/modify and duplicate-signature conflict checks → rendering with whitespace imitation. **Fast mode**: line-based merge first; structured algorithm only on conflicted regions, with pre-seeded matchings from conflict-free areas. Lessons: tree-sitter + GumTree is production-proven and portable; leader-based node identity is the right cross-revision identity model; cheap-pass-first layering keeps structural tools responsive.

### Tool docs

- **Diff/AST** (`diff-ast.md`): OCaml fine-grained AST differ (Hashimoto & Mori, WCRE 2008); TED-based with divide-and-conquer heuristics (pure TED is ≥quadratic); exports facts to RDF stores; caches aggressively; git difftool integration.
- **CodeVisualizer** (`CodeVisualizer.md`): VS Code extension; tree-sitter (WASM) → IR → Mermaid flowcharts per function + dependency graphs per codebase; 8+ languages; optional LLM node labels (labels only, cached, local-first privacy stance).
- **CodeSee (Kaka-cheaper)** (`CodeSee.md`): AI-maintained `features.json` semantic flow graph (Epics→Features→Steps), React Flow + ELK viewer. Key cognitive-design argument: working memory ≈ 4±1 chunks; a 22-node canvas can be *looked at* but not *understood*; guided tours (question-first, predict-at-forks, nodes lighting up in order) beat maps — "the map is the diploma, not the textbook."
- **Emerge** (`emerge.md`): Python multi-language dependency-graph tool; force-directed D3 + Louvain modularity coloring; heatmaps from SLOC/fan-out and git churn; useful pattern language for reading such graphs (modularity, ball-of-mud, irrelevant-dependency filtering).
- **Onboard-CLI** (`onboard-cli.md`): Go CLI + React Flow canvas; tree-sitter AST slicing; architecture drift rules; impact analysis. (Deeper findings in §3.)

---

## 3. URL deep-dives

### 3.1 SemanticDiff vs Difftastic — semanticdiff.com/blog/semanticdiff-vs-difftastic/

Both go beyond line-based diffing, but "structural" (Difftastic) and "semantic" (SemanticDiff) are distinct levels of language awareness.

**Baseline**: `git diff` aligns lines via Myers; adding line breaks between statements is enough to break matching — reformatting produces noisy diffs.

**Difftastic (structural)**: parses both versions with tree-sitter grammars, aligns AST nodes by common structure; whitespace not in the AST is inherently filtered; reports token-level changes. Cannot distinguish moved code from unrelated delete+add; shows a repeated rename as many token edits; known trouble with Python indentation-structure changes. 50+ languages (cheap breadth — needs only a parse tree). CLI-only, terminal side-by-side or inline, open source.

**SemanticDiff (semantic)**: structural diff plus semantic interpretation — recognizes `1337` ≡ `0x539`, filters optional parentheses, understands string-concatenation rewrites ("invariances" that provably don't alter logic). Detects and highlights **moved code**; groups **repeated changes** (e.g., a rename across a file). 11–16 languages incl. **Swift** (each needs a higher-quality parser + semantic rules). VS Code extension + GitHub PR app; freemium, closed source. UI: side-by-side only, **minimap**, **dynamic context expansion**, native-theme rendering, PR review features.

**Follow-up post — "What should semantic diffs highlight: The change or its effect?"** (semanticdiff.com/blog/language-aware-diff-highlight/): a tiny edit can semantically alter *unchanged* text (`x = f"foo {bar}"` → `x = "foo {bar}"` — the untouched `{bar}` changes meaning). Three strategies: highlight the trigger only (consequences missed), the effect only (looks like a bug), or both (chosen default, but noisy). Proposed ideal: **a third highlight category with its own color beyond red/green** for "semantically altered but textually unchanged," ideally with **causality tracing** from trigger to effect. *(This unshipped proposal became FlowDelta's headline `affected` state.)*

**Follow-up post — "How far should a programming language aware diff go?"** (semanticdiff.com/blog/language-aware-diff-how-far/): a four-level spectrum of diff awareness:

| Level | Filters | Verdict |
|---|---|---|
| 1 — Irrelevant whitespace | formatting/line breaks | uncontroversial |
| 2 — Irrelevant tokens | trailing commas, optional parens | "discussing these in reviews is a waste of time" |
| 3 — Semantic equivalence | number bases, stylistic rewrites | boundary: `for`→`while` is behavior-preserving but reviewers still want to see it |
| 4 — Mostly identical | import reordering | can change behavior via side effects; hiding risks trust |

SemanticDiff sits "somewhere inside level 3" using **predefined per-pattern invariance rules**, not general equivalence checking. Core tension: noise reduction vs. developer trust.

Also on their blog: review tools mostly fail to flag malicious Unicode (argument for rendering diffs from parsed tokens, not raw text).

### 3.2 Onboard-CLI blogs — onboard-cli.vercel.app/blog/1 and /blog/2

*(Site is a client-rendered SPA; content recovered from the JS bundle, GitHub README, and the Show HN thread.)*

**Blog 1 — "The Architecture of Onboard-CLI"** (2026-06-18): local-first Go CLI + ephemeral local web server serving a React bundle; tree-sitter AST layer ("a real, navigable AST — not regex"); graph layer (nodes = functions/classes/files; edges = imports/calls/injections); all metadata cached in a hidden **SQLite** DB read via **mmap**; drift = graph traversal for forbidden edge paths; routes = S-expression queries for framework routing signatures. Principle: **"the visualizer is never 'loading' — it is simply rendering the graph that the CLI engine has already pre-processed."**

**Blog 2 — "Building the Graph Abstraction Engine"** (2026-06-29): war stories —
- In-memory graph failed: >4GB RAM on a large codebase. Fix: **streaming ingestion** — compute **deterministic SHA-256 node hashes** (file path + line numbers) during parse and flush straight to SQLite; memory flat ~40MB regardless of repo size.
- Naive blast-radius queries took ~15s; rewritten as **recursive CTEs so SQLite's C engine does BFS natively — 15s → <80ms**.
- CGO/tree-sitter broke Windows builds → ship pre-compiled binaries.
- Conclusion: push heavy lifting into C (tree-sitter, SQLite); the host language is "merely an incredibly fast orchestrator."

**HN reception (cautionary)**: sharpest criticism — the demo video never showed a *connected* graph, only "a single, unconnected node that can be moved around on a canvas." A graph canvas that doesn't visibly show meaningful edges destroys credibility instantly. Commenters also noted codebase-graph tools are trending because they feed LLMs better context and help humans "visualize the shape of code" as engineers grow less familiar with implementations.

### 3.3 Sourcegraph — resources, blog, GitHub org

**SCIP** (github.com/sourcegraph/scip): language-agnostic code-indexing protocol (LSIF's successor, 2022) powering compiler-accurate go-to-def/find-refs; Protobuf schema, Go/Rust bindings, CLI; indexer ecosystem (scip-java, -typescript, -python, -clang, -dotnet, -ruby via Sorbet, rust-analyzer…). **"The future of SCIP"** (Mar 2026): governance moved to an independent community project (scip-code.org) with a SCIP Enhancement Proposal process and a steering committee from **Meta, Uber, and Sourcegraph** — now a credible cross-vendor standard for symbol/occurrence-level code graphs.

**Precise code navigation docs**: "Sourcegraph automatically uses Precise Code Navigation whenever available, and Search-based Code Navigation is used as a fallback" — a graceful-degradation pattern worth copying verbatim (precise where indexed, heuristic elsewhere, labeled as such).

**"Why coding agents fail in large codebases"** (May 2026; CodeScaleBench, 1,281 runs, 40+ repos): five failure patterns — lost in the codebase (~400K LOC onset), wrong file/symbol from lexical search, partial completion, **tool thrashing (96 tool calls/84 min vs. 5 calls/4.4 min with indexing)**, context overflow. Thesis: context problems, not intelligence problems; fixes are precise structural navigation and task-aware context.

**"AI Code Review in 2026"**: three-stage review-agent pipeline (context gathering from the diff outward → specialized model passes → confidence-thresholded filtering; "suppress comments on lines the developer hasn't touched"). Key limitation named: diff-only analysis misses **cross-cutting effects**. Quote: **"A tool that sees the diff produces diff-quality comments. A tool that sees the codebase produces codebase-quality comments."** Precision discipline: "one false positive costs seconds… a thousand trains engineers to ignore every comment."

**Agentic Batch Changes** (public beta Jun 2026): scope → execute → react to CI → iterate → human check-in loop for repo-fleet migrations; success metric is *mergeability*.

**Other org repos of note**: zoekt (trigram code search), go-diff (unified diff parser — good spec reference), go-tree-sitter + tree-sitter-wasms + many grammars, syntect fork; archived lineage srclib → LSIF → SCIP.

---

## 4. Tool landscape 2024–2026

### 4.1 Structural/semantic diff engines

| Tool | Status | Technique | Presentation | Key lessons |
|---|---|---|---|---|
| **Difftastic** (github.com/Wilfred/difftastic) | Active; de facto standard | tree-sitter CSTs → uniform s-expressions → diff as shortest-path search (Dijkstra) over (left,right) states | Terminal side-by-side, changed *nodes* highlighted | Uniform tree IR makes multi-language tractable; explicit `--graph-limit`/`--byte-limit` fallbacks to line diff; even the best structural algorithm still presents as text |
| **SemanticDiff** (semanticdiff.com) | Active, commercial | Dedicated ASTs; parse → AST diff → classify relevant/irrelevant; move/rename detection | Familiar two-pane + faded irrelevant changes | "Suppress the irrelevant" ≈ as valuable as "show the structural"; keeping familiar layout lowered adoption friction |
| **diffsitter** (github.com/afnanenayet/diffsitter) | Active, hobby-scale | tree-sitter, diff on AST leaves | Terminal | Leaf-level diffing is cheap and filters formatting noise; added an MCP server — agent-queriable structural analysis is now expected |
| **Mergiraf** (codeberg.org/mergiraf/mergiraf) | Very active; distros | tree-sitter generic trees + declarative per-language "commutative children" rules; line-merge first, GumTree matching only on conflicts | Merged files/conflict markers | Layered cheap→expensive strategy; language semantics as *data, not code*; GumTree reusable as a component |
| **GumTree v4 "Ginkgo"** (github.com/GumTreeDiff/gumtree) | Active (v4 beta through 2024) | Two-phase matching + Chawathe edit scripts (insert/delete/update/move); v4 moved to tree-sitter generators | `webdiff` HTML: color-coded actions, click a node to see its counterpart | The edit-script vocabulary is the standard data model; even GumTree converged on tree-sitter; bidirectional node-correspondence highlighting is the essential interaction primitive |
| **RefactoringMiner AST-diff** (arXiv 2403.05939; TOSEM 2025) | Active research (Java) | Refactoring detection drives matching; multi-mappings; commit-level (multi-file) | Research tool | Injecting refactoring knowledge measurably improves mappings; first AST-mapping benchmark (800 bug-fix + 188 refactoring commits) |
| **HyperAST/HyperDiff** (ESEC/FSE 2023) | Research (Inria) | Deduplicated DAG AST of an entire git history; lazified GumTree | — | Persistent/incremental tree store beats re-parsing for history-scale animation; structural sharing is the key trick |
| **sem** (github.com/ataraxy-labs/sem) | **Active, notable new entrant** (3.2k★, v0.21.0 Jul 2026) | "Semantic version control on git": entity-level (function/class) diff/blame/history + impact analysis; tree-sitter, 32 languages **incl. Swift**; three-phase matching: exact ID → structural hash → fuzzy >80% token overlap | Terminal UI, JSON, Markdown; MCP server + GitHub Action | The *entity* is the right human/agent granularity; the tiered cascade is a pragmatic fast alternative to GumTree; JSON+MCP output drove agent adoption |
| **SAT-DIFF** (arXiv 2404.04731) | Research | Tree diffing via SAT for provably minimal scripts | — | Exactness costs exponential time — citation for why heuristics |

**Incumbent absences:** JetBrains — no semantic diff (open YouTrack issues confirm). GitHub — rich diffs only for markdown/images/Jupyter/manifests; **stack graphs withered and precise code nav was unshipped** because per-language `.tsg` rule authoring was unmaintainable. SemanticMerge (Plastic SCM) — discontinued standalone, absorbed into Unity VCS: a standalone semantic-diff product is hard to sell; semantic diff survives as a *feature* of a bigger surface.

### 4.2 Control/data-flow delta visualization (the thin area)

- **BinDiff** (github.com/google/bindiff; open-sourced 2023): matches functions/blocks across binaries via call-graph + CFG structure, propagates matches through neighborhoods, computes similarity/confidence per match. **The gold-standard delta UX**: side-by-side call-graph and CFG views, matched nodes color-coded (matched/changed/unmatched), synchronized pan/zoom, click-to-counterpart. Lessons: visualize *one pair of synchronized graphs with a matching* — the matching **is** the diff; similarity is a spectrum, encode confidence; basic-block + function granularity = two zoom levels.
- **Diaphora** (diaphora.re; v3.4, ML-assisted match ranking): heuristic ensemble over CFGs/call graphs/pseudo-code with per-heuristic confidence; pseudo-code diff beside graph diff. Lessons: ensembles beat single matchers; *graphs orient, text confirms*.
- **ghidriff** (github.com/clearbluejar/ghidriff): headless Ghidra patch diffing; added/deleted/modified function triage; **Markdown/JSON output designed for sharing ("social diffing")**. Lessons: a portable artifact multiplies utility; the triage table is the right executive summary above any graph.
- **ChangePrism** (VISSOFT 2025, arXiv 2508.12649): argues red/green line diffs prevent commit-level overviews; General View (change *kinds* across a commit) + Detailed View. Validates two-level overview→drill design.
- **CFGConf** (LLNL, arXiv 2108.03047, VISSOFT 2022): JSON spec + library for domain-correct CFG drawing derived from expert task analysis — downward flow, loop contours, back-edge conventions, linear block order. Don't invent CFG layout; encode these.
- **flowR** (github.com/flowr-analysis/flowr): R static analysis building interprocedural dataflow graph + CFG, visualized in VS Code/Positron (mermaid), **~100ms for average scripts** — the latency bar. No delta view.
- **Joern** (github.com/joernio/joern): Code Property Graph = AST + CFG + PDG in one queryable graph — the reference data model for combining flows; no two-version diff.
- **CRABViz** (github.com/chanhx/crabviz): LSP-based interactive call graphs, functions grouped by file. Lesson: piggyback on LSP/indexes for call edges; file-grouping is an effective containment hierarchy.
- **DisViz** (arXiv 2510.18311): current research direction is linking dynamic traces onto CFGs.
- **IDE plugin marketplaces**: all call-graph/flowchart plugins visualize a single version; **no before/after CFG-diff plugin exists** in VS Code or JetBrains marketplaces.

### 4.3 Code visualization products

- **CodeSee (codesee.io)** — **dead**. Shut down Feb 22, 2024; assets to GitKraken May 2024. Auto-generated codebase maps + PR "Review Maps" (affected files/dependencies). Founder's stated cause: inconsistent sales; "nice to have" visualization didn't convert. Lessons: willingness-to-pay lives inside existing workflows (review/IDE), not a destination app; file-level PR maps were too coarse to change review behavior — function-level flow is the untested deeper layer; ship as embeddable library/SDK.
- **Windsurf Codemaps** (cognition.com/blog/codemaps; Nov 2025): LLM-generated, **task-scoped** maps (only the slice relevant to a prompt/task); every node clickable to file/function; maps referenceable by the agent as compressed context (a map answers instantly what costs an agent ~35k tokens of searching). Lessons: task-scoped slices beat whole-repo maps — for a diff visualizer the *commit is the scope*; node↔source linkage is table stakes; the graph is agent context as much as human UI.
- **AppMap** (appmap.io): runtime traces → sequence diagrams/dependency maps/flame graphs; can diff sequence diagrams between revisions in CI — prior art for behavioral flow deltas on the dynamic axis.
- **Sourcetrail**: original dead (2021); **petermost fork actively maintained** (monthly releases through Dec 2025; C++/Java). Demand persists for offline code cartography; note the concentrated maintenance burden.
- **Understand (SciTools)**: active commercial v7.x; the most complete static graph suite (per-function control flow, data flow, butterfly/call graphs, UML). **No temporal comparison of any graph** — the missing feature across the whole category.
- **CodeScene** (codescene.com): behavioral analysis from git history — hotspots (change frequency × complexity), **change coupling** down to function level (X-Ray). Lesson: git history can *weight* the visualization (emphasize changed functions historically coupled to others).
- **swark / gitdiagram**: LLM→Mermaid architecture diagrams (commodity pipeline; deterministic output is the differentiation). gitdiagram: instant gratification + click-through to source drive adoption.

### 4.4 LLM-era change understanding

- **CodeRabbit** (docs.coderabbit.ai; coderabbit.ai/blog — Atlas/Change Stack, May 2026): the leader in *visual* diff explanation. Every PR gets a walkthrough; **Mermaid sequence diagrams of updated flows rendered inline** when interactions change. **Change Stack**: reorganizes a PR into *functional layers* ordered "as an engineer would explain it"; three panels (layer nav / diff / synchronized summaries); per-layer sequence/state/ER diagrams **only where a visual helps**; every layer anchored to concrete diff line ranges. Lessons: direct market validation that diffs need flow-level visual explanation; diagrams are LLM-generated (probabilistic) — a deterministic, analysis-derived delta is the credibility gap to fill; "diagram only when it earns its place"; narrative ordering matters as much as the diagram.
- **GitHub Copilot PR summaries** (GA Apr 2025): prose linked to specific lines; manual-trigger; documented hallucination risk; text-only. Line-anchored claims are the trust mechanism.
- **Graphite/Diamond**: $52M Series B Mar 2025; **acquired by Cursor Dec 2025**. Review tooling is consolidating into AI IDE vendors — a visualization library is acquisition-relevant infrastructure; stacked-diff workflows need per-commit visual explanations.
- **GitLab Duo Code Review**: agentic pre-scan of MR diffs to fetch related context (tests, dependencies) before reviewing — the pre-scan is exactly the graph slice a library should compute deterministically.
- **Mermaid Chart AI**: added diagram *diffing* (two diagram versions highlighted) in 2025 — diagram-as-code diffs in PRs are now a review pattern; export Mermaid for portability.

### 4.5 Git diff UX innovations

- **GitHub "Files changed" overhaul** (preview Jun 2025 → default Jan 2026): React rewrite; comment on any line; resizable file tree; **commit-by-commit review**; overview panel. No semantic features — even GitHub's ceiling is better ergonomics on line diffs, and commit-by-commit review gives per-commit visualizations a natural slot.
- **jj/Jujutsu**: changes mutable until pushed; conflicts first-class; universal undo. The diff is becoming an *editable, addressable object* — treat "a change" as an identity that evolves, not a one-shot render.
- **GitButler** ($17M Series A): virtual branches as drag-and-drop lanes; hunks as draggable objects — proven direct-manipulation UX (select a subgraph → act on it).
- **difit** (github.com/yoshiko-pg/difit): `npx difit` → local GitHub-style review UI for any commit; comments copyable as AI prompts; ships a Claude Code skill. Zero-install, local, single-commit review is the distribution wedge.
- **delta (git-delta)**: terminal remains first-class; word-level intra-line highlighting is the minimum fidelity users expect.
- **ReviewStack** (Meta/Sapling): stack review one commit at a time — the unit of review is shrinking to the single coherent change: small graphs, tractable layout.

---

## 5. Academic literature 2020–2026

⭐ = directly visualizes flow/graph deltas (rare, most valuable).

### 5.1 AST/tree diffing beyond GumTree-2024

- **Hyperparameter Optimization for AST Differencing (DAT)** — Martinez, Falleri, Monperrus, TSE 2023. GumTree-family matchers are highly hyperparameter-sensitive; data-driven tuning against developer-preferred mappings beats defaults. → Per-language tuning measurably improves perceived diff quality.
- **Refactoring- and Semantic-Aware AST Differencing + Benchmark** — Alikhanifard & Tsantalis, TOSEM 2025 (10.1145/3696002). The de facto accuracy benchmark (commit-level, multi-file, refactoring-aware mappings).
- **BDiff** — Lu, Liu, et al., arXiv 2510.21094 (2025). Text-based differ recovering block-level move/copy — a pragmatic middle ground when AST diffing is too slow or the file doesn't parse; block hunks map onto CFG regions better than Myers hunks.
- **SoliDiffy** — Eshghie et al., arXiv 2411.07718 (2024). GumTree ported to Solidity; documents exactly what porting structural diffing to a new language costs — the template for a Swift port.
- **ChangeDistiller Retrospective** — Fluri, Würsch, Pinzger, Gall, TSE 2025. What held up over ~18 years: the change-type taxonomy and statement-level granularity — a ready-made semantic label set.
- **TransplantFix** — Yang et al., ASE 2022. Graph differencing over ECFG-like program graphs for fix transplantation — one of the few post-JDiff works literally computing deltas on control-flow-augmented graphs; machinery reusable.
- **Understanding Code Changes with Small-Scale LMs** — Li et al., ASE 2024. Deployable small models produce usable change summaries — relevant for on-device annotation in a local Mac tool.
- **Micro-Changes** — Chen, Lanza, Hayashi, ICSME 2024 (arXiv 2409.09923). Catalog of intention-revealing change patterns (guard insertion, condition strengthening…) detected atop AST diffs — the ideal intermediate layer between raw edits and visualization labels.
- **AtomicCommitBench** — Lin et al., arXiv 2607.03332 (2026). Decomposing squashed patches into atomic sequences; dependency-aware evidence (control/data deps) improves groupings — the preprocessing for "one concern at a time."

### 5.2 Semantic diff / equivalence checking

- **PASDA** — Glock, Pichler, Pinzger, JSS 2024. Partition-based semantic differencing with best-effort confidence verdicts on solver timeouts; per-input-partition verdicts are renderable ("these paths behave identically, these diverge").
- **ProbeGen** — Allamanis & Yin, arXiv 2502.18473 (2025). LLM-with-execution-feedback counterexample search; disproves 18% of "equivalent" pairs — a cheap way to attach "behavior diverges, here's an input" evidence where no SymDiff-class infra exists.
- **EquiBench** — Wei et al., EMNLP 2025 (and **CETBench**, arXiv 2506.04019). Best LLMs barely beat random on hard equivalence categories and lean on syntactic similarity. → Don't build trust on raw LLM equivalence judgments.
- **DiffKemp TOSEM extension** (Zenodo 10.5281/zenodo.13254075). Current reference for pattern-based scalable equivalence of refactored C.
- **Semantic merge conflicts**: **SAM** (Da Silva, Borba et al., JSS 2024 — test-generation-based detection), **Muylaert et al.** (SCAM 2023 — differential symbolic execution on three-way merges; path-condition deltas *are* control-flow deltas in logical form), **ConflictLens** (SEKE 2025 — LLM-based), Zhang et al. ISSTA 2022 (pretrained LMs resolving merge conflicts). Merge scenarios are a killer use case for flow-diff visualization.
- **SigmaDiff** — Gao et al., NDSS 2024. Deep graph matching over IR-level interprocedural PDGs for binary diffing, seeded by symbolic features — the current SOTA for the matching problem a delta visualizer must solve; the pretrain/fine-tune recipe transfers. (Adjacent: Contextual Diffing, AsiaCCS 2025 — call-graph-context matching across versions.)

### 5.3 Change comprehension / untangling / review studies

- **ColaUntangle** — Hou, Tan et al., TOSEM 2025 (arXiv 2507.16395). Multi-agent LLM untangler reasoning over explicit control/data-flow dependencies + implicit semantics; +44–82% over prior best. Its "explicit context" is literally a PDG slice — outputs give free concern-groups for coloring.
- **HD-GNN** — Fan et al., ASE 2024. Heterogeneous GNN finds dependencies invisible to local PDG edges; +19–25% over prior untanglers. → Local flow edges alone mis-cluster; grouping needs entity-level context too.
- **Tangled-change detection with LLMs** — Opu et al., arXiv 2505.08263 (2025). F1 ≈ 0.9 pre-filter for "does this commit need untangling at all."
- **Deknop et al.** — VISSOFT 2021 + PhD 2023 ⭐. Scalable log-differencing visualization for COBOL migration triage (expected vs. unexpected changes) — rare user-facing diff visualization with industrial evaluation; aggregate-first, drill-down patterns.
- **Review empirics**: Sun et al., TSE 2026 (22k AI review comments — concise, snippet-bearing, **hunk-level** comments are what cause code changes); Aðalsteinsson et al., ESEM 2025 (reviewers suffer missing context; want upfront AI-led review for large/unfamiliar PRs — a flow-delta overview is precisely the missing-context artifact); Pirouzkhah et al. 2026 (purpose/rationale are what reviewers value — pair the flow diff with intent summaries).

### 5.4 Visualization

- **DiffSeer** — Wen, Wang et al., IEEE CG&A 43(2) 2023 ⭐⭐. *The* recent methodological statement of the core idea: visualize the **differences** between graph snapshots instead of the graphs — overview timeline of change + structural-delta detail views + nonlinear time-slicing focused on high-change intervals; change-magnitude glyphs on edges transfer directly to CFG/DFG diffs.
- **CFGConf** — Devkota et al., VISSOFT 2022. (See §4.2 — CFG-specific layout requirements + JSON spec.)
- **Lee, Archambault, Nacenta** — TVCG 27(2) 2021. User study: interactive time navigation/scrubbing beats autoplay animation for dynamic-graph change tasks.
- **CodeLens** — arXiv 2307.14902 (2023). Token/AST/CFG/DFG in one interactive web tool (single version) — the baseline UI to differentiate from.
- **AI Chain CFG generation** — Huang et al., arXiv 2306.00757 (2023). Decomposed LLM pipeline builds CFGs for incomplete/uncompilable code, beating parser-based tools on broken snippets — a recipe for flow mid-edit.
- **Probe Log** — Krebs et al., ‹Programming› 2023. Example-based cross-procedure control flow rendered *inline with code* — model for editor-embedded (vs. separate-window) flow visualization.
- **Dynamic-CFG commit representation** — Du et al., Machine Learning 114 (2025). Represents a commit as CFG deltas and feeds them to commit-message generation, beating token-diff baselines — independent evidence that CFG-level deltas carry the semantics developers describe.
- **Giovannangeli et al.** — Visual Informatics 2020. Metrics-based framework for comparing graph-visualization techniques without full user studies.

### 5.5 Slicing / change impact / incremental analysis

- **LADDDER** — Szabó, Erdweg, Bergmann, PLDI 2021. Millisecond incremental whole-program lattice dataflow in Datalog — the reference design for "recompute flow facts after a diff in O(change)."
- **Elastic incrementalization for Datalog** — Zhao et al., PPDP 2021 (Soufflé line). Choose incremental vs. full recompute based on change size — commits vary wildly; elasticity keeps a visualizer responsive. (Related: JavaDL OOPSLA 2021; Differential Datalog 2019.)
- **CodeFuse-Query** — Xie et al., 2024. Ant Group's industrial Datalog code-analysis platform with incremental extraction and explicit code-change task types at 10B LOC/day — diff-triggered, query-based flow analysis proven at scale.
- **NESA** — Wang, Zhang et al., 2025. Compilation-free neuro-symbolic static analysis (restricted Datalog; parsers for syntax, LLMs for semantics, lazy/incremental prompting) — the emerging hybrid recipe, attractive where compiler-integrated analysis is heavyweight.
- **Program slicing with LLMs** — Shahandashti et al., COMPSAC 2025 (arXiv 2409.12369). Best model ~60% slicing accuracy; complex control flow is the dominant failure. → LLMs label, they don't compute edges. (Learned slicers for broken code: SLICET5 arXiv 2509.17338; Sliceformer arXiv 2604.26961.)
- **codebadger** — Lekssays, 2026. MCP server exposing Joern CPG operations (slicing, taint, dataflow) to LLMs — architecture blueprint for an LLM copilot querying the same flow graphs the UI renders.
- **RippleGUItester** — Su, Pradel, Chen, arXiv 2603.03121 (2026). A code change as the epicenter of a ripple effect; executes pre/post versions and diffs behavior — matches the radial/impact framing of a flow-diff view.

### 5.6 Swift analysis in academia (near-exhaustive — it's thin)

- **SWAN** — Tiganov, Cho, Ali, Dolby, ESEC/FSE 2020. The only substantive academic Swift analysis framework: dumps SIL via the compiler, parses it (~99% coverage), lowers to SWIRL IR, builds call graphs (CHA/VTA/UCG), taint/typestate analysis. Proves SIL→CFG/call-graph feasibility; documents the toolchain-version-tracking pain. Follow-up: "Designing UIs for Static Analysis Tools" (ACM Queue 2021) — user-centered presentation of Swift findings.
- **AccessiblePreview** — MOBILESoft 2025. SwiftSyntax-based static inspection surfaced through Xcode previews — precedent for that integration channel.
- Context: IR-design survey (arXiv 2405.12841); **ArkAnalyzer** (arXiv 2501.05798) — the closest "bootstrap analysis for an ecosystem without one" playbook.

---

## 6. Swift ecosystem building blocks

### 6.1 Parsing

| Component | Status (mid-2026) | Verdict |
|---|---|---|
| **swift-syntax / SwiftParser** (github.com/swiftlang/swift-syntax) | Very active; 603.0.2 (Jun 2026); incremental parsing via `Parser.parseIncrementally` | **Use** — best-in-class for Swift; but Swift-only, purely syntactic, heavy dependency. The Swift-specific enrichment backend, not the multi-language spine. |
| **SwiftTreeSitter** (ChimeHQ) | Active; v0.10.0 Mar 2026; incremental, error-tolerant, S-expression queries; **50+ grammars as SPM packages**; `SwiftTreeSitterLayer` for nested languages | **Use — the only credible multi-language parsing path in a Swift app.** Same substrate as difftastic/GitHub code-nav. Caveats: byte/UTF-16 index translation; per-grammar quality/maintenance varies. |
| tree-sitter-swift (alex-pinkus) | Active, community "best effort" | Uniform fallback for Swift; SwiftSyntax upgrades fidelity. |
| **Neon** (ChimeHQ) | Active | **Use** for source-pane highlighting (merges tree-sitter + LSP + regex token sources). |
| SwiftSemantics (SwiftDocOrg) | **Archived** (org archived Sep 2023) | Avoid; trivial to reimplement. |

### 6.2 Semantic info / CFG extraction

- **SourceKit-LSP**: active; background indexing default since Swift 6.1 (Mar 2025); call hierarchy, references. It's a server process — pair with ChimeHQ **LanguageClient** (active) → the same client speaks to *any* language's LSP server for call-hierarchy extraction. macOS surface.
- **IndexStoreDB** (github.com/swiftlang/indexstore-db): active; SPM library querying compiler index stores — symbols (USR), occurrences, **relations (calledBy, overrides)**. Requires a built project; Swift/Clang only; no temporal awareness (two commits = two index stores). **Use** for precision on macOS. Wrappers: CheekyGhost-Labs/IndexStore, swift-indexstore.
- **Periphery** (github.com/peripheryapp/periphery): active (3.7.4). Its architecture is the recipe to steal: **index store for edges + SwiftSyntax walks to fill gaps the index can't express** → declaration/reference graph → root-walk.
- **SourceKitten**: alive (0.37.0 Feb 2026) but superseded — avoid for new work.
- **SIL / CFG feasibility**: `xcrun swiftc -emit-sil` emits canonical SIL, which *is* a CFG serialization (basic blocks + terminators). No shippable tooling exists; SWAN proves parsing is feasible (JVM-based, research-grade — mine its SIL grammar, don't depend on it). Requires compiling code → breaks on mid-edit states.
- **Practical verdict**: **no Swift-native CFG library exists for any language.** The established recipe is CFG-from-tree-sitter-CST with per-language node mappings — precedents: tree-climber (github.com/bstee615/tree-climber; algorithm cribbed from Joern's `CfgCreator.scala`), COMEX (arXiv 2307.04693), Joern's CPG. tree-sitter-graph (Rust DSL for CST→graph) is the closest portable mapping format but has no Swift bindings. → Per-language visitor over tree-sitter CSTs, statement-level basic blocks; Swift optionally upgraded via SwiftSyntax/IndexStoreDB/SIL.

### 6.3 Git access

- **SwiftGit2**: effectively dormant (last release 0.6, May 2019). **Avoid.** Forks (SwiftGit3, light-tech, sharplet/swift-git) all small — watch, none safe as foundation.
- **Shelling out to `git`** via `Process`: zero deps, always current — **use on macOS**. Not available on iPadOS (libgit2 is the iPad-only escalation — Working Copy's path).
- **Unified diff parsing**: ~200 lines; **tornikegomareli/gitdiff** (pure-Swift parser + SwiftUI GitHub-style renderer, 2024–25) is the closest package — vendor or own it.
- Design the core to accept `(oldBlob, newBlob, unifiedDiff)` as pure inputs so git access is pluggable.

### 6.4 Graph layout & rendering

- **elk-swift** (github.com/lukilabs/elk-swift) — **key find**: pure-Swift port of ELK's *layered (Sugiyama)* algorithm by Luki Labs (Craft); v1.0.0, early (5 commits, 9★), EPL-2.0; compound graphs, ports, edge labels. **Primary CFG layout candidate** — the missing Sugiyama-in-Swift piece. Fallbacks: extend the port, or elkjs via JavaScriptCore.
- **BeautifulMermaid** (lukilabs/beautiful-mermaid-swift): v1.0.4 Apr 2026, 348★; native (no WebView) Mermaid rendering on elk-swift; SwiftUI view + CoreGraphics layer. Watch — export/preview path and reference code; not the interactive core (no click callbacks/tooltips).
- **Grape + ForceSimulation** (github.com/li3zhen1/Grape): v1.1.0 Jan 2025; simd-accelerated force-directed SwiftUI graphs (2D/3D, visionOS). ~5ms/120 iterations on 77v/254e in release (**debug ~100× slower**). Force-direction is wrong for CFGs — reserve for call-graph constellation views.
- **SwiftGraph** (davecom): maintained; graph *containers* + algorithms, no layout/rendering — fine as model-layer container.
- **GraphViz Swift wrapper**: archived org + requires system graphviz — avoid at runtime; DOT emission is trivial to hand-write for debug/export.
- **SwiftUI primitives**: the community-standard hybrid is **`Canvas` for edges + individual views for nodes** (hit-testing, context menus, accessibility) + custom `Layout` conformance wrapping ELK output + **`matchedGeometryEffect` keyed on stable block IDs** for before/after morphs. The OS 26 rendering rewrite (6×/16× large-list improvements, ~40% GPU reduction claims; Instruments 26 SwiftUI Cause & Effect Graph) raises the ceiling before Metal is needed.
- **Swift Charts**: still no node-link chart type (WWDC24 function plots; WWDC25 Chart3D) — irrelevant for the graph itself; fine for ancillary metrics.

### 6.5 Diff/source-viewer precedents

- **Kaleidoscope**: the benchmark macOS diff UX (Blocks/Fluid/Unified, character-level refinement) — **text-based only; nobody in the native-Mac space does semantic/CFG diffing. That's the open lane.** Tower/Fork/Xcode: all line/hunk-based.
- **Difftastic (Rust) and GumTree (Java) have no Swift implementations** — a Swift GumTree-over-tree-sitter is itself a notable sub-deliverable.
- Sequence alignment for animations: stdlib **`CollectionDifference`** (Myers + `inferringMoves()`) first; Differ/DifferenceKit if performance demands.
- Source panes: **Runestone** (iOS/iPadOS, tree-sitter, production-grade); **CodeEditSourceEditor** (macOS, active, self-described not-production-ready); **STTextView** (active; author candid about TextKit 2 instability); minimal path — AttributedString + Neon over a plain text view for read-only display.

---

## 7. Cross-cutting synthesis

The ten load-bearing conclusions that shaped the plan:

1. **The intersection is empty.** Structural diff (text output) × flow visualization (single version) × graph-delta rendering (binary only) × LLM diagrams (probabilistic) — a deterministic source-level flow-delta visualizer has no incumbent, in products or literature.
2. **The data model is settled by convergent evolution**: normalized tree IR (Difftastic) → entity tier (sem) → GumTree edit scripts (insert/delete/update/move) → **matched graph pair with a confidence spectrum** (BinDiff). Serialize everything (JSON/Mermaid/MCP) — agents are now a first-class consumer.
3. **The pipeline doctrine is settled too**: cheap pass first, structural analysis lazily per entity, hard resource limits, labeled fallback at every level (Mergiraf fast mode, Difftastic limits, Sourcegraph precise/search fallback). Latency bars: ~100ms/file (flowR), sub-second to first delta.
4. **The headline visual feature is unshipped everywhere**: a fourth state — *affected-but-unedited* code with causality links from trigger to effect (SemanticDiff proposed it; Horwitz 1990 formalized it; Sourcegraph's "diff-quality vs codebase-quality comments" is the business case).
5. **Interaction primitives are proven, just never assembled**: overview triage table → drill (ghidriff, ChangePrism); synchronized correspondence click-through (GumTree, BinDiff); slice-scoped focus (both local reports); scrubbed staged transitions (GraphDiaries + Lee 2021); guided walkthrough for cognitive load (CodeSee's 4±1-chunks argument, CodeRabbit's narrative layers); hunk-anchored terse annotations (TSE 2026 review empirics).
6. **CFG drawing has domain conventions** (CFGConf): downward flow, distinct back-edges, loop contours, stable linear block order — encode them, don't invent layout. Layout *stability* across the delta (stable IDs, anchored relayout) is the #2 gap in the literature and non-negotiable.
7. **LLM division of labor is calibrated by evidence**: good at labeling, narration, counterexample search (ProbeGen), untangling assistance (ColaUntangle); unreliable at equivalence (EquiBench/CETBench) and slicing (~60%). Deterministic core, optional LLM garnish.
8. **The Swift stack exists but is young at the load-bearing joint**: SwiftTreeSitter (solid) + elk-swift (v1.0.0, needs a validation spike) + Canvas/Layout/matchedGeometryEffect (solid); **CFG-from-CST construction is the library's original IP** — no Swift CFG library exists for any language.
9. **Per-language maintenance is the death risk** (GitHub stack graphs, Sourcetrail): keep language knowledge declarative and minimal (query files + small CFG mappings), launch with few languages, share C-family logic.
10. **Distribution: embed, don't build a destination** (CodeSee and SemanticMerge died as destinations; difit's zero-install wedge, MCP adoption of sem/diffsitter, review consolidating into IDE/agent vendors) — library + reference app + MCP server, riding the shrinking unit of review (commit-by-commit GitHub, ReviewStack, jj).

→ Full design consequences, architecture, roadmap, and risk register: [`../PLAN.md`](../PLAN.md).
