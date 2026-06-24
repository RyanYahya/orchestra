#!/bin/bash
# sync-agents.sh — make .orchestra/agents/ specialists natively discoverable by
# Claude Code, Codex, and Cursor by linking them into each tool's agents dir.
# .orchestra/agents/ stays the single source of truth; the tool dirs hold
# relative symlinks back to it (or copies with --copy).
#
# Usage:
#   sync-agents.sh                  # symlink into claude, codex, cursor
#   sync-agents.sh cursor           # only the named tool(s): claude|codex|cursor
#   sync-agents.sh --copy           # copy instead of symlink (portable across OSes)
#   sync-agents.sh --prune          # also remove our stale links for deleted agents

set -euo pipefail

SCRIPT_DIR="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-utils.sh"

cd "$PROJECT_ROOT"

SRC=".orchestra/agents"

MODE="symlink"
PRUNE=0
TOOLS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy)    MODE="copy"; shift ;;
    --symlink) MODE="symlink"; shift ;;
    --prune)   PRUNE=1; shift ;;
    claude|claude-code) TOOLS+=("claude"); shift ;;
    codex)     TOOLS+=("codex"); shift ;;
    cursor)    TOOLS+=("cursor"); shift ;;
    *) echo "ERROR: unknown arg: $1 (expected claude|codex|cursor, --copy, --prune)" >&2; exit 1 ;;
  esac
done
[[ "${#TOOLS[@]}" -gt 0 ]] || TOOLS=(claude codex cursor)

tool_dir() {
  case "$1" in
    claude) echo ".claude/agents" ;;
    codex)  echo ".codex/agents" ;;
    cursor) echo ".cursor/agents" ;;
  esac
}

# Count available agents up front.
agent_count=0
for a in "$SRC"/*.md; do [[ -e "$a" ]] && agent_count=$((agent_count + 1)); done
if [[ "$agent_count" -eq 0 ]]; then
  echo "No agents in $SRC/ — nothing to sync. Create specialists there first (e.g. /orchestra:agent)."
  exit 0
fi

for tool in "${TOOLS[@]}"; do
  dest="$(tool_dir "$tool")"
  mkdir -p "$dest"

  if [[ "$PRUNE" == "1" ]]; then
    for link in "$dest"/*.md; do
      [[ -L "$link" ]] || continue
      case "$(readlink "$link")" in
        *".orchestra/agents/"*) [[ -e "$link" ]] || rm -f "$link" ;;
      esac
    done
  fi

  linked=0
  for agent in "$SRC"/*.md; do
    [[ -e "$agent" ]] || continue
    name="$(basename "$agent")"
    target="$dest/$name"
    if [[ -e "$target" && ! -L "$target" ]]; then
      echo "  skip $dest/$name — a real file is already there (not overwriting)"
      continue
    fi
    if [[ "$MODE" == "copy" ]]; then
      cp -f "$agent" "$target"
    else
      # dest is always two levels deep (.<tool>/agents), so the repo root is ../../
      ln -snf "../../$SRC/$name" "$target"
    fi
    linked=$((linked + 1))
  done
  echo "✓ $tool → $dest ($linked agent(s))"
done

echo "Synced $agent_count agent(s) across ${#TOOLS[@]} tool(s) via $MODE."
echo "Reload each tool so it re-scans its agents directory."
