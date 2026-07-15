#!/bin/bash
# Durable state and lock ownership for Codex app phase-to-task handoffs.
# Usage: autopilot-state.sh start|state|phase-complete|prepare|activate|resume|cancel|stop|finish ...

set -euo pipefail

SCRIPT_DIR="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-utils.sh"

usage() {
  cat <<'EOF'
usage:
  autopilot-state.sh start [max-phases]
  autopilot-state.sh state
  autopilot-state.sh phase-complete <owner-token> <phase-id>
  autopilot-state.sh prepare <owner-token> <next-phase-id>
  autopilot-state.sh activate <owner-token> <next-owner-token> <thread-id>
  autopilot-state.sh resume <owner-token>
  autopilot-state.sh cancel <owner-token> <next-owner-token> <reason>
  autopilot-state.sh stop <owner-token> <reason>
  autopilot-state.sh finish <owner-token>
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

new_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    printf '%s-%s-%s\n' "$(date +%s)" "$$" "${RANDOM:-0}"
  fi
}

write_status() {
  local filter="$1"
  shift
  jq "$@" "$filter" "$STATUS_FILE" > "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

state_json() {
  jq -c '.autopilot // empty' "$STATUS_FILE"
}

owner_actor() {
  jq -r '.autopilot.ownerActor // ""' "$STATUS_FILE"
}

owner_token() {
  jq -r '.autopilot.ownerToken // ""' "$STATUS_FILE"
}

assert_owner() {
  local token="$1" actor held_actor held_token
  [[ "$(jq -r '.autopilot.status // ""' "$STATUS_FILE")" == "running" ]] || fail "no running Codex autopilot"
  [[ "$(owner_token)" == "$token" ]] || fail "autopilot ownership has moved to another task"
  actor="$(owner_actor)"
  [[ -f "$LOCK_FILE" ]] || fail "workflow lock is missing"
  held_actor=$(jq -r '.actor // ""' "$LOCK_FILE")
  held_token=$(jq -r '.token // ""' "$LOCK_FILE")
  [[ "$held_actor" == "$actor" && "$held_token" == "$token" ]] || fail "workflow lock is held by another owner"
}

transfer_lock() {
  local from_token="$1" to_actor="$2" to_token="$3" now_epoch tmp
  assert_owner "$from_token"
  now_epoch=$(date +%s)
  tmp="$LOCK_FILE.tmp"
  jq --arg actor "$to_actor" --arg token "$to_token" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson epoch "$now_epoch" --arg host "$(hostname -s 2>/dev/null || hostname)" '
      .actor = $actor
      | .token = $token
      | .pid = null
      | .started = $started
      | .startedEpoch = $epoch
      | .host = $host
    ' "$LOCK_FILE" > "$tmp"
  mv "$tmp" "$LOCK_FILE"
}

workflow_exists || fail "no active workflow"
command -v jq >/dev/null 2>&1 || fail "jq is required"

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  start)
    MAX_PHASES="${1:-50}"
    [[ "$MAX_PHASES" =~ ^[1-9][0-9]*$ ]] || fail "max phases must be a positive integer"
    [[ "$(jq -r '.planApproved // false' "$STATUS_FILE")" == "true" ]] || fail "workflow plan is not approved"
    [[ "$(jq -r '.status // ""' "$STATUS_FILE")" != "COMPLETED" ]] || fail "workflow is already completed"
    jq -e 'any(.phases[]?; .status != "completed")' "$STATUS_FILE" >/dev/null || fail "workflow has no pending phases"

    if [[ "$(jq -r '.autopilot.status // ""' "$STATUS_FILE")" == "running" ]]; then
      fail "a Codex execute-all autopilot is already running under $(owner_actor)"
    fi

    RUN_ID="$(new_id)"
    TOKEN="$(new_id)"
    ACTOR="codex-execute-all:$RUN_ID"
    bash "$SCRIPT_DIR/lock.sh" "$ACTOR" --token "$TOKEN" >/dev/null
    TS="$(get_timestamp)"
    write_status '
      .autopilot = {
        status: "running",
        runId: $run,
        maxPhases: $max,
        completedPhases: [],
        phasesCompleted: 0,
        ownerActor: $actor,
        ownerToken: $token,
        handoffs: [],
        startedAt: $ts,
        lastUpdated: $ts
      }
      | .log += [{time: $ts, actor: $actor, action: "Codex execute-all autopilot started"}]
    ' --arg run "$RUN_ID" --argjson max "$MAX_PHASES" --arg actor "$ACTOR" --arg token "$TOKEN" --arg ts "$TS"
    state_json
    ;;

  state)
    state_json
    ;;

  phase-complete)
    TOKEN="${1:-}"
    PHASE_ID="${2:-}"
    [[ -n "$TOKEN" && -n "$PHASE_ID" ]] || { usage; exit 1; }
    assert_owner "$TOKEN"
    jq -e --arg id "$PHASE_ID" 'any(.phases[]?; .id == $id and .status == "completed")' "$STATUS_FILE" >/dev/null \
      || fail "$PHASE_ID is not completed in status.json"
    TS="$(get_timestamp)"
    write_status '
      .autopilot.completedPhases = ((.autopilot.completedPhases + [$phase]) | unique)
      | .autopilot.phasesCompleted = (.autopilot.completedPhases | length)
      | .autopilot.lastUpdated = $ts
    ' --arg phase "$PHASE_ID" --arg ts "$TS"
    state_json
    ;;

  prepare)
    TOKEN="${1:-}"
    NEXT_PHASE="${2:-}"
    [[ -n "$TOKEN" && -n "$NEXT_PHASE" ]] || { usage; exit 1; }
    assert_owner "$TOKEN"
    [[ "$(jq -r '.autopilot.pendingHandoff // null' "$STATUS_FILE")" == "null" ]] \
      || fail "a handoff is already prepared"
    jq -e --arg id "$NEXT_PHASE" 'any(.phases[]?; .id == $id and .status != "completed")' "$STATUS_FILE" >/dev/null \
      || fail "$NEXT_PHASE is not a pending phase"
    [[ "$(jq -r '.autopilot.phasesCompleted < .autopilot.maxPhases' "$STATUS_FILE")" == "true" ]] \
      || fail "autopilot phase limit reached"
    NEXT_TOKEN="$(new_id)"
    RUN_ID="$(jq -r '.autopilot.runId' "$STATUS_FILE")"
    NEXT_ACTOR="codex-execute-all:$RUN_ID:$NEXT_PHASE"
    TS="$(get_timestamp)"
    write_status '
      .autopilot.pendingHandoff = {
        state: "prepared",
        nextPhase: $phase,
        actor: $actor,
        token: $token,
        createdAt: $ts
      }
      | .autopilot.lastUpdated = $ts
    ' --arg phase "$NEXT_PHASE" --arg actor "$NEXT_ACTOR" --arg token "$NEXT_TOKEN" --arg ts "$TS"
    jq -c '.autopilot.pendingHandoff' "$STATUS_FILE"
    ;;

  activate)
    TOKEN="${1:-}"
    NEXT_TOKEN="${2:-}"
    THREAD_ID="${3:-}"
    [[ -n "$TOKEN" && -n "$NEXT_TOKEN" && -n "$THREAD_ID" ]] || { usage; exit 1; }
    assert_owner "$TOKEN"
    [[ "$(jq -r '.autopilot.pendingHandoff.token // ""' "$STATUS_FILE")" == "$NEXT_TOKEN" ]] \
      || fail "handoff token does not match the prepared handoff"
    [[ "$(jq -r '.autopilot.pendingHandoff.state // ""' "$STATUS_FILE")" == "prepared" ]] \
      || fail "handoff is not ready to activate"
    NEXT_ACTOR="$(jq -r '.autopilot.pendingHandoff.actor' "$STATUS_FILE")"
    TS="$(get_timestamp)"
    jq --arg thread "$THREAD_ID" --arg ts "$TS" --arg actor "$NEXT_ACTOR" '
      .autopilot.pendingHandoff.state = "active"
      | .autopilot.pendingHandoff.threadId = $thread
      | .autopilot.pendingHandoff.activatedAt = $ts
      | .autopilot.handoffs += [.autopilot.pendingHandoff]
      | .autopilot.ownerActor = .autopilot.pendingHandoff.actor
      | .autopilot.ownerToken = .autopilot.pendingHandoff.token
      | .autopilot.pendingHandoff = null
      | .autopilot.lastUpdated = $ts
      | .log += [{time: $ts, actor: $actor, action: ("Autopilot handed off to Codex task " + $thread)}]
    ' "$STATUS_FILE" > "$STATUS_FILE.tmp"
    transfer_lock "$TOKEN" "$NEXT_ACTOR" "$NEXT_TOKEN"
    mv "$STATUS_FILE.tmp" "$STATUS_FILE"
    state_json
    ;;

  resume)
    TOKEN="${1:-}"
    [[ -n "$TOKEN" ]] || { usage; exit 1; }
    assert_owner "$TOKEN"
    TS="$(get_timestamp)"
    write_status '
      if (.autopilot.handoffs | length) > 0 then
        .autopilot.handoffs[-1].state = "claimed"
        | .autopilot.handoffs[-1].claimedAt = $ts
        | .autopilot.lastUpdated = $ts
      else . end
    ' --arg ts "$TS"
    state_json
    ;;

  cancel)
    TOKEN="${1:-}"
    NEXT_TOKEN="${2:-}"
    REASON="${3:-fresh Codex task creation unavailable}"
    [[ -n "$TOKEN" && -n "$NEXT_TOKEN" ]] || { usage; exit 1; }
    assert_owner "$TOKEN"
    [[ "$(jq -r '.autopilot.pendingHandoff.token // ""' "$STATUS_FILE")" == "$NEXT_TOKEN" ]] \
      || fail "handoff token does not match the prepared handoff"
    TS="$(get_timestamp)"
    write_status '
      .autopilot.pendingHandoff.state = "cancelled"
      | .autopilot.pendingHandoff.reason = $reason
      | .autopilot.pendingHandoff.cancelledAt = $ts
      | .autopilot.handoffs += [.autopilot.pendingHandoff]
      | .autopilot.pendingHandoff = null
      | .autopilot.lastUpdated = $ts
    ' --arg reason "$REASON" --arg ts "$TS"
    state_json
    ;;

  stop)
    TOKEN="${1:-}"
    REASON="${2:-autopilot stopped}"
    [[ -n "$TOKEN" ]] || { usage; exit 1; }
    assert_owner "$TOKEN"
    ACTOR="$(owner_actor)"
    TS="$(get_timestamp)"
    write_status '
      .autopilot.status = "stopped"
      | .autopilot.stopReason = $reason
      | .autopilot.stoppedAt = $ts
      | .autopilot.lastUpdated = $ts
      | .log += [{time: $ts, actor: $actor, action: ("Codex execute-all autopilot stopped: " + $reason)}]
    ' --arg reason "$REASON" --arg ts "$TS" --arg actor "$ACTOR"
    bash "$SCRIPT_DIR/unlock.sh" "$ACTOR" --token "$TOKEN" >/dev/null
    state_json
    ;;

  finish)
    TOKEN="${1:-}"
    [[ -n "$TOKEN" ]] || { usage; exit 1; }
    assert_owner "$TOKEN"
    [[ "$(jq -r '.status // ""' "$STATUS_FILE")" == "COMPLETED" ]] || fail "workflow is not completed; use stop instead"
    ACTOR="$(owner_actor)"
    TS="$(get_timestamp)"
    write_status '
      .autopilot.status = "completed"
      | .autopilot.finishedAt = $ts
      | .autopilot.lastUpdated = $ts
      | .log += [{time: $ts, actor: $actor, action: "Codex execute-all autopilot finished"}]
    ' --arg ts "$TS" --arg actor "$ACTOR"
    bash "$SCRIPT_DIR/unlock.sh" "$ACTOR" --token "$TOKEN" >/dev/null
    state_json
    ;;

  -h|--help|help)
    usage
    ;;

  *)
    usage >&2
    exit 1
    ;;
esac
