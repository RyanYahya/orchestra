# orchestra

Plan / execute / audit / resolve workflow orchestration for AI coding agents. Tool-agnostic on-disk state, identical slash commands across **Claude Code**, **Codex CLI**, **Gemini CLI**, **Cursor**, and others.

Multiple tools can drive the same workflow on the same repo — state lives in `.orchestra/workflows/current/`, every tool reads the same prompts in `.orchestra/prompts/`, every action is logged with an `actor` field so a Claude Code session and a Codex session can collaborate on one workflow.

## Install

### Claude Code (plugin)

```
/plugin marketplace add RyanYahya/orchestra
/plugin install orchestra
```

Then, in any project where you want to use orchestra, run once:

```
/orchestra:phase-runner
```

This is the bootstrap. It drops `.orchestra/` into the project, wires up adapters for any other AI tools you have installed (`.codex/`, `.gemini/`, `.cursor/`), appends a pointer to `CLAUDE.md` / `AGENTS.md`, and adds `.orchestra/workflows/current/` to `.gitignore`. Idempotent — safe to run again.

### Updating

When orchestra ships improvements, the update flow has two layers:

1. `/plugin update orchestra` — refreshes the slash command wrappers in Claude Code (and equivalent in other tools).
2. `/orchestra:update` — pulls the latest `prompts/` and `scripts/` into `.orchestra/`. Your `.orchestra/workflows/` (active, current, archived) are never touched. Run this in every project where you've bootstrapped orchestra.

Both are safe to run repeatedly.

### Any other AI coding tool

Tell your AI:

> Install the orchestra system from `https://github.com/RyanYahya/orchestra` into this project. Follow `INSTALL.md`.

The AI will read [INSTALL.md](INSTALL.md), detect which tool surfaces are present, and install slash command adapters into all of them.

### Manual

```bash
git clone https://github.com/RyanYahya/orchestra /tmp/orch
cd /your/project
bash /tmp/orch/install.sh --source /tmp/orch
```

## Slash commands

Once bootstrapped, the following commands are available:

| Command | What it does |
|---|---|
| `phase-runner` | Bootstrap orchestra into a project (run once per project) |
| `update` | Pull the latest prompts/scripts from GitHub (workflows preserved) |
| `plan` | Research codebase, draft plan, validate against docs |
| `plan-advanced` | Same as `plan` plus a relentless interview pass — walks the decision tree one question at a time |
| `execute` | Walk the plan phase-by-phase, with self-review and audits each phase |
| `execute-headless` | Execute one phase headlessly (driven by `phase-runner.sh`) |
| `revise` | Revise the plan mid-execution when reality diverges |
| `agent` | Dispatch a specialized sub-agent against the workflow |
| `resolve` | Resolve open decisions logged during planning |
| `docs-sync` | Sync project docs with the implemented changes |
| `archive` | Move the current workflow to `archived/` and clear |

In Claude Code these are namespaced as `/orchestra:plan` etc. In other tools they are `/plan`, `/plan-advanced`, etc. (filename = command name).

## Autonomous execution

For multi-phase autonomous runs, use the phase runner from a real terminal (not from inside Claude Code Desktop, since it spawns headless `claude` CLI processes):

```bash
bash .orchestra/scripts/phase-runner.sh           # auto mode
bash .orchestra/scripts/phase-runner.sh --manual  # pause between phases
bash .orchestra/scripts/phase-runner.sh 15        # cap at 15 phases
```

Each phase runs through plan → execute → self-review → external audit → commit. Advisory findings (over-engineering, drive-by edits, repeated patterns) auto-correct or accumulate in `Advisory_Notes.md` so subsequent phases learn from them — no human in the loop required.

In Claude Code these are namespaced as `/orchestra:plan` etc. In other tools they are `/plan`, `/plan-advanced`, etc. (filename = command name).

## Layout

```
.
├── prompts/              # canonical prompt bodies (single source of truth)
├── scripts/              # phase-runner.sh + workflow helpers (bash, universal)
├── adapters/
│   ├── claude-code/      # Claude Code plugin (slash commands + plugin.json)
│   ├── codex/            # Codex CLI prompts
│   ├── gemini/           # Gemini CLI commands
│   ├── cursor/           # Cursor commands
│   └── aider/            # Aider integration notes
├── .claude-plugin/       # marketplace manifest for Claude Code
├── install.sh            # one-shot installer
├── INSTALL.md            # AI-readable install guide
└── README.md
```

## How multi-tool coordination works

Every workflow produces four artifacts in `.orchestra/workflows/current/`:

- `status.json` — current phase, totals, append-only `log[]` of actions with timestamps and actor names
- `Plan.md` — phased plan with manual verification steps
- `Decisions.md` — every resolved design decision (D001, D002, …)
- `Implementation_Notes.md` — codebase + docs research

Any AI tool that follows the prompts in `.orchestra/prompts/` will read and write the same files. Hand-off between sessions / tools is automatic — the next agent reads `status.json`, sees `currentPhase`, and continues.

A simple lockfile (`.orchestra/workflows/current/.lock`) prevents concurrent writers from clobbering each other.

## Editing prompts

The slash commands across every tool are thin wrappers — they all read `.orchestra/prompts/<name>.md`. Edit a prompt once and every tool's slash command updates on next invocation. No need to re-install or sync.

## License

MIT.
