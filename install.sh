#!/bin/bash
# orchestra installer — copies core + per-tool adapters into the current project.
# Safe to re-run; skips files that already exist unless --force.

set -euo pipefail

FORCE=0
SOURCE_DIR=""
TARGET="$(pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --source) SOURCE_DIR="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: install.sh [--source <repo path or url>] [--target <project dir>] [--force]

  --source   Path to a checked-out copy of the orchestra repo. If omitted,
             the script clones to a temp dir.
  --target   Project root to install into. Defaults to current directory.
  --force    Overwrite existing files in .orchestra/ and adapter dirs.
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

if [[ -d "$SOURCE_DIR/skills/orchestra" ]]; then
  echo "→ installing Codex/Open Agent skill into .agents/skills/orchestra"
  mkdir -p .agents/skills
  copy_dir_to_parent "$SOURCE_DIR/skills/orchestra" .agents/skills
fi

# Per-tool adapters
install_adapter() {
  local detect="$1" src="$2" dest="$3" label="$4"
  if [[ -e "$detect" ]]; then
    echo "→ detected $label — installing adapter into $dest"
    mkdir -p "$dest"
    if [[ "$FORCE" == "1" ]]; then
      cp -R "$SOURCE_DIR/$src/." "$dest/"
    else
      cp -R -n "$SOURCE_DIR/$src/." "$dest/" 2>/dev/null || true
    fi
  fi
}

install_adapter ".claude"   "adapters/claude-code/commands/orchestra" ".claude/commands/orchestra" "Claude Code"
install_adapter ".codex"    "adapters/codex/prompts"                     ".codex/prompts"                 "Codex CLI"
install_adapter ".gemini"   "adapters/gemini/commands"                   ".gemini/commands"               "Gemini CLI"
install_adapter ".cursor"   "adapters/cursor/commands"                   ".cursor/commands"               "Cursor"

# If no tool surface detected, still leave the .orchestra/ core in place
# and tell the user to invoke prompts manually.

# Append AGENTS.md / CLAUDE.md / GEMINI.md / .cursorrules pointer
POINTER="## Orchestration

Workflows live in \`.orchestra/\`. To plan, execute, audit, or archive a task, follow the prompts in \`.orchestra/prompts/<name>.md\`. State persists in \`.orchestra/workflows/current/\`. Multiple AI tools may be active on this repo simultaneously — they share the same workflow state.

Claude Code: use \`/orchestra:<command>\`. Codex: use the repo-scoped \`\$orchestra\` skill, natural language like \"orchestra execute\", or the installed \`/orchestra <command>\` prompt adapter when available.

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
echo "  skill: .agents/skills/orchestra"
echo "  next: run /orchestra:plan <task> in Claude Code, or \$orchestra plan <task> in Codex"
