# Claude: join the organization

Claude on a Claude subscription joins the organization the same way Codex does. Read `CODEX_ORG.md`: everything
there holds, with these substitutions.

| | Codex | Claude |
|---|---|---|
| Worker login | `codex-worker` | `claude-worker` (`claude` is the interactive agent and the hourly orchestrator) |
| Tick | `org_worker.py --agent codex --once` | `org_worker.py --agent claude --once` |
| Logged in? | `codex login status` | `claude auth status` |
| Host run | `codex exec -C <repo> -s workspace-write --add-dir <scratch>` | `claude -p --permission-mode acceptEdits --add-dir <scratch> --allowedTools Read,Grep,Glob,Edit,Write` |
| Records | `~/.org/workers/codex/` | `~/.org/workers/claude/` |
| Task name | `ADID org_worker codex` | `ADID org_worker claude` |

## What a scheduled Claude run may do

**File tools only:**
- Read, Grep, Glob, Edit and Write;
- Claude Code scopes them to the workspace and the run's scratch dir.

**No Bash rule at all.** Every program tried behind a narrow prefix turned out to be an interpreter. Measured by the installer lane on 2026-10-08:
- `python *org.py*` matches every python command;
- `fossil sql --readonly` runs `.shell`;
- `git diff --output=` writes files;
- a `core.fsmonitor` line in `.git/config` runs a command on `git status`.

**Where the run's inputs and outputs live:**
- The worker supplies the reads in `<scratch>/brief.md`, including the repository state it took itself.
- It applies the outcome from `<scratch>/outcome.json`.
- A ticket that needs build or test commands ends `BLOCKED` with the missing permission named. Widening the list is the user's opt-in, never the agent's.

## Interactive Claude sessions in a project

The Claude kernel reaches a project through the ADID installer: `.claude/reasoning_kernel.md`, imported by `.claude/CLAUDE.md`.
`claude-org.settings.template.json` lets those sessions run the org verbs without a prompt:
- it allows exactly one rule, `Bash("{PYTHON}" "{ORG_HOME}/genesis/org.py" *)`;
- the installer fills `{PYTHON}` and `{ORG_HOME}` on the target machine and shows the rule in its change list before applying it (opt-in);
- an interactive session has its user present to approve anything else.
