---
name: simplify
description: Review changed code for reuse, simplification, efficiency, and abstraction-level cleanups, then apply behavior-preserving fixes. Quality only; it does not hunt for bugs.
argument-hint: "[<target>]"
---

# Simplify

Use this when the user asks for `/simplify`, `$simplify`, a simplification pass, cleanup-only review, or an Orchestra phase step says to run `/simplify` over the diff.

You are improving the quality of changed code, not hunting for correctness bugs. Review for reuse, simplification, efficiency, and altitude issues, then fix what is safe. Do not look for correctness/security bugs; that is the implementation audit or code-review path.

## Scope

- If the user provided a target, review that target instead of the default diff.
- Apply only behavior-preserving cleanups.
- Do not expand scope, rewrite unrelated code, or change public behavior.
- If a finding would require behavior changes, broad refactors, or work outside the reviewed diff, skip it and mention why.

## Phase 0 - Gather the diff

Determine the review scope:

1. If a PR number, branch name, file path, or explicit target was provided, inspect that target.
2. Otherwise run `git diff @{upstream}...HEAD`.
3. If there is no upstream, try `git diff main...HEAD`, then `git diff HEAD~1`.
4. If there are uncommitted changes, or the range diff is empty, also run `git diff HEAD` and include working-tree changes.

Treat the collected diff as the review scope.

## Phase 1 - Review with four cleanup agents

Launch four independent review agents in parallel, one for each angle below. Pass each agent the diff, the target if any, and the output format.

Host dispatch:

- **Claude Code:** use the Task/subagent mechanism.
- **Codex:** use `multi_agent_v1.spawn_agent`. If the spawn tool is not visible, use tool discovery for "multi-agent spawn subagent", then spawn the agents. Use read-only `explorer` agents for the four review lanes.
- **Cursor (2.4+):** use the **Task tool** to launch the four cleanup lanes as subagents **in parallel, in a single message**; name each lane and set `readonly: true`. If the Task mechanism isn't available, use the local-passes fallback below.
- If the host truly has no subagent mechanism, perform four separate local passes with the same headings. Do not collapse the headings into one general review.

### Reuse

Flag new code that re-implements something the codebase already has. Search shared/utility modules and files adjacent to the change, and name the existing helper or pattern to use instead.

### Simplification

Flag unnecessary complexity the diff adds: redundant or derivable state, copy-paste with slight variation, deep nesting, dead code left behind, or abstractions that do not pay for themselves. Name the simpler form that does the same job.

### Efficiency

Flag wasted work the diff introduces: redundant computation or repeated I/O, independent operations run sequentially, blocking work added to startup or hot paths, or long-lived objects built from closures that retain large enclosing scopes. Name the cheaper alternative.

### Altitude

Check that each change is implemented at the right depth, not as a fragile local patch. Special cases layered on shared infrastructure are a sign the fix is not deep enough; prefer generalizing the underlying mechanism over adding one-off branches.

Each review agent returns findings with:

```markdown
- file: path/to/file
  line: 123
  angle: reuse | simplification | efficiency | altitude
  summary: one-line issue
  cost: what is duplicated, wasted, or harder to maintain
  fix: concrete behavior-preserving cleanup
```

## Phase 2 - Apply the fixes

Wait for all four agents/passes to complete. Deduplicate findings that point at the same line or mechanism. Apply each remaining safe cleanup directly.

Skip any finding whose fix would change intended behavior, require changes well outside the reviewed diff, or is a false positive. Do not argue with skipped findings; note the skip briefly.

Finish with a short summary:

- Cleanups applied
- Findings skipped, with reason
- Confirmation if the diff was already clean
