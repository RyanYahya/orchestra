# thermonuclear-review

Read and follow the instructions in `.orchestra/prompts/thermonuclear-review.md`.

Cursor passes no structured arguments to commands, so treat anything typed after the command as the review scope — a phase id like `P3`, `working`, `branch`, an explicit git range, and/or `--fix`. If nothing was provided, use the default scope in that prompt (the cumulative workflow diff when a workflow is active, otherwise the working-tree diff).

That prompt asks you to fan out review lanes. In Cursor, do this with the **Task tool**: launch one subagent per lane **in parallel, in a single message** (multiple Task calls in one message run simultaneously), naming each lane explicitly rather than relying on automatic delegation. Pin a stronger model to the reasoning lanes (correctness, conformance, integration) and a cheaper one to the doc-checking lanes via each subagent's `model` field, and set `readonly: true`. The orchestra specialist agents live in `.orchestra/agents/` — Cursor does not auto-discover that directory, so read the relevant specialist file and pass its instructions inline to the subagent. If the Task/subagent mechanism is unavailable (Cursor < 2.4), run the lanes as sequential labeled passes instead of skipping any.
