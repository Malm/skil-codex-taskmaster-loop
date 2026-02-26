---
name: taskmaster-codex-loop
description: Execute PRD-driven development with TaskMaster and Codex CLI. Use when a user has a PRD and wants tasks generated, then implemented one-by-one with verification, per-task commits, resume support, graceful stop behavior, and watchdog auto-restart for unattended runs.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
---

# TaskMaster + Codex Task Loop

Use this skill when the user wants a deterministic PRD -> TaskMaster -> implementation loop.

## Preconditions

Assume these are already true unless the user says otherwise:
- A PRD exists (single file or multiple plan markdown files).
- `codex` CLI is installed and authenticated.
- `task-master`, `jq`, `git`, and `node` are installed.
- `task-master` CLI is configured for the target repo (working `.taskmaster/config.json`, provider/API keys as needed for `--research` flows).
- Work is happening inside a git repository.

## Skill Dependencies

- This skill is standalone for execution loops.
- It does not require the separate `prd-taskmaster` skill.
- Optional pairing: use `prd-taskmaster` first if the user still needs PRD authoring or PRD restructuring before task generation.

## Bundled Scripts

- `scripts/compile-plan-prd.sh`
Purpose: Merge multiple plan markdown files into one PRD file.

- `scripts/bootstrap-taskmaster.sh`
Purpose: Parse PRD into tasks, expand tasks, validate/fix dependencies, and generate task files.

- `scripts/task-loop.sh`
Purpose: Execute tasks sequentially with verify-before-complete and commit-per-task.

- `scripts/task-loop-watchdog.sh`
Purpose: Keep `task-loop.sh --auto` alive and restart it if it stops unexpectedly.

- `scripts/install-to-repo.sh`
Purpose: Copy the bundled scripts into `<repo>/scripts`.

## Setup In A Target Repo

If the target repo does not already have these scripts, run:

```bash
bash <skill-dir>/scripts/install-to-repo.sh <repo-path>
```

Then run commands from the target repo root.

## Standard Workflow

1. Compile a PRD only if source plan is split across files.

```bash
./scripts/compile-plan-prd.sh <plan-dir> .taskmaster/docs/prd.md
```

2. Generate and expand tasks from PRD.

```bash
./scripts/bootstrap-taskmaster.sh --input .taskmaster/docs/prd.md --tag mvp --num-tasks 35
```

3. Implement tasks with Codex loop.

Single next task:

```bash
./scripts/task-loop.sh
```

Continuous mode:

```bash
./scripts/task-loop.sh --auto
```

Stop at checkpoint (for example after task 8):

```bash
./scripts/task-loop.sh --auto --stop-after-task 8
```

Full-access Codex sandbox (for dependency installs):

```bash
./scripts/task-loop.sh --auto --codex-danger-full-access
```

Unattended mode with auto-restart:

```bash
./scripts/task-loop-watchdog.sh --interval 20
```

Background watchdog mode:

```bash
nohup ./scripts/task-loop-watchdog.sh --interval 20 > .taskmaster/task-loop-watchdog.out 2>&1 < /dev/null &
```

## Required Execution Rules

- Do not bypass `task-loop.sh` for normal execution.
- Keep verify gate enabled (`--verify-cmd` defaults to `npm run verify`).
- Keep one commit per completed task (`task(<id>): complete`).
- If verify fails, stop and report; do not force status to done.
- Use resume behavior by default after interruptions.
- For unattended runs, prefer watchdog over a single detached `task-loop.sh`.
- Agent responsibility is active supervision: monitor running loop/Codex processes, state files, output logs, and repo file changes while loop is running.
- Do not treat loop execution as fire-and-forget; intervene when progress stalls.
- Keep only one active loop/watchdog per repo to avoid duplicate verify/test trees.
- When all tasks are complete, shut down loop/watchdog and confirm no leftover background processes.
- Use graceful stop for running loops:

```bash
./scripts/task-loop.sh --request-stop
```

Graceful stop when watchdog is active:

```bash
./scripts/task-loop-watchdog.sh --request-stop
```

## Active Supervision Checklist (Critical)

Run these checks repeatedly during loop execution:

