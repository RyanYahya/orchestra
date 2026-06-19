
# Resolve Audit Issues

## Current Workflow (auto-loaded)

!`cat .orchestra/workflows/current/status.json 2>/dev/null | jq '{task, status, currentPhase, totalPhases}' || echo "NO_ACTIVE_WORKFLOW"`

## Audit Issues

!`cat .orchestra/workflows/current/Audit_Issues.md 2>/dev/null || echo "NO_AUDIT_ISSUES"`

## Available Specialized Agents

!`ls .orchestra/agents/`

---

## Your Instructions

### If NO_ACTIVE_WORKFLOW:

Tell user: "No active workflow. Nothing to resolve."

### If NO_AUDIT_ISSUES:

Check `status.json` status field:
- If `BLOCKED` without an Audit_Issues.md → use AskUserQuestion: "Workflow is BLOCKED but no Audit_Issues.md found. What needs to be resolved?"
- Otherwise → Tell user: "No audit issues to resolve. Workflow is not blocked."

### If workflow is BLOCKED with audit issues:

---

## STEP 1: Load Full Context

1. Read `.orchestra/workflows/current/status.json` — full state
2. Read `.orchestra/workflows/current/Audit_Issues.md` — the issues to fix
3. Read `.orchestra/workflows/current/Plan.md` — understand the phase that was being executed
4. Read `.orchestra/workflows/current/Implementation_Notes.md` — research context
5. Read `.orchestra/workflows/current/Decisions.md` — resolved decisions

Identify:
- Which phase was blocked
- Which agent(s) raised issues
- Exactly what files are affected
- What the specific problems are

---

## STEP 2: Present Issues

Show the user a clear summary:

```markdown
## Blocked at Phase [N]: [Phase Name]

### Issues Found

| # | Agent | Severity | Issue | File(s) |
|---|-------|----------|-------|---------|
| 1 | [agent] | [critical/warning] | [description] | `path/file.ts` |
| 2 | ... | ... | ... | ... |
```

Use AskUserQuestion: "How would you like to proceed?"
- **Fix all issues** — Address every finding
- **Fix critical only** — Skip warnings, fix only critical issues
- **Dismiss and continue** — Mark issues as acknowledged, unblock without fixing

---

## STEP 3: Walk Through Issues One by One

Process each issue individually. Do NOT batch-fix. The user must understand and approve each fix.

**For each issue:**

1. **Explain the issue** — What the agent found, why it matters, and what file(s) are affected. Keep it concise but make sure the user understands the problem before you propose anything.

2. **Propose a fix** — Describe what you would change and why. If there are multiple valid approaches, present them.

3. **Use AskUserQuestion** to let the user decide:
   - **Apply this fix** — Proceed with the proposed change
   - **Fix differently** — User provides an alternative approach
   - **Skip this issue** — Acknowledge but don't fix (will be logged as skipped)

4. **Implement** the chosen fix (if not skipped)

5. **Confirm** — Briefly show what changed, then move to the next issue

**Rules:**
- NEVER fix an issue without explaining it to the user first
- NEVER assume which approach the user wants — always ask when there's ambiguity
- Stay within scope — only fix what the audit flagged
- Do NOT refactor surrounding code
- Do NOT add things not related to the issue
- If you discover a NEW problem while fixing, flag it to the user via AskUserQuestion — do not silently fix it

---

## STEP 4: Re-Audit (MANDATORY)

After all fixes are applied, spawn the SAME agents that originally found issues **in parallel** to verify the fixes.

```
Task([agent-name]):
RE-AUDIT for Phase [N]: [Phase Name]

Original issues:
[List the issues this agent originally raised]

Files modified during fix:
[List files changed]

Verify:
1. Are the original issues resolved?
2. Did the fixes introduce any NEW issues?
3. Are implementations correct per latest docs?

Return: APPROVED or ISSUES with specifics.
```

---

## STEP 5: Handle Re-Audit Results

### If APPROVED by all agents:

1. Update `status.json` via Bash + jq:
   - Set the blocked phase's `status` to `"completed"`
   - Increment `currentPhase`
   - If this was the last phase → set top-level `status` to `"COMPLETED"`
   - Otherwise → set top-level `status` to `"PENDING"`
   - Append to `log`: `{ "time": "TIMESTAMP", "actor": "resolver", "action": "Phase N audit issues resolved — APPROVED" }`
   - Update `lastUpdated`

2. Remove or archive `Audit_Issues.md`:
   ```bash
   mv .orchestra/workflows/current/Audit_Issues.md .orchestra/workflows/current/Audit_Issues_Resolved.md
   ```

3. Tell user:
   ```
   Audit issues resolved. Workflow unblocked.

   To continue execution:
   - Auto:   npm run execute
   - Manual: npm run execute:manual
   - Interactive: `/orchestra:execute` in Claude Code or `$orchestra execute` in Codex
   ```

### If ISSUES persist:

1. Update `Audit_Issues.md` with the new findings
2. Present remaining issues to user
3. Use AskUserQuestion: "Some issues remain. How to proceed?"
   - **Fix remaining issues** — Loop back to STEP 3
   - **Dismiss and continue** — Unblock anyway (see dismiss flow below)

---

## Dismiss Flow

If user chose to dismiss issues:

1. Update `status.json` via Bash + jq:
   - Set top-level `status` to `"PENDING"`
   - Append to `log`: `{ "time": "TIMESTAMP", "actor": "resolver", "action": "Phase N audit issues DISMISSED by user" }`
   - Update `lastUpdated`
   - Do NOT mark the phase as completed — let the next execution cycle handle it

2. Rename `Audit_Issues.md`:
   ```bash
   mv .orchestra/workflows/current/Audit_Issues.md .orchestra/workflows/current/Audit_Issues_Dismissed.md
   ```

3. Tell user the workflow is unblocked and they can resume execution.
