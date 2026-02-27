# Active Supervision

Use this file during long-running task loop execution. The loop is not fire-and-forget.

## Non-Negotiable Rules

- Monitor loop/watchdog/codex process health continuously.
- Monitor state files and log output to detect stalls.
- Confirm code and task statuses are progressing.
- Keep only one active loop/watchdog per repository.
- Intervene if state stays unchanged too long.
- Treat `phase=verifying` with no log output for 5+ minutes as a stuck verification incident.

## Repeated Health Checks

```bash
# loop/watchdog/codex process health
pgrep -af "task-loop.sh|task-loop-watchdog.sh|codex exec"

# current task + phase (detect stalls)
cat .taskmaster/task-loop-state.json 2>/dev/null || echo "no active state"

# state-file age in seconds (quick stall signal)
now="$(date +%s)"; mtime="$(stat -f %m .taskmaster/task-loop-state.json 2>/dev/null || stat -c %Y .taskmaster/task-loop-state.json 2>/dev/null || echo 0)"; echo $((now-mtime))

# watchdog output (if watchdog mode is used)
tail -n 120 .taskmaster/task-loop-watchdog.out 2>/dev/null || true

# verify/test process tree health
pgrep -af "npm run verify|turbo run test|tsx --test"

# code + task progression
git status --short
task-master list --format json | jq '{done:(.tasks|map(select(.status=="done"))|length), in_progress:[.tasks[]|select(.status=="in-progress")|.id], pending:(.tasks|map(select(.status=="pending"))|length)}'
```

If state stays on the same task/phase for too long, inspect and recover immediately.
If verifying appears idle/stuck, restart loop with explicit guards:

```bash
./scripts/task-loop.sh --auto --verify-idle-timeout 300 --verify-timeout 5400
```

## Graceful Stop Commands

Request loop stop:

```bash
./scripts/task-loop.sh --request-stop
```

Request watchdog stop:

```bash
./scripts/task-loop-watchdog.sh --request-stop
```

## End-Of-Run Shutdown

When all tasks are complete, request stop and confirm no remaining loop/watchdog processes:

```bash
./scripts/task-loop.sh --request-stop || true
./scripts/task-loop-watchdog.sh --request-stop || true
pgrep -af "task-loop.sh|task-loop-watchdog.sh|codex exec" || echo "no loop/watchdog processes"
```

## Status Reporting Contract

After each completed task, report:

- Task ID
- Commit hash
- Verify result
- Any blockers or skipped tests
