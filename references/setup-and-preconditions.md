# Setup And Preconditions

Use this file when you need to confirm environment readiness or install scripts into a target repository.

## Preconditions

Assume these are true unless user context says otherwise:

- A PRD exists (single file or multiple plan markdown files).
- `codex` CLI is installed and authenticated.
- `task-master`, `jq`, `git`, and `node` are installed.
- `task-master` is configured for the target repo (`.taskmaster/config.json`, provider/API keys as needed for `--research`).
- Work is happening inside a git repository.

## Install Scripts Into Target Repo

If the target repo does not already contain the scripts, run:

```bash
bash <skill-dir>/scripts/install-to-repo.sh <repo-path>
```

Then run all loop commands from the target repo root.

## Optional Skill Pairing

- This skill is standalone for execution loops.
- If user still needs PRD authoring/restructuring, run `prd-taskmaster` first.

## Baseline Repo Checks

Before starting long runs, confirm:

```bash
git rev-parse --show-toplevel
task-master --help >/dev/null
codex --help >/dev/null
```

## Verify Gate Expectation

Default verify gate is `npm run verify`.
Use a stable repo-level verify script (for example test + lint) before unattended runs.

