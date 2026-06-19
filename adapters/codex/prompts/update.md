---
description: Orchestra update - refresh prompts, scripts, skills, and adapters
argument-hint: [SOURCE]
---

Update orchestra in this project to the latest version. Run:

```
bash -c '
set -e
[[ -d .orchestra ]] || { echo "ERROR: run \$orchestra phase-runner first"; exit 1; }
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
git clone --depth 1 https://github.com/RyanYahya/orchestra "$TMP" >/dev/null 2>&1
rm -rf .orchestra/prompts .orchestra/scripts
cp -R "$TMP/prompts" .orchestra/; cp -R "$TMP/scripts" .orchestra/
chmod +x .orchestra/scripts/phase-runner.sh .orchestra/scripts/orchestra/*.sh 2>/dev/null || true
mkdir -p .orchestra/agents
if [[ -d "$TMP/skills/orchestra" ]]; then
  mkdir -p .agents/skills
  rm -rf .agents/skills/orchestra
  cp -R "$TMP/skills/orchestra" .agents/skills/
fi
for t in "claude-code:.claude:adapters/claude-code/commands/orchestra:.claude/commands/orchestra" \
         "codex:.codex:adapters/codex/prompts:.codex/prompts" \
         "gemini:.gemini:adapters/gemini/commands:.gemini/commands" \
         "cursor:.cursor:adapters/cursor/commands:.cursor/commands"; do
  IFS=: read -r _ d s o <<< "$t"
  [[ -e "$d" ]] && { mkdir -p "$o"; cp -R "$TMP/$s/." "$o/"; }
done
echo "✓ updated"'
```

Workflows preserved. The Codex/Open Agent skill is refreshed at `.agents/skills/orchestra` when present in the source.
