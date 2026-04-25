# Execution Orchestrator

**Phase to execute (optional):** $ARGUMENTS

## Current Workflow (auto-loaded)

Run: `ls -la .orchestra/workflows/current/ 2>/dev/null || echo "NO_ACTIVE_WORKFLOW"`

## Available Specialized Agents

Run: `ls .claude/agents/ 2>/dev/null || ls .agents/ 2>/dev/null || echo "NO_AGENTS_DIR"`

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

If the plan itself looks wrong, **stop and run `/orchestra:revise`** (or describe the issue and ask the user) — don't silently improvise.

### If NO_ACTIVE_WORKFLOW:

Tell user: "No active workflow. Run `/orchestra:plan [task]` first." Release the lock and stop.

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
   jq --arg pid "P1" --arg sid "P1.S2" '
     .phases = (.phases | map(if .id == $pid then
       .steps = (.steps | map(if .id == $sid then .done = true else . end))
     else . end))
   ' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json
   ```
4. **Show your work** — do not rush

If a step is significantly larger or riskier than the plan suggested, pause and confirm before continuing.

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

Log the result:

```
bash .orchestra/scripts/orchestra/log-event.sh executor "Phase P1 verify: auto=PASS manual=PASS"
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

### 6b. External audit (specialized agents)

After your self-review and any auto-fixes, dispatch specialized agents in parallel for an independent check:

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

Log:

```
bash .orchestra/scripts/orchestra/log-event.sh executor "Phase P1 audit: APPROVED (auto-fixed: <count>, surfaced: <count>, learned: <count>)"
```

---

## STEP 7: Commit the Phase (if in a git repo)

```
bash .orchestra/scripts/orchestra/commit-phase.sh P1
```

This stages all changes and commits with `orchestra(P1): <Phase Name>`. The SHA is recorded in `status.json.git.phaseCommits.P1`.

If not in a git repo, the script no-ops.

---

## STEP 8: Mark Phase Complete

```
jq --arg pid "P1" --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" '
  .phases = (.phases | map(if .id == $pid then .status = "completed" else . end))
  | .currentPhase = (.currentPhase + 1)
  | .lastUpdated = $ts
' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json

bash .orchestra/scripts/orchestra/log-event.sh executor "Phase P1 completed"
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

Present final summary and ask: "Archive this workflow? (`/orchestra:archive`)"
