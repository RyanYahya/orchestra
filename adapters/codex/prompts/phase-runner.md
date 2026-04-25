Set up the orchestra workflow system in the current project.

Run:

```
bash -c '
set -e
if [[ -d .orchestra/scripts && -f .orchestra/scripts/phase-runner.sh ]]; then
  echo "✓ already installed"; exit 0
fi
TMP=$(mktemp -d); trap "rm -rf $TMP" EXIT
git clone --depth 1 https://github.com/RyanYahya/orchestra "$TMP" >/dev/null 2>&1
bash "$TMP/install.sh" --source "$TMP" --target "$(pwd)"
'
```

After install, available commands: /plan, /plan-advanced, /execute, /resolve, /revise, /archive. Autonomous: `bash .orchestra/scripts/phase-runner.sh` from a terminal.
