# Execution Orchestrator

**Phase to execute (optional):** $ARGUMENTS

## Current Workflow (auto-loaded)

Run: `ls -la .orchestra/workflows/current/ 2>/dev/null || echo "NO_ACTIVE_WORKFLOW"`

## Available Specialized Agents

Run: `ls .orchestra/agents/ 2>/dev/null || ls .claude/agents/ 2>/dev/null || ls .agents/ 2>/dev/null || echo "NO_AGENTS_DIR"`

---

## Your Instructions

### Step 0: Acquire the lock

Run: `bash .orchestra/scripts/orchestra/lock.sh executor`

If non-zero, another actor is driving the workflow. Stop and report.

### CRITICAL: No Autonomous Decisions

**Never make decisions mid-execution.** If you hit any of the following, STOP and ask the user:

- Ambiguity in requirements or implementation approach
- Multiple valid ways to implement something
- Unexpected errors or edge cases not in the plan
- Deviations from the original plan
- Unclear file locations or naming conventions
- Trade-offs between solutions

**Your role is to EXECUTE the plan, not to interpret it.** When in doubt, ask.

If the plan itself looks wrong, **stop and run `/orchestra:revise` in Claude Code or `$orchestra revise` in Codex** (or describe the issue and ask the user) — don't silently improvise.

### If NO_ACTIVE_WORKFLOW:

Tell user: "No active workflow. Run `/orchestra:plan [task]` in Claude Code or `$orchestra plan [task]` in Codex first." Release the lock and stop.

### If workflow exists:

---

## STEP 1: Load Context

1. Read `.orchestra/workflows/current/status.json` — current phase, progress, step tracking, git data
2. Read `.orchestra/workflows/current/Plan.md` — full implementation plan (source of truth for steps)
3. Read `.orchestra/workflows/current/Implementation_Notes.md` — research findings
4. Read `.orchestra/workflows/current/Decisions.md` — resolved decisions

If `status.json` shows `planApproved: false`, stop and tell the user to finish planning first.

---

## STEP 2: Identify Current Phase

- If `$ARGUMENTS` provided (e.g. `P3`) → execute that phase
- Otherwise → first phase in `status.json.phases[]` whose `status` is not `"completed"`

Present to user:

- Phase ID + name + objective (from Plan.md)
- Steps (from `status.json.phases[N].steps[]` — text + done flag)
- Files to modify/create (from Plan.md)
- Verify block (`status.json.phases[N].verify`)

Ask: "Ready to execute Phase [ID]?"

---

## STEP 3: Pre-flight — Internalize Context

Before writing any code, do a quick context pass. The goal is to start the phase with a sharper mental model than you'd have from the plan alone — so the implementation comes out cleaner the first time and doesn't need rework.

Read in order:

1. **`Plan.md` — `## Assumptions` section.** Verified items are background; untested items need attention.
   - For each `[untested]` assumption, do a cheap check now (read a file, grep a symbol, run a quick command). Upgrade to `[verified]` if it holds; if it doesn't, stop and ask before proceeding (the phase plan is built on a false premise).
   - If a check is genuinely expensive without the user, note it and proceed.

2. **`Decisions.md` — resolved decisions.** Internalize the answers; do not re-litigate them mid-phase.

3. **`Advisory_Notes.md` — patterns to avoid.** Treat every entry as a "do not repeat" rule for this phase. If the rules conflict with what the plan asks for, follow the plan and surface the conflict to the user.

State briefly to the user: which assumptions you cheap-checked and the result, and which advisory patterns you'll be watching for. Keep it short — this is orientation, not interrogation.

Dirty-worktree policy:

- Before editing, run `git status --short` and note any dirty files.
- Do not stash, reset, overwrite, or reformat unrelated user/agent changes.
- If a file you must edit already has unrelated user changes, pause and ask before touching it.
- Treat the phase's listed `file: ` paths as the commit scope. If the plan omitted a changed file, write the actual phase file list to a temp file and use `commit-phase.sh P1 --paths-file <file>`.
- Never use `commit-phase.sh --all` unless the user explicitly authorizes a blanket commit.

