# sync-agents

Read and follow the instructions in `.orchestra/prompts/sync-agents.md`.

Cursor passes no structured arguments to commands, so treat anything typed after the command as arguments to the script — tool names (`claude`, `codex`, `cursor`), `--copy`, or `--prune`. With nothing provided, sync to all three:

```
bash .orchestra/scripts/orchestra/sync-agents.sh
```

This symlinks the `.orchestra/agents/` specialists into `.cursor/agents/` (and the others) so Cursor discovers them as native subagents. **Reload Cursor afterward** so it re-scans its agents directory.
