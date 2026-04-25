# Update Orchestra in This Project

Pull the latest `prompts/`, `scripts/`, and adapter wrappers from `RyanYahya/orchestra` into this project. Workflows in `.orchestra/workflows/` are preserved.

When to run:
- After `/plugin update orchestra` (Claude Code) — that updates the slash commands but not the on-disk `.orchestra/` core
- Whenever you want the latest improvements
- After pulling a repo where someone else upgraded orchestra

Safe to run anytime — it never touches `workflows/active/`, `workflows/current/`, or `workflows/archived/`.

---

## Step 1: Update

Run:

```
bash -c '
set -e
if [[ ! -d .orchestra ]]; then
  echo "ERROR: .orchestra/ not found. Run /orchestra:phase-runner to bootstrap first." >&2
  exit 1
fi
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
echo "→ fetching latest..."
git clone --depth 1 https://github.com/RyanYahya/orchestra "$TMP" >/dev/null 2>&1

# Refresh prompts and scripts (workflows/ stays untouched).
rm -rf .orchestra/prompts .orchestra/scripts
cp -R "$TMP/prompts" .orchestra/
cp -R "$TMP/scripts" .orchestra/
chmod +x .orchestra/scripts/phase-runner.sh .orchestra/scripts/orchestra/*.sh 2>/dev/null || true

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
- That workflows were preserved
- That if `/plugin update orchestra` hasn't run yet (Claude Code users), they should run it to refresh the slash command wrappers too
