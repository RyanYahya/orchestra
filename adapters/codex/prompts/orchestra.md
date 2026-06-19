---
description: Orchestra dispatcher - route plan, execute, resolve, revise, update, docs-sync, agent, or archive
argument-hint: [COMMAND] [ARGS]
---

Parse the first word of `$ARGUMENTS` as the Orchestra command. Route aliases exactly as follows:

- `plan` -> `.orchestra/prompts/plan.md`
- `plan-advanced` -> `.orchestra/prompts/plan-advanced.md`
- `execute` -> `.orchestra/prompts/execute.md`
- `execute-headless` -> `.orchestra/prompts/execute-headless.md`
- `revise` -> `.orchestra/prompts/revise.md`
- `resolve` -> `.orchestra/prompts/resolve.md`
- `docs-sync` -> `.orchestra/prompts/docs-sync.md`
- `agent` -> `.orchestra/prompts/agent.md`
- `archive` -> `.orchestra/prompts/archive.md`
- `update` -> `.orchestra/prompts/update.md`
- `phase-runner` or `bootstrap` -> `.orchestra/prompts/phase-runner.md`

Read the matching prompt completely and follow it exactly. Pass the remaining words after the command as that prompt's arguments.

Arguments: $ARGUMENTS
