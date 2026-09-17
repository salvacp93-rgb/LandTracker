#!/usr/bin/env bash
# Launches a LandTracker subagent headlessly and reports its status to
# .claude/dashboard/status/ so dashboard.py can render it live.
#
# Usage: .claude/dashboard/run-agent.sh <agent-name> "<prompt>"
# Run it backgrounded (append `&`) to keep using the same terminal,
# or from its own terminal/pane while dashboard.py runs in another.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <agent-name> \"<prompt>\"" >&2
  exit 1
fi

AGENT="$1"
shift
PROMPT="$*"

DASH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_DIR="$DASH_DIR/status"
LOG_DIR="$DASH_DIR/logs"
mkdir -p "$STATUS_DIR" "$LOG_DIR"

RUN_ID="${AGENT}-$(date +%Y%m%d-%H%M%S)"
STATUS_FILE="$STATUS_DIR/$RUN_ID.json"
LOG_FILE="$LOG_DIR/$RUN_ID.log"
STARTED_AT=$(date +%s)

write_status() {
  local status="$1"
  local ended_at="${2:-}"
  python3 - "$STATUS_FILE" "$AGENT" "$status" "$STARTED_AT" "$ended_at" "$$" "$LOG_FILE" "$PROMPT" <<'PY'
import json, sys
path, agent, status, started_at, ended_at, pid, log_path, prompt = sys.argv[1:9]
json.dump({
    "agent": agent,
    "status": status,
    "started_at": float(started_at),
    "ended_at": float(ended_at) if ended_at else None,
    "pid": int(pid),
    "log_path": log_path,
    "task": prompt[:120],
}, open(path, "w"))
PY
}

write_status running

PROJECT_ROOT="$(cd "$DASH_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

if claude -p "$PROMPT" --agent "$AGENT" > "$LOG_FILE" 2>&1; then
  write_status done "$(date +%s)"
else
  write_status failed "$(date +%s)"
fi
