#!/bin/bash
# orchestra installer — copies core + per-tool adapters into the current project.
# Safe to re-run; skips files that already exist unless --force.

set -euo pipefail

FORCE=0
SOURCE_DIR=""
TARGET="$(pwd)"
WITH_TOOLS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --with) WITH_TOOLS="$2"; shift 2 ;;
    --source) SOURCE_DIR="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: install.sh [--source <repo path or url>] [--target <project dir>] [--force]

  --source   Path to a checked-out copy of the orchestra repo. If omitted,
             the script clones to a temp dir.
  --target   Project root to install into. Defaults to current directory.
  --force    Overwrite existing files in .orchestra/ and adapter dirs.
  --with     Comma-separated tools to install slash-command adapters for even
             if their config dir is absent: claude-code,codex,gemini,cursor.
             Useful for Cursor, which is often used without a .cursor/ dir.
EOF
      exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Resolve source — clone if not provided
CLEANUP=""
if [[ -z "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$(mktemp -d)"
  CLEANUP="$SOURCE_DIR"
  echo "→ cloning orchestra repo to $SOURCE_DIR"
  git clone --depth 1 https://github.com/RyanYahya/orchestra "$SOURCE_DIR" >/dev/null 2>&1 || {
    echo "ERROR: clone failed. Pass --source <path> if you have a local copy." >&2
    exit 1
  }
fi

trap '[[ -n "$CLEANUP" ]] && rm -rf "$CLEANUP"' EXIT

cd "$TARGET"

copy_dir_to_parent() {
  local src="$1" parent="$2" name dest
  name="$(basename "$src")"
  dest="$parent/$name"

  if [[ "$FORCE" == "1" ]]; then
    rm -rf "$dest"
    cp -R "$src" "$parent/"
  elif [[ -e "$dest" ]]; then
    echo "→ preserving existing $dest"
  else
    cp -R "$src" "$parent/"
  fi
}

echo "→ installing core into .orchestra/"
mkdir -p .orchestra/workflows/{active,current,archived} .orchestra/agents
copy_dir_to_parent "$SOURCE_DIR/prompts" .orchestra
copy_dir_to_parent "$SOURCE_DIR/scripts" .orchestra
chmod +x .orchestra/scripts/phase-runner.sh .orchestra/scripts/orchestra/*.sh 2>/dev/null || true

if [[ -f "$SOURCE_DIR/templates/audit-map.json" && ! -e .orchestra/audit-map.json ]]; then
  cp "$SOURCE_DIR/templates/audit-map.json" .orchestra/audit-map.json
fi

if [[ -d "$SOURCE_DIR/skills" ]]; then
  echo "→ installing Codex/Open Agent skills into .agents/skills"
  mkdir -p .agents/skills
  for skill_dir in "$SOURCE_DIR"/skills/*; do
    [[ -d "$skill_dir" ]] || continue
    copy_dir_to_parent "$skill_dir" .agents/skills
  done
fi

# Per-tool adapters
install_adapter() {
  local key="$1" detect="$2" src="$3" dest="$4" label="$5"
  local forced=0
  case ",$WITH_TOOLS," in *",$key,"*) forced=1 ;; esac
  if [[ -e "$detect" || "$forced" == "1" ]]; then
    if [[ "$forced" == "1" && ! -e "$detect" ]]; then
      echo "→ forcing $label adapter (--with $key) into $dest"
    else
      echo "→ detected $label — installing adapter into $dest"
    fi
    mkdir -p "$dest"
    if [[ "$FORCE" == "1" ]]; then
      cp -R "$SOURCE_DIR/$src/." "$dest/"
    else
      cp -R -n "$SOURCE_DIR/$src/." "$dest/" 2>/dev/null || true
    fi
  fi
}

install_adapter "claude-code" ".claude" "adapters/claude-code/commands/orchestra" ".claude/commands/orchestra" "Claude Code"
install_adapter "codex"       ".codex"  "adapters/codex/prompts"                  ".codex/prompts"            "Codex CLI"
install_adapter "gemini"      ".gemini" "adapters/gemini/commands"                ".gemini/commands"          "Gemini CLI"
install_adapter "cursor"      ".cursor" "adapters/cursor/commands"                ".cursor/commands"          "Cursor"

# If no tool surface detected, still leave the .orchestra/ core in place
# and tell the user to invoke prompts manually.

# Append AGENTS.md / CLAUDE.md / GEMINI.md / .cursorrules pointer
POINTER="## Orchestration

Workflows live in \`.orchestra/\`. To plan, execute, audit, or archive a task, follow the prompts in \`.orchestra/prompts/<name>.md\`. State persists in \`.orchestra/workflows/current/\`. Multiple AI tools may be active on this repo simultaneously — they share the same workflow state.

Claude Code: use \`/orchestra:<command>\`. Codex: use the repo-scoped \`\$orchestra\` skill, \`\$orchestra execute all\` for Codex-only autonomous execution with a fresh app task for each next phase, \`\$simplify\` for cleanup-only review, natural language like \"orchestra execute\", or the installed \`/orchestra <command>\` / \`/simplify\` prompt adapters when available.

Do not edit \`.orchestra/workflows/current/\` by hand unless the active Orchestra prompt tells you to. Respect \`.orchestra/workflows/current/.lock\`; if another actor holds it, report the holder instead of taking over silently."

append_if_missing() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if ! grep -q "^## Orchestration" "$file" 2>/dev/null; then
    echo "→ appending pointer to $file"
    printf "\n%s\n" "$POINTER" >> "$file"
  fi
}

append_if_missing CLAUDE.md
append_if_missing AGENTS.md
append_if_missing GEMINI.md
append_if_missing .cursorrules

# If none existed, create AGENTS.md so something points at .orchestra/
if [[ ! -f AGENTS.md && ! -f CLAUDE.md && ! -f GEMINI.md && ! -f .cursorrules ]]; then
  echo "→ creating AGENTS.md"
  printf "%s\n" "$POINTER" > AGENTS.md
fi

# .gitignore
if [[ -f .gitignore ]] && ! grep -q "^\.orchestra/workflows/current/" .gitignore; then
  echo "→ adding .orchestra/workflows/current/ to .gitignore"
  printf "\n# Orchestration live workflow state\n.orchestra/workflows/current/\n" >> .gitignore
fi

echo
echo "✓ orchestra installed"
echo "  core: .orchestra/"
echo "  prompts: $(ls .orchestra/prompts/ | wc -l | tr -d ' ') files"
echo "  skills: .agents/skills"
echo "  next: run /orchestra:plan <task> in Claude Code, or \$orchestra plan <task> in Codex; use \$orchestra execute all for Codex autopilot and \$simplify for cleanup-only review"
