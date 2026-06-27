# Planning Orchestrator — Advanced (Interview Mode)

**Task:** $ARGUMENTS

## Current Workflow (auto-loaded)

Run: `ls -la .orchestra/workflows/current/ 2>/dev/null || echo "NO_ACTIVE_WORKFLOW"`

## Available Specialized Agents

Run: `ls .orchestra/agents/ 2>/dev/null || ls .claude/agents/ 2>/dev/null || ls .agents/ 2>/dev/null || echo "NO_AGENTS_DIR"`

---

## Your Instructions

This produces the **same artifacts** as `/orchestra:plan` in Claude Code or `$orchestra plan` in Codex (`Plan.md`, `Implementation_Notes.md`, `decisions.json`+`Decisions.md`, `status.json`) but with relentless interview passes that walk every branch of the decision tree.

### Step 0: Acquire the lock

Run: `bash .orchestra/scripts/orchestra/lock.sh planner-advanced`

If non-zero, another actor holds it. Report the holder and stop.

### Interview rules (apply in every interview phase below)

- Ask **one question at a time**. Never batch.
- For every question, provide your **recommended answer** with reasoning.
- If a question can be answered by exploring the codebase, **explore first** and only ask if exploration leaves real ambiguity.
- Walk the decision tree depth-first: each answer may unlock sub-questions — chase them down before moving sideways.
- Resolve dependencies between decisions one-by-one. If decision B depends on A, settle A first.
- Keep going until you reach **shared understanding** — every branch resolved, no hand-waving.
- Log every resolved question into `decisions.json` immediately via `add-decision.sh`.

### If workflow exists:

1. Read `status.json` and `Plan.md`
2. Ask: **Continue Planning (Interview)** or **Start Executing**
3. If continuing → jump to PHASE 5 (Design Tree Walk)
4. If executing → tell user to run `/orchestra:execute` in Claude Code or `$orchestra execute` in Codex for one phase, or `$orchestra execute all` in Codex for autopilot

### If NO_ACTIVE_WORKFLOW:

---

## PHASE 1: Initialize

Run: `bash .orchestra/scripts/orchestra/init-workflow.sh "$ARGUMENTS"`

---

## PHASE 2: Pre-Research Interview

