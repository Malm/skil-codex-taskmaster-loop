#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

PLAN_DIR="${1:-$REPO_ROOT/implementation-plan}"
OUT_FILE="${2:-$REPO_ROOT/.taskmaster/docs/prd.md}"

if [[ ! -d "$PLAN_DIR" ]]; then
  echo "Plan directory not found: $PLAN_DIR" >&2
  exit 1
fi

PLAN_FILES="$(find "$PLAN_DIR" -maxdepth 1 -type f -name "*.md" | sort)"
if [[ -z "$PLAN_FILES" ]]; then
  echo "No markdown files found in plan directory: $PLAN_DIR" >&2
  exit 1
fi

PLAN_COUNT="$(printf "%s\n" "$PLAN_FILES" | sed '/^$/d' | wc -l | tr -d ' ')"

mkdir -p "$(dirname "$OUT_FILE")"

{
  echo "# Compiled PRD"
  echo
  echo "Generated from implementation plan files in: $PLAN_DIR"
  echo
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    echo "---"
    echo
    echo "## Source: $(basename "$file")"
    echo
    cat "$file"
    echo
  done <<< "$PLAN_FILES"
} > "$OUT_FILE"

echo "Compiled $PLAN_COUNT files into: $OUT_FILE"
