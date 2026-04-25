# Set Up Orchestra in This Project

Run this once per project. It installs `.orchestra/` (prompts, scripts, phase-runner) into the current working directory and wires up your AI tools to use it.

---

## Step 1: Bootstrap

Run:

```
bash -c '
set -e
if [[ -d .orchestra/scripts && -f .orchestra/scripts/phase-runner.sh ]]; then
  echo "✓ orchestra already installed in this project"
  exit 0
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
- Adds a pointer line to `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.cursorrules` (whichever exists; creates `AGENTS.md` if none)
- Adds `.orchestra/workflows/current/` to `.gitignore`
- Detects which tools are installed (`.claude/`, `.codex/`, `.gemini/`, `.cursor/`) and drops their slash command adapters

Idempotent — running it again is a no-op.

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

**Inside Codex / Gemini / Cursor:**
- Same commands without the `orchestra:` prefix (e.g. `/plan`, `/execute`).

**Autonomous execution (terminal, not from inside Claude Code):**
```
bash .orchestra/scripts/phase-runner.sh           # auto mode
bash .orchestra/scripts/phase-runner.sh --manual  # pause between phases
bash .orchestra/scripts/phase-runner.sh 15        # cap at 15 phases
```

`phase-runner.sh` spawns headless `claude` CLI processes in a loop and walks every phase through plan → execute → audit. It must run from a real terminal because it controls a child Claude process; it cannot run from inside an active Claude Code session.

---

## Step 3: Confirm the install

Show the user:

```
ls .orchestra/prompts | wc -l
```

Should print `9`. If you see a different number, the install was incomplete — re-run Step 1 (it will overwrite if you pass `--force` to `install.sh`).
