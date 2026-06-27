# Planning Orchestrator

**Task:** $ARGUMENTS

## Current Workflow (auto-loaded)

Run: `ls -la .orchestra/workflows/current/ 2>/dev/null || echo "NO_ACTIVE_WORKFLOW"`

## Available Specialized Agents

Run: `ls .orchestra/agents/ 2>/dev/null || ls .claude/agents/ 2>/dev/null || ls .agents/ 2>/dev/null || echo "NO_AGENTS_DIR"`

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

- Tell the user: "Run `/orchestra:execute` in Claude Code or `$orchestra execute` in Codex to execute one phase at a time. In Codex, use `$orchestra execute all` for autonomous execution through every remaining phase."

### If NO_ACTIVE_WORKFLOW:

---

## PHASE 1: Initialize

Run: `bash .orchestra/scripts/orchestra/init-workflow.sh "$ARGUMENTS"`

This records the current git branch into `status.json.git.branch` so phase commits can be tied back to the workflow.

---

## PHASE 2: Research (Parallel)

Analyze the task and dispatch parallel research using whatever sub-agent or task-spawning mechanism your host tool provides. Run them concurrently where supported. If the host cannot spawn subagents, do the research locally and cite the files/docs read.

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

**Write for an autonomous, possibly-weaker executor.** This plan may be run end-to-end by `phase-runner.sh` (or `$orchestra execute all`) with no human in the loop and no pause for questions — and possibly by a cheaper model. The executor will NOT stop to interpret, choose, or research; it applies what's written and defers anything it can't resolve. So the rigor lives here: every step must be specific enough that a faithful, literal execution can't make the code worse. Where you'd otherwise expect the executor to decide, **bake the decision into the step** as a pre-authorized default ("if X, do Y").

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
- `[untested]` — you're guessing

**Verify assumptions now, at plan time.** Because the autonomous executor won't pause to confirm a wrong premise, `[untested]` items should be near-zero by approval — do the cheap check (read the file, grep the symbol, run the command) while planning and upgrade to `[verified]`. If a premise genuinely can't be checked without the user, ask them during PHASE 6 rather than leaving it for the executor. Any `[untested]` item that survives to approval is one the user has explicitly accepted the risk on.

### Phase format (parser will fail otherwise)

```markdown
### Phase 1: Phase Name

**Intent:** Why this phase exists and what "done well" looks like — the outcome a reviewer would check for. One or two sentences.

**Steps:**
1. In `path/to/file.ts`, inside `handleAuth()` (just after the `const session = ...` line), add a `retries: number` parameter and pass it to `fetchWithRetry(...)`. Update both call sites: `path/to/caller.ts` and `path/to/other.ts`. (file: `path/to/file.ts`, `path/to/caller.ts`, `path/to/other.ts`, action: modify)
2. Create the `RetryConfig` type — `{ retries: number; backoffMs: number }` — mirroring the existing pattern at `path/to/example.ts:40-60`. If the field naming is ambiguous, default to `camelCase` to match that file. (file: `path/to/config.ts`, action: create)

**Avoid:** Anti-patterns and out-of-scope edits for this phase — what NOT to touch. e.g. "Do not refactor `legacyHandler`; do not add caching; do not reformat untouched lines."

**Verify:**
- Manual: Human verification steps — what to do, what to expect
- Auto: `runnable-command` (strongly preferred — see rules)
```

**Plan structure rules:**

