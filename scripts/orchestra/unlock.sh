#!/bin/bash
# Release workflow lock if held by the given actor.
# Usage: bash .orchestra/scripts/orchestra/unlock.sh <actor> [--token <token>]
# Always exits 0 (releasing a lock you don't own is a no-op, not an error).

set -euo pipefail

SCRIPT_DIR="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-utils.sh"

ACTOR="${1:-unknown}"
shift || true
TOKEN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) TOKEN="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: unlock.sh <actor> [--token <token>]"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

LOCK_FILE="$WORKFLOW_DIR/.lock"

if [[ ! -f "$LOCK_FILE" ]]; then
  exit 0
fi

HELD_BY=$(jq -r '.actor // "unknown"' "$LOCK_FILE" 2>/dev/null || echo "unknown")
HELD_TOKEN=$(jq -r '.token // ""' "$LOCK_FILE" 2>/dev/null || echo "")

if [[ "$HELD_BY" == "$ACTOR" && "$HELD_TOKEN" == "$TOKEN" ]]; then
  rm -f "$LOCK_FILE"
  echo "lock released: $ACTOR"
else
  echo "warn: lock held by another owner; not releasing" >&2
fi
