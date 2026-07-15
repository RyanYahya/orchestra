#!/bin/bash

set -euo pipefail

ROOT="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.orchestra/scripts/orchestra/lib" "$TMP/.orchestra/workflows/current"
cp "$ROOT/scripts/orchestra/autopilot-state.sh" "$TMP/.orchestra/scripts/orchestra/"
cp "$ROOT/scripts/orchestra/lock.sh" "$ROOT/scripts/orchestra/unlock.sh" "$TMP/.orchestra/scripts/orchestra/"
cp "$ROOT/scripts/orchestra/lib/workflow-utils.sh" "$TMP/.orchestra/scripts/orchestra/lib/"

cat > "$TMP/.orchestra/workflows/current/status.json" <<'EOF'
{
  "task": "Autopilot test",
  "status": "PENDING",
  "currentPhase": 1,
  "totalPhases": 2,
  "planApproved": true,
  "phases": [
    {"id": "P1", "status": "completed", "steps": []},
    {"id": "P2", "status": "pending", "steps": []}
  ],
  "log": []
}
EOF

RUNNER="$TMP/.orchestra/scripts/orchestra/autopilot-state.sh"

STARTED=$(bash "$RUNNER" start 2)
TOKEN=$(jq -r '.ownerToken' <<<"$STARTED")
ACTOR=$(jq -r '.ownerActor' <<<"$STARTED")
[[ -n "$TOKEN" && "$TOKEN" != "null" ]]
[[ "$(jq -r '.token' "$TMP/.orchestra/workflows/current/.lock")" == "$TOKEN" ]]
if bash "$RUNNER" start 2 >/dev/null 2>&1; then
  echo "a second autopilot started while the first was active" >&2
  exit 1
fi

bash "$RUNNER" phase-complete "$TOKEN" P1 >/dev/null
bash "$RUNNER" phase-complete "$TOKEN" P1 >/dev/null
[[ "$(jq -r '.autopilot.phasesCompleted' "$TMP/.orchestra/workflows/current/status.json")" == "1" ]]

PREPARED=$(bash "$RUNNER" prepare "$TOKEN" P2)
NEXT_TOKEN=$(jq -r '.token' <<<"$PREPARED")
if bash "$TMP/.orchestra/scripts/orchestra/lock.sh" "$ACTOR" --token wrong-token >/dev/null 2>&1; then
  echo "lock accepted a second owner with the same actor" >&2
  exit 1
fi
bash "$RUNNER" cancel "$TOKEN" "$NEXT_TOKEN" "test fallback" >/dev/null
[[ "$(jq -r '.token' "$TMP/.orchestra/workflows/current/.lock")" == "$TOKEN" ]]

PREPARED=$(bash "$RUNNER" prepare "$TOKEN" P2)
NEXT_TOKEN=$(jq -r '.token' <<<"$PREPARED")
NEXT_ACTOR=$(jq -r '.actor' <<<"$PREPARED")
bash "$RUNNER" activate "$TOKEN" "$NEXT_TOKEN" thread-p2 >/dev/null
[[ "$(jq -r '.actor' "$TMP/.orchestra/workflows/current/.lock")" == "$NEXT_ACTOR" ]]
[[ "$(jq -r '.autopilot.handoffs[-1].threadId' "$TMP/.orchestra/workflows/current/status.json")" == "thread-p2" ]]

if bash "$RUNNER" phase-complete "$TOKEN" P2 >/dev/null 2>&1; then
  echo "old owner retained access after handoff" >&2
  exit 1
fi

bash "$RUNNER" resume "$NEXT_TOKEN" >/dev/null
[[ "$(jq -r '.autopilot.handoffs[-1].state' "$TMP/.orchestra/workflows/current/status.json")" == "claimed" ]]

jq '(.phases[] | select(.id == "P2")).status = "completed" | .status = "COMPLETED"' \
  "$TMP/.orchestra/workflows/current/status.json" > "$TMP/status.tmp"
mv "$TMP/status.tmp" "$TMP/.orchestra/workflows/current/status.json"
bash "$RUNNER" phase-complete "$NEXT_TOKEN" P2 >/dev/null
bash "$RUNNER" finish "$NEXT_TOKEN" >/dev/null

[[ ! -e "$TMP/.orchestra/workflows/current/.lock" ]]
[[ "$(jq -r '.autopilot.status' "$TMP/.orchestra/workflows/current/status.json")" == "completed" ]]
[[ "$(jq -r '.autopilot.phasesCompleted' "$TMP/.orchestra/workflows/current/status.json")" == "2" ]]

LEGACY_LOCK="$TMP/.orchestra/scripts/orchestra/lock.sh"
LEGACY_UNLOCK="$TMP/.orchestra/scripts/orchestra/unlock.sh"
bash "$LEGACY_LOCK" legacy-owner >/dev/null
bash "$LEGACY_LOCK" legacy-owner >/dev/null
bash "$LEGACY_UNLOCK" legacy-owner >/dev/null
[[ ! -e "$TMP/.orchestra/workflows/current/.lock" ]]

jq '
  .status = "PENDING"
  | .phases[1].status = "pending"
  | .autopilot = null
' "$TMP/.orchestra/workflows/current/status.json" > "$TMP/status.tmp"
mv "$TMP/status.tmp" "$TMP/.orchestra/workflows/current/status.json"
LIMITED=$(bash "$RUNNER" start 1)
LIMITED_TOKEN=$(jq -r '.ownerToken' <<<"$LIMITED")
bash "$RUNNER" phase-complete "$LIMITED_TOKEN" P1 >/dev/null
if bash "$RUNNER" prepare "$LIMITED_TOKEN" P2 >/dev/null 2>&1; then
  echo "handoff prepared after the phase budget was exhausted" >&2
  exit 1
fi
bash "$RUNNER" stop "$LIMITED_TOKEN" "phase limit reached" >/dev/null
[[ ! -e "$TMP/.orchestra/workflows/current/.lock" ]]
[[ "$(jq -r '.autopilot.status' "$TMP/.orchestra/workflows/current/status.json")" == "stopped" ]]

echo "autopilot-state: PASS ($ACTOR -> $NEXT_ACTOR)"