- Use `### Phase N:` headings, numbered sequentially
- **`**Intent:**` (required)** — one or two sentences on the why and the done-condition. Put it right after the heading, before `**Steps:**`.
- **`**Avoid:**` (required)** — explicit anti-patterns, out-of-scope edits, and do-not-touch areas for this phase. Put it after `**Steps:**`, before `**Verify:**`. This is the rail that stops a literal executor from gold-plating or drive-by refactoring.
- Steps under `**Steps:**` as a numbered list. **Anchor every step:** name the exact file AND location (a symbol, "just after X", or a `file.ts:40-60` line range) and the exact change — never "update the handler."
- **Specify signatures and call sites.** Any new or changed function / type / API states its full signature (names + types), and the step lists *every* call site to update. The executor applies; it does not design.
- **Embed the reference, don't defer research.** Point to an in-repo example as `path:line` to mirror, or inline the exact API/doc snippet from `Implementation_Notes.md`. The autonomous executor won't re-research, so don't make it.
- **Pre-authorize defaults.** For any residual ambiguity, write the default into the step ("if X is missing, do Y"). A pre-decided default keeps the run going instead of forcing a guess.
- Every implementation step must include `file: ` with one or more separate backticked paths so `commit-phase.sh --paths-from-plan` can create a scoped phase commit
- Verify block under `**Verify:**` with `- Manual:` (required) and `- Auto:` (strongly preferred). **Give every phase a runnable `Auto:` command wherever the project tooling allows** (typecheck, build, lint, or an existing test script). A weaker executor can't reliably self-assess, but a command can — and a red `Auto:` verify is the *one* quality failure that halts the autonomous run, so it's your hardest safety net. Omit only when the project has no usable script.
- NO checkboxes — `done` flags live in status.json
- NO new automated test scaffolding (the `Auto:` line is for an existing project script, not new test files, unless the user explicitly asks)
- NO rollback or backwards-compatibility code by default — confirm breaking changes with the user
- NO assumed fallbacks — if something might not exist, ask the user (MANDATORY)
- Keep the plan minimal: every step should trace to the user's request. No speculative abstractions, flexibility hooks, or "while we're at it" cleanup unless asked. (Execution folds in a behavior-preserving `/simplify` pass per phase, so don't pre-bake cleanup into steps.)

**Detect the project's tooling before generating Auto verify commands.** Don't hardcode `npm run X` or any other runner. Check the repo for:

- `pnpm-lock.yaml` → use `pnpm <script>`
- `yarn.lock` → use `yarn <script>`
- `bun.lockb` → use `bun <script>`
- `package-lock.json` → use `npm run <script>`
- `pyproject.toml` with `[tool.poetry]` → use `poetry run <cmd>` ; with `[tool.uv]` → use `uv run`
- `requirements.txt` only → plain `python` / `pytest`
- `Cargo.toml` → use `cargo <cmd>`
- `go.mod` → use `go <cmd>`
- `Gemfile` → use `bundle exec <cmd>`

Read `package.json` `scripts` (or equivalent config) to find the right command name (e.g. `typecheck`, `check`, `lint`) — don't invent one. If the project has no usable verify script, omit the `- Auto:` line; manual verification is always sufficient on its own.

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

**Readiness gate — do NOT set `planApproved: true` until all hold** (the plan is about to be run autonomously, so a gap here becomes a deferred issue later):

1. Every decision in `decisions.json` has an `answer` — no implicit choices remain.
2. Every `[untested]` assumption has been verified, or the user explicitly accepted its risk in PHASE 6.
3. Every phase has an `**Intent:**`, an `**Avoid:**`, anchored steps with signatures/call-sites, and an `**Auto:**` verify command wherever the project tooling supports one.

If any fail, fix the plan (re-run `parse-plan.sh`) or loop back to PHASE 6 before finalizing.

Update status.json and release the lock:

```
jq '.status = "READY" | .planApproved = true' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json
bash .orchestra/scripts/orchestra/log-event.sh planner "Plan approved — ready for execution"
bash .orchestra/scripts/orchestra/unlock.sh planner
```

Tell the user the next step: `/orchestra:execute` in Claude Code or `$orchestra execute` in Codex for single-phase execution. In Codex, `$orchestra execute all` runs every remaining phase in-app; `bash .orchestra/scripts/phase-runner.sh` remains the terminal headless loop.
