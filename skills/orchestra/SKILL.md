---
name: orchestra
description: Use when the user asks to plan, execute, audit, revise, resolve, sync docs, update, archive, bootstrap, or otherwise manage an Orchestra workflow, or mentions Orchestra slash commands such as /orchestra:plan.
---

# Orchestra

Orchestra is a shared workflow system for AI coding tools. The source of truth is always the target repository's `.orchestra/` directory. Do not recreate workflow state from memory.

## Command Routing

When the user asks for an Orchestra action, read the matching prompt completely and follow it exactly:

- `plan` -> `.orchestra/prompts/plan.md`
- `plan-advanced` -> `.orchestra/prompts/plan-advanced.md`
- `execute all` -> this skill's `references/execute-all.md` (Codex-only autopilot)
- `execute` -> `.orchestra/prompts/execute.md`
- `execute-headless` -> `.orchestra/prompts/execute-headless.md`
- `thermonuclear-review` -> `.orchestra/prompts/thermonuclear-review.md`
- `sync-agents` -> `.orchestra/prompts/sync-agents.md`
- `revise` -> `.orchestra/prompts/revise.md`
- `resolve` -> `.orchestra/prompts/resolve.md`
- `docs-sync` -> `.orchestra/prompts/docs-sync.md`
- `agent` -> `.orchestra/prompts/agent.md`
- `archive` -> `.orchestra/prompts/archive.md`
- `simplify` -> `.agents/skills/simplify/SKILL.md`
- `update` -> `.orchestra/prompts/update.md`
- `phase-runner` -> `.orchestra/prompts/phase-runner.md`

If the user uses Claude-style names such as `/orchestra:plan`, route to the command after the colon. If the user uses Codex-style phrasing such as `$orchestra plan`, `/orchestra plan`, or "orchestra execute", route to the first command word after `orchestra`. Special case `execute all` before generic `execute`; `execute` alone remains the normal single-phase command.

## Workflow Rules

- Respect `.orchestra/workflows/current/.lock`. If a lock is held by another actor, follow the active prompt's lock instructions and report the holder.
- Do not remove or overwrite a lock unless the user explicitly asks.
- Do not edit `.orchestra/workflows/current/` by hand unless the selected prompt instructs it.
- Prefer scripts under `.orchestra/scripts/orchestra/` when the selected prompt names them.
- For audits and design reviews, use `.orchestra/agents/` as the project specialist list when present.
- During `execute`, `execute all`, and `execute-headless`, spawned-agent audit is mandatory after every phase. Treat `$orchestra execute`, `$orchestra execute all`, `/orchestra:execute`, and phase-runner execution as explicit user authorization to spawn subagents for the audit. In Codex, use `multi_agent_v1.spawn_agent` after tool discovery if needed; in Cursor (2.4+), use the Task tool to launch the audit subagents in parallel in a single message. Do not replace the spawned-agent audit with self-review; block the phase only if the host genuinely has no subagent mechanism.
- Keep workflow changes scoped to the active Orchestra command. Do not advance phases, mark steps done, or archive workflows outside the selected prompt's procedure.

## Codex Notes

- This skill is the primary Codex surface. Prefer `$orchestra <command>` or natural language like "orchestra execute P2". Use `$orchestra execute` for the normal single-phase flow and `$orchestra execute all` for Codex-only autonomous execution through every remaining phase. For cleanup-only review, use `$simplify` directly or `$orchestra simplify`.
- Codex custom prompt wrappers may also exist under `.codex/prompts/` for compatibility. Treat them as thin adapters that read the same `.orchestra/prompts/<command>.md` files.
- If no `.orchestra/` directory exists yet, route `phase-runner` to the bootstrap prompt, or run `install.sh` from the Orchestra source repo when instructed by the prompt.
