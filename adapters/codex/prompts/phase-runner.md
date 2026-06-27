---
description: Orchestra phase-runner - bootstrap Orchestra into this project
---

Set up the orchestra workflow system in the current project.

Run:

```
bash -c '
set -e
if [[ -d .orchestra/scripts && -f .orchestra/scripts/phase-runner.sh ]]; then
  echo "✓ orchestra core already installed; refreshing any missing adapters/skills"
fi
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
git clone --depth 1 https://github.com/RyanYahya/orchestra "$TMP" >/dev/null 2>&1
bash "$TMP/install.sh" --source "$TMP" --target "$(pwd)"
'
```

After install, available commands in Codex: `$orchestra plan`, `$orchestra plan-advanced`, `$orchestra execute`, `$orchestra execute all`, `$orchestra resolve`, `$orchestra revise`, `$orchestra archive`. If `.codex/prompts/` adapters are installed, `/orchestra plan`, `/orchestra execute`, and `/orchestra execute all` are compatibility aliases.

In-app autopilot: `$orchestra execute all`.

Terminal autopilot: `bash .orchestra/scripts/phase-runner.sh --engine codex` from a terminal, or omit `--engine` to auto-select the available CLI.
