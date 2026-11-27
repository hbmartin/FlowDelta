# M3 validation record

Date: 2026-11-27

Result: **FlowDelta 0.3.0 gate passed**

Validation began after `notes/013-m3-implementation.md` declared the M3 implementation complete. It ran against the committed candidate `12de6d8` (the coverage ratchet followed as `b8a6baa`) on `codex/m2-closeout-m3`.

## Package results

- Debug: `swift test` passed all 145 XCTest cases.
- Release: `swift test -c release` passed all 145 cases, and `swift build -c release` passed.
- Extension: `swift test --package-path Extensions/FlowDeltaIndexStore` passed all 5 cases against a real Swift compiler index. Its release build passed.
- Coverage: the Xcode result bundle passed `scripts/check_coverage.py` at **95.12% across 58 library files**, up from 94.03% across 38. `--record-improvements` raised the overall floor and the four tracked file floors.
- Style: pinned SwiftFormat 0.62.1 lint and pinned SwiftLint 0.63.2 strict passed with no violations.
- Native UI: the reference snapshot was re-recorded deliberately and then passed. The new snapshot has the M3 header controls, the tangled-revision banner and the corrected summary. The noise dial, concern rows, banner, walkthrough, identifiers and tab order pass in `FlowDeltaReviewM3Tests`.
- Diagnostic still: `notes/artifacts/m3-reference-review.png` was inspected at its original resolution. No screen recording was made.
- CLI: the release `flowdelta` reports 0.3.0. A 32-run smoke matrix exited 0 and produced output for each run, and every JSON output parsed. It covered:
  - all four formats (table, JSON, Mermaid, Markdown);
  - four flag sets: none, `--noise hide-cosmetic`, `--group-by-concern --walkthrough`, and all three together;
  - real Swift history (FlowDelta `d4ac844..0722fea`) and real Python history (a GitX script-test revision).

## Defects found and fixed during validation

- **Dark Mode legibility.** Inside a Dark Mode window, the review chrome's system text colors resolved to white on its fixed light fills. The canvas and triage band also turned black. The reference snapshot depended on the machine's appearance when the test ran. The review view now adopts Aqua unless its host sets an appearance. Layer colors are resolved for each view's own appearance, and `FlowDeltaReviewAppearanceTests` pins the behavior.
- **`--noise` help.** `--help` printed the default as `showAll`, the Swift case name, which the parser rejects. It now prints `show-all`.
- **Summary plural.** The review summary read "1 files (Swift)". It now counts files and function deltas in the singular when there is one. GitX's own Flow tests match the old text and change with the 0.3.0 pin.
- **Per-file coverage floors.** The first coverage run passed overall, but three tracked files fell below their floors after the review-view split and the cancellation work:
  - Tests now cover the "No flow graph was available" diagnostic for a removed function, non-UTF-8 name-status output, nib decoding, and a revision with no function changes.
  - Two unreachable branches were removed rather than tested: a cancellation rethrow, and an unsupported-path guard after the caller had already filtered paths.

## Consumer gate

A clean executable package resolved FlowDelta through `file:///Volumes/Pro2T/FlowDelta` at exact version 0.3.0. It linked Core, Analysis, Git, Export, Layout and UI, then built and ran: it printed the noise policies, a full set of export options and a fresh review view's state. FlowDelta resolved at its tagged revision. ArgumentParser resolved at 1.8.2 standalone; GitX's Sparkle constraint keeps it on the compatible 0.x line, and the CLI's help fix uses API present since 0.4.3. This exercises SwiftPM's semantic-version resolution rather than a local path dependency. GitX's own integration follows in its `codex/flowdelta-0.3-review` branch.

## Accepted risks and deferrals

- **Python and Go def-use are lexical.** The binding rules can add false data edges where a name is shadowed in ways the rules do not model.
- **Concern grouping is heuristic.** Name references can still over-merge unrelated changes that share an identifier.
- **Cancellation.** `FlowDeltaAnalyzer.analyze` and `GitCLIRevisionProvider.comparison` throw `CancellationError` when their task is cancelled. Hosts must not report that as a failure.
- **Deferred:**
  - MCP hooks;
  - the iPad-ready core audit;
  - a dark palette for the review chrome. The review view stays Aqua.
