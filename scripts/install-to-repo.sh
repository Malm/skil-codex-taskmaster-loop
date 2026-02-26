#!/usr/bin/env bash
set -euo pipefail

TARGET_REPO="${1:-$(pwd)}"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_SCRIPTS_DIR="$TARGET_REPO/scripts"

if [[ ! -d "$TARGET_REPO" ]]; then
  echo "Target repo directory not found: $TARGET_REPO" >&2
  exit 1
fi

mkdir -p "$TARGET_SCRIPTS_DIR"

cp "$SKILL_DIR/scripts/task-loop.sh" "$TARGET_SCRIPTS_DIR/task-loop.sh"
cp "$SKILL_DIR/scripts/task-loop-watchdog.sh" "$TARGET_SCRIPTS_DIR/task-loop-watchdog.sh"
cp "$SKILL_DIR/scripts/compile-plan-prd.sh" "$TARGET_SCRIPTS_DIR/compile-plan-prd.sh"
cp "$SKILL_DIR/scripts/bootstrap-taskmaster.sh" "$TARGET_SCRIPTS_DIR/bootstrap-taskmaster.sh"

chmod +x \
  "$TARGET_SCRIPTS_DIR/task-loop.sh" \
  "$TARGET_SCRIPTS_DIR/task-loop-watchdog.sh" \
  "$TARGET_SCRIPTS_DIR/compile-plan-prd.sh" \
  "$TARGET_SCRIPTS_DIR/bootstrap-taskmaster.sh"

echo "Installed scripts to: $TARGET_SCRIPTS_DIR"
echo "- task-loop.sh"
echo "- task-loop-watchdog.sh"
echo "- compile-plan-prd.sh"
echo "- bootstrap-taskmaster.sh"
