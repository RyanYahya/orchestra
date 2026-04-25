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

## STEP 3: Execute Phase (One Step at a Time)

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

## STEP 4: Verify the Phase

Two-part verification — do both:

### 4a. Auto verify (if `verify.auto` is set)

```
jq -r --arg pid "P1" '.phases[] | select(.id == $pid) | .verify.auto' .orchestra/workflows/current/status.json
```

If non-empty, run that command. Capture exit code and last 50 lines of output. If it fails, stop and ask the user how to proceed.

### 4b. Manual verify

Read `verify.manual` from status.json and present it to the user. Wait for their report ("looks good", "X is broken", etc.).

Log the result:

```
bash .orchestra/scripts/orchestra/log-event.sh executor "Phase P1 verify: auto=PASS manual=PASS"
```

---

## STEP 5: Phase Audit (specialized agents)

Dispatch specialized agents in parallel (using your host tool's sub-agent mechanism) to audit the changes:

```
IMPLEMENTATION AUDIT for Phase [ID]: [Phase Name]

Files changed:
[list of files]

Review against official documentation:
1. Implementations correct per latest docs?
2. Anti-patterns or mistakes?
3. Missing error handling or edge cases?
4. Security concerns?

Return: APPROVED or ISSUES with specific fixes.
```

**If APPROVED:** continue to STEP 6.
**If ISSUES:** present to user, fix per their direction, re-audit until APPROVED.

---

## STEP 6: Commit the Phase (if in a git repo)

```
bash .orchestra/scripts/orchestra/commit-phase.sh P1
```

This stages all changes and commits with `orchestra(P1): <Phase Name>`. The SHA is recorded in `status.json.git.phaseCommits.P1`.

If not in a git repo, the script no-ops.

---

## STEP 7: Mark Phase Complete

```
jq --arg pid "P1" --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" '
  .phases = (.phases | map(if .id == $pid then .status = "completed" else . end))
  | .currentPhase = (.currentPhase + 1)
  | .lastUpdated = $ts
' .orchestra/workflows/current/status.json > /tmp/orch.status && mv /tmp/orch.status .orchestra/workflows/current/status.json

bash .orchestra/scripts/orchestra/log-event.sh executor "Phase P1 completed"
```

---

## STEP 8: Next Phase or Complete

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
