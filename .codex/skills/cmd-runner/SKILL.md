---
name: cmd-runner
description: Run interactive commands safely via cmd_runner with per-run logs, inbox bridge, terminal auto-detection, and image capture support.
kernel-gates: [G7, G8]
---

# cmd-runner

**Kernel gates:** G7 (execute bounded implementation steps), G8 (run oracle instruments — tests, builds, probes) — see reasoning-kernel.mdc.

Use this skill when a command may be:
- long/noisy,
- interactive (prompts, TUIs),
- crash-prone or likely to destabilize the agent when run directly,
- render terminal graphics (Kitty/iTerm2/Sixel protocols).

## When to use cmd_runner

**Use cmd_runner for:**
- Long-running builds: `cargo build --release`, `msbuild`, `make`, `gradle build`
- Package installs: `npm install`, `pip install -r requirements.txt`, `cargo fetch`
- Test suites: `pytest`, `cargo test`, `npm test`, `mvn test`
- Interactive TUIs: `htop`, `ncurses` apps, installers with prompts
- Image-rendering commands: `chafa`, `timg`, any Kitty/Sixel protocol output
- Crash-prone or unstable commands
- Commands that produce thousands of lines of output

**Do NOT use cmd_runner for:**
- Quick checks: `list`, `glob`, `git status`, `echo`, `cat` (use product tools, not shell)
- Simple file operations: `cp`, `mv`, `rm`
- Commands that complete in <1 second
- Commands you need to see output from immediately

## Process window behavior

- All subprocesses open with `SW_SHOWMINNOACTIVE` (minimized, taskbar-visible, no focus steal).
- Terminal selection via `--terminal` (see below).
- Default terminal auto-detected by priority.

## What cmd_runner is

- Windows + Linux compatible.
- Default backend uses ConPTY (Windows) or PTY (Linux) for terminal I/O.
- `--direct-terminal` is a Windows Terminal-only graphics backend: the child inherits the actual WT console, so SIXEL capability negotiation and output are not consumed by ConPTY.
- Raw pipe capture mode (`--raw`) for image protocol passthrough — converts Kitty/iTerm2/Sixel to `[IMG:PROTO:b64]` in logs.
- Terminal auto-detection: wt > wezterm > conhost (fallback) (Windows); wezterm > guake > yakuake > xterm > bash (Linux).
- **Default start is minimized** (`SW_SHOWMINNOACTIVE`, taskbar-visible, no focus steal) — including
  wt: its window belongs to WindowsTerminal.exe and not to the launcher PID, so cmd_runner finds it
  by window title (`_minimize_window_by_title_async`) instead of by PID. What PID-based lookup still
  cannot do is *capture* a wt window — use `screenshot` (title-based) or `--direct-terminal`.
- conhost stays as the always-available fallback — use `--terminal conhost` when you need it.
- **No flash, no focus steal** (2026-10-27, owner: «запуск дефолт, фокус не нужен, запуск минимизированным сразу»):
  window state is controlled at the **WinAPI level** — `SW_SHOWMINNOACTIVE` on the launcher, then
  synchronous `ShowWindow(SW_SHOWMINNOACTIVE)` + `SetForegroundWindow(prev)` on the terminal HWND
  (found by title). No CLI position hacks. `--direct-terminal` is the exception — graphics need a
  visible surface.
- Logs: `logs/cmd_runner/<run_id>/`
- Programmatic input bridge: `logs/cmd_runner/<run_id>/inbox.jsonl`
- Can be launched from any working directory (binary found via PATH or absolute path).

## Native input (the tunnel contract, 2026-10-26)

cmd_runner transports the terminal conversation; it does not re-encode it. Measured defects
this replaces: paste arrived as a sheet of typed text, mouse movement printed
`ESC[<35;53;1M` walls, focus events vanished, Cyrillic became mojibake.

- **Input is read raw** (`ENABLE_VIRTUAL_TERMINAL_INPUT`, with `ECHO`/`LINE` off and
  `SetConsoleCP(CP_UTF8)`), so bracketed paste, kitty keys and focus events reach the child
  byte-for-byte and non-ASCII keys arrive as UTF-8. A console that refuses the mode falls
  back to the old record path.
