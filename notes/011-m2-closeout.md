# M2 closeout

Date: 2026-11-27

M2 is complete. FlowDelta 0.2.2 is the M2 release.

## Evidence

- Package: `notes/009-m2-validation.md` (multi-language CFG, Swift and TypeScript/JavaScript def-use, backward slices, call-graph neighborhood, optional IndexStoreDB extension).
- Semantic-release boundary: `notes/010-m2-release-boundary-correction.md`. 0.2.2 supersedes 0.2.0 and 0.2.1. It has no revision- or branch-based dependencies in the core graph, and it accepts Sparkle's `swift-argument-parser` range.
- Consumer: GitX resolved the pushed exact 0.2.2 tag at revision `dcb4be3` and shipped the History Flow tab through a thin adapter. Its full correctness, UI, Thread Sanitizer, Address/Undefined Behavior Sanitizer, performance, analyzer and coverage gates passed; the evidence is in GitX `notes/002-flowdelta-m2-validation.md`.
- Post-release review fixes from FlowDelta PR #3 (`e6ee855`) are on `main` and ship in 0.3.0. They were never tagged as an 0.2.x patch.

## What GitX surfaces after M2

The M2 Flow tab shows the triage list, the graph and the source pane, and selects a review mode through `setReviewMode(Int)`. Most host controls (presentation, slice direction, export, node context menus and keyboard navigation) are not reachable from GitX yet. The 0.3.0 release adds a typed host API for them, together with the M3 features GitX will show: the noise dial, concern grouping, the walkthrough, and Python and Go def-use.
