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

## When To Use

- User has a PRD and wants implementation split into dependency-aware tasks.
- User wants verify-before-complete and one commit per completed task.
- User wants resumable or unattended execution with watchdog supervision.

## Scope

- This skill is focused on execution loops, not PRD authoring.
- If PRD authoring/restructuring is still needed, use `prd-taskmaster` first.
- Keep this skill workflow-centric; avoid expanding it into tool encyclopedias.

## Progressive Disclosure Rules

- Treat this file as a routing map, not full documentation.
- Load only the reference file needed for the current step.
- Prefer bundled scripts for deterministic actions over long inline instructions.

## Quick Start Workflow

1. Validate prerequisites and install scripts into target repo when needed.
See: `references/setup-and-preconditions.md`

2. Compile a PRD only when the source plan is split across files.

```bash
./scripts/compile-plan-prd.sh <plan-dir> .taskmaster/docs/prd.md
```

3. Bootstrap and expand TaskMaster tasks from PRD.

```bash
./scripts/bootstrap-taskmaster.sh --input .taskmaster/docs/prd.md --tag mvp --num-tasks 35
```

4. Run the implementation loop.

```bash
./scripts/task-loop.sh --auto
```

For unattended runs, keep verify guards explicit:

```bash
./scripts/task-loop.sh --auto --verify-idle-timeout 300 --verify-timeout 5400
```

5. For unattended execution, run watchdog.

```bash
./scripts/task-loop-watchdog.sh --daemon --interval 300 --loop-arg "--verify-idle-timeout" --loop-arg "300" --loop-arg "--verify-timeout" --loop-arg "5400"
```

## Bundled Scripts

- `scripts/compile-plan-prd.sh`: Merge multiple plan markdown files into one PRD.
- `scripts/bootstrap-taskmaster.sh`: Parse PRD, expand tasks, and generate task files.
- `scripts/task-loop.sh`: Execute tasks with verify-before-complete and commit-per-task.
- `scripts/task-loop-watchdog.sh`: Keep `task-loop.sh --auto` alive and restart on exits.
- `scripts/install-to-repo.sh`: Copy bundled scripts into `<repo>/scripts`.

## References (Load Only If Needed)

- `references/setup-and-preconditions.md`
Use for prerequisites, target-repo installation, and baseline repo checks.

- `references/workflow-commands.md`
Use for command variants: research/no-research, checkpoints, sandbox modes, daemonized watchdog.

- `references/active-supervision.md`
Use for monitoring checklist, stall recovery, graceful stop, and reporting contract.

- `references/failure-modes.md`
Use when loop behavior deviates; contains known incidents, fixes, and prevention notes.

## Required Execution Contract

- Do not bypass `task-loop.sh` for normal execution.
- Keep verify gate enabled before marking tasks done.
- Ensure repo scripts expose `npm run validate` and `npm run verify` (where `verify` runs `validate`).
- Keep one commit per completed task (`task(<id>): complete`).
- If verify fails, stop and report; do not force task completion.
- Use resume behavior after interruptions unless user explicitly requests otherwise.
- Keep only one active loop/watchdog per repo.
- Shut down loop/watchdog when all tasks are complete and confirm no leftover processes.

## Status Reporting Contract

After each completed task, report:
- Task ID
- Commit hash
- Verify result
- Any blockers or skipped tests