- **Mouse frames go only to a child that asked for mouse** (?1000/?1002/?1003, tracked from
  the child's own output). ConPTY asks the outer terminal for any-event tracking on its own
  behalf, so frames keep arriving — a child that never requested mouse must not see them.
  A frame split across two reads is carried, never leaked as text.
- **Output is untouched**: the raw chunk goes to the terminal first; image/ANSI/CR
  transformations feed the logs only.
- Escape hatch while tuning: `set CMD_RUNNER_NO_VT_INPUT=1` falls back to the record path
  without a rebuild.
- A ConPTY child's only input channel is a VT byte pipe — there is no message channel into it.
  The WM-native host (one `WM_*` event in, one frame out) is planned separately
  (`plans/2026-10-26_cmd-runner-wm-native-host.md`).

## How to run it

- Repo checkout: `.\cmd_runner.exe <command> ...`
- Release bundle: `cmd_runner.exe <command> ...`
- Via adm: `tools/adm.exe --cmd-runner <args...>`
- From any directory: `cmd_runner <command> ...` (if on PATH)
- Version: `cmd_runner --version` (prints build date)

## Core workflow

### 1) Start a run

```
cmd_runner start [--terminal HOST[=ARGS]] [--cols N --rows N] [--direct-terminal] [--raw|--no-raw] [--cwd PATH] -- <command ...>
```

- Prints `run_id` and `inbox=` path.
- Auto-tails last 5 lines after 500ms (default; `--auto-tail 0` to disable).
- `--shell cmd|pwsh|bash` — explicit shell wrapper.
- `--terminal` — select terminal host (see Terminal section below).
- `--cols` / `--rows` — initial ConPTY grid; with the default `wt` launch they also become `wt --size COLS,ROWS`. Use a taller grid (for example, `80x60`) for portrait graphics rendered by `chafa`.
- `--raw` — force raw pipes (no ConPTY, non-interactive batch commands only).
- `--no-raw` — force ConPTY (interactive mode, default).
- Default: ConPTY (interactive) — supports full send/inbox, TUI apps, interactive shells.
- `--direct-terminal` — require `--terminal wt`; preserve SIXEL/terminal graphics and retain `status`, `stop`, job control, and inbox `send` while the payload runs. The direct WT window stays visible. Its stdout/stderr cannot be captured to runner logs by design.

### Graphics in Windows Terminal

Use the direct-terminal backend when `chafa` or another renderer chooses a symbol fallback under ConPTY:

```
cmd_runner start --terminal wt --direct-terminal --cols 80 --rows 60 --keep-open --cwd D:\zPython\ADID_Python\experiments\Vision -- .\dragon.bat
cmd_runner status <run_id>
cmd_runner send <run_id> --keys ENTER
cmd_runner screenshot <run_id>
cmd_runner screenshot <run_id> --out D:\captures\dragon.png
```

- The host enables `ENABLE_VIRTUAL_TERMINAL_PROCESSING` before it creates the child, then the child inherits the real WT console handles.
- Screenshot identifies the visible WT tab by its per-run title. Do not minimize or close that window before capture.
- Use `tail` for ConPTY/raw runs. Direct-terminal image output is intentionally terminal-only, not a log artifact.

### 2) Check status

```
cmd_runner list [--all] [--limit N] [--json]
cmd_runner status <run_id> [--json]
```

### 3) Tail output

```
cmd_runner tail <run_id> [--follow] [-n N] [--text|--stdout] [--wait-ms N]
```

**Key facts:**

- `cmd_runner tail <run_id>` (without `--follow`) reads the **full captured log** directly from disk (`stdout_text.log`). It works **after the run has finished** — no `--follow` needed.
- `--follow` streams the output in real time. It **exits automatically** when the run reaches a terminal state.
- `--follow --wait-ms 0` follows until the run finishes, then returns the full output. This is the simplest way to stream-to-completion.
- `-n N` shows only the last N lines of the log.

**Reading output after a run finishes (canonical flow):**

```
cmd_runner start -- python my_script.py       # returns run_id
cmd_runner wait <run_id>                      # blocks until done
cmd_runner tail <run_id>                      # reads full captured output
cmd_runner tail <run_id> -n 50                # last 50 lines only
```

**Streaming output until completion:**

```
cmd_runner start -- long_command -- <args>    # returns run_id
cmd_runner tail <run_id> --follow --wait-ms 0 # streams until run exits, then stops
```

**Note:** `--auto-tail N` (default 5, on `start`) and `--send-tail N` (default 3, on `send`) are **snapshots only** — they show the last N lines at that moment, not the full output. Use `cmd_runner tail <run_id>` for the complete log.

### 4) Send input (inbox bridge)

```
cmd_runner send <run_id> --text "uptime" --crlf
cmd_runner send <run_id> --keys "ctrl+c"
cmd_runner send <run_id> --keys "TEXT:root,ENTER"
cmd_runner send <run_id> --stdin-file FILEPATH
cmd_runner send <run_id> --text-file FILEPATH
cmd_runner send <run_id> --text-file FILEPATH --paste --no-tail
cmd_runner send <run_id> --text "whoami" --text-as-b64 --crlf
cmd_runner send <run_id> --hex 03
```

- `--keys` tokens: `LEFT,RIGHT,UP,DOWN,HOME,END,INSERT,DELETE,TAB,ESC,ENTER,BACKSPACE,ctrl+a..ctrl+z,TEXT:text,CHAR:char,HEX:hex`
- `--crlf` appends CRLF after text.
- `--paste` sends `ESC[200~`, the exact source bytes, then `ESC[201~`. Use it for a large
  TUI text attachment after the input field is ready. With `--crlf`, the final Enter is
  outside the paste; omit it to leave the attachment unsubmitted. A closing paste marker
  inside the source is rejected. `--keys` cannot be combined with `--paste`.
- Ordinary text sources normalize bare LF to CRLF. Existing CRLF gains no extra bytes.
  Binary sources (`--stdin-file`, `--stdin-b64-file`, `--hex`, `--b64`, `--text-as-b64`)
  preserve bytes; `--stdin-b64-file` is a binary-file alias. Paste preserves both LF and CRLF.
- Auto-tails last 3 lines after send (default; `--send-tail 0` to disable).

**Quoting tips (PowerShell):**
```
cmd_runner send <id> --crlf -- "python3 -c 'print(1+2)'"
cmd_runner send <id> --crlf -- 'echo ~~~hello~~~'           # ~ instead of "
cmd_runner send <id> --crlf -- @'                           # PS here-string
echo LINE1
echo LINE2
'@
```

### 5) Stop / Wait

```
cmd_runner stop <run_id> --reason "done"
cmd_runner wait <run_id> [--timeout-s N] [--json]
cmd_runner killall [--force] [--json]
```

## Terminal selection

```
cmd_runner start --terminal wezterm -- <command ...>
cmd_runner start --terminal wt -- <command ...>
cmd_runner start --terminal conhost -- <command ...>
cmd_runner start --terminal alacritty -- <command ...>       # any exe on PATH
```

### Custom terminal arguments

```
cmd_runner start --terminal wezterm="--config-file ~/.config/wezterm/wezterm.lua" -- <command ...>
cmd_runner start --terminal wt="-w new -d C:\project" -- <command ...>
```

### Auto-detection (default)

| Priority | Windows | Linux |
|----------|---------|-------|
| 1 | wt (Windows Terminal) | wezterm |
| 2 | wezterm | guake |
| 3 | conhost (fallback) | yakuake |
| 4 | bash (git-bash) | xterm |
| 5 | — | bash |

First terminal found on PATH is used. Omit `--terminal` for auto-detection.
- **wt CLI reference**: `docs/wt-cli-reference.md` (archived from learn.microsoft.com, 2026-10-27) — window targeting with `-w <name>`, stacking via `new-tab`, all commands and options. Do not guess; read the reference.

## Image capture (--raw)

**Important:** Raw mode is for non-interactive batch commands only. It does NOT support:
- Interactive input (send/inbox)
- TUI applications
- Shell sessions

When running image-rendering batch commands (`chafa`, `timg`, etc.):

```
cmd_runner start --raw -- <image_command ...>
```

- Raw pipes bypass ConPTY filtering — Kitty/Sixel/iTerm2 escape sequences survive.
- Output is captured in logs with `[IMG:...]` markers.
- Text-based tools (`tail`, `assert`, `snapshot`) work on clean text.
- `--no-raw` forces ConPTY mode (no image capture in logs).

### Output encoding

- `stdout.log` holds the payload's bytes exactly as written; `stdout_text.log` is the readable copy.
- The text copy never stops a run: valid UTF-8 is decoded, any other byte goes through the console OEM code
  page (console apps such as pwsh write that, not UTF-8, to a pipe), and an unmappable byte becomes U+FFFD.
  Read `stdout.log` when the exact bytes matter.
- A fault while writing the logs is recorded in `stderr.log` as `[cmd_runner] output path fault ...`; the
  capture and the payload go on.

## What `state.json` notes mean

- `log final` — the host wrote the final state itself; `exit_code` is the payload's real exit code.
- `host error: <class>: <message>` (status `host_error`) — the host failed and said so; `wait` and `status`
  return `host_error` at once, and the cause is also in `stderr.log`.
- `host error: program not found: <program>` — the program is not on PATH, or its path does not exist.
  Fix the name or the path.
- `wrapper_failed: <message>` in the output, exit **127** — a `.cmd`/`.bat` shim (npm's `bun.cmd`) failed
  before its payload started. The payload's own exit code passes through unchanged.
- `finished by health-check: exit unknown` — the host died without writing its final state. The exit code
  is NOT known; never read it as success. While the host lives, the run stays `running` until its final write.

### Robot lifecycle (2026.10.11)

- `start` explicitly requests Job breakaway for its terminal host. Runner-owned ConPTY,
  raw and direct-terminal Jobs allow explicit breakaway; ordinary children remain managed.
  If Windows denies breakaway, `start` fails visibly and never retries with inherited ownership.
- Processes already launched through an older runner keep their old Job policy. Updating the
  executable does not change their Jobs; restart those launches before using nested `start`.
- A successful breakaway can retain system Job membership. Actual survival after parent exit
  is the lifecycle check. Arbitrary restrictive external Job hierarchies are not qualified.
- `status --json` and JSON `list` refresh process liveness. A raw file read is a saved snapshot.
  `running` means a live payload or host; it does not prove an HTTP listener, TUI input readiness,
  provider progress, or completion of a robot task.
- For OpenCode robots, use the `opencode-bridge` HTTP route: validate the worktree host nonce,
  authenticated request and session completion. A live PID with a failed HTTP probe is a transport
  failure to investigate, never a successful agent run.

## Screenshot

```
cmd_runner screenshot <run_id> [--out PATH]
```

- Captures a visible `--direct-terminal --terminal wt` window to PNG.
- Without `--out`, writes `logs/cmd_runner/<run_id>/screenshot.png`.

## Auto-tail options

| Flag | Default | Description |
|------|---------|-------------|
| `--auto-tail N` | 5 | After start, show last N lines |
| `--send-tail N` | 3 | After send, show last N lines |
| `--wait-ms N` | 500 | Delay before auto-tail (ms) |
| `--tail-timeout N` | 0 | Retry tail up to N seconds |

## Log layout

The run store is `<exe dir>/logs/cmd_runner/` (the `tools/` parent when it also holds `cmd_runner.exe`).
`CMD_RUNNER_LOG_ROOT=<dir>` moves it for every subcommand (start, tail, status, wait, list, stop, send, ...);
`--log-root <dir>` does the same for one invocation. Use it when the tool's folder must stay unchanged,
e.g. an install that is re-verified against a manifest. `start` passes the root to its host explicitly.

```
logs/cmd_runner/<run_id>/
  meta.json       — session metadata (argv, cwd, normalized_argv, terminal)
  state.json      — current state (status, exit_code, timestamps)
  stdout.log      — captured output (with [IMG:...] markers in raw mode)
  stdout_text.log — ANSI-stripped text
  stderr.log      — stderr output
  in.log          — inbox messages
  inbox.jsonl     — input bridge (append JSONL to send input)
  payload.cmd     — generated wrapper script (when applicable)
```

## SSH session example

```
cmd_runner start -- ssh root@host                       # start interactive SSH
cmd_runner send <run_id> --text "uptime; df -h" --crlf  # send command
cmd_runner send <run_id> --keys ctrl+c                  # interrupt
cmd_runner send <run_id> --keys ctrl+d                  # end session
```

## Notes

- Bare Windows script shims (npm, npx) auto-wrapped in PowerShell `-File`.
- `.bat`/`.cmd` files auto-wrapped in `cmd.exe /c` to prevent `SearchPathW` AV.
- `add_crlf` defaults to `false` (no implicit Enter).
- All subprocess windows open minimized.
- Direct-terminal Windows Terminal windows are the exception: they remain visible for graphics rendering and screenshot capture.
- `wait` without `--timeout-s` blocks indefinitely.
