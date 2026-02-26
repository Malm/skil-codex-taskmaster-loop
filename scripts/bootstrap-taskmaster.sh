#!/usr/bin/env bash
set -euo pipefail

TAG="mvp"
INPUT=""
NUM_TASKS=35
RESEARCH=1
FORCE=1

usage() {
  cat <<'USAGE'
Usage: scripts/bootstrap-taskmaster.sh --input <prd.md> [options]

Parse a PRD into TaskMaster tasks, expand tasks, and validate dependencies.

Options:
  --input <path>       Path to PRD markdown file (required)
  --tag <tag>          TaskMaster tag (default: mvp)
  --num-tasks <n>      Initial parse target count (default: 35)
  --no-research        Disable research flags
  --no-force           Do not overwrite existing tasks on parse
  -h, --help           Show this help

Example:
  scripts/bootstrap-taskmaster.sh --input .taskmaster/docs/prd.md --tag mvp --num-tasks 35
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      INPUT="${2:-}"
      shift 2
      ;;
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --num-tasks)
      NUM_TASKS="${2:-}"
      shift 2
      ;;
    --no-research)
      RESEARCH=0
      shift
      ;;
    --no-force)
      FORCE=0
      shift
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

if [[ -z "$INPUT" ]]; then
  echo "--input is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "PRD file not found: $INPUT" >&2
  exit 1
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

for cmd in task-master git; do
  require_cmd "$cmd"
done

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "This script must run inside a git repository." >&2
  exit 1
fi
cd "$PROJECT_ROOT"

RESEARCH_FLAGS=()
if [[ "$RESEARCH" -eq 1 ]]; then
  RESEARCH_FLAGS+=(--research)
fi

FORCE_FLAGS=()
if [[ "$FORCE" -eq 1 ]]; then
  FORCE_FLAGS+=(--force)
fi

echo "==> Parsing PRD into tasks"
task-master parse-prd --input "$INPUT" --num-tasks "$NUM_TASKS" --tag "$TAG" "${RESEARCH_FLAGS[@]}" "${FORCE_FLAGS[@]}"

echo "==> Analyzing complexity"
task-master analyze-complexity --tag "$TAG" "${RESEARCH_FLAGS[@]}"

echo "==> Expanding tasks"
task-master expand --all --tag "$TAG" "${RESEARCH_FLAGS[@]}"

echo "==> Validating dependencies"
task-master validate-dependencies --tag "$TAG"

echo "==> Fixing dependencies"
task-master fix-dependencies --tag "$TAG"

echo "==> Generating task files"
task-master generate --tag "$TAG"

echo "==> Current task list"
task-master list --with-subtasks --tag "$TAG"
