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
4. If executing → tell user to run `/orchestra:execute` in Claude Code or `$orchestra execute` in Codex

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

### Assumptions block (write before phases)

Surface every non-trivial premise the plan rests on. Tag each as `[verified]` (you actually checked) or `[untested]` (you're guessing — the executor will surface these at phase start). Example:

```markdown
## Assumptions

- [verified] Auth middleware lives at `src/middleware/auth.ts` (checked).
- [untested] The `useUser` hook returns `null` when logged out — assumed but not confirmed.
```

Assumptions are advisory; they don't block execution. They prevent the most common failure mode: plan looked right but rested on a wrong premise.

### Phase format (strict)

```markdown
### Phase 1: Phase Name

**Steps:**
1. First step (file: `path/to/file.ts`, action: create|modify)
2. Second step (file: `path/to/other.ts`, action: modify)

**Verify:**
- Manual: Human verification steps
- Auto: `optional-shell-command`
```

Rules:
- `### Phase N:` headings, numbered
- Steps under `**Steps:**` as numbered list
- Every implementation step must include `file: ` with one or more separate backticked paths so `commit-phase.sh --paths-from-plan` can create a scoped phase commit
- `**Verify:**` block with `- Manual:` (required), `- Auto:` (optional)
- Reference decision IDs inline where a step embodies a decision: `_(see D003)_`
- NO checkboxes, NO speculative tests, NO rollback/back-compat unless asked, NO assumed fallbacks
- Keep the plan minimal: every step should trace to the user's request. No drive-by cleanup, no speculative abstractions.

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

```
jq '.status = "READY" | .planApproved = true' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json
bash .orchestra/scripts/orchestra/log-event.sh planner-advanced "Plan approved via interview — ready for execution"
bash .orchestra/scripts/orchestra/unlock.sh planner-advanced
```

Tell the user: `/orchestra:execute` in Claude Code, `$orchestra execute` in Codex, or `bash .orchestra/scripts/phase-runner.sh`.
