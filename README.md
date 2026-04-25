# orchestra

Plan / execute / audit / resolve workflow orchestration for AI coding agents. Tool-agnostic on-disk state, identical slash commands across **Claude Code**, **Codex CLI**, **Gemini CLI**, **Cursor**, and others.

Multiple tools can drive the same workflow on the same repo — state lives in `.orchestra/workflows/current/`, every tool reads the same prompts in `.orchestra/prompts/`, every action is logged with an `actor` field so a Claude Code session and a Codex session can collaborate on one workflow.

## Install

### Claude Code (plugin)

```
/plugin marketplace add RyanYahya/orchestra
/plugin install orchestra
```

After install, run the bootstrap once to drop `.orchestra/` into your project:

```bash
curl -fsSL https://raw.githubusercontent.com/RyanYahya/orchestra/main/install.sh | bash
```

### Any other AI coding tool

Tell your AI:

> Install the orchestra system from `https://github.com/RyanYahya/orchestra` into this project. Follow `INSTALL.md`.

The AI will read [INSTALL.md](INSTALL.md), detect which tool surfaces are present (`.claude/`, `.codex/`, `.gemini/`, `.cursor/`, etc.), and install slash command adapters into all of them.

### Manual

```bash
git clone https://github.com/RyanYahya/orchestra /tmp/orch
cd /your/project
bash /tmp/orch/install.sh --source /tmp/orch
```

## Slash commands

Once installed, the following commands are available:

| Command | What it does |
|---|---|
| `plan` | Research codebase, draft plan, validate against docs |
| `plan-advanced` | Same as `plan` plus a relentless interview pass — walks the decision tree one question at a time |
| `execute` | Walk the plan phase-by-phase with manual verification |
| `execute-headless` | Run plan autonomously via `phase-runner.sh` |
| `agent` | Dispatch a specialized sub-agent against the workflow |
| `resolve` | Resolve open decisions logged during planning |
| `docs-sync` | Sync project docs with the implemented changes |
| `archive` | Move the current workflow to `archived/` and clear |

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