Resolve scope, intent, and constraint ambiguity *before* spending agent budget on research. Walk these branches (only ask if codebase exploration can't answer):

- **Scope** — what's in / out? Which surfaces, users, environments?
- **Constraints** — performance, compatibility, security, deadlines, budgets?
- **Success criteria** — how will the user verify this? What does "done" look like?
- **Non-goals** — what should explicitly *not* change?
- **Existing patterns** — in-repo patterns to follow or deliberately deviate from? (Explore first.)

Log each resolved question:

```
bash .orchestra/scripts/orchestra/add-decision.sh add "Question text" "Recommended answer"
bash .orchestra/scripts/orchestra/add-decision.sh answer D001 "User's chosen answer" user
```

---

## PHASE 3: Research (Parallel)

Dispatch parallel research using your host tool's sub-agent mechanism. Always include a codebase researcher; add domain-specific agents whose `description` overlaps with the task. If the host cannot spawn subagents, do focused local research and cite the files/docs read.

Include the resolved decisions from PHASE 2 in the agent prompts so they research with full context.

---

## PHASE 4: Synthesize Research

Append findings to `.orchestra/workflows/current/Implementation_Notes.md` under `## Findings`, with sub-sections per agent/source. Cite everything.

---

## PHASE 5: Design Tree Walk (the heart of plan-advanced)

Now that research is in, grill the user on every design decision the research surfaced.

For each branch (data model, API shape, UI flow, error handling, migration strategy, rollout, etc.):

1. State the branch and why it matters
2. Provide your **recommended answer** with reasoning grounded in the research
3. Ask one question
4. If the answer opens a sub-branch, recurse before moving to the next sibling
5. `add-decision.sh add` then `add-decision.sh answer` for each

Do not move on until every branch is resolved or explicitly deferred (mark deferred ones with `answer: "DEFERRED — <reason>"`).

---

## PHASE 6: Create Plan

Edit `.orchestra/workflows/current/Plan.md`.

**Write for an autonomous, possibly-weaker executor.** This plan may be run end-to-end by `phase-runner.sh` (or `$orchestra execute all`) with no human in the loop and no pause for questions, possibly by a cheaper model. The executor applies what's written and defers what it can't resolve — it won't interpret, choose, or research. All the interview rigor you just did must land *in the plan* as specificity, so a faithful literal execution can't make the code worse. Where you'd expect the executor to decide, **bake the decision into the step** as a pre-authorized default ("if X, do Y").

### Assumptions block (write before phases)

Surface every non-trivial premise the plan rests on. Tag each as `[verified]` (you actually checked) or `[untested]` (you're guessing). Example:

```markdown
## Assumptions

- [verified] Auth middleware lives at `src/middleware/auth.ts` (checked).
- [untested] The `useUser` hook returns `null` when logged out — assumed but not confirmed.
```

**Verify assumptions now, at plan time.** The autonomous executor won't pause to catch a wrong premise, so `[untested]` items should be near-zero by approval — do the cheap check while planning and upgrade to `[verified]`, or ask the user in PHASE 8. Any `[untested]` item that survives approval is a risk the user has explicitly accepted.

### Phase format (strict)

```markdown
### Phase 1: Phase Name

**Intent:** Why this phase exists and what "done well" looks like — the outcome a reviewer checks for. One or two sentences.

**Steps:**
1. In `path/to/file.ts`, inside `handleAuth()` (just after `const session = ...`), add a `retries: number` param and pass it to `fetchWithRetry(...)`. Update both call sites: `path/to/caller.ts`, `path/to/other.ts`. _(see D003)_ (file: `path/to/file.ts`, `path/to/caller.ts`, `path/to/other.ts`, action: modify)
2. Create the `RetryConfig` type — `{ retries: number; backoffMs: number }` — mirroring `path/to/example.ts:40-60`. If field naming is ambiguous, default to `camelCase` to match that file. (file: `path/to/config.ts`, action: create)

**Avoid:** Anti-patterns and out-of-scope edits for this phase — what NOT to touch. e.g. "Do not refactor `legacyHandler`; do not add caching; do not reformat untouched lines."

**Verify:**
- Manual: Human verification steps
- Auto: `runnable-command`
```

Rules:
- `### Phase N:` headings, numbered
- **`**Intent:**` (required)** after the heading; **`**Avoid:**` (required)** after `**Steps:**`, before `**Verify:**`. Intent is the done-condition; Avoid is the rail against gold-plating and drive-by edits.
- Steps under `**Steps:**` as numbered list. **Anchor every step** to the exact file AND location (symbol / "just after X" / `file.ts:40-60`) and the exact change — never "update the handler."
- **Specify full signatures and every call site** for any new/changed function, type, or API. **Embed the reference** (`path:line` to mirror, or the exact snippet from `Implementation_Notes.md`) so the executor never re-researches. **Pre-authorize a default** for any residual ambiguity, written into the step.
- Every implementation step must include `file: ` with one or more separate backticked paths so `commit-phase.sh --paths-from-plan` can create a scoped phase commit
- `**Verify:**` block with `- Manual:` (required), `- Auto:` (strongly preferred — give every phase a runnable command wherever the tooling allows; a red `Auto:` verify is the one quality failure that halts the autonomous run)
- Reference decision IDs inline where a step embodies a decision: `_(see D003)_`
- NO checkboxes, NO speculative tests, NO rollback/back-compat unless asked, NO assumed fallbacks
- Keep the plan minimal: every step should trace to the user's request. No drive-by cleanup, no speculative abstractions. (Execution folds in a behavior-preserving `/simplify` pass per phase, so don't pre-bake cleanup into steps.)

**Detect the project's tooling before generating Auto verify commands.** Check lockfiles / manifests: `pnpm-lock.yaml` → `pnpm`, `yarn.lock` → `yarn`, `bun.lockb` → `bun`, `package-lock.json` → `npm run`, `Cargo.toml` → `cargo`, `go.mod` → `go`, `pyproject.toml` (poetry/uv) accordingly, `Gemfile` → `bundle exec`, etc. Read the manifest to find the actual script name; don't invent one. Omit the `- Auto:` line if no usable script exists.

After editing, run:

```
bash .orchestra/scripts/orchestra/parse-plan.sh
```

---

## PHASE 7: Final Decision Sweep

Re-read `decisions.json`. For any decision still missing an `answer`, run one more question round. No decision should be implicit at this point.

---

## PHASE 8: User Review

1. Present plan summary and resolved decisions
2. Ask: **Approve** / **Revise** / **More questions**
3. If Revise / More questions → loop back to PHASE 5 with the targeted area
4. **Wait for explicit approval before proceeding.**

---

## PHASE 9: Validation Pass

Re-dispatch the specialized agents from PHASE 3 to validate the plan:

```
VALIDATION REVIEW for: "$ARGUMENTS"

Plan: [relevant sections]
Decisions: [relevant D### references]

Return APPROVED or CONCERNS.
```

If concerns: edit Plan.md, re-run `parse-plan.sh`, present changes.

---

## PHASE 10: Finalize

**Readiness gate — do NOT set `planApproved: true` until all hold:**

1. Every decision in `decisions.json` has an `answer` (PHASE 7 should have closed these) — no implicit choices remain.
2. Every `[untested]` assumption is verified, or the user explicitly accepted its risk.
3. Every phase has `**Intent:**`, `**Avoid:**`, anchored steps with signatures/call-sites, and an `**Auto:**` verify wherever tooling supports one.

If any fail, fix the plan (re-run `parse-plan.sh`) or loop back to PHASE 5 before finalizing.

```
jq '.status = "READY" | .planApproved = true' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json
bash .orchestra/scripts/orchestra/log-event.sh planner-advanced "Plan approved via interview — ready for execution"
bash .orchestra/scripts/orchestra/unlock.sh planner-advanced
```

Tell the user: `/orchestra:execute` in Claude Code, `$orchestra execute` in Codex for one phase, `$orchestra execute all` in Codex for in-app autopilot, or `bash .orchestra/scripts/phase-runner.sh` for the terminal loop.
