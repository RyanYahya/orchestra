# Sync Agents

Make orchestra's specialist agents in `.orchestra/agents/` natively discoverable by Claude Code, Codex, and Cursor, so each tool can invoke them as first-class subagents — instead of relying on the executing agent to read each file and pass it inline (which weaker/faster models routinely skip).

**Arguments (optional):** $ARGUMENTS
- Tool names to limit the sync: `claude`, `codex`, `cursor` (default: all three)
- `--copy` — copy the agent files instead of symlinking (portable across OSes / Windows; loses the live single-source link)
- `--prune` — also remove this command's stale links for agents that were deleted from `.orchestra/agents/`

## Run

```
bash .orchestra/scripts/orchestra/sync-agents.sh $ARGUMENTS
```

Then report which tools were synced and how many agents each received.

`.orchestra/agents/` stays the single source of truth — the tool dirs (`.claude/agents/`, `.codex/agents/`, `.cursor/agents/`) hold relative symlinks back to it. Editing an already-linked agent propagates immediately; adding or removing agents needs another sync (use `--prune` to clear links for deleted ones). A tool's own pre-existing agents are never overwritten — same-named real files are skipped.

After syncing, tell the user to **reload the tool** (Cursor especially) so it re-scans its agents directory, after which the orchestra specialists appear by name for audits and reviews.
