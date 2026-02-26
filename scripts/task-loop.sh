#!/usr/bin/env bash
set -euo pipefail

MODEL="gpt-5.3-codex"
VERIFY_CMD="npm run verify"
CODEX_SANDBOX="workspace-write"
TASK_ID=""
AUTO_MODE=0
ALLOW_DIRTY=0
REQUEST_STOP=0
NO_RESUME=0
STOP_AFTER_TASK=""
STATE_FILE=""
STOP_FILE=""
STOP_REQUESTED=0
CURRENT_TASK_RUNNING=0
RESUME_TASK_ID=""
COMMIT_EXCLUDES=(
  ":(exclude).taskmaster/task-loop-state.json"
  ":(exclude).taskmaster/tasks/tasks.json"
  ":(exclude).turbo"
)

usage() {
  cat <<'USAGE'
Usage: scripts/task-loop.sh [options]

Run TaskMaster tasks one-at-a-time with Codex, verify before completion, and
commit after each successful task.

Options:
  --task-id <id>         Work a specific task ID (for example: 1 or 2.3)
  --model <model>        Codex model to use (default: gpt-5.3-codex)
  --codex-sandbox <mode> Codex sandbox mode: read-only | workspace-write | danger-full-access
  --codex-danger-full-access
                         Shortcut for --codex-sandbox danger-full-access
  --verify-cmd <cmd>     Verify command to run before commit (default: npm run verify)
  --auto                 Keep processing next available tasks until exhausted
  --allow-dirty          Allow running with a dirty git working tree
  --request-stop         Request graceful stop for a running --auto loop
  --stop-after-task <id> Stop automatically after completing the given task id (for example: 8)
  --no-resume            Ignore existing task-loop resume state
  --state-file <path>    Override state file path
  --stop-file <path>     Override graceful-stop signal file path
  -h, --help             Show this help

Examples:
  scripts/task-loop.sh
  scripts/task-loop.sh --task-id 3 --verify-cmd "npm run test && npm run lint"
  scripts/task-loop.sh --auto
  scripts/task-loop.sh --auto --stop-after-task 8
  scripts/task-loop.sh --auto --codex-danger-full-access
  scripts/task-loop.sh --request-stop
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-id)
      TASK_ID="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    --codex-sandbox)
      CODEX_SANDBOX="${2:-}"
      shift 2
      ;;
    --codex-danger-full-access)
      CODEX_SANDBOX="danger-full-access"
      shift
      ;;
    --verify-cmd)
      VERIFY_CMD="${2:-}"
      shift 2
      ;;
    --auto)
      AUTO_MODE=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    --request-stop)
      REQUEST_STOP=1
      shift
      ;;
    --stop-after-task)
      STOP_AFTER_TASK="${2:-}"
      shift 2
      ;;
    --no-resume)
      NO_RESUME=1
      shift
      ;;
    --state-file)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --stop-file)
      STOP_FILE="${2:-}"
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

case "$CODEX_SANDBOX" in
  read-only|workspace-write|danger-full-access)
    ;;
  *)
    echo "Invalid --codex-sandbox value: $CODEX_SANDBOX" >&2
    echo "Expected one of: read-only, workspace-write, danger-full-access" >&2
    exit 1
    ;;
esac

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in task-master codex jq git; do
  require_cmd "$cmd"
done

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "This script must run inside a git repository." >&2
  exit 1
fi

cd "$PROJECT_ROOT"

STATE_FILE="${STATE_FILE:-$PROJECT_ROOT/.taskmaster/task-loop-state.json}"
STOP_FILE="${STOP_FILE:-$PROJECT_ROOT/.taskmaster/task-loop.stop}"

mkdir -p "$(dirname "$STATE_FILE")"
mkdir -p "$(dirname "$STOP_FILE")"

if [[ "$REQUEST_STOP" -eq 1 ]]; then
  touch "$STOP_FILE"
  echo "Graceful stop requested. Running loop will stop after current task: $STOP_FILE"
  exit 0
fi

if [[ "$ALLOW_DIRTY" -eq 0 ]] && [[ -n "$(git status --porcelain)" ]]; then
  if [[ -f "$STATE_FILE" ]] && [[ "$NO_RESUME" -eq 0 ]]; then
    echo "Working tree is dirty, but resume state exists. Continuing in resume mode."
  else
    echo "Working tree is dirty. Commit/stash changes first, or rerun with --allow-dirty." >&2
    exit 1
  fi
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

on_signal() {
  STOP_REQUESTED=1
  if [[ "$CURRENT_TASK_RUNNING" -eq 1 ]]; then
    echo
    echo "Signal received. Graceful stop requested; will stop after current task boundary."
    touch "$STOP_FILE"
    return 0
  fi
  echo
  echo "Signal received. Exiting."
  exit 130
}
trap on_signal INT TERM

