#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOOP_SCRIPT="$PROJECT_ROOT/scripts/task-loop.sh"
WATCHDOG_STOP_FILE="$PROJECT_ROOT/.taskmaster/task-loop-watchdog.stop"
WATCHDOG_PID_FILE="$PROJECT_ROOT/.taskmaster/task-loop-watchdog.pid"
WATCHDOG_LOG_FILE="$PROJECT_ROOT/.taskmaster/task-loop-watchdog.out"
STATE_FILE="$PROJECT_ROOT/.taskmaster/task-loop-state.json"
CHECK_INTERVAL=30
MAX_RESTARTS=0
REQUEST_STOP=0
DAEMONIZE=0
STATUS_ONLY=0
RESTART_COUNT=0
BASE_LOOP_ARGS=(--auto --allow-dirty --codex-danger-full-access)
EXTRA_LOOP_ARGS=()

usage() {
  cat <<'USAGE'
Usage: scripts/task-loop-watchdog.sh [options]

Monitor TaskMaster loop execution and restart it when it stops unexpectedly.

Options:
  --interval <seconds>   Check interval between health checks (default: 30)
  --max-restarts <n>     Max restart attempts on failure (0 = unlimited)
  --daemon               Run watchdog in background and return immediately
  --status               Print watchdog/loop/state status and exit
  --request-stop         Gracefully stop running loop and stop watchdog
  --loop-arg <value>     Extra argument forwarded to scripts/task-loop.sh
  -h, --help             Show this help

Examples:
  ./scripts/task-loop-watchdog.sh --daemon
  ./scripts/task-loop-watchdog.sh --status
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
    --daemon)
      DAEMONIZE=1
      shift
      ;;
    --status)
      STATUS_ONLY=1
      shift
      ;;
    --request-stop)
      REQUEST_STOP=1
      shift
      ;;
    --loop-arg)
      EXTRA_LOOP_ARGS+=("${2:-}")
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

watchdog_pids() {
  local raw
  raw="$(pgrep -f "scripts/task-loop-watchdog.sh" || true)"
  if [[ -z "$raw" ]]; then
    return 0
  fi
  while IFS= read -r pid; do
    if [[ -n "$pid" ]] && [[ "$pid" != "$$" ]]; then
      printf '%s\n' "$pid"
    fi
  done <<<"$raw"
}

loop_pids() {
  pgrep -f "scripts/task-loop.sh --auto" || true
}

watchdog_pidfile_pid() {
  if [[ ! -f "$WATCHDOG_PID_FILE" ]]; then
    return 1
  fi

  local pid
  pid="$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]] || [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  printf '%s\n' "$pid"
}

watchdog_pidfile_running() {
  local pid
  if ! pid="$(watchdog_pidfile_pid)"; then
    return 1
  fi

  ps -p "$pid" >/dev/null 2>&1
}

has_work_remaining() {
  local out remaining

  if [[ -s "$STATE_FILE" ]]; then
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

status_report() {
  local watchdog_pidfile loop_running current_epoch state_mtime state_age

  echo "watchdog.pid_file: $WATCHDOG_PID_FILE"
  if watchdog_pidfile_running; then
    watchdog_pidfile="$(watchdog_pidfile_pid)"
    echo "watchdog.status: running (pid=$watchdog_pidfile)"
  else
    if [[ -f "$WATCHDOG_PID_FILE" ]]; then
      echo "watchdog.status: stale pid file"
    else
      echo "watchdog.status: not running"
    fi
  fi

  echo "watchdog.extra_pids: $(watchdog_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

  loop_running="$(loop_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ -n "$loop_running" ]]; then
    echo "loop.status: running (pid=${loop_running})"
  else
    echo "loop.status: not running"
  fi

  if [[ -f "$STATE_FILE" ]]; then
    current_epoch="$(date +%s)"
    state_mtime="$(stat -f %m "$STATE_FILE" 2>/dev/null || echo 0)"
    if [[ "$state_mtime" =~ ^[0-9]+$ ]] && [[ "$state_mtime" -gt 0 ]]; then
      state_age=$((current_epoch - state_mtime))
      echo "loop.state_file_age_seconds: $state_age"
    fi
    echo "loop.state:"
    cat "$STATE_FILE"
  else
    echo "loop.state: none"
  fi

  if [[ -f "$STATE_FILE" ]] && [[ -z "$loop_running" ]]; then
    echo "loop.health_hint: state exists but loop is not running (recoverable; restart watchdog/loop)"
  fi
}

start_daemon() {
  local cmd=("$0" "--interval" "$CHECK_INTERVAL" "--max-restarts" "$MAX_RESTARTS")
  local existing

  if watchdog_pidfile_running; then
    echo "Watchdog already running (pid=$(watchdog_pidfile_pid))."
    return 0
  fi

  existing="$(watchdog_pids | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [[ -n "$existing" ]]; then
    echo "Watchdog appears to already be running (pids=$existing)."
    return 0
  fi

  for arg in "${EXTRA_LOOP_ARGS[@]-}"; do
    if [[ -z "$arg" ]]; then
      continue
    fi
    cmd+=("--loop-arg" "$arg")
  done

  nohup "${cmd[@]}" >>"$WATCHDOG_LOG_FILE" 2>&1 &
  echo "$!" >"$WATCHDOG_PID_FILE"
  echo "Watchdog started in background (pid=$!)."
  echo "Log: $WATCHDOG_LOG_FILE"
}

if [[ "$REQUEST_STOP" -eq 1 ]]; then
  touch "$WATCHDOG_STOP_FILE"
  graceful_stop_loop
  log "Watchdog stop requested: $WATCHDOG_STOP_FILE"
  exit 0
fi

if [[ "$STATUS_ONLY" -eq 1 ]]; then
  status_report
  exit 0
fi

if [[ "$DAEMONIZE" -eq 1 ]]; then
  start_daemon
  exit 0
fi

cleanup_watchdog_pid() {
  if [[ -f "$WATCHDOG_PID_FILE" ]]; then
    local current
    current="$(cat "$WATCHDOG_PID_FILE" 2>/dev/null || true)"
    if [[ "$current" == "$$" ]]; then
      rm -f "$WATCHDOG_PID_FILE"
    fi
  fi
}
trap cleanup_watchdog_pid EXIT
echo "$$" >"$WATCHDOG_PID_FILE"

LOOP_ARGS=("${BASE_LOOP_ARGS[@]}")
for arg in "${EXTRA_LOOP_ARGS[@]-}"; do
  if [[ -z "$arg" ]]; then
    continue
  fi
  LOOP_ARGS+=("$arg")
done
log "Watchdog started (interval=${CHECK_INTERVAL}s, max_restarts=${MAX_RESTARTS})."
log "Watchdog using loop args: ${LOOP_ARGS[*]}"

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
