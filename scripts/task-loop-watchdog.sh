#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP_SCRIPT="$PROJECT_ROOT/scripts/task-loop.sh"
WATCHDOG_STOP_FILE="$PROJECT_ROOT/.taskmaster/task-loop-watchdog.stop"
CHECK_INTERVAL=30
MAX_RESTARTS=0
REQUEST_STOP=0
RESTART_COUNT=0
LOOP_ARGS=(--auto --allow-dirty --codex-danger-full-access)

usage() {
  cat <<'USAGE'
Usage: scripts/task-loop-watchdog.sh [options]

Monitor TaskMaster loop execution and restart it when it stops unexpectedly.

Options:
  --interval <seconds>   Check interval between health checks (default: 30)
  --max-restarts <n>     Max restart attempts on failure (0 = unlimited)
  --request-stop         Gracefully stop running loop and stop watchdog
  --loop-arg <value>     Extra argument forwarded to scripts/task-loop.sh
  -h, --help             Show this help

Examples:
  ./scripts/task-loop-watchdog.sh
  ./scripts/task-loop-watchdog.sh --interval 20
  ./scripts/task-loop-watchdog.sh --loop-arg "--model" --loop-arg "gpt-5.3-codex"
  ./scripts/task-loop-watchdog.sh --request-stop
USAGE
}

log() {
  printf '[%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      CHECK_INTERVAL="${2:-}"
      shift 2
      ;;
    --max-restarts)
      MAX_RESTARTS="${2:-}"
      shift 2
      ;;
    --request-stop)
      REQUEST_STOP=1
      shift
      ;;
    --loop-arg)
      LOOP_ARGS+=("${2:-}")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! "$CHECK_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$CHECK_INTERVAL" -lt 1 ]]; then
  echo "--interval must be a positive integer" >&2
  exit 1
fi

if [[ ! "$MAX_RESTARTS" =~ ^[0-9]+$ ]]; then
  echo "--max-restarts must be an integer >= 0" >&2
  exit 1
fi

if [[ ! -x "$LOOP_SCRIPT" ]]; then
  echo "Loop script not found or not executable: $LOOP_SCRIPT" >&2
  exit 1
fi

mkdir -p "$PROJECT_ROOT/.taskmaster"

loop_pids() {
  pgrep -f "scripts/task-loop.sh --auto" || true
}

has_work_remaining() {
  local out remaining

  if [[ -s "$PROJECT_ROOT/.taskmaster/task-loop-state.json" ]]; then
    return 0
  fi

  out="$(cd "$PROJECT_ROOT" && task-master list --format json 2>/dev/null || true)"
  remaining="$(
    jq -r '
      [
        .tasks[]?
        | select(.status == "pending" or .status == "in-progress")
      ] | length
    ' <<<"$out" 2>/dev/null || echo 0
  )"

  [[ "$remaining" =~ ^[0-9]+$ ]] && [[ "$remaining" -gt 0 ]]
}

graceful_stop_loop() {
  if [[ -n "$(loop_pids)" ]]; then
    log "Requesting graceful stop on running task loop."
    (cd "$PROJECT_ROOT" && "$LOOP_SCRIPT" --request-stop >/dev/null 2>&1 || true)
  fi
}

if [[ "$REQUEST_STOP" -eq 1 ]]; then
  touch "$WATCHDOG_STOP_FILE"
  graceful_stop_loop
  log "Watchdog stop requested: $WATCHDOG_STOP_FILE"
  exit 0
fi

log "Watchdog started (interval=${CHECK_INTERVAL}s, max_restarts=${MAX_RESTARTS}, loop_args=${LOOP_ARGS[*]})."

while true; do
  if [[ -f "$WATCHDOG_STOP_FILE" ]]; then
    graceful_stop_loop
    rm -f "$WATCHDOG_STOP_FILE"
    log "Watchdog stop file consumed. Exiting."
    exit 0
  fi

  running_pids="$(loop_pids)"
  if [[ -n "$running_pids" ]]; then
    sleep "$CHECK_INTERVAL"
    continue
  fi

  if ! has_work_remaining; then
    log "No available tasks. Watchdog exiting."
    exit 0
  fi

  log "Task loop not running. Starting: $LOOP_SCRIPT ${LOOP_ARGS[*]}"
  set +e
  (cd "$PROJECT_ROOT" && "$LOOP_SCRIPT" "${LOOP_ARGS[@]}")
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    if has_work_remaining; then
      log "Loop exited with code 0 but tasks remain. Restarting after ${CHECK_INTERVAL}s."
      sleep "$CHECK_INTERVAL"
      continue
    fi
    log "Loop exited cleanly and no tasks remain. Watchdog exiting."
    exit 0
  fi

  RESTART_COUNT=$((RESTART_COUNT + 1))
  log "Loop exited with code $rc. Restart attempt ${RESTART_COUNT}."
  if [[ "$MAX_RESTARTS" -gt 0 ]] && [[ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]]; then
    log "Reached max restarts ($MAX_RESTARTS). Exiting watchdog."
    exit 1
  fi

  sleep "$CHECK_INTERVAL"
done
