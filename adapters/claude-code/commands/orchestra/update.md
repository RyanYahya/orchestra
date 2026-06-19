---
name: update
description: Pull the latest orchestra prompts, scripts, and adapters from GitHub (workflows preserved)
---

You are updating the orchestra workflow system in this project to the latest version.

## Step 1: Update

```
bash -c '
set -e
if [[ ! -d .orchestra ]]; then
  echo "ERROR: .orchestra/ not found. Run /orchestra:phase-runner to bootstrap first." >&2
  exit 1
fi
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
git clone --depth 1 https://github.com/RyanYahya/orchestra "$TMP" >/dev/null 2>&1

rm -rf .orchestra/prompts .orchestra/scripts
cp -R "$TMP/prompts" .orchestra/
cp -R "$TMP/scripts" .orchestra/
chmod +x .orchestra/scripts/phase-runner.sh .orchestra/scripts/orchestra/*.sh 2>/dev/null || true
mkdir -p .orchestra/agents
if [[ -d "$TMP/skills/orchestra" ]]; then
  mkdir -p .agents/skills
  rm -rf .agents/skills/orchestra
  cp -R "$TMP/skills/orchestra" .agents/skills/
fi

for t in claude-code codex gemini cursor; do
  case "$t" in
    claude-code) detect=".claude"; src="adapters/claude-code/commands/orchestra"; dest=".claude/commands/orchestra" ;;
    codex)       detect=".codex";  src="adapters/codex/prompts";                  dest=".codex/prompts" ;;
    gemini)      detect=".gemini"; src="adapters/gemini/commands";                dest=".gemini/commands" ;;
    cursor)      detect=".cursor"; src="adapters/cursor/commands";                dest=".cursor/commands" ;;
  esac
  if [[ -e "$detect" ]]; then
    mkdir -p "$dest"
    cp -R "$TMP/$src/." "$dest/"
  fi
done

echo "✓ orchestra updated (workflows preserved)"
'
```

## Step 2: Confirm

Tell the user the number of prompts installed (`ls .orchestra/prompts | wc -l`), that `.agents/skills/orchestra` was refreshed for Codex, and remind them: if they're on Claude Code and haven't run `/plugin update orchestra` yet, do that too — it refreshes the slash command wrappers, while this command refreshed the on-disk core.
