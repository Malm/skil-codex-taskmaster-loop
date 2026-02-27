# TaskMaster + Codex Loop Skill

**A deterministic, context-efficient system for implementing large PRDs with AI agents.**

## What Is This?

This skill enables your AI agent (Codex, OpenClaw, or any similar tool) to implement large Product Requirements Documents (PRDs) by breaking them into discrete tasks and executing each one in isolation with a fresh context. Instead of one long, context-bloated agent session, you get a structured loop where:

1. **A PRD is parsed** into actionable tasks with dependencies
2. **Each task runs independently** with clean context
3. **Every task is verified** before marking complete
4. **Each success is committed** to git with proper isolation
5. **The loop resumes automatically** after interruptions or errors

## Why Is This Good?

### The Problem with Traditional Long-Running Agent Sessions

When you give an AI agent a 50-page PRD and ask it to "build this," several things go wrong:

- **Context window fills up** with implementation details, losing sight of the big picture
- **Agent forgets earlier decisions** as conversation grows
- **Errors compound** because there's no verification gate between steps
- **No checkpoints** — if it crashes at step 45, you lose everything
- **Difficult to resume** or parallelize work
- **Vibe-driven execution** rather than systematic progress

### How This Skill Solves It

✅ **Context Reset Per Task** — Every task starts fresh, focused only on its specific goal  
✅ **Deterministic Progress** — TaskMaster manages dependencies and execution order  
✅ **Built-in Verification** — Each task must pass `npm run verify` (tests + lint) before completion  
✅ **Atomic Commits** — One commit per successful task, easy to review and rollback  
✅ **Graceful Resume** — Stop and restart anytime without losing progress  
✅ **Unattended Operation** — Watchdog keeps the loop alive, restarts on failures  
✅ **No Context Bloat** — Codex sees only: task description + current codebase state  
✅ **Works with Any Agent** — Codex CLI, OpenClaw, or any system that can run shell commands

