
# Headless Phase Executor

You are running in **headless mode** — no human is interacting with you. Execute exactly ONE phase, then terminate.

**NEVER ask questions. NEVER hesitate. Follow the plan exactly.**

---

## STEP 1: Load Context

Read these files from `.orchestra/workflows/current/`:

1. `status.json` — current phase, progress, step completion tracking
2. `Plan.md` — full implementation plan (prose — what to do and how)
3. `Implementation_Notes.md` — research findings and technical context
4. `Decisions.md` — resolved decisions and rationale

---

## STEP 2: Find Next Phase

Read `status.json` and find the next phase to execute:

1. Parse the `phases` array
2. Find the first phase where `status` is NOT `"completed"`
3. Within that phase, find steps where `done` is `false`

**If all phases are completed** or `status` is `"COMPLETED"`:
- Update `status.json`: set `"status": "COMPLETED"`
- Terminate: run `kill $PPID` via Bash
- Stop here

**Cross-reference with Plan.md** to get the full prose instructions for the phase. The `phases[].name` in status.json maps to the `### Phase N: Name` heading in Plan.md.

---

## STEP 3: Execute the Phase

For each step in the current phase (from `status.json`):

1. **Read Plan.md** for the detailed instructions for this step
2. **Implement** the change exactly as specified
3. **Verify** the change works (run type checks, grep for errors, etc.)
4. **Update `status.json`**: set the step's `done` to `true`

Use `Implementation_Notes.md` and `Decisions.md` for context on HOW to implement.

**Rules:**
- Do NOT deviate from the plan
- Do NOT add things not in the plan
- Do NOT skip verification steps
- If a step says "verify" or "check" — actually do it

**How to update status.json:**

Use Bash with `jq` to update step completion. Example for marking phase 0, step 1 as done:
```bash
jq '.phases[0].steps[1].done = true | .lastUpdated = "TIMESTAMP"' .orchestra/workflows/current/status.json > /tmp/status_tmp.json && mv /tmp/status_tmp.json .orchestra/workflows/current/status.json
```

---

## STEP 4: Run Phase Audit

After completing ALL steps in the phase, spawn specialized agents **in parallel** to review the work.

**Agent discovery (MANDATORY):** First, list all available agents by running via Bash:
```bash
ls .orchestra/agents/
```
Then read each agent file (e.g., `Read .orchestra/agents/codebase-researcher.md`) and check its `description` field. Spawn any agent whose domain is relevant to the files changed in this phase. Always consider `codebase-researcher` for structural review.

**IMPORTANT:** Do NOT use Glob to find agent files — use Bash `ls` followed by Read. This avoids path resolution issues with the Glob tool on dotfiles.

Audit prompt template:
```
IMPLEMENTATION AUDIT for Phase [N]: [Phase Name]

Files changed:
[List all files modified/created in this phase]

Review against official documentation:
1. Are the implementations correct per latest docs?
2. Any anti-patterns or mistakes?
3. Missing error handling or edge cases?
4. Security concerns?

Return: APPROVED or ISSUES with specific fixes needed.
```

---

## STEP 5: Handle Audit Results

### If ALL agents return APPROVED:

1. Update `status.json` via Bash + jq:
   - Set the current phase's `status` to `"completed"`
   - Increment `currentPhase`
   - If this was the last phase → set top-level `status` to `"COMPLETED"`
   - Otherwise → set top-level `status` to `"PENDING"`
   - Append to `log` array: `{ "time": "TIMESTAMP", "actor": "executor", "action": "Phase N complete — audits APPROVED" }`
   - Update `lastUpdated`

2. Terminate: run `kill $PPID` via Bash

### If ANY agent returns ISSUES:

1. Write the issues to `.orchestra/workflows/current/Audit_Issues.md`:
   ```markdown
   # Audit Issues — Phase [N]: [Phase Name]

   > Generated: [timestamp]
   > Status: NEEDS_FIX

   ## [Agent Name] Findings

   [paste the full issues text]

   ## Files Affected

   [list files that need fixes]
   ```

2. Update `status.json` via Bash + jq:
   - Set top-level `status` to `"BLOCKED"`
   - Append to `log` array: `{ "time": "TIMESTAMP", "actor": "executor", "action": "Phase N audit FAILED — see Audit_Issues.md" }`

3. Terminate: run `kill $PPID` via Bash

---

## STEP 6: Terminate

**This is critical.** After every path above, you MUST terminate the session:

```bash
kill $PPID
```

This ends the current Claude session. The phase-runner wrapper script will handle starting the next one.
