# orchestra

Plan / execute / audit / resolve workflow orchestration for AI coding agents. Tool-agnostic on-disk state, natural command surfaces for **Claude Code**, **Codex**, **Gemini CLI**, **Cursor**, and others.

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

This is the bootstrap. It drops `.orchestra/` into the project, installs bundled Codex/Open Agent skills under `.agents/skills/`, wires up adapters for any other AI tools you have installed (`.codex/`, `.gemini/`, `.cursor/`), appends a pointer to `CLAUDE.md` / `AGENTS.md`, and adds `.orchestra/workflows/current/` to `.gitignore`. Idempotent — safe to run again.

### Codex (plugin or skill)

Orchestra is also a native Codex plugin/skill. The repo includes `.codex-plugin/plugin.json` and bundled skills under `skills/`, so Codex can invoke the workflow through `$orchestra` and `$simplify`.

For a local/plugin install, add this repo as a Codex marketplace source, install the `orchestra` plugin, restart Codex, then run once per project:

```bash
codex plugin marketplace add RyanYahya/orchestra
```

Then open `/plugins` in Codex and install Orchestra.

```
$orchestra phase-runner
```

After bootstrap, use:

```
$orchestra plan <task>
$orchestra execute
$orchestra resolve
$orchestra revise
$orchestra archive
$simplify [target]
```

If `.codex/prompts/` adapters are installed in the project, `/orchestra plan <task>` and `/orchestra execute` are compatibility aliases. The `$orchestra` skill is the preferred Codex surface because Codex custom prompts are deprecated in favor of skills.

### Updating

When orchestra ships improvements, the update flow has two layers:

1. `/plugin update orchestra` in Claude Code, or the Codex plugin update flow — refreshes the installable plugin/wrapper surface.
2. `/orchestra:update` in Claude Code or `$orchestra update` in Codex — pulls the latest `prompts/`, `scripts/`, adapters, and skill into the project. Your `.orchestra/workflows/` (active, current, archived) are never touched. Run this in every project where you've bootstrapped orchestra.

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
| `update` | Pull the latest prompts, scripts, and bundled skills from GitHub (workflows preserved) |
| `plan` | Research codebase, draft plan, validate against docs |
| `plan-advanced` | Same as `plan` plus a relentless interview pass — walks the decision tree one question at a time |
| `execute` | Walk the plan phase-by-phase, with self-review and audits each phase |
| `execute-headless` | Execute one phase headlessly (driven by `phase-runner.sh`) |
| `revise` | Revise the plan mid-execution when reality diverges |
| `agent` | Dispatch a specialized sub-agent against the workflow |
| `resolve` | Resolve open decisions logged during planning |
| `docs-sync` | Sync project docs with the implemented changes |
| `archive` | Move the current workflow to `archived/` and clear |
| `simplify` | Cleanup-only diff review for reuse, simplification, efficiency, and altitude; then apply behavior-preserving fixes |
| `thermonuclear-review` | Deep, plan-aware, adversarially-verified quality review on demand — Layer 2 on top of the per-phase audit |

In Claude Code these are namespaced as `/orchestra:plan` etc. In Codex, invoke the same command names through `$orchestra plan`, `$orchestra execute`, etc. Use `$simplify` for the cleanup-only review pass. The Codex prompt adapter also includes `/orchestra <command>` and `/simplify` compatibility aliases when `.codex/prompts/` wrappers are installed.

## Autonomous execution

For multi-phase autonomous runs, use the phase runner from a real terminal (not from inside an interactive agent session, since it spawns child CLI processes):

```bash
bash .orchestra/scripts/phase-runner.sh           # auto mode
bash .orchestra/scripts/phase-runner.sh --manual  # pause between phases
bash .orchestra/scripts/phase-runner.sh 15        # cap at 15 phases
bash .orchestra/scripts/phase-runner.sh --engine claude
bash .orchestra/scripts/phase-runner.sh --engine codex
```

Each phase runs through plan → execute → self-review → external audit → commit. Advisory findings (over-engineering, drive-by edits, repeated patterns) auto-correct or accumulate in `Advisory_Notes.md` so subsequent phases learn from them — no human in the loop required.

### Worktree safety

Phase commits are scoped by default. `commit-phase.sh P1 --paths-from-plan` stages only files named in the phase steps, leaves unrelated unstaged user changes alone, and refuses if unrelated changes are already staged. For unusual phases, pass `--paths-file <file>` with an explicit newline-delimited path list. Use `--all` only when you intentionally want a blanket commit.

Workflow state transitions also have wrappers for agents: `mark-step-done.sh`, `record-verify.sh`, `record-audit.sh`, and `complete-phase.sh`. Audit routing can be made deterministic with `.orchestra/audit-map.json` and `select-audit-agents.sh`.

## Layout

```
.
├── prompts/              # canonical prompt bodies (single source of truth)
├── scripts/              # phase-runner.sh + workflow helpers (bash, universal)
├── adapters/
│   ├── claude-code/      # Claude Code plugin (slash commands + plugin.json)
│   ├── codex/            # Codex prompt adapters
│   ├── gemini/           # Gemini CLI commands
│   ├── cursor/           # Cursor commands
│   └── aider/            # Aider integration notes
├── .claude-plugin/       # marketplace manifest for Claude Code
├── .codex-plugin/        # native Codex plugin manifest
├── .agents/plugins/      # Codex marketplace entry for local/repo installs
├── skills/               # Codex/Open Agent skills bundled with the plugin (`orchestra`, `simplify`)
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

The command surfaces across every tool are thin wrappers — they all read `.orchestra/prompts/<name>.md`. Edit a prompt once and every tool's command updates on next invocation. No need to re-install or sync.

## License

MIT.
