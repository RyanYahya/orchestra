# Set Up Orchestra in This Project

Run this once per project. It installs `.orchestra/` (prompts, scripts, phase-runner) into the current working directory and wires up your AI tools to use it.

---

## Step 1: Bootstrap

**First, note which tool you (the agent) are running in.** Slash adapters auto-install only for tools whose config dir already exists (`.claude/`, `.codex/`, `.gemini/`, `.cursor/`). Cursor especially is often used with no `.cursor/` dir — so if you are running inside Cursor or Gemini and its dir is absent, append `--with <tool>` (e.g. `--with cursor`, or several: `--with cursor,gemini`) to the `install.sh` line below so your current tool gets its commands.

Run (append `--with <your-host>` to the last line only if your tool's dir is absent):

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

This:
- Installs `.orchestra/` (prompts + scripts + workflows dirs)
- Installs bundled Codex/Open Agent skills under `.agents/skills/`
- Adds a pointer line to `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.cursorrules` (whichever exists; creates `AGENTS.md` if none)
- Adds `.orchestra/workflows/current/` to `.gitignore`
- Detects which tools are installed (`.claude/`, `.codex/`, `.gemini/`, `.cursor/`) and drops their slash command adapters — plus any tool named in `--with`, even if its dir was absent

Idempotent — running it again preserves existing files and fills in missing adapters/skills.

---

## Step 2: Tell the user what to do next

After the bootstrap reports success, summarize the available commands. Tailor the list to the host tool you're running in:

**Inside Claude Code:**
- `/orchestra:plan <task>` — start an interactive planning workflow
- `/orchestra:plan-advanced <task>` — same, but with a relentless interview pass
- `/orchestra:execute` — execute the plan phase-by-phase, with audits
- `/orchestra:resolve` — resolve open decisions logged during planning
- `/orchestra:revise` — revise the plan mid-execution if reality diverges
- `/orchestra:archive` — archive the workflow when finished
- `/orchestra:simplify [target]` — cleanup-only review for reuse, simplification, efficiency, and altitude
- `/orchestra:thermonuclear-review [scope]` — deep, plan-aware, adversarially-verified review on demand
- `/orchestra:sync-agents` — symlink the project's specialist agents into each tool so they're discovered natively

**Inside Codex:**
- `$orchestra plan <task>` — start an interactive planning workflow
- `$orchestra plan-advanced <task>` — same, but with a relentless interview pass
- `$orchestra execute` — execute the plan phase-by-phase, with audits
- `$orchestra resolve`, `$orchestra revise`, `$orchestra archive` — workflow utilities
- `$simplify [target]` — cleanup-only review for reuse, simplification, efficiency, and altitude
- `$orchestra thermonuclear-review [scope]` — deep, plan-aware, adversarially-verified review on demand
- `$orchestra sync-agents` — symlink the project's specialist agents into each tool so they're discovered natively
- If `.codex/prompts/` adapters are installed, `/orchestra plan <task>`, `/orchestra execute`, and `/simplify` are compatibility aliases.

**Inside Gemini / Cursor:**
- Same commands without the `orchestra:` prefix (e.g. `/plan`, `/execute`, `/simplify`, `/thermonuclear-review`).
- These appear only if that tool's adapters were installed. Cursor needs a `.cursor/` dir at bootstrap — if its commands are missing, re-run Step 1 with `--with cursor`, then reload Cursor so it re-scans its command list.

**Autonomous execution (terminal):**
```
bash .orchestra/scripts/phase-runner.sh           # auto mode
bash .orchestra/scripts/phase-runner.sh --manual  # pause between phases
bash .orchestra/scripts/phase-runner.sh 15        # cap at 15 phases
bash .orchestra/scripts/phase-runner.sh --engine codex   # force Codex CLI
bash .orchestra/scripts/phase-runner.sh --engine claude  # force Claude Code
```

`phase-runner.sh` spawns headless `claude` or `codex exec` processes in a loop and walks every phase through plan → execute → audit. It must run from a real terminal because it controls child processes; it should not run from inside an active interactive coding-agent session.

---

## Step 3: Confirm the install

Show the user:

```
ls .orchestra/prompts | wc -l
```

The count should match the number of prompt files in the Orchestra source repo. If it is empty or missing expected commands, the install was incomplete — re-run Step 1 (it will overwrite if you pass `--force` to `install.sh`).