Log:

```
bash .orchestra/scripts/orchestra/log-event.sh executor "Phase P1 pre-flight: <N verified, M untested resolved, K patterns loaded>"
```

---

## STEP 4: Execute Phase (One Step at a Time)

For each pending step:

1. **Announce** what you're about to do
2. **Implement** the change
3. **Mark done** in status.json:
   ```
   bash .orchestra/scripts/orchestra/mark-step-done.sh P1 P1.S2
   ```
4. **Show your work** — do not rush

If a step is significantly larger or riskier than the plan suggested, pause and confirm before continuing.

If a step says to run `/simplify`, run the bundled cleanup-only Simplify pass over this phase diff. In Claude Code, use `/simplify` or `/orchestra:simplify`; in Codex, use `$simplify` or the installed `/simplify` prompt adapter. This pass is for behavior-preserving reuse/simplification/efficiency/altitude cleanups only, and does not replace the mandatory external audit.

---

## STEP 5: Verify the Phase

Two-part verification — do both:

### 5a. Auto verify (if `verify.auto` is set)

```
jq -r --arg pid "P1" '.phases[] | select(.id == $pid) | .verify.auto' .orchestra/workflows/current/status.json
```

If non-empty, run that command. Capture exit code and last 50 lines of output. If it fails, stop and ask the user how to proceed.

### 5b. Manual verify

Read `verify.manual` from status.json and present it to the user. Wait for their report ("looks good", "X is broken", etc.).

Record the result:

```
bash .orchestra/scripts/orchestra/record-verify.sh P1 --auto PASS --manual PASS
```

---

## STEP 6: Self-Review + Audit

This is a two-pass review — first you critique your own diff, then external agents do an independent check. The goal is the AI, not the human, doing most of the cleanup work.

### 6a. Self-review (you, against your own diff)

Get the diff for this phase: `git diff HEAD` (or against the prior phase commit if available in `status.json.git.phaseCommits`).

Review your own changes against three criteria:

- **Simplicity:** any code, abstraction, flag, parameter, error-handling branch, or comment NOT required by this phase's steps?
- **Trace:** does every changed line map to a step in this phase? Any files modified that aren't in the phase's listed files?
- **Surgical:** any drive-by improvements to adjacent code, formatting, or comments that the plan didn't ask for?
- **Patterns:** any pattern from `Advisory_Notes.md` that you just repeated?

For each finding, classify:

- **Cheap to fix now** → fix it silently in this phase. "Cheap" = single-line removals, deleting a comment you added, reverting a formatting change, removing an unused import/parameter you introduced, deleting an abstraction you added that isn't used yet. Do not surface these to the user — just clean up.
- **Material** → changes scope or behavior, or affects an API. Surface to the user with a one-line summary and proceed only after they confirm.
- **Pattern (recurring)** → append to `Advisory_Notes.md` under `## Patterns to avoid` so future phases learn from it.

Updating `Advisory_Notes.md`:

```
cat >> .orchestra/workflows/current/Advisory_Notes.md <<'EOF'
- (Phase P1) <one-line description of the pattern, e.g. "Avoid adding error handling for impossible states; trust upstream guarantees.">
EOF
```

### 6b. External audit (specialized agents) — MANDATORY

After your self-review and any auto-fixes, you MUST dispatch specialized agents in parallel for an independent check. This is not optional. The user's request to run Orchestra execution is explicit authorization to use subagents for the phase audit.

Use `.orchestra/agents/` as the specialist list when present. If `.orchestra/audit-map.json` exists, use it first:

```
bash .orchestra/scripts/orchestra/select-audit-agents.sh P1 $(git diff --name-only HEAD)
```

Treat returned agent names as the mandatory first-choice audit lanes, read those agent files, and include their role/instructions in each spawned agent's task. If the map is missing, empty, or returns no available agents, infer relevant specialists from `.orchestra/agents/` as before. If there are no matching specialist agents, spawn at least one general implementation-audit agent.

Host-specific dispatch:

