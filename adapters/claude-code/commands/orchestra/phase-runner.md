---
name: phase-runner
description: Set up orchestra in this project (run once per project)
---

You are setting up the orchestra workflow system in the current project. Follow the instructions below — they are self-contained and do not depend on any pre-existing `.orchestra/` directory.

## Step 1: Bootstrap

Run:

```
bash -c '
set -e
if [[ -d .orchestra/scripts && -f .orchestra/scripts/phase-runner.sh ]]; then
  echo "✓ orchestra core already installed; refreshing any missing adapters/skills"
fi
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
echo "→ fetching orchestra..."
git clone --depth 1 https://github.com/RyanYahya/orchestra "$TMP" >/dev/null 2>&1
bash "$TMP/install.sh" --source "$TMP" --target "$(pwd)"
'
```

This installs `.orchestra/` (prompts + scripts + workflows dirs), installs bundled Codex/Open Agent skills under `.agents/skills/`, wires up slash commands for whichever AI tools are installed (`.claude/`, `.codex/`, `.gemini/`, `.cursor/`), appends a pointer to your project's instruction file (CLAUDE.md / AGENTS.md / GEMINI.md / .cursorrules — creates AGENTS.md if none), and adds `.orchestra/workflows/current/` to `.gitignore`. Idempotent: reruns preserve existing files and fill in missing adapters/skills.

## Step 2: Summarize next steps

After the bootstrap reports success, tell the user:

- `/orchestra:plan <task>` — start an interactive planning workflow
- `/orchestra:plan-advanced <task>` — planning with a relentless interview pass
- `/orchestra:execute` — execute the plan phase-by-phase with audits
- `/orchestra:resolve`, `/orchestra:revise`, `/orchestra:archive` — workflow utilities
- `/orchestra:simplify [target]` — cleanup-only review for reuse, simplification, efficiency, and altitude
- In Codex, use `$orchestra plan <task>` / `$orchestra execute`, `$simplify [target]` for cleanup-only review, or `/orchestra plan <task>` and `/simplify` when prompt adapters are installed.

For autonomous execution (must run from a real terminal, not from inside Claude Code):

```
bash .orchestra/scripts/phase-runner.sh           # auto mode
bash .orchestra/scripts/phase-runner.sh --manual  # pause between phases
bash .orchestra/scripts/phase-runner.sh --engine codex
```

## Step 3: Confirm

Show the user the result of: `ls .orchestra/prompts | wc -l` and confirm `.agents/skills/orchestra/SKILL.md` and `.agents/skills/simplify/SKILL.md` exist.
