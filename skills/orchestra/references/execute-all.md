# Execute All (Codex Autopilot)

Use this only for Codex when the user asks for `$orchestra execute all`, `/orchestra execute all`, or natural language like "orchestra execute all". This is intentionally Codex-specific. Do not change the shared Claude Code, Cursor, Gemini, or terminal `phase-runner.sh` contract.

`execute all` means: keep executing the approved workflow until `.orchestra/workflows/current/status.json` is `COMPLETED` or a genuine hard stop makes further progress unsafe. In the Codex app, complete one phase per top-level task and hand the next phase to a fresh task. Do not ask for phase readiness, manual approval, or user confirmation between phases.

## Arguments

If the user passes a number after `execute all`, treat it as the maximum number of phases for the whole cross-task run. Otherwise use a safety cap of 50 phases. The durable autopilot state carries this budget across fresh tasks. Hitting the safety cap is a hard stop; record it in `Autopilot_Issues.md` and report progress.

## Source Of Truth

The workflow state on disk is authoritative:

- `.orchestra/workflows/current/status.json`
- `.orchestra/workflows/current/Plan.md`
- `.orchestra/workflows/current/Implementation_Notes.md`
- `.orchestra/workflows/current/Decisions.md`
- `.orchestra/workflows/current/Advisory_Notes.md`
- `status.json.autopilot` for the current cross-task run, owner, budget, and handoff history

Use Codex native surfaces when available, but only as mirrors:

- Use `update_plan` to show the current phase/loop progress when available.
- Use `multi_agent_v1.spawn_agent` for mandatory audits when available.
- In the Codex app, use the app's fresh-task creation capability for the next phase when it can target this exact saved local project and checkout.
- Do not use a Codex goal as workflow state. Goals are session-level; `.orchestra/` is workflow-level.
- Do not use `fork_thread` for phase handoff because it copies the completed conversation. Do not use a subagent as the next-phase owner.
- Do not rely on conversation history or manual compaction. After every phase, append a short durable recap to `.orchestra/workflows/current/Phase_Summaries.md`.

## Fresh-task policy

`$orchestra execute all` is explicit user authorization to create one fresh top-level Codex task after each completed phase. The new task is the sole owner of the next phase and may create the following phase task under the same authorization.

Use fresh tasks only when all of these are true:

- The Codex app exposes task creation plus project listing.
- The current working directory maps to a saved local project.
- The new task can use the same local project and checkout. Never create a new worktree merely to obtain fresh context.
- The current phase has been verified, audited, completed, summarized, and committed or has a recorded commit-skip reason.

If any condition is false, cancel the prepared handoff, append a one-line fallback note to `Phase_Summaries.md`, and continue in the current task. Fresh-task unavailability is not a hard stop.

## Run-to-completion policy

The whole point of `execute all` is to finish the entire plan in one unattended run. **Default to defer-and-continue, not to stopping.** When something is imperfect — an audit finding you can't fully resolve, a wrong-but-recoverable assumption, a manual check you can't confirm, a commit you can't scope cleanly — do your best within the phase's scope, append the residual to `.orchestra/workflows/current/Deferred_Issues.md`, and let the phase complete. The user resolves deferred items after the full run.

`Deferred_Issues.md` entry format: `## [Phase Pn] <title> — severity: low|med|high`, then `Category`, `What`, `Best-effort taken`, and `Suggested resolution` lines.

## Hard Stops

Stop without asking the user only when continuing would be unsafe or impossible:

- No active workflow exists.
- `status.json.planApproved` is false.
- The workflow lock is held by another actor.
- A required local command or file is missing and cannot be recreated from the installed Orchestra core.
- Applying a fix would require destructive git operations, or overwriting **uncommitted unrelated user changes**.
- Forward progress is mechanically impossible — the next phase's prerequisites genuinely do not exist and cannot be produced in scope.
- **A phase's auto-verify command stays red after the 3-try fix budget.** A confirmed-red build / typecheck / test run is the one quality failure that halts, because every later phase compounds on it.

Codex subagent spawning being unavailable is **not** a hard stop: run a thorough self-review against the audit checklist, note it in `Deferred_Issues.md`, and continue. Residual **audit** issues are **not** a hard stop either — they defer. Only the cases above halt the run.

If a hard stop happens, write a concise note to `.orchestra/workflows/current/Autopilot_Issues.md`, stop the durable autopilot with `autopilot-state.sh stop`, and report the issue. Do not prompt for a decision mid-run.

