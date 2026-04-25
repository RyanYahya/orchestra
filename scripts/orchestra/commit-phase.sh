#!/bin/bash
# Commit work for a completed phase and record the SHA in status.json.
# Usage: bash .orchestra/scripts/orchestra/commit-phase.sh <phase-id> [extra message]
#
# Stages all tracked + new files (`git add -A`), creates a commit with a
# structured message, and stores the SHA in status.json under git.phaseCommits[<id>].

set -euo pipefail

SCRIPT_DIR="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-utils.sh"

PHASE_ID="${1:-}"
EXTRA_MSG="${2:-}"

[[ -n "$PHASE_ID" ]] || { echo "usage: commit-phase.sh <phase-id> [extra message]" >&2; exit 1; }
workflow_exists || { echo "ERROR: no active workflow" >&2; exit 1; }

if ! command -v git >/dev/null 2>&1 || ! git -C "$PROJECT_ROOT" rev-parse >/dev/null 2>&1; then
  echo "warn: not a git repo; skipping commit" >&2
  exit 0
fi

cd "$PROJECT_ROOT"

# Look up phase name
PHASE_NAME=$(jq -r --arg id "$PHASE_ID" '.phases[] | select(.id == $id) | .name' "$STATUS_FILE")
[[ -n "$PHASE_NAME" ]] || { echo "ERROR: phase $PHASE_ID not found in status.json" >&2; exit 1; }

TASK=$(get_task_name)

git add -A

if git diff --cached --quiet; then
  echo "no staged changes for $PHASE_ID; skipping commit"
  exit 0
fi

MSG="orchestra($PHASE_ID): $PHASE_NAME"
if [[ -n "$EXTRA_MSG" ]]; then
  MSG="$MSG

$EXTRA_MSG"
fi
MSG="$MSG

Workflow: $TASK
Phase: $PHASE_ID — $PHASE_NAME"

git commit -m "$MSG" >/dev/null
SHA=$(git rev-parse HEAD)

# Record SHA in status.json under git.phaseCommits[<id>]
jq --arg id "$PHASE_ID" --arg sha "$SHA" --arg ts "$(get_timestamp)" '
  .git = (.git // {})
  | .git.phaseCommits = (.git.phaseCommits // {})
  | .git.phaseCommits[$id] = $sha
  | .lastUpdated = $ts
  | .log += [{"time": $ts, "actor": "git", "action": "commit \($sha[0:7]) for \($id)"}]
' "$STATUS_FILE" > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"

echo "committed $SHA for $PHASE_ID"
