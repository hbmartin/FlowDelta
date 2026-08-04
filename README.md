# FlowDelta

FlowDelta is a deterministic Swift library for explaining how a Git change alters program control flow. It parses source into a normalized syntax tree, matches declarations and syntax across revisions, constructs statement-level control-flow graphs, computes a matched graph delta, and renders the result with native AppKit.

The first release is intentionally Swift-only. Multi-language parsing, data-flow analysis, call graphs, and the GitX History integration are later milestones.

## Requirements

- Swift 6.2 or newer
- macOS 15 or newer
- arm64

FlowDelta is licensed under LGPL-3.0. Linking it into a GPLv2-only application is formally incompatible according to the FSF; embedders make that decision for their own distribution.