## Start or resume ownership

The first task starts the durable run and acquires a tokenized workflow lock:

```bash
AUTOPILOT=$(bash .orchestra/scripts/orchestra/autopilot-state.sh start <MAX_PHASES>)
OWNER_TOKEN=$(printf '%s' "$AUTOPILOT" | jq -r '.ownerToken')
OWNER_ACTOR=$(printf '%s' "$AUTOPILOT" | jq -r '.ownerActor')
```

A fresh task receives its owner token in its initial prompt. Before doing any work, it must claim the transferred ownership. Task creation and lock transfer can race briefly, so retry for at most 60 seconds:

```bash
for attempt in $(seq 1 30); do
  bash .orchestra/scripts/orchestra/autopilot-state.sh resume <OWNER_TOKEN> && break
  [[ "$attempt" == "30" ]] && exit 1
  sleep 2
done
```

If ownership cannot be claimed, stop and report the handoff failure. Do not remove or overwrite the lock. For every state-changing workflow helper, pass the durable `OWNER_ACTOR` as `--actor`; never fall back to the static `codex-execute-all` actor.

## Loop

Run this loop until the workflow completes or a successful fresh-task handoff ends the current task:

1. Read `status.json` and find the first phase whose `status` is not `completed`.
2. Read the matching phase section in `Plan.md`, the resolved decisions, implementation notes, and advisory notes.
3. Cheap-check `[untested]` assumptions that affect this phase. If one is false but recoverable, log it and proceed with the corrected local truth. If it makes the phase unworkable, hard stop.
4. Run `git status --short` before edits. Work with existing changes, but do not overwrite unrelated user changes.
5. Execute all unfinished steps for the phase. After each step, mark it done with:
   ```bash
   bash .orchestra/scripts/orchestra/mark-step-done.sh <PHASE_ID> <STEP_ID> --actor <OWNER_ACTOR>
   ```
6. Run the phase's auto verification command when present. If it fails, fix within the phase scope and retry up to three times. If it stays red after the third attempt, that is the red-build hard stop: log the failing command and output to `Deferred_Issues.md`, write `Autopilot_Issues.md`, and stop. If no auto verification exists, record `SKIP`.
7. For manual verification, perform the closest agent-driven equivalent you can: inspect the UI, run a smoke command, read generated output, or verify the changed behavior from code. If no meaningful substitute is possible, record manual verification as `SKIP`; do not stop for the user.
8. Record verification:
   ```bash
   bash .orchestra/scripts/orchestra/record-verify.sh <PHASE_ID> --auto PASS|SKIP --manual PASS|SKIP --actor <OWNER_ACTOR>
   ```
9. Run self-review against the phase diff. Immediately fix cheap scope/simplicity/trace issues. Append recurring lessons to `Advisory_Notes.md`. Then run the mandatory **Simplify pass** over this phase's diff only — apply behavior-preserving reuse / simplification / efficiency / altitude fixes within the phase's file scope (no behavior, API, or out-of-scope changes; defer anything that would cross that line to `Deferred_Issues.md`).
10. Run the mandatory spawned-agent audit. Use `.orchestra/audit-map.json` and `.orchestra/agents/` when present. In Codex, use `multi_agent_v1.spawn_agent`; if it is not visible, use tool discovery for "multi-agent spawn subagent".
11. If the audit returns blocking issues, fix them within the phase scope and re-audit. Retry up to three full fix/audit cycles. Do not ask the user. For any issue still unresolved after the budget, append a `Deferred_Issues.md` entry describing it and your best-effort attempt, then continue — residual audit issues do NOT hard stop (only a red build does).
12. Record the final approved audit:
    ```bash
    bash .orchestra/scripts/orchestra/record-audit.sh <PHASE_ID> --approved --auto-fixed <N> --learned <N> --actor <OWNER_ACTOR>
    ```
13. Commit scoped phase changes when it can be done safely:
    ```bash
    bash .orchestra/scripts/orchestra/commit-phase.sh <PHASE_ID> --paths-from-plan
    ```
    If commit fails because plan file paths are missing but the changed files are clearly phase-scoped, write a temp paths file and retry with `--paths-file`. If commit still cannot be made safely, log the commit skip in `Phase_Summaries.md` and continue. Do not use `--all` unless the user explicitly asked for blanket staging.
