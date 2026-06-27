# Plan Revision

**Issue / scope of revision:** $ARGUMENTS

Use when execution surfaces that the plan is wrong, incomplete, or based on a faulty assumption. Revising mid-execution is normal — silent improvisation is not.

---

## Step 0: Acquire the lock

Run: `bash .orchestra/scripts/orchestra/lock.sh reviser`

If non-zero, another actor holds it. Stop and report.

---

## Step 1: Capture what's changed

Read:
- `.orchestra/workflows/current/status.json` — see which phase you're on, what's already committed
- `.orchestra/workflows/current/Plan.md`
- `.orchestra/workflows/current/Decisions.md`

Summarize for the user:
- Which phase / step you're at
- What's been completed and committed (from `status.json.git.phaseCommits`)
- The specific issue with the current plan (in your own words)

---

## Step 2: Decide the revision shape

Ask the user (one question at a time):

1. **Scope** — does this affect just the current phase, downstream phases, or the whole approach?
2. **Preserve completed work?** — keep already-committed phases, or revert some of them?
3. **New decisions?** — what choices does this revision require? (Add to `decisions.json` via `add-decision.sh`.)

For each new decision:

```
bash .orchestra/scripts/orchestra/add-decision.sh add "Question" "Recommendation"
bash .orchestra/scripts/orchestra/add-decision.sh answer D### "User answer" user
```

---

## Step 3: Edit Plan.md

Make the surgical changes:

- Modify, add, or remove phases as needed
- Keep the strict format (`### Phase N:`, `**Steps:**`, `**Verify:**`)
- Reference new decision IDs inline where they shape steps
- Note in the phase body that it was revised: `_(revised: <reason>)_`

After editing, run:

```
bash .orchestra/scripts/orchestra/parse-plan.sh
```

This rebuilds `status.json.phases[]`. Existing `done` flags are preserved by step ID — if a step's text changed but its position didn't, its `done` flag carries over. **Verify by reading status.json that completed steps you intended to keep are still marked done.**

If you renumbered or removed phases that had been marked completed, the corresponding `phaseCommits` entries in `status.json.git` will refer to commits that no longer match the current plan. That's fine — they remain in git history; just note it for the user.

---

## Step 4: Re-validate (optional but recommended)

Dispatch specialized agents to validate the revised plan:

```
VALIDATION REVIEW (revision)

Original issue: $ARGUMENTS
Revised plan: [paste affected sections]

Return APPROVED or CONCERNS.
```

---

## Step 5: Log and release

```
bash .orchestra/scripts/orchestra/log-event.sh reviser "Plan revised: $ARGUMENTS"
bash .orchestra/scripts/orchestra/unlock.sh reviser
```

Tell the user the next step: resume `/orchestra:execute` in Claude Code or `$orchestra execute` in Codex from the affected phase. In Codex, `$orchestra execute all` resumes autopilot through every remaining phase.
