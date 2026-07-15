# Install Instructions (for AI agents)

You are installing the **orchestra** system into the user's current project. Follow the steps in order. Do not skip steps.

## Source

This repo: <https://github.com/RyanYahya/orchestra>

You can either clone it to a temp directory, or fetch individual files via raw GitHub URLs.

## Steps

1. **Determine the project root.** Use the user's current working directory (where they invoked you).

2. **Detect installed AI tool surfaces.** Check for the existence of any of:
   - `.claude/` (Claude Code)
   - `.codex/` (Codex CLI)
   - `.gemini/` (Gemini CLI)
   - `.cursor/` (Cursor)
   - `.aider*` (Aider)
   - `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules` files

   Multiple may exist — that is normal. The user may have several tools active on the same repo. Install slash commands for **all** detected tools so they share one orchestra system.

3. **Copy the core into `.orchestra/` at the project root:**
   - `prompts/` → `.orchestra/prompts/`
   - `scripts/` → `.orchestra/scripts/`
   - Create empty dirs: `.orchestra/workflows/active/`, `.orchestra/workflows/current/`, `.orchestra/workflows/archived/`
   - Make all `.sh` files in `.orchestra/scripts/` executable: `chmod +x`

4. **Install slash command adapters for each detected tool:**

   | Tool | Source | Destination |
   |---|---|---|
   | Claude Code | `adapters/claude-code/commands/orchestra/` | `.claude/commands/orchestra/` |
   | Codex prompt fallback | `adapters/codex/prompts/` | `.codex/prompts/` |
   | Gemini CLI | `adapters/gemini/commands/` | `.gemini/commands/` |
   | Cursor | `adapters/cursor/commands/` | `.cursor/commands/` |
   | Aider | `adapters/aider/README.md` | append the alias snippet to user's shell rc, or skip and tell user |

   If none of these surfaces exist, still install `.orchestra/` itself — the prompts can be invoked manually.

   Always install the bundled Codex/Open Agent skills:

   | Source | Destination |
   |---|---|
   | `skills/*/` | `.agents/skills/*/` |

5. **Update the project's primary instruction file(s).** For each of these that exists (or create `AGENTS.md` if none), append (idempotently — check first):

   ```markdown
   ## Orchestration

   Workflows live in `.orchestra/`. To plan, execute, audit, or archive a task, follow the prompts in `.orchestra/prompts/<name>.md`. State persists in `.orchestra/workflows/current/`. Multiple AI tools (Claude Code, Codex, Gemini, Cursor, etc.) may be active on this repo simultaneously — they share the same workflow state.

   Claude Code: use `/orchestra:<command>`. Codex: use the repo-scoped `$orchestra` skill, `$orchestra execute all` for Codex-only autonomous execution with a fresh app task for each next phase, `$simplify` for cleanup-only review, natural language like "orchestra execute", or the installed `/orchestra <command>` / `/simplify` prompt adapters when available.

   Do not edit `.orchestra/workflows/current/` by hand unless the active Orchestra prompt tells you to. Respect `.orchestra/workflows/current/.lock`; if another actor holds it, report the holder instead of taking over silently.
   ```

   Files to update if present: `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`.

6. **Update `.gitignore`.** Append (if not already present):
   ```
   .orchestra/workflows/current/
   ```
   Live workflow state is per-developer scratch. The `active/` and `archived/` dirs stay tracked.

7. **Verify install:**
   - `ls .orchestra/prompts/` — should list the installed prompt files.
   - `ls .orchestra/scripts/` — should show `phase-runner.sh` and `orchestra/`.
   - `test -f .orchestra/audit-map.json` — should pass; projects can edit it to pin audit agents by phase or path.
   - `test -f .agents/skills/orchestra/SKILL.md` and `test -f .agents/skills/simplify/SKILL.md` — should pass for Codex.
   - For each detected tool, list the installed command directory and confirm the expected wrappers are there.

8. **Report back to the user:**
   - Which tools you installed adapters for.
   - The command they can run next: `/orchestra:plan <task>` in Claude Code or `$orchestra plan <task>` in Codex. For Codex autopilot after approval, use `$orchestra execute all`. For cleanup-only review, use `/orchestra:simplify` in Claude Code or `$simplify` in Codex.
   - That `.orchestra/workflows/current/` was added to `.gitignore`.

## Quick install script

If a shell is available, the repo includes `install.sh` which performs steps 3–6 automatically. Run from the project root:

```bash
curl -fsSL https://raw.githubusercontent.com/RyanYahya/orchestra/main/install.sh | bash
```

## How the system works (background for the AI)

- All workflow state is on disk in `.orchestra/workflows/current/` (Plan.md, status.json, Decisions.md, Implementation_Notes.md). No tool-specific state.
- Command surfaces across every tool delegate to the same prompt bodies in `.orchestra/prompts/`. Edit the prompt file once and every tool's command updates.
- The `status.json.log[]` array records every action with an `actor` field — when a Claude Code session and a Codex session both touch the same workflow, the log shows who did what.
- The `phase-runner.sh` script drives autonomous execution; the `execute.md` prompt drives interactive execution. Both read/write the same `status.json`.
