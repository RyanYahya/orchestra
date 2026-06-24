# Thermonuclear Code Quality Review

**Scope (optional):** $ARGUMENTS

A deep, on-demand, plan-aware review you summon when confidence in the implementation dips, or at the end of a plan. This is **Layer 2** — it runs *on top of* the mandatory per-phase audit in `execute`, never replaces it. Where the per-phase audit asks "is this one phase correct against the docs?", this asks "did the whole thing hold together, stay faithful to the plan, and honor every decision?"

Two rules govern every finding:

1. **Ground in objective knowledge, never memory.** Every claim must cite either fetched documentation (via Context7 / the project's doc specialists) or a specific line of code. "I think the API changed" is not a finding; "per `<doc>`, `foo()` now requires X — see `bar.ts:42`" is.
2. **Verify before you report.** Every candidate finding is adversarially checked (Step 4) before it reaches the report. High precision over high recall.

Report-only by default. Pass `--fix` to apply the safe, confirmed fixes after the report.

---

## STEP 0: Resolve the review scope

Determine what diff to review. `$ARGUMENTS` may contain a scope token and/or `--fix`:

- `P<id>` (e.g. `P3`) → the diff for that phase. Use `status.json.git.phaseCommits.P<id>` against its parent if present; otherwise the commit whose message matches `orchestra(P<id>)`.
- `working` → uncommitted changes: `git diff HEAD`.
- `branch` → the branch vs the default branch: `git diff $(git merge-base HEAD main)...HEAD` (substitute the repo's default branch).
- An explicit git range → use it verbatim.
- **No scope token** → the default below.

**Default scope (when a workflow is active):** the *cumulative* workflow diff — from the workflow's starting point to now, plus any uncommitted changes. Find the start from the earliest entry in `status.json.git.phaseCommits` (diff against its parent) or `git merge-base HEAD <default-branch>`; union with `git diff HEAD` to include working-tree changes.

**No active workflow + no scope token** → `git diff HEAD`; if empty, fall back to `git diff $(git merge-base HEAD main)...HEAD`.

Capture the changed-file list (`git diff --name-only <range>`) and the full diff. If the diff is empty, report "nothing in scope to review" and stop.

---

## STEP 1: Load intent (what *should* have happened)

This is what separates this review from a generic diff review. When a workflow is active, read:

1. `.orchestra/workflows/current/Plan.md` — the phases, steps, and the `## Assumptions` block
2. `.orchestra/workflows/current/Decisions.md` — every resolved decision (D001, …)
3. `.orchestra/workflows/current/Implementation_Notes.md` — research and technical context
4. `.orchestra/workflows/current/Advisory_Notes.md` — patterns prior phases were told to avoid
5. `.orchestra/workflows/current/status.json` — which steps are marked done

Hold these as the oracle for the **conformance lens** below. If no workflow is active, skip this step — the review is diff-only and the conformance lens is dropped.

---

## STEP 2: Assemble the panel

Pull in the project's doc-grounded specialists, then add the fixed lenses.

```bash
bash .orchestra/scripts/orchestra/select-audit-agents.sh review $(git diff --name-only <range>)
ls .orchestra/agents/ 2>/dev/null || ls .claude/agents/ 2>/dev/null || ls .agents/ 2>/dev/null || echo "NO_AGENTS_DIR"
```

Read each returned/listed agent's `description`. Dispatch any whose domain overlaps the changed files — these are the ones that fetch current docs (Context7) and check the implementation against ground truth. They carry the same authority as the per-phase audit specialists.

Then run these **fixed lenses** regardless of which specialists exist:

- **Correctness** — logic errors, unhandled edge cases, error handling, concurrency/ordering, off-by-one, null/undefined paths.
- **Conformance** (skip if no workflow) — does the diff implement what `Plan.md` specified? Does it honor *every* entry in `Decisions.md`? Any silent drift from the stated steps? Any step marked `done` in `status.json` that the code doesn't actually satisfy? Any `Advisory_Notes.md` pattern repeated?
- **Security & data safety** — injection, authz gaps, secret handling, unsafe deserialization, data loss.
- **Integration & blast radius** — callers, type contracts, public API consumers, migrations, anything *outside* the diff that this change breaks. Grep for usages; don't assume the diff is self-contained.
- **Simplicity & dead code** — over-engineering, abstractions that don't pay for themselves, code/flags/branches not required by the plan, leftover dead code. (The `/simplify` lens, reporting only.)
- **Test & verify adequacy** — is the change actually exercised? Are the `Verify` blocks sufficient? What's untested that matters?

---

## STEP 3: Fan out the reviewers (host-specific dispatch)

Launch the lenses **in parallel**, one agent per lens, plus the matched doc specialists. The user's request to run this review is explicit authorization to spawn subagents.

Host dispatch:

- **Claude Code:** use the Task/subagent mechanism. Prefer the strongest available model for the reasoning lenses (correctness, conformance, integration); the doc-grounded specialists may run on a smaller model since their job is objective doc-checking, not reasoning.
- **Codex:** use `multi_agent_v1.spawn_agent` per lane. If the spawn tool isn't visible, use tool discovery for "multi-agent spawn subagent", then spawn. Use read-only `explorer` agents for review lanes.
- **Cursor (2.4+):** use the **Task tool** to launch one subagent per lane **in parallel, in a single message** — multiple Task calls in one message run simultaneously. Name each lane explicitly. Pin a stronger model to the reasoning lanes and a cheaper one to the doc-checking specialists via each subagent's `model` field, and set `readonly: true`. The `.orchestra/agents/*` specialists become discoverable by name once symlinked into `.cursor/agents/` via `/orchestra:sync-agents`; if they aren't synced, read each matching specialist file and pass its instructions inline. Cursor has a real subagent mechanism — do not treat it as lacking one.
- **No subagent mechanism:** do each lens as a separate, clearly-headed local pass. Do not collapse them into one general review.

Pass each agent: the diff, the changed-file list, the relevant intent docs (for conformance), the doc-grounding rule, and this finding format:

```markdown
- file: path/to/file
  line: 123
  lens: correctness | conformance | security | integration | simplicity | tests
  severity: blocking | should-fix | advisory
  summary: one-line issue
  evidence: the doc citation or code reference that proves it
  fix: concrete, specific change
```

Wait for every agent to finish and collect all candidate findings.

---

## STEP 4: Adversarial verification (the precision gate)

Do **not** trust the panel's output directly. For each candidate finding (or each batch, grouped by file), dispatch a verifier whose job is to *refute* it:

```
Try to REFUTE this finding. It is only real if you can confirm it with a specific
doc citation or code reference. Default to REFUTED if the evidence is weak, the cited
line doesn't actually have the problem, the issue is already handled elsewhere, or the
claim rests on memory rather than a source.

Finding: [paste]
Return: CONFIRMED (with the confirming citation) or REFUTED (with why).
```

Drop every finding that isn't CONFIRMED. This is what makes the review thermonuclear rather than a noise cannon — the human should be able to trust that every surviving item is real.

---

## STEP 5: Synthesize

From the confirmed findings:

1. Deduplicate items pointing at the same line or mechanism.
2. Rank by severity:
   - **Blocking** — correctness, security, conformance violations, or breakage outside the diff. Ship-stoppers.
   - **Should-fix** — real problems that aren't ship-stoppers.
   - **Advisory** — simplicity / dead-code / test-gap observations.
3. For each: `file:line`, what's wrong, why it matters, the concrete fix, and the confirming citation.

---

## STEP 6: Output

Write the report to the workflow dir when one is active:

```bash
cat > .orchestra/workflows/current/Review_Report.md <<'EOF'
# Thermonuclear Review — <scope>

> Generated: <timestamp>

## Blocking
...

## Should-fix
...

## Advisory
...
EOF
```

Feed the loop: append any **recurring** pattern (something that shows up across multiple files/phases) to `Advisory_Notes.md` under `## Patterns to avoid`, so future phases steer clear.

```bash
bash .orchestra/scripts/orchestra/log-event.sh reviewer "Thermonuclear review (<scope>): <B> blocking, <S> should-fix, <A> advisory"
```

If no workflow is active, present the report inline instead of writing a file.

**If `--fix` was passed:** after presenting the report, apply the Blocking and Should-fix items whose fixes are safe and confined to the reviewed scope. Re-run any available auto-verify (typecheck/lint/build). Leave Advisory items for the human unless they're trivial. Never expand scope or rewrite unrelated code. Summarize what you applied and what you left.

**Otherwise:** present the report and stop. You are the senior reviewer surfacing findings — the human decides what to act on.
