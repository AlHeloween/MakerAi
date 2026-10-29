---
name: fleet-delegation
description: Delegate a bounded task to a robot session through tools/fleet.exe and verify the result yourself. Use whenever a task needs code, a deep search or a long tool tail — this host frames, dispatches, watches and verifies; the robot executes. tools/fleet.exe REPLACES dispatch.py, send_note.py, watch3.py and fleet.py, so any older command line in another skill is stale.
metadata:
  owner_decision: "2026-10-26 — the big-model hosts frame and verify, they do not write code"
  measured_against: "tools/fleet/*.go read 2026-10-26 (send.go, wait.go, finish.go, record.go, dispatch.go, status.go, main.go)"
---

# fleet-delegation — the big model frames, the robot executes

Your window carries a large model and a thin working memory: search, tactics and long tool tails are
where it loses. The robot's window is the opposite. So the split is fixed:

- **this host**: understand the request, frame ONE bounded task, write the brief, dispatch it, watch it,
  **run the oracle itself**, and make the commit;
- **the robot**: read the binding, write the code, run the tests, report what it changed.

Writing the code here instead is the defect this skill exists to prevent — it costs more tokens, lands
worse, and leaves the big model's judgment spent on typos instead of on the verdict.

## The binary

`D:\zPython\opencode\tools\fleet.exe <verb> [flags]` — the canonical home is `tools/`, built from `tools/fleet/*.go`; never copy it and never edit `bin/`.

The verbs, measured from the Go source (2026-10-26) — **not** from its own `help`, which lists only
four of them:

| verb | what it does | flags that matter |
|---|---|---|
| `send` | the dispatch act. **Dry run by default**: without `--send` it only prints the body it WOULD post | `--session` (required), `--message` or `--message-file`, `--model`/`--provider`/`--transcript` (keeps the session's own model), `--agent`, `--owner`, `--task`, `--worktree`, `--timeout`, `--send` |
| `wait` | polls a transcript for the handshake row — no nudge, no resend | `--session`/`--transcript`, `--after`, `--timeout`, `--poll`, `--json` |
| `state` | the run's state for one robot session | `--session`, `--worktree`, `--db`, `--json` |
| `status` | every robot and its state | `--worktree` |
| `record` | ownership rows: which chat ordered which robot for which task | `--robot`, `--owner`, `--task`, `--lookup`, `--list`, `--reassign`, `--json` |
| `dispatch` | reads the dispatch rows (what HAPPENED to the HTTP request) | `--id`, `--worktree`, `--json` |

There is **no `finish` verb** (the `runState` implementation happens to live in `finish.go`), and
`fleet dispatch` is a read, not the act — `send … --send` is the act.

## The cycle, in this order

1. **Frame.** One bounded task with a concrete binding and one oracle. Write the brief to a FILE
   (`experiments/<ISO-date>_robot-<task>/brief.md`), never a quoted shell string: address the robot by
   name, quote the plan's intention, name the paths it may touch, name the oracle — and **withhold the
   expected result**.
2. **Dry run first.** `fleet.exe send --session <robot> --message-file <brief> --task <id> --owner <id>`
   prints the model it resolved and the exact body. Read it; only then add `--send`.
3. **Dispatch.** `--send` **refuses** without `--owner <this session id>` and `--task <task id>` — the
   ownership row is written BEFORE the POST, so a robot cannot exist that no chat knows it ordered.
   The dispatch outcome states are `prepared`, `sent`, `failed` and `uncertain` (no HTTP answer at all);
   `uncertain` is KEPT and reported — never silently retried, because the server may have accepted it.
4. **Watch — immediately, in the background.** `fleet.exe wait --session <robot> --after <row>
   --timeout 1800 --json`. Its exit is the event that brings you back; never end a turn on a promise to
   check later.
5. **Read back only what you need**: `fleet.exe state`, the last `text` event (the final message), every
   `error` event, then `git status --short` and the diff of the BOUND paths only. A hunk outside the
   binding is off-direction: revert it or justify it.
6. **Run the oracle yourself.** The robot's green is testimony, not evidence. One command, its exit, its
   output.
7. **Close**: tick the plan box, write the progress entry, and make ONE commit that names the plan. The
   delegator is the one committer — the robot does not commit.


## Automation — how a robot keeps going without you typing «continue»

The robot's session can be armed to WAKE ITSELF. The settings belong to the SESSION, live in
`{worktree}/.opencode/data/sessions/<id>.jsonc` under `automation`, and two surfaces write that same
file: the `/automation` form in the TUI and `fleet automation` here.

| flag | meaning |
|---|---|
| `--wake-on-child-done on\|off` | wake the session once when a child session IT dispatched reaches idle |
| `--heartbeat 15m\|1h\|900\|off` | wake it when it has been idle that long |
| `--auto current\|all\|N\|off` | this session's own /auto: until a plan leaves `plans/`, until `plans/` is empty, or N turns |
| `--auto-every 5m\|off` | the pause BETWEEN /auto continuations (an interval alone schedules nothing) |
| `--show` / `--json` | read it back |

`fleet automation --session <id> --heartbeat 15m --show` writes and prints it. Durations accept `900`
(seconds), `15m`, `1h`. The verb MERGES: the session's models, sampling and routing survive, and a
file it cannot parse is refused with its path named rather than overwritten.

What a wake IS: one synthetic turn whose text is an `<automation-turn>` block naming the event, the
turn id and the reason — a message nobody typed. Measured 2026-10-26: a 60 s heartbeat armed this way
woke an idle session and opened the very turn it announced, once.

The containment, and why you must not defeat it: a wake fires only when the session is `idle`; a
MISSING status counts as «still starting», never idle; and after a wake the gate stays shut until the
session is observed busy again, so ONE completion produces ONE turn. Do not poll a robot for a
result — arm the heartbeat, end your turn, and let the wake bring you back.

LIMIT, stated rather than hidden: the wake is driven by the TUI's adapter, so it fires only while a
TUI is open on that worktree. A headless `serve` host has no adapter yet — for one, read the session
back with `fleet state` / `fleet wait` instead of expecting a wake.

## Never

- Write product code in this window when the task could be dispatched. Framing is the work.
- Spawn your own subagents for the work. They spend this window's budget, produce a tail nobody verifies, and stall —
  the whole point of the split is that the ROBOT carries the tail. One order to the robot, then insure the result.
- Dispatch without a watcher, or approve a blanket permission flag to "make it go".
- Run two robot tasks on overlapping paths in one tree — they share one oracle and neither is attributable.
- Edit, move or copy anything into `bin/`.
- Retry a `failed` or `uncertain` dispatch with the same id and the same text without first reading its
  row: a duplicate order is worse than a slow one.
