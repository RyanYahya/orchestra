# Update Orchestra in This Project

Pull the latest `prompts/`, `scripts/`, skills, and adapter wrappers from `RyanYahya/orchestra` into this project. Workflows in `.orchestra/workflows/` are preserved.

When to run:
- After `/plugin update orchestra` in Claude Code or updating the Orchestra plugin in Codex — that updates the installable command/skill surface but not the on-disk `.orchestra/` core
- Whenever you want the latest improvements
- After pulling a repo where someone else upgraded orchestra

Safe to run anytime — it never touches `workflows/active/`, `workflows/current/`, or `workflows/archived/`.

Adapters refresh only for tools whose config dir already exists. If a tool's slash commands are missing — commonly Cursor, which is often used without a `.cursor/` dir — create its command dir first so this refresh installs them: `mkdir -p .cursor/commands` (or `.gemini/commands`), then run the update. Reload the tool afterward so it re-scans its command list.

---

## Step 1: Update

Run:

```
bash -c '
set -e
if [[ ! -d .orchestra ]]; then
  echo "ERROR: .orchestra/ not found. Run /orchestra:phase-runner in Claude Code or \$orchestra phase-runner in Codex to bootstrap first." >&2
  exit 1
fi
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
echo "→ fetching latest..."
git clone --depth 1 https://github.com/RyanYahya/orchestra "$TMP" >/dev/null 2>&1

# Refresh prompts, scripts, and bundled Codex/Open Agent skills (workflows/ stays untouched).
rm -rf .orchestra/prompts .orchestra/scripts
cp -R "$TMP/prompts" .orchestra/
cp -R "$TMP/scripts" .orchestra/
chmod +x .orchestra/scripts/phase-runner.sh .orchestra/scripts/orchestra/*.sh 2>/dev/null || true
mkdir -p .orchestra/agents
if [[ -f "$TMP/templates/audit-map.json" && ! -e .orchestra/audit-map.json ]]; then
  cp "$TMP/templates/audit-map.json" .orchestra/audit-map.json
fi
if [[ -d "$TMP/skills" ]]; then
  mkdir -p .agents/skills
  for skill_dir in "$TMP"/skills/*; do
    [[ -d "$skill_dir" ]] || continue
    skill_name="$(basename "$skill_dir")"
    rm -rf ".agents/skills/$skill_name"
    cp -R "$skill_dir" .agents/skills/
  done
fi

# Refresh adapters for whichever tools are installed in this project.
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
    echo "✓ refreshed $t adapter"
  fi
done

echo "✓ orchestra updated"
'
```

## Step 2: Confirm

Tell the user:
- The number of prompts now installed: `ls .orchestra/prompts | wc -l`
- That bundled `.agents/skills/*` were refreshed when source skills exist
- That workflows were preserved
- That if the host plugin update has not run yet, they should run it too to refresh the installable wrapper/skill surface
