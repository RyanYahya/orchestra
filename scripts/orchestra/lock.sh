#!/bin/bash
# Acquire workflow lock for a given actor.
# Usage: bash .orchestra/scripts/orchestra/lock.sh <actor>
# Exits 0 if lock acquired (or already ours), 1 if held by another actor.
# Stale locks (older than ORCH_LOCK_TTL seconds, default 3600) auto-release.

set -euo pipefail

SCRIPT_DIR="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-utils.sh"

ACTOR="${1:-unknown}"
TTL="${ORCH_LOCK_TTL:-3600}"
LOCK_FILE="$WORKFLOW_DIR/.lock"

mkdir -p "$WORKFLOW_DIR"

NOW_EPOCH=$(date +%s)

if [[ -f "$LOCK_FILE" ]]; then
  HELD_BY=$(jq -r '.actor // "unknown"' "$LOCK_FILE" 2>/dev/null || echo "unknown")
  STARTED_EPOCH=$(jq -r '.startedEpoch // 0' "$LOCK_FILE" 2>/dev/null || echo 0)

  if [[ "$HELD_BY" != "$ACTOR" ]]; then
    AGE=$(( NOW_EPOCH - STARTED_EPOCH ))
    if [[ $AGE -lt $TTL ]]; then
      STARTED_HUMAN=$(jq -r '.started // ""' "$LOCK_FILE" 2>/dev/null || echo "")
      echo "ERROR: workflow locked by '$HELD_BY' since $STARTED_HUMAN (age ${AGE}s)" >&2
      echo "       Set ORCH_LOCK_TTL or remove .orchestra/workflows/current/.lock if stuck." >&2
      exit 1
    fi
    echo "warn: stale lock from '$HELD_BY' (age ${AGE}s); releasing" >&2
  fi
fi

cat > "$LOCK_FILE" <<EOF
{
  "actor": "$ACTOR",
  "pid": $$,
  "started": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "startedEpoch": $NOW_EPOCH,
  "host": "$(hostname -s 2>/dev/null || hostname)"
}
EOF

echo "lock acquired: $ACTOR"
