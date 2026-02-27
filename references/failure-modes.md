# Failure Modes And Fixes

Use this file when loop behavior deviates from expected operation.

## 1) Dependency installs fail inside Codex task runs

- Symptom: Task cannot install missing packages or build tools.
- Fix: Run loop with full access: `./scripts/task-loop.sh --auto --codex-danger-full-access`.
- Preventive: Preinstall core dependencies (`pnpm install`) before long unattended runs.

## 2) Detached loop exits silently

- Symptom: `task-loop.sh` disappears while tasks remain.
- Fix: Run `task-loop-watchdog.sh` instead of relying on a detached loop.
- Preventive: Capture watchdog logs in `.taskmaster/task-loop-watchdog.out`.

## 3) Loop appears complete while a task is still in progress

- Symptom: `task-master next` returns empty during a mid-task state.
- Fix: Check both `.taskmaster/task-loop-state.json` and TaskMaster statuses (`pending` + `in-progress`) before exit decisions.

## 4) Dirty git tree blocks loop startup

- Symptom: Script exits with "Working tree is dirty."
- Fix: Commit/stash changes, or pass `--allow-dirty` intentionally for active dev branches.

## 5) Task order is not numeric

- Symptom: Loop selects task `24` before `20`.
- Cause: TaskMaster selects by dependency graph, not task ID sequence.
- Fix: Accept DAG order, or use `--stop-after-task` checkpoints for manual test gates.

## 6) Verify command missing or too weak

- Symptom: Loop cannot reliably validate task completion.
- Fix: Add stable repo scripts (`validate` and `verify`) and keep `verify` as loop gate.

## 7) PNPM monorepo dependency lookup confusion

- Symptom: Package is not found at root `node_modules/<pkg>`.
- Fix: Check workspace package `node_modules` layout and avoid npm-flat assumptions.

## 8) Codex subprocess hangs mid-task after writing files

- Symptom: `.taskmaster/task-loop-state.json` remains at `running_codex`, with modified files but no verify/commit.
- Fix: Inspect changes and Codex output, stop the stuck subprocess, run verify manually, then commit + mark task done if checks pass.
- Preventive: Monitor state file and process uptime, and escalate when unchanged too long.

## 9) Duplicate verify/test trees run concurrently

- Symptom: Multiple `npm run verify` or `turbo run test` trees consume resources and appear to hang.
- Fix: Terminate orphaned duplicates, rerun one clean verify, then continue loop.
- Preventive: Keep one loop instance only; avoid manual verify overlap while loop verify is active.

## 10) Integration tests hang due to missing shared-connection teardown

- Symptom: Assertions pass but test command never exits.
- Cause: Unclosed queue/redis/pool/shared clients.
- Fix: Add explicit `after(...)` teardown for shared resources in integration tests.
- Preventive: Enforce teardown for tests that open long-lived connections.

## 11) Loop/watchdog left running after all tasks are done

- Symptom: Idle background processes remain with no work.
- Fix:

```bash
./scripts/task-loop.sh --request-stop || true
./scripts/task-loop-watchdog.sh --request-stop || true
pgrep -af "task-loop.sh|task-loop-watchdog.sh|codex exec" || echo "no loop/watchdog processes"
```

