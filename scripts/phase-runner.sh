#!/bin/bash
# phase-runner.sh — Phase-by-phase executor with auto and manual modes.
# Launches a headless coding agent in a loop, one per phase, with fresh context each time.
# Supports Claude Code (`claude`) and Codex CLI (`codex exec`).
#
# Usage:
#   bash .orchestra/scripts/phase-runner.sh                  # auto mode (default)
#   bash .orchestra/scripts/phase-runner.sh --manual         # pause between phases
#   bash .orchestra/scripts/phase-runner.sh --manual 10      # manual + max 10 phases
#   bash .orchestra/scripts/phase-runner.sh 15               # auto + max 15 phases
#   bash .orchestra/scripts/phase-runner.sh --engine codex   # force Codex CLI
#   bash .orchestra/scripts/phase-runner.sh --engine claude  # force Claude Code

set -euo pipefail

# --- Parse arguments ---
MODE="auto"
MAX_PHASES=20
ENGINE="${ORCHESTRA_ENGINE:-auto}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manual) MODE="manual"; shift ;;
    --auto)   MODE="auto"; shift ;;
    --claude) ENGINE="claude"; shift ;;
    --codex)  ENGINE="codex"; shift ;;
    --engine)
      ENGINE="${2:-}"
      if [[ -z "$ENGINE" ]]; then
        echo "ERROR: --engine requires one of: auto, claude, codex" >&2
        exit 1
      fi
      shift 2
      ;;
    [0-9]*) MAX_PHASES="$1"; shift ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

# --- Configuration ---
WORKFLOW_DIR=".orchestra/workflows/current"
STATUS_FILE="$WORKFLOW_DIR/status.json"
COMMAND_FILE=".orchestra/prompts/execute-headless.md"
LOG_FILE="/tmp/phase-runner.log"
NOTIFY_SCRIPT=".orchestra/scripts/orchestra/notify.sh"

# --- Helpers ---
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() {
  echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

divider() {
  echo "========================================" | tee -a "$LOG_FILE"
}

get_status() {
  jq -r '.status' "$STATUS_FILE"
}

get_task() {
  jq -r '.task' "$STATUS_FILE"
}

get_current_phase_name() {
  local idx
  idx=$(jq -r '.currentPhase' "$STATUS_FILE")
  jq -r ".phases[$idx].name // \"Phase $((idx + 1))\"" "$STATUS_FILE"
}

get_progress() {
  local done total
  done=$(jq '[.phases[].steps[] | select(.done == true)] | length' "$STATUS_FILE")
  total=$(jq '[.phases[].steps[]] | length' "$STATUS_FILE")
  if [[ "$total" -eq 0 ]]; then
    echo "0"
  else
    echo $(( done * 100 / total ))
  fi
}

wait_for_keypress() {
  echo ""
  echo "Phase completed: $(get_current_phase_name)"
  echo "Progress: $(get_progress)%"
  echo ""
  echo "Press ENTER to continue to the next phase, or Ctrl+C to stop..."
  read -r
}

resolve_engine() {
  case "$ENGINE" in
    auto)
      if command -v claude &> /dev/null; then
        echo "claude"
      elif command -v codex &> /dev/null; then
        echo "codex"
      else
        echo "ERROR: neither 'claude' nor 'codex' CLI was found in PATH" >&2
        exit 1
      fi
      ;;
    claude|codex)
      echo "$ENGINE"
      ;;
    *)
      echo "ERROR: invalid engine '$ENGINE' (expected auto, claude, or codex)" >&2
      exit 1
      ;;
  esac
}

build_runner_prompt() {
  local host="$1"
  cat "$COMMAND_FILE"
  printf '\n\n---\n\n'
  if [[ "$host" == "claude" ]]; then
    printf 'Runner host: Claude Code CLI via phase-runner. Execute exactly one pending phase. When the prompt instructs termination, run `kill $PPID` so phase-runner can continue.\n'
  else
    printf 'Runner host: Codex CLI via `codex exec`. Execute exactly one pending phase. Do not run `kill $PPID`; finish with a concise final status so `codex exec` exits normally.\n'
  fi
}

# --- Pre-flight checks ---
if [ ! -f "$STATUS_FILE" ]; then
  echo "ERROR: No active workflow found at $STATUS_FILE"
  echo "Run '/orchestra:plan [task]' in Claude Code or '\$orchestra plan [task]' in Codex first to create a workflow."
  exit 1
fi

if [ ! -f "$COMMAND_FILE" ]; then
  echo "ERROR: Headless command not found at $COMMAND_FILE"
  exit 1
fi

ENGINE="$(resolve_engine)"

if ! command -v "$ENGINE" &> /dev/null; then
  echo "ERROR: '$ENGINE' CLI not found in PATH"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "ERROR: 'jq' not found in PATH. Install with: brew install jq"
  exit 1
fi

# --- Acquire workflow lock ---
ACTOR="phase-runner"
LOCK_SCRIPT=".orchestra/scripts/orchestra/lock.sh"
UNLOCK_SCRIPT=".orchestra/scripts/orchestra/unlock.sh"
if ! bash "$LOCK_SCRIPT" "$ACTOR"; then
  echo "ERROR: could not acquire workflow lock — another actor is active." >&2
  exit 1
