# Planning Orchestrator

**Task:** $ARGUMENTS

## Current Workflow (auto-loaded)

Run: `ls -la .orchestra/workflows/current/ 2>/dev/null || echo "NO_ACTIVE_WORKFLOW"`

## Available Specialized Agents

Run: `ls .claude/agents/ 2>/dev/null || ls .agents/ 2>/dev/null || echo "NO_AGENTS_DIR"`

---

## Your Instructions

### Step 0: Acquire the lock

Run: `bash .orchestra/scripts/orchestra/lock.sh planner`

If the script exits non-zero, another actor is already driving the workflow. **Stop**, report which actor holds the lock, and ask the user how to proceed (wait, take over manually by removing `.orchestra/workflows/current/.lock`, or coordinate with the other session).

### If workflow exists:

1. Read `.orchestra/workflows/current/status.json` to get task name and current phase
2. Read `.orchestra/workflows/current/Plan.md` to summarize current plan
3. Ask the user (using whatever interactive question mechanism your host tool provides):
   - **Continue Planning** — extend or refine the plan
   - **Start Executing** — begin implementation

**If Continue Planning:**

- Ask: "What do you want to add or extend in the plan?"
- Run targeted research based on the user's response
- Update Plan.md with new findings using the strict format below
- Run `bash .orchestra/scripts/orchestra/parse-plan.sh` to refresh status.json
- Re-present updated plan for approval

**If Start Executing:**

- Tell the user: "Run `/orchestra:execute` (or the equivalent in your tool) to begin phase-by-phase implementation."

### If NO_ACTIVE_WORKFLOW:

---

## PHASE 1: Initialize

Run: `bash .orchestra/scripts/orchestra/init-workflow.sh "$ARGUMENTS"`

This records the current git branch into `status.json.git.branch` so phase commits can be tied back to the workflow.

---

## PHASE 2: Research (Parallel)

Analyze the task and dispatch parallel research using whatever sub-agent or task-spawning mechanism your host tool provides. Run them concurrently where supported.

**Always research:**

- Codebase: relevant files, implementations, integration points

**Research if relevant to task:**
Read each agent's `description` field. If the task overlaps with an agent's domain, dispatch it. Don't keyword-match — infer from descriptions.

**Dispatch prompt template:**

```
Research for task: "$ARGUMENTS"

Provide:
1. Relevant documentation/APIs
2. Best practices for this use case
3. Codebase patterns that apply
4. Recommendations with citations
```

> **Cost note:** parallel agents are roughly N× the cost of one. For small tasks, one or two agents is plenty.

---

## PHASE 3: Synthesize Research

1. Read `.orchestra/workflows/current/Implementation_Notes.md`
2. Append findings under `## Findings`, using free-form sub-sections per source/agent
3. Cite where each finding came from (codebase path, doc URL, agent name)

---

## PHASE 4: Create Plan

Edit `.orchestra/workflows/current/Plan.md` directly. **Plan.md is the source of truth** for phase/step structure — `parse-plan.sh` derives `status.json.phases[]` from it.

### Assumptions block (write before phases)

Surface every non-trivial premise the plan rests on. Think before coding: hidden assumptions are the most common cause of wasted phases. Format:

```markdown
## Assumptions

- [verified] User auth middleware lives at `src/middleware/auth.ts` (checked).
- [verified] We're targeting web only, not mobile (per D002).
- [untested] The existing `useUser` hook returns `null` when logged out — assumed but not confirmed.
- [untested] No other code consumes the response shape we're about to change.
```

Tag each item:
- `[verified]` — you actually checked the codebase, the docs, or the user
- `[untested]` — you're guessing; the executor will surface these at phase start so the user can correct them if wrong

Assumptions are advisory — they don't block execution, they just give the executor a chance to catch a wrong premise before acting on it.

### Phase format (parser will fail otherwise)

```markdown
### Phase 1: Phase Name

**Steps:**
1. First step description (file: `path/to/file.ts`, action: create|modify)
2. Second step description

**Verify:**
- Manual: Human verification steps — what to do, what to expect
- Auto: `optional-shell-command` (omit line if none)
```

**Plan structure rules:**

- Use `### Phase N:` headings, numbered sequentially
- Steps under `**Steps:**` as a numbered list
- Verify block under `**Verify:**` with `- Manual:` (required) and `- Auto:` (optional)
- NO checkboxes — `done` flags live in status.json
- NO new automated test scaffolding (the `Auto:` line is for an existing project script like `npm run typecheck`, not new test files, unless the user explicitly asks)
- NO rollback or backwards-compatibility code by default — confirm breaking changes with the user
- NO assumed fallbacks — if something might not exist, ask the user (MANDATORY)
- Keep the plan minimal: every step should trace to the user's request. No speculative abstractions, flexibility hooks, or "while we're at it" cleanup unless asked.

After editing Plan.md, run:

```
bash .orchestra/scripts/orchestra/parse-plan.sh
```

This rebuilds `status.json.phases[]` and `totalPhases`. Existing `done` flags are preserved by step ID; if steps are reordered, flags realign by new position.

---

## PHASE 5: Identify Decisions

For ambiguous choices, add them to `decisions.json` (canonical store). Never edit `Decisions.md` directly — it is generated.

```
bash .orchestra/scripts/orchestra/add-decision.sh add "Question text" "Recommended answer"
```

The script returns the new ID (D001, D002, …) and re-renders `Decisions.md`.

---

## PHASE 6: User Review

1. Present the plan summary and pending decisions
2. Ask the user for answers (one decision at a time if there are several)
3. For each answered decision:
   ```
   bash .orchestra/scripts/orchestra/add-decision.sh answer D001 "Chosen answer" user
   ```
4. **Wait for explicit approval before proceeding.**

---

## PHASE 7: Validation Pass

After approval, dispatch the same specialized agents from Phase 2 with a validation review:

```
VALIDATION REVIEW for: "$ARGUMENTS"

Plan: [paste the relevant phase sections]

Verify:
1. Does this follow official documentation best practices?
2. Anti-patterns or gotchas?
3. API usage correct per latest docs?
4. Recommendations to improve?

Return: APPROVED or CONCERNS with specific issues.
```

If concerns: edit Plan.md, re-run `parse-plan.sh`, present changes to the user.

---

## PHASE 8: Finalize

Update status.json and release the lock:

```
jq '.status = "READY" | .planApproved = true' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json
bash .orchestra/scripts/orchestra/log-event.sh planner "Plan approved — ready for execution"
bash .orchestra/scripts/orchestra/unlock.sh planner
```

Tell the user the next step: `/orchestra:execute` (interactive, phase-by-phase with audits) or `bash .orchestra/scripts/phase-runner.sh` (autonomous).
