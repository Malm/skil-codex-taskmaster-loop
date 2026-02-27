# Workflow Commands

Use this file when selecting command variants for setup, bootstrap, loop execution, and watchdog operation.

## 1) Compile PRD (Only For Split Plans)

```bash
./scripts/compile-plan-prd.sh <plan-dir> .taskmaster/docs/prd.md
```

## 2) Bootstrap TaskMaster

Default bootstrap (research enabled):

```bash
./scripts/bootstrap-taskmaster.sh --input .taskmaster/docs/prd.md --tag mvp --num-tasks 35
```

Incremental refresh (research disabled):

```bash
./scripts/bootstrap-taskmaster.sh --input .taskmaster/docs/prd.md --tag mvp --num-tasks 12 --no-research
```

### Research Mode Policy

- Keep research enabled for first parse of a new PRD.
- Keep research enabled for architecture-heavy or ambiguous scopes.
- Keep research enabled for initial `parse-prd`, `analyze-complexity`, and `expand --all` on net-new projects.
- Disable research for small incremental updates when speed/cost is prioritized over discovery.

## 3) Run Task Loop

Single next task:

```bash
./scripts/task-loop.sh
```

Continuous mode:

```bash
./scripts/task-loop.sh --auto
```

Continuous mode with explicit verify guards (recommended for unattended runs):

```bash
./scripts/task-loop.sh --auto --verify-idle-timeout 300 --verify-timeout 5400
```

Stop at checkpoint:

```bash
./scripts/task-loop.sh --auto --stop-after-task 8
```

Full access sandbox (needed for dependency installs in some repos):

```bash
./scripts/task-loop.sh --auto --codex-danger-full-access
```

Graceful stop request:

```bash
./scripts/task-loop.sh --request-stop
```

## 4) Watchdog For Unattended Runs

Foreground watchdog:

```bash
./scripts/task-loop-watchdog.sh --interval 300 --loop-arg "--verify-idle-timeout" --loop-arg "300"
```

Daemonized watchdog:

```bash
./scripts/task-loop-watchdog.sh --daemon --interval 300 --loop-arg "--verify-idle-timeout" --loop-arg "300" --loop-arg "--verify-timeout" --loop-arg "5400"
```

Legacy background pattern:

```bash
nohup ./scripts/task-loop-watchdog.sh --interval 300 --loop-arg "--verify-idle-timeout" --loop-arg "300" --loop-arg "--verify-timeout" --loop-arg "5400" > .taskmaster/task-loop-watchdog.out 2>&1 < /dev/null &
```

Watchdog status:

```bash
./scripts/task-loop-watchdog.sh --status
```

Watchdog graceful stop request:

```bash
./scripts/task-loop-watchdog.sh --request-stop
```