fi
trap 'bash "$UNLOCK_SCRIPT" "$ACTOR" >/dev/null 2>&1 || true' EXIT

# --- Start ---
START_TIME=$(date +%s)

divider
log "Phase Runner started"
log "Task: $(get_task)"
log "Mode: $MODE"
log "Engine: $ENGINE"
log "Workflow: $WORKFLOW_DIR"
log "Max phases: $MAX_PHASES"
log "Log file: $LOG_FILE"
divider

PHASES_COMPLETED=0

for ((PHASE=1; PHASE<=MAX_PHASES; PHASE++)); do
  echo ""

  STATUS=$(get_status)

  # Check if workflow is complete
  if [[ "$STATUS" == "COMPLETED" ]]; then
    divider
    log "ALL PHASES COMPLETE ($(get_progress)%)"
    divider
    break
  fi

  # Check if workflow is blocked (audit failure)
  if [[ "$STATUS" == "BLOCKED" ]]; then
    divider
    log "WORKFLOW BLOCKED — audit issues need resolution"
    divider
    echo ""
    echo "The workflow is blocked due to audit failures."
    echo "Review the issues:  cat $WORKFLOW_DIR/Audit_Issues.md"
    echo ""
    echo "To fix interactively:"
    if [[ "$ENGINE" == "claude" ]]; then
      echo "  claude --dangerously-skip-permissions"
      echo "  Then: /orchestra:execute"
    else
      echo "  codex"
      echo "  Then: \$orchestra execute"
    fi
    echo ""
    echo "After fixing, update status.json (change BLOCKED → PENDING) and re-run:"
    echo "  bash .orchestra/scripts/phase-runner.sh"
    echo ""

    # Fire notification
    if [ -f "$NOTIFY_SCRIPT" ]; then
      bash "$NOTIFY_SCRIPT" "Workflow blocked — audit review needed"
    fi

    break
  fi

  log "--- Launching Phase $PHASE (progress: $(get_progress)%) ---"

  # Launch the selected engine with the headless command injected.
  EXIT_CODE=0
  RUNNER_PROMPT="$(build_runner_prompt "$ENGINE")"

  if [[ "$ENGINE" == "claude" ]]; then
    read -r -a CLAUDE_ARGS <<< "${ORCHESTRA_CLAUDE_FLAGS:---dangerously-skip-permissions}"
    claude "${CLAUDE_ARGS[@]}" \
      --append-system-prompt "$RUNNER_PROMPT" \
      "Execute the next pending phase now." || EXIT_CODE=$?
    log "Claude exited with code $EXIT_CODE"
  else
    read -r -a CODEX_ARGS <<< "${ORCHESTRA_CODEX_FLAGS:---dangerously-bypass-approvals-and-sandbox}"
    codex exec "${CODEX_ARGS[@]}" \
      --cd "$(pwd)" \
      "$RUNNER_PROMPT

Execute the next pending phase now." || EXIT_CODE=$?
    log "Codex exited with code $EXIT_CODE"
  fi

  if [[ "$EXIT_CODE" -ne 0 && "$ENGINE" == "codex" ]]; then
    log "Codex returned a non-zero exit code; stopping so the workflow can be inspected."
    exit "$EXIT_CODE"
  fi

  PHASES_COMPLETED=$((PHASES_COMPLETED + 1))

  # Notify after every phase
  if [ -f "$NOTIFY_SCRIPT" ]; then
    bash "$NOTIFY_SCRIPT" "Phase $PHASE complete ($(get_progress)%)"
  fi

  # --- Between-phase pause ---
  if [[ "$MODE" == "manual" ]]; then
    # Manual mode: wait for user to press Enter
    wait_for_keypress
  else
    # Auto mode: brief pause to let filesystem settle
    log "Waiting 3s before next phase..."
    sleep 3
  fi
done

# --- Summary ---
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
MINUTES=$(( ELAPSED / 60 ))
SECONDS=$(( ELAPSED % 60 ))

echo ""
divider
log "Phase Runner finished"
log "Mode: $MODE"
log "Phases completed: $PHASES_COMPLETED"
log "Total time: ${MINUTES}m ${SECONDS}s"
log "Log file: $LOG_FILE"

# Final status
STATUS=$(get_status)
if [[ "$STATUS" == "COMPLETED" ]]; then
  log "Result: SUCCESS — all phases completed"
  if [ -f "$NOTIFY_SCRIPT" ]; then
    bash "$NOTIFY_SCRIPT" "Workflow complete! All phases finished."
  fi
elif [[ "$STATUS" == "BLOCKED" ]]; then
  log "Result: BLOCKED — audit issues need resolution"
  log "See: $WORKFLOW_DIR/Audit_Issues.md"
elif [ "$PHASE" -gt "$MAX_PHASES" ]; then
  log "Result: SAFETY LIMIT — hit max phase limit ($MAX_PHASES)"
  if [ -f "$NOTIFY_SCRIPT" ]; then
    bash "$NOTIFY_SCRIPT" "Phase runner hit safety limit ($MAX_PHASES phases)"
  fi
fi

divider