- **Claude Code:** use the Task/subagent mechanism with the relevant `.orchestra/agents/*` specialists.
- **Codex:** use `multi_agent_v1.spawn_agent` for each audit lane. If the spawn tool is not currently visible, use tool discovery for "multi-agent spawn subagent", then spawn the agents. Prefer `explorer` agents for read-only audit lanes and `worker` only when the audit agent is explicitly asked to patch a bounded write set.
- **Cursor (2.4+):** the `.orchestra/agents/*` specialists must be symlinked into `.cursor/agents/` first (run `/orchestra:sync-agents` once — Cursor auto-discovers `.cursor/agents/` but not `.orchestra/agents/`). Then use the **Task tool** to launch the matching specialists as named subagents **in parallel, in a single message**, set `readonly: true`, and pin a cheaper model to doc-checking lanes via the `model` field. If they aren't synced yet, read each `.orchestra/agents/*` file and pass its instructions inline as a fallback. Cursor has a real subagent mechanism — do not treat it as a host lacking one.

After spawning, wait for every audit agent to finish and collect their verdicts before continuing to Step 6c.

Do NOT substitute self-review or a local audit for this step when a subagent mechanism exists. If no subagent mechanism is available in the host, stop before Step 7, set top-level `status` to `"BLOCKED"`, log `"Phase P1 audit BLOCKED — subagent mechanism unavailable"`, and ask the user to run the phase in a host with subagent support.

```
IMPLEMENTATION AUDIT for Phase [ID]: [Phase Name]

Files changed: [list]
Self-review summary: [paste your self-review output, including what you auto-fixed]

== BLOCKING checks — return APPROVED or ISSUES ==
1. Implementations correct per latest docs?
2. Anti-patterns or mistakes?
3. Missing error handling for cases that could break the system?
4. Security concerns?

== ADVISORY checks — return under a separate ADVISORY section ==
5. Simplicity: code beyond what the steps required?
6. Trace: changes outside the phase's listed files?
7. Surgical: drive-by edits the executor missed in self-review?

Format:
  ISSUES: [...]    ← blocking; empty if none
  ADVISORY: [...]  ← informational; do not change the verdict

Return APPROVED if ISSUES is empty, ISSUES otherwise.
```

### 6c. Apply audit results

**If ISSUES:** present to user, fix per their direction, re-audit until APPROVED.

**If APPROVED:**
- For each ADVISORY item the external agents raised that the self-review missed:
  - Cheap to fix → fix silently
  - Material → surface to user
  - Recurring pattern → append to `Advisory_Notes.md`
- Continue to STEP 7.

Record the audit result:

```
bash .orchestra/scripts/orchestra/record-audit.sh P1 --approved --auto-fixed 0 --surfaced 0 --learned 0
```

---

## STEP 7: Commit the Phase (if in a git repo)

```
bash .orchestra/scripts/orchestra/commit-phase.sh P1 --paths-from-plan
```

This stages only files listed in the phase steps and commits with `orchestra(P1): <Phase Name>`. Unrelated unstaged user changes are left alone. If unrelated changes are already staged, the script refuses to commit; stop and ask the user to unstage them or provide an explicit `--paths-file` for this phase. The SHA is recorded in `status.json.git.phaseCommits.P1`.

If not in a git repo, the script no-ops.

---

## STEP 8: Mark Phase Complete

```
bash .orchestra/scripts/orchestra/complete-phase.sh P1
```

---

## STEP 9: Next Phase or Complete

**If more phases remain:**

- Ask: "Ready for Phase [next ID]?"
- If yes → return to STEP 2
- If no → release the lock and pause:
  ```
  bash .orchestra/scripts/orchestra/unlock.sh executor
  ```

**If all phases complete:**

```
jq '.status = "COMPLETED"' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json
bash .orchestra/scripts/orchestra/log-event.sh executor "All phases completed"
bash .orchestra/scripts/orchestra/unlock.sh executor
```

Present final summary and ask: "Archive this workflow? (`/orchestra:archive` in Claude Code, `$orchestra archive` in Codex)"