```bash
# loop/watchdog/codex process health
pgrep -af "task-loop.sh|task-loop-watchdog.sh|codex exec"

# current task + phase (detect stalls)
cat .taskmaster/task-loop-state.json 2>/dev/null || echo "no active state"

# loop/watchdog output (when watchdog mode is used)
tail -n 120 .taskmaster/task-loop-watchdog.out 2>/dev/null || true

# verify that code is actually changing and progressing
git status --short
task-master list --format json | jq '{done:(.tasks|map(select(.status=="done"))|length), in_progress:[.tasks[]|select(.status=="in-progress")|.id], pending:(.tasks|map(select(.status=="pending"))|length)}'
```

If state is stuck on the same task/phase for too long, inspect and recover immediately; do not wait indefinitely.

## Status Reporting Contract

After each completed task, report:
- Task ID
- Commit hash
- Verify result
- Any blockers or skipped tests

## Notes

- `task-loop.sh` intentionally excludes `.taskmaster/tasks/tasks.json`, `.taskmaster/task-loop-state.json`, and `.turbo` from task commits.
- If the repo has no upstream remote, commits are still valid; push is a separate step.
- Watchdog stop signal path: `.taskmaster/task-loop-watchdog.stop`.

## Failure Modes and Fixes (Observed in Real Use)

1. Dependency installs fail inside Codex task runs.
- Symptom: task cannot install missing packages or build tools.
- Fix: run loop with full access: `./scripts/task-loop.sh --auto --codex-danger-full-access`.
- Preventive: preinstall core deps (`pnpm install`) before long unattended runs.

2. Detached loop exits silently (TTY/background process quirks).
- Symptom: `task-loop.sh` disappears while tasks remain.
- Fix: run `task-loop-watchdog.sh` instead of relying on a single detached loop.
- Preventive: capture watchdog logs in `.taskmaster/task-loop-watchdog.out`.

3. Loop looks complete while a task is still in progress.
- Symptom: `task-master next` can return empty during a mid-task state.
- Fix: watchdog checks both `.taskmaster/task-loop-state.json` and TaskMaster statuses (`pending` + `in-progress`) before exiting.

4. Dirty git tree blocks loop startup.
- Symptom: script exits with "Working tree is dirty."
- Fix: commit/stash changes, or use `--allow-dirty` intentionally for active dev branches.

5. Task order is not strictly numeric.
- Symptom: loop selects task `24` before `20`.
- Cause: TaskMaster selects based on dependency graph, not ID sequence.
- Fix: accept DAG order, or use `--stop-after-task` checkpoints for manual test gates.

6. Verify command missing or too weak.
- Symptom: loop cannot reliably validate task completion.
- Fix: add stable repo scripts (`validate` and `verify`) and keep `verify` as loop gate.

7. PNPM monorepo dependency lookup confusion.
- Symptom: package not found at root `node_modules/<pkg>`.
- Fix: check workspace package `node_modules` (symlink layout) and avoid npm-flat assumptions.

8. Codex subprocess hangs mid-task after writing files.
- Symptom: `.taskmaster/task-loop-state.json` stays on `running_codex` for one task, but files were already modified and no verify/commit occurs.
- Fix: inspect written changes and recent Codex output, stop the stuck subprocess, run verify once manually, then commit + mark task done if checks pass, and restart loop.
- Preventive: monitor `task-loop-state.json` and process uptime; escalate when unchanged too long.

9. Duplicate verify/test process trees run concurrently.
- Symptom: multiple `npm run verify` / `turbo run test` trees consume resources and appear to hang.
- Fix: terminate orphaned duplicate trees, rerun a single clean verify, then continue loop.
- Preventive: keep one loop instance only; avoid manual verify overlap while loop verify is active.

10. Integration tests hang due missing teardown of shared connections.
- Symptom: test assertions pass but test command never exits.
- Cause: unclosed queue/redis/pool/shared clients.
- Fix: add explicit `after(...)` teardown for shared resources in integration tests.
- Preventive: enforce teardown pattern for any test that opens long-lived connections.

11. Loop/watchdog left running after all tasks are done.
- Symptom: idle background processes keep running with no work.
- Fix: request graceful stop for both loop and watchdog, then confirm no remaining processes.
- Commands:
```bash
./scripts/task-loop.sh --request-stop || true
./scripts/task-loop-watchdog.sh --request-stop || true
pgrep -af "task-loop.sh|task-loop-watchdog.sh|codex exec" || echo "no loop/watchdog processes"
```
