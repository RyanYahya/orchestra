#!/bin/bash
# Initialize a new workflow: status.json + Plan.md skeleton + decisions.json + Implementation_Notes.md.
# Plan.md is the source of truth for phase/step structure; status.json tracks done/log/git.
# decisions.json is the canonical decision store; Decisions.md is rendered from it.

set -euo pipefail

SCRIPT_DIR="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-utils.sh"

TASK_NAME="${1:-}"

if [[ -z "$TASK_NAME" ]]; then
  echo "ERROR: Task name required" >&2
  exit 1
fi

if workflow_exists; then
  echo "ERROR: Active workflow exists: $(get_task_name)" >&2
  echo "       Archive (/orchestra:archive) or clear it first." >&2
  exit 1
fi

mkdir -p "$WORKFLOW_DIR"
TIMESTAMP=$(get_timestamp)
ISO_TS=$(get_iso_timestamp)
BRANCH=$(get_git_branch || true)
BASE_BRANCH=$(get_git_base_branch || true)

# status.json — single source of truth for execution state.
cat > "$STATUS_FILE" <<EOF
{
  "task": "$TASK_NAME",
  "status": "RESEARCH",
  "currentPhase": 0,
  "totalPhases": 0,
  "lastUpdated": "$TIMESTAMP",
  "createdAt": "$ISO_TS",
  "planApproved": false,
  "phases": [],
  "git": {
    "branch": "${BRANCH:-}",
    "baseBranch": "${BASE_BRANCH:-}",
    "phaseCommits": {}
  },
  "log": [
    { "time": "$TIMESTAMP", "actor": "system", "action": "Workflow initialized" }
  ]
}
EOF

# Implementation_Notes.md — populated dynamically.
cat > "$WORKFLOW_DIR/Implementation_Notes.md" <<EOF
# Implementation Notes

> Task: $TASK_NAME
> Created: $TIMESTAMP

_Populated during research. Add sections as agents complete; structure is free-form._

## Findings

EOF

# Plan.md — the source of truth for phases and steps.
cat > "$WORKFLOW_DIR/Plan.md" <<'PLAN_EOF'
# Implementation Plan

> Task: __TASK__
> Created: __TIMESTAMP__

## Overview

_Summary of implementation_

## Prerequisites

_What must exist first_

## Phases

<!--
PHASE FORMAT (parsed by parse-plan.sh — keep strict):

### Phase 1: Phase Name

**Steps:**
1. First step description
2. Second step description

**Verify:**
- Manual: Human verification instructions
- Auto: `optional-shell-command-to-verify`

The Auto line is optional. Phase IDs (P1, P2, ...) and step IDs (P1.S1, P1.S2, ...)
are positional. Reordering steps will reset their `done` flags.
-->

### Phase 1: [Name]

**Steps:**
1. Step description (file: `path/to/file.ts`, action: create|modify)

**Verify:**
- Manual: What to do, what to expect
- Auto: `optional-command`

PLAN_EOF

# Substitute placeholders (BSD/GNU sed compatible)
if sed --version >/dev/null 2>&1; then
  sed -i "s|__TASK__|$TASK_NAME|g; s|__TIMESTAMP__|$TIMESTAMP|g" "$WORKFLOW_DIR/Plan.md"
else
  sed -i '' "s|__TASK__|$TASK_NAME|g; s|__TIMESTAMP__|$TIMESTAMP|g" "$WORKFLOW_DIR/Plan.md"
fi

# decisions.json — canonical decision store
cat > "$WORKFLOW_DIR/decisions.json" <<EOF
{
  "task": "$TASK_NAME",
  "decisions": []
}
EOF

bash "$SCRIPT_DIR/render-decisions.sh" >/dev/null

echo "Workflow initialized: $TASK_NAME"
echo "  branch: ${BRANCH:-<not a git repo>}"
echo "  artifacts: $WORKFLOW_DIR"
