# Reviewer timing follow-up

Date: 2026-08-04

Status: post-`0.1.0` dogfood metric; not a release gate

## Question

Can a reviewer answer “what does this commit change about this function's control flow?” faster and at least as accurately with FlowDelta than with a plain textual diff?

## Corpus

Use the ten provenance-locked commits in `Tests/FlowDeltaAnalysisTests/Fixtures/revision-corpus.json`: five from `swift-syntax` and five from `swift-nio`. Each entry already carries a concrete control-flow review question. Randomize tool order per participant and do not reuse a commit across both conditions for the same participant.

## Conditions

1. `git diff` (or the host's normal native diff view).
2. FlowDelta entity triage + superimposed CFG delta + synchronized source.

The same repository checkout, revision pair, display, and time limit apply to both. FlowDelta may not use any LLM narration.

## Measures

- task completion time;
- answer correctness against a maintainer-authored rubric;
- confidence on a five-point scale;
- whether the participant opened source after viewing the graph;
- matcher or analysis trust issue observed during the task.

Time alone is not success: faster wrong answers fail. Report median time and correctness, individual paired differences, and the exact commits used. Keep preference comments separate from effectiveness results.

## Dogfood trigger

Run the exercise after `0.1.0` has reviewed at least three of its own changes and the permanent corpus has no unresolved matcher regressions. Results can reprioritize M2 interaction work, but do not retroactively redefine the deterministic correctness gates.