## How It Works

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  1. PRD (Product Requirements Document)                         │
│     - Single markdown file or multiple plan files               │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. TaskMaster Bootstrapping                                    │
│     - Parse PRD → Initial task list                             │
│     - Analyze complexity                                        │
│     - Expand into subtasks                                      │
│     - Validate & fix dependencies                               │
│     - Generate task files (.taskmaster/tasks/*.md)              │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. Task Execution Loop (task-loop.sh)                          │
│                                                                 │
│     ┌───────────────────────────────────────────┐              │
│     │  Select Next Available Task (dep-free)    │              │
│     └───────┬───────────────────────────────────┘              │
│             │                                                   │
│             ▼                                                   │
│     ┌───────────────────────────────────────────┐              │
│     │  Run Codex with Task File as Prompt      │              │
│     │  (Fresh context: task + current code)    │              │
│     └───────┬───────────────────────────────────┘              │
│             │                                                   │
│             ▼                                                   │
│     ┌───────────────────────────────────────────┐              │
│     │  Verify Implementation                    │              │
│     │  (npm run verify: tests + lint)           │              │
│     └───────┬───────────────────────────────────┘              │
│             │                                                   │
│             ▼                                                   │
│     ┌───────────────────────────────────────────┐              │
│     │  Mark Task Complete                       │              │
│     └───────┬───────────────────────────────────┘              │
│             │                                                   │
│             ▼                                                   │
│     ┌───────────────────────────────────────────┐              │
│     │  Git Commit (task(<id>): complete)        │              │
│     └───────┬───────────────────────────────────┘              │
│             │                                                   │
│             └───────► Repeat until all tasks done              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. Watchdog (Optional, for Unattended Runs)                    │
│     - Monitors task-loop.sh process                             │
│     - Auto-restarts if loop exits with remaining tasks          │
│     - Graceful shutdown on completion or stop signal            │
└─────────────────────────────────────────────────────────────────┘
```

### Key Scripts

| Script | Purpose |
|--------|---------|
| `compile-plan-prd.sh` | Merge multiple plan markdown files into a single PRD |
| `bootstrap-taskmaster.sh` | Parse PRD → Generate task files with dependencies |
| `task-loop.sh` | Execute tasks one-by-one with verification and commits |
| `task-loop-watchdog.sh` | Keep task-loop running unattended with auto-restart |
| `install-to-repo.sh` | Copy these scripts into a target repository |

## Setup

### Prerequisites

Ensure these are installed:

- **TaskMaster CLI** — Task orchestration and dependency management
- **Codex CLI** — AI agent executor (or your preferred agent)
- **Git** — Version control for commits
- **Node.js + npm/pnpm** — For running verify scripts
- **jq** — JSON parsing in shell scripts

### Installation in Your Repository

1. **Clone or reference this skill:**

```bash
git clone <this-skill-repo> ~/.agents/skills/taskmaster-codex-loop
```

2. **Install scripts into your target repo:**

```bash
cd ~/my-project
~/.agents/skills/taskmaster-codex-loop/scripts/install-to-repo.sh .
```

This copies the scripts to `~/my-project/scripts/`.

3. **Configure TaskMaster for your repo:**

Ensure `.taskmaster/config.json` exists with your AI provider settings:

```json
{
  "provider": "openai",
  "model": "gpt-5.3-codex",
  "apiKey": "your-api-key-or-env-var"
}
```

4. **Set up verification command:**

Add to `package.json`:

```json
{
  "scripts": {
    "validate": "npm run lint && npm run test && npm run build",
    "verify": "npm run validate",
    "test": "vitest run",
    "lint": "eslint ."
  }
}
```

## Usage

### Step 1: Prepare Your PRD

**Option A: Single PRD file**

Create `.taskmaster/docs/prd.md` with your requirements.

**Option B: Multiple plan files**

Store plan files in `implementation-plan/`:

```
implementation-plan/
  01-architecture.md
  02-database.md
  03-api.md
  04-frontend.md
```

Then compile them:

```bash
./scripts/compile-plan-prd.sh implementation-plan .taskmaster/docs/prd.md
```

### Step 2: Generate Tasks from PRD

```bash
./scripts/bootstrap-taskmaster.sh \
  --input .taskmaster/docs/prd.md \
  --tag mvp \
  --num-tasks 35
```

`bootstrap-taskmaster.sh` enables TaskMaster research mode by default.

Use default research mode for:
- first parse of a new PRD
- large/ambiguous scopes
- architecture-heavy or domain-unknown projects

Disable research for small incremental task refreshes:

```bash
./scripts/bootstrap-taskmaster.sh \
  --input .taskmaster/docs/prd.md \
  --tag mvp \
  --num-tasks 12 \
  --no-research
```

This creates task files in `.taskmaster/tasks/`.

**What happens:**
- Parses PRD into ~35 initial tasks
- Analyzes complexity
- Expands complex tasks into subtasks
- Validates and fixes dependency ordering
- Generates markdown files for each task

### Step 3: Run the Task Loop

**Execute one task (manual mode):**

```bash
./scripts/task-loop.sh
```

**Continuous auto mode (runs until all tasks complete):**

```bash
./scripts/task-loop.sh --auto
```

**Continuous mode with verify stall guards (recommended):**

```bash
./scripts/task-loop.sh --auto --verify-idle-timeout 300 --verify-timeout 5400
```

**Stop at a checkpoint (e.g., after task 8 for review):**

```bash
./scripts/task-loop.sh --auto --stop-after-task 8
```

**Full system access (for package installs):**

```bash
./scripts/task-loop.sh --auto --codex-danger-full-access
```

**Graceful stop:**

```bash
./scripts/task-loop.sh --request-stop
```

### Step 4: Unattended Operation with Watchdog

For long-running projects, use the watchdog to keep the loop alive:

**Foreground watchdog:**

```bash
./scripts/task-loop-watchdog.sh --interval 300 --loop-arg "--verify-idle-timeout" --loop-arg "300"
```

**Background watchdog (unattended):**

```bash
nohup ./scripts/task-loop-watchdog.sh --interval 300 \
  --loop-arg "--verify-idle-timeout" --loop-arg "300" \
  --loop-arg "--verify-timeout" --loop-arg "5400" \
  > .taskmaster/task-loop-watchdog.out 2>&1 &
```

**Stop the watchdog:**

```bash
./scripts/task-loop-watchdog.sh --request-stop
```

## Agent Supervision Guidelines

When using this skill with your agent, follow these practices:

### Active Monitoring (Critical)

Don't treat the loop as "fire and forget." Your agent should periodically check:

```bash
# Check running processes
pgrep -af "task-loop.sh|task-loop-watchdog.sh|codex exec"

# Check current task state
cat .taskmaster/task-loop-state.json

# State-file age (seconds)
now="$(date +%s)"; mtime="$(stat -f %m .taskmaster/task-loop-state.json 2>/dev/null || stat -c %Y .taskmaster/task-loop-state.json 2>/dev/null || echo 0)"; echo $((now-mtime))

# View recent watchdog logs
tail -n 120 .taskmaster/task-loop-watchdog.out

# Verify/test process tree (stuck detection)
pgrep -af "npm run verify|turbo run test|tsx --test"

# Check overall progress
task-master list --format json | jq '{
  done: (.tasks | map(select(.status=="done")) | length),
  in_progress: [.tasks[] | select(.status=="in-progress") | .id],
  pending: (.tasks | map(select(.status=="pending")) | length)
}'

# Verify code is actually changing
git status --short
git log --oneline -10
```

### When to Intervene

- **Verify phase stuck/no output for >5 minutes** — Restart with `--verify-idle-timeout 300`
- **Task stuck for >10 minutes** — Check logs, may need manual fix
- **Verify fails repeatedly** — Review the task requirements or fix test issues
- **Dependency install failures** — May need `--codex-danger-full-access`
- **Context confusion** — Task description may need refinement in TaskMaster

### Status Reporting

After each completed task, report:

- ✅ Task ID and title
- 📝 Commit hash
- ✔️ Verify result (passed/failed)
- 🚧 Any blockers or issues

## Configuration Options

### task-loop.sh Options

| Option | Description | Default |
|--------|-------------|---------|
| `--model` | Codex model to use | `gpt-5.3-codex` |
| `--verify-cmd` | Verification command | `npm run verify` |
| `--verify-timeout <sec>` | Max total verify runtime before fail | `1800` |
| `--verify-idle-timeout <sec>` | Max seconds with no verify output before fail | `300` |
| `--codex-sandbox` | Sandbox mode: `read-only`, `workspace-write`, `danger-full-access` | `workspace-write` |
| `--auto` | Run continuously until all tasks complete | Off |
| `--stop-after-task <id>` | Stop after completing specific task | None |
| `--allow-dirty` | Allow running with uncommitted changes | Off |
| `--no-resume` | Ignore existing resume state | Off |

### task-loop-watchdog.sh Options

| Option | Description | Default |
|--------|-------------|---------|
| `--interval` | Seconds between health checks | `30` |
| `--max-restarts` | Max restart attempts (0=unlimited) | `0` |
| `--loop-arg` | Pass args to task-loop.sh | None |

## Common Issues and Solutions

### 1. Dependency Installation Failures

**Symptom:** Codex can't install packages during task execution

**Solution:** Use full-access mode:
```bash
./scripts/task-loop.sh --auto --codex-danger-full-access
```

Or pre-install dependencies:
```bash
pnpm install
```

### 2. Loop Exits Silently

**Symptom:** task-loop.sh stops running, but tasks remain

**Solution:** Use the watchdog instead:
```bash
./scripts/task-loop-watchdog.sh --interval 300 --loop-arg "--verify-idle-timeout" --loop-arg "300"
```

### 3. Verify Command Fails

**Symptom:** Loop blocks because `npm run verify` fails

**Solutions:**
- Fix test/lint issues manually
- Adjust verify command: `--verify-cmd "npm run test"`
- Review task quality — may need better task descriptions

### 4. Dirty Git Tree

**Symptom:** "Working tree is dirty" error

**Solutions:**
- Commit or stash changes
- Use `--allow-dirty` (for active dev branches only)

### 5. Task Order Seems Random

**Symptom:** Task 24 runs before Task 20

**Explanation:** TaskMaster uses dependency graphs, not numeric order. This is intentional.

**Solution:** Use `--stop-after-task` for manual checkpoints if needed.

### 6. PNPM Monorepo Issues

**Symptom:** Codex can't find installed packages

**Solution:** Ensure hoisting is configured, or use `danger-full-access` mode.

## Best Practices

### 1. Write Clear Task Descriptions

TaskMaster-generated tasks should be:
- **Specific** — "Implement user authentication API endpoint" not "Add auth"
- **Testable** — Include acceptance criteria
- **Independent** — Minimize dependencies when possible

### 2. Maintain Strong Verify Scripts

Your `npm run verify` command should:
- Call `npm run validate`
- Run unit tests
- Run integration tests (if fast)
- Lint code
- Type-check (TypeScript)
- Exit with non-zero on any failure

### 3. Use Checkpoints for Review

For critical milestones, stop the loop to manually review:

```bash
./scripts/task-loop.sh --auto --stop-after-task 12
# Review changes, test manually
git push
./scripts/task-loop.sh --auto --stop-after-task 24
```

### 4. Commit Message Convention

The loop uses: `task(<id>): complete`

This makes it easy to trace commits back to task files:

```bash
git log --grep="task(8)"
```

### 5. One Loop Per Repo

Don't run multiple task-loops simultaneously in the same repo. This causes:
- Duplicate verify runs
- Git conflicts
- State file corruption

### 6. Background Mode Best Practices

When running watchdog in background:

```bash
# Start
nohup ./scripts/task-loop-watchdog.sh --interval 300 \
  --loop-arg "--verify-idle-timeout" --loop-arg "300" \
  --loop-arg "--verify-timeout" --loop-arg "5400" \
  > .taskmaster/watchdog.log 2>&1 &
echo $! > .taskmaster/watchdog.pid

# Monitor
tail -f .taskmaster/watchdog.log

# Stop gracefully
./scripts/task-loop-watchdog.sh --request-stop
rm .taskmaster/watchdog.pid
```

## Integration with Agents

### Codex CLI (Default)

This skill is built for Codex CLI:

```bash
./scripts/task-loop.sh --model gpt-5.3-codex
```

### OpenClaw

Should work with OpenClaw if it exposes a similar CLI:

```bash
# Modify task-loop.sh to call OpenClaw instead:
# openclaw exec --prompt "$TASK_FILE" --sandbox workspace-write
```

### Custom Agents

Any agent that can:
- Read a markdown file (task description)
- Make code changes
- Be invoked from shell
- Exit with success/failure status

Can replace Codex in `task-loop.sh`.

## File Structure

After setup, your repo will have:

```
your-repo/
├── .taskmaster/
│   ├── config.json                    # TaskMaster + AI config
│   ├── docs/
│   │   └── prd.md                     # Compiled PRD
│   ├── tasks/
│   │   ├── tasks.json                 # Task metadata
│   │   ├── task-1.md                  # Individual task files
│   │   ├── task-2.md
│   │   └── ...
│   ├── task-loop-state.json           # Resume state
│   └── task-loop-watchdog.out         # Watchdog logs
├── scripts/
│   ├── bootstrap-taskmaster.sh        # PRD → Tasks
│   ├── compile-plan-prd.sh            # Merge plans
│   ├── task-loop.sh                   # Main executor
│   ├── task-loop-watchdog.sh          # Auto-restart monitor
│   └── install-to-repo.sh             # Setup helper
└── implementation-plan/               # Optional: multi-file PRDs
    ├── 01-architecture.md
    └── 02-database.md
```

## License & Credits

This skill is designed for use with TaskMaster and Codex CLI as part of agent-driven development workflows.

**Created for:** Deterministic, context-efficient PRD implementation  
**Works with:** Codex (OpenAI), OpenClaw, or any shell-invocable AI agent  
**Dependencies:** TaskMaster, Git, Node.js, jq

---

## Quick Start Example

```bash
# 1. Install scripts to your repo
cd ~/my-project
~/.agents/skills/taskmaster-codex-loop/scripts/install-to-repo.sh .

# 2. Create PRD
mkdir -p .taskmaster/docs
cat > .taskmaster/docs/prd.md << 'EOF'
# My Project PRD

Build a REST API for managing todo items with:
- CRUD operations
- User authentication
- PostgreSQL database
- Express.js backend
- Input validation
- Unit tests
EOF

# 3. Bootstrap tasks
./scripts/bootstrap-taskmaster.sh --input .taskmaster/docs/prd.md --num-tasks 20

# 4. Run the loop
./scripts/task-loop.sh --auto

# 5. Monitor progress
watch -n 5 'task-master list --with-subtasks'
```

Now your agent will systematically implement the PRD, one verified task at a time, with clean context per task.

**No more lost context. No more runaway sessions. Just deterministic progress.** 🚀