14. Complete the phase:
    ```bash
    bash .orchestra/scripts/orchestra/complete-phase.sh <PHASE_ID> --actor <OWNER_ACTOR>
    ```
15. Append a durable recap to `Phase_Summaries.md` with the phase id, files changed, verification result, audit result, commit SHA or commit-skip reason, and any advisory lesson.
16. Record the completed phase in the durable autopilot budget:
    ```bash
    bash .orchestra/scripts/orchestra/autopilot-state.sh phase-complete <OWNER_TOKEN> <PHASE_ID>
    ```
17. If the workflow is now `COMPLETED`, skip to **Finish**. If the durable phase count reached `maxPhases`, record the safety-cap hard stop and run `autopilot-state.sh stop`.
18. Otherwise identify the next pending phase and prepare a unique handoff:
    ```bash
    HANDOFF=$(bash .orchestra/scripts/orchestra/autopilot-state.sh prepare <OWNER_TOKEN> <NEXT_PHASE_ID>)
    NEXT_OWNER_TOKEN=$(printf '%s' "$HANDOFF" | jq -r '.token')
    ```
19. Discover the Codex app project/task tools. List projects first and match the project whose local root is the current working directory. If there is no exact saved-local-project match, the current task is in a Codex worktree, or fresh task creation is unavailable, cancel the handoff and continue the loop in this task:
    ```bash
    bash .orchestra/scripts/orchestra/autopilot-state.sh cancel <OWNER_TOKEN> <NEXT_OWNER_TOKEN> "<reason>"
    ```
20. Create exactly one fresh top-level task in that same local project. Omit model and reasoning overrides so the user's configured defaults are inherited. Its initial prompt must be:

    ```text
    Continue the approved Orchestra execute-all run <RUN_ID> in a fresh Codex app task.

    The user's original `$orchestra execute all` command explicitly authorizes this continuation and one fresh top-level task per remaining phase. Work only in the same local project and checkout. Do not fork the previous task and do not use a subagent as the phase owner.

    Before any work, retry this ownership claim for at most 60 seconds:
    for attempt in $(seq 1 30); do
      bash .orchestra/scripts/orchestra/autopilot-state.sh resume <NEXT_OWNER_TOKEN> && break
      [[ "$attempt" == "30" ]] && exit 1
      sleep 2
    done

    Then read `.agents/skills/orchestra/SKILL.md` and its `references/execute-all.md`, read the on-disk workflow state, and execute exactly the next pending phase. Do not redo completed phases. After that phase, continue the documented fresh-task handoff chain.
    ```

    When task renaming is available, name it `<workflow task> · <phase id>/<total> · <phase name>`.
21. Only after task creation returns a thread ID, atomically transfer durable ownership:
    ```bash
    bash .orchestra/scripts/orchestra/autopilot-state.sh activate <OWNER_TOKEN> <NEXT_OWNER_TOKEN> <THREAD_ID>
    ```
    If creation fails before returning a thread ID, cancel the handoff and continue in this task. If activation fails, hard stop and report both task IDs; do not continue execution in either task automatically.
22. After successful activation, do no more filesystem or Git work. End this task with a concise handoff message and include the host's created-task UI directive when required. The newly created task now owns the workflow.

## Finish

After the last phase, ensure `status.json.status` is `COMPLETED`, then finish the durable run and release its tokenized lock:

```bash
bash .orchestra/scripts/orchestra/autopilot-state.sh finish <OWNER_TOKEN>
```

Give the user a concise final summary, including how many phases and fresh tasks ran, the number of `Deferred_Issues.md` entries, and the suggestion to resolve them with `$orchestra resolve` or `$orchestra thermonuclear-review`.

## Audit Prompt

Use this for spawned audit agents:

```markdown
IMPLEMENTATION AUDIT for Phase <PHASE_ID>: <PHASE_NAME>

Review only this phase's diff and the relevant Plan.md section.

Files changed:
<list>

Plan steps:
<paste phase steps>

Verification:
<commands/results>

Return:
- APPROVED if there are no blocking correctness, integration, security, or plan-conformance issues.
- ISSUES with file/line-specific findings if anything must be fixed before this phase can complete.

Also include an ADVISORY section for non-blocking simplicity, trace, scope, or maintainability notes.
```

Advisory notes never block `execute all`; cheap fixes are applied immediately and larger lessons are recorded for later phases.