write_state() {
  local task_id="$1"
  local phase="$2"
  cat >"$STATE_FILE" <<STATE
{
  "task_id": "$task_id",
  "phase": "$phase",
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
STATE
}

clear_state() {
  rm -f "$STATE_FILE"
}

stop_requested() {
  [[ "$STOP_REQUESTED" -eq 1 ]] || [[ -f "$STOP_FILE" ]]
}

commit_candidate_status() {
  git status --porcelain -- . "${COMMIT_EXCLUDES[@]}"
}

task_major_id() {
  local id="$1"
  printf '%s\n' "${id%%.*}"
}

reached_stop_after_task() {
  local id="$1"
  if [[ -z "$STOP_AFTER_TASK" ]]; then
    return 1
  fi

  local current_major stop_major
  current_major="$(task_major_id "$id")"
  stop_major="$(task_major_id "$STOP_AFTER_TASK")"

  if [[ ! "$current_major" =~ ^[0-9]+$ ]] || [[ ! "$stop_major" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  [[ "$current_major" -ge "$stop_major" ]]
}

next_task_id() {
  local out
  out="$(task-master next --format json)"
  jq -r '.task.id // empty' <<<"$out"
}

next_task_id_with_stop_preference() {
  if [[ -z "$STOP_AFTER_TASK" ]]; then
    next_task_id
    return
  fi

  local stop_major list_json candidate
  stop_major="$(task_major_id "$STOP_AFTER_TASK")"
  if [[ ! "$stop_major" =~ ^[0-9]+$ ]]; then
    next_task_id
    return
  fi

  list_json="$(task-master list --format json)"
  candidate="$(
    jq -r --argjson stop "$stop_major" '
      .tasks as $tasks
      | ($tasks | map({ key: .id, value: .status }) | from_entries) as $status_by_id
      | $tasks
      | map(select(
          ((.id | split(".")[0] | tonumber) <= $stop)
          and (.status != "done")
          and (.dependencies | all($status_by_id[.] == "done"))
        ))
      | sort_by(
          (.id | split(".")[0] | tonumber),
          ((.id | split(".")[1]? // "0") | tonumber)
        )
      | .[0].id // empty
    ' <<<"$list_json"
  )"

  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return
  fi

  next_task_id
}

run_phase_running_codex() {
  local id="$1"
  local task_json_file="$TMP_DIR/task-${id//\//-}.json"
  local prompt_file="$TMP_DIR/prompt-${id//\//-}.md"

  write_state "$id" "running_codex"
  echo "==> Setting task $id to in-progress"
  task-master set-status "$id" in-progress >/dev/null

  task-master show --id "$id" --format json >"$task_json_file"

  cat >"$prompt_file" <<PROMPT
Implement TaskMaster task $id in this repository.

Rules:
- Scope: complete only this task (and its subtasks) according to TaskMaster details.
- Follow project docs and implementation plan in this repo.
- Make code changes directly in the repo.
- Run relevant checks for changed areas.
- Do not commit; the outer loop handles commit/status updates.
- Start coding quickly: avoid broad repository scans unless strictly required.
- Treat changes in \`.taskmaster/tasks/tasks.json\`, \`.taskmaster/task-loop-state.json\`, and \`.turbo/\` as loop bookkeeping/cache. Ignore them unless this task explicitly targets those files.
- If you need assumptions, make reasonable defaults and proceed.

Task payload (JSON):
\`\`\`json
$(cat "$task_json_file")
\`\`\`
PROMPT

  echo "==> Running Codex for task $id with model $MODEL"
  codex exec \
    -c 'model_reasoning_effort="medium"' \
    -s "$CODEX_SANDBOX" \
    -m "$MODEL" \
    -C "$PROJECT_ROOT" \
    - <"$prompt_file"
}

run_phase_verifying() {
  local id="$1"
  write_state "$id" "verifying"

  echo "==> Verifying task $id with: $VERIFY_CMD"
  if ! bash -lc "$VERIFY_CMD"; then
    echo "Verification failed for task $id. Keeping status as in-progress." >&2
    return 2
  fi
}

run_phase_committing() {
  local id="$1"
  local strict="${2:-1}"
  write_state "$id" "committing"

  local candidate_status
  candidate_status="$(commit_candidate_status)"
  if [[ -z "$candidate_status" ]]; then
    if [[ "$strict" -eq 1 ]]; then
      echo "No commit-eligible file changes detected for task $id. Not committing and leaving task in-progress." >&2
      return 3
    fi
    echo "No commit-eligible changes detected for task $id; assuming commit already exists."
    return 0
  fi

  echo "==> Committing task $id"
  git add -A -- .
  git restore --staged .taskmaster/task-loop-state.json .taskmaster/tasks/tasks.json .turbo >/dev/null 2>&1 || true
  if git diff --cached --quiet; then
    if [[ "$strict" -eq 1 ]]; then
      echo "Only excluded metadata/cache changes were present for task $id. Not committing." >&2
      return 3
    fi
    echo "Only excluded metadata/cache changes were present for task $id; assuming commit already exists."
    return 0
  fi
  git commit -m "task($id): complete"
}

run_phase_mark_done() {
  local id="$1"
  write_state "$id" "marking_done"
  echo "==> Marking task $id as done"
  task-master set-status "$id" done >/dev/null
  clear_state
  echo "==> Task $id completed successfully"
}

run_task_fresh() {
  local id="$1"
  CURRENT_TASK_RUNNING=1
  run_phase_running_codex "$id"
  run_phase_verifying "$id"
  run_phase_committing "$id" 1
  run_phase_mark_done "$id"
  CURRENT_TASK_RUNNING=0
}

resume_task_from_phase() {
  local id="$1"
  local phase="$2"
  CURRENT_TASK_RUNNING=1
  echo "==> Resuming task $id from phase: $phase"
  case "$phase" in
    running_codex|set_in_progress|fresh|"")
      run_phase_running_codex "$id"
      run_phase_verifying "$id"
      run_phase_committing "$id" 1
      run_phase_mark_done "$id"
      ;;
    verifying)
      run_phase_verifying "$id"
      run_phase_committing "$id" 1
      run_phase_mark_done "$id"
      ;;
    committing)
      run_phase_committing "$id" 0
      run_phase_mark_done "$id"
      ;;
    marking_done)
      run_phase_mark_done "$id"
      ;;
    *)
      echo "Unknown resume phase '$phase'. Starting task $id from codex phase."
      run_phase_running_codex "$id"
      run_phase_verifying "$id"
      run_phase_committing "$id" 1
      run_phase_mark_done "$id"
      ;;
  esac
  CURRENT_TASK_RUNNING=0
}

maybe_resume_unfinished_task() {
  if [[ "$NO_RESUME" -eq 1 ]] || [[ -n "$TASK_ID" ]]; then
    return 1
  fi
  if [[ ! -f "$STATE_FILE" ]]; then
    return 1
  fi

  local resume_task_id resume_phase
  if ! resume_task_id="$(jq -r '.task_id // empty' "$STATE_FILE" 2>/dev/null)"; then
    clear_state
    return 1
  fi
  resume_phase="$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)"

  if [[ -z "$resume_task_id" ]]; then
    clear_state
    return 1
  fi

  RESUME_TASK_ID="$resume_task_id"
  resume_task_from_phase "$resume_task_id" "$resume_phase"
  return 0
}

run_task() {
  local id="$1"
  run_task_fresh "$id"
}

if [[ -n "$TASK_ID" ]]; then
  run_task "$TASK_ID"
  exit $?
fi

RESUMED=0
if maybe_resume_unfinished_task; then
  RESUMED=1
  if stop_requested; then
    rm -f "$STOP_FILE"
    echo "Graceful stop request honored after resuming unfinished task."
    exit 0
  fi
  if [[ "$AUTO_MODE" -eq 0 ]]; then
    echo "Resumed unfinished task and completed it. Exiting."
    exit 0
  fi
  if reached_stop_after_task "$RESUME_TASK_ID"; then
    echo "Stop-after-task target reached at task $RESUME_TASK_ID. Exiting."
    exit 0
  fi
fi

if [[ "$AUTO_MODE" -eq 1 ]]; then
  while true; do
    if stop_requested; then
      rm -f "$STOP_FILE"
      echo "Graceful stop request honored. Exiting before starting a new task."
      exit 0
    fi

    id="$(next_task_id_with_stop_preference)"
    if [[ -z "$id" ]]; then
      echo "No available tasks. Done."
      exit 0
    fi
    if reached_stop_after_task "$id"; then
      if [[ "$(task_major_id "$id")" -gt "$(task_major_id "$STOP_AFTER_TASK")" ]]; then
        echo "Stop-after-task target $STOP_AFTER_TASK was already passed (next task is $id). Exiting."
        exit 0
      fi
    fi

    run_task "$id"

    if reached_stop_after_task "$id"; then
      echo "Reached stop-after-task target ($STOP_AFTER_TASK) after completing task $id. Exiting."
      exit 0
    fi

    if stop_requested; then
      rm -f "$STOP_FILE"
      echo "Graceful stop request honored after completing task $id."
      exit 0
    fi
  done
else
  id="$(next_task_id)"
  if [[ -z "$id" ]]; then
    echo "No available tasks."
    exit 0
  fi
  run_task "$id"
fi
