# Feature: session-bootstrap

## Scope

- Read a TOML config declaring named tmux sessions with a start directory
  and either one startup command or a list of named windows (each with an
  optional dir and command).
- Create any configured session that does not already exist; skip ones that
  do (idempotent re-runs).
- Select a subset of sessions via positional args; `--list` names; `--dry-run`
  previews actions without touching tmux.

## Non-scope

- Split panes / layouts within a window (schema stops at windows).
- Attaching to a session after creation.
- Killing or reconciling existing sessions to match config (no `--force` yet).
- Environment variable expansion in config values (only leading `~` expands).

## Data / control flow

0. Source guard: before anything else (and before `set -e`), the script
   compares `BASH_SOURCE[0]` to `$0`. If they differ it was sourced, so it
   logs an error and `return`s 1 without defining or changing anything in
   the caller. This protects rc files from the `exit`/`set -e` below.
1. `main` parses CLI args (`-c/--config`, `-n/--dry-run`, `-l/--list`,
   `-h`, `-V`, positional session names), then `check_deps` verifies
   `tmux`, `yq`, `jq` exist (exit 3 if not).
2. `load_config` requires the file to exist, converts TOML to JSON once via
   `yq -p toml -o json`, and requires a non-empty `sessions` table
   (exit 2 on any failure). The JSON is held in `CONFIG_JSON` and all later
   reads are `jq` queries against it.
3. `--list` prints `.sessions | keys[]` and exits.
4. `validate_session` runs per session: name must not contain `:` or `.`
   (tmux target separators); `dir`/`cmd` must be strings; `windows` must be
   an array of objects with string `name`/`dir`/`cmd`; setting both `cmd`
   and `windows` is a config error.
5. Positional args are checked against the config; unknown names exit 2
   before anything is created.
6. `create_session` per target:
   - `tmux has-session -t "=name"` → log and skip if it exists.
   - Resolve session `dir` (default `~`, tilde-expanded, must exist).
   - No windows: `new-session -d -c dir -P -F '#{pane_id}'`, then
     `send-keys <cmd> C-m` to the returned pane id if `cmd` is set.
   - With windows: window 0 via `new-session`, the rest via
     `new-window -d -t "=name"`; each uses its own dir (default: session
     dir) and optional `-n name`; commands are sent by pane id.
   - Dry-run logs `would create ...` lines instead of calling tmux mutators.
7. Final summary log: `created=N skipped=M dry_run=B`.

Commands are injected with `send-keys` into the pane's interactive shell
(rather than as the window's process) so the window survives command exit.

## Files

- `bin/tmux-bootstrap` — the entire CLI. Key functions: `log`/`die`
  (structured stderr logging, typed exit codes 1=usage 2=config 3=deps),
  `tmx` (tmux wrapper honoring `TMUX_BOOTSTRAP_SOCKET`), `load_config`,
  `validate_session`, `expand_tilde`, `resolve_dir`, `create_session`, `main`.
- `tests/run_tests.sh` — 14 black-box tests; each runs against a private
  tmux server (`tmux -L tbtest-$$`) created in `setup` and killed in
  `teardown`, with configs generated in a per-test `mktemp -d`.
- `examples/sessions.toml` — annotated example config.

## Invariants and constraints

- Idempotent: an existing session is never modified, and its windows/commands
  are never re-run.
- Validation is completed for all sessions before any tmux mutation happens,
  so a bad config never partially applies (per-window missing dirs are the
  exception: checked at creation time, so earlier sessions may exist).
- The user-facing tmux server is only reached when `TMUX_BOOTSTRAP_SOCKET`
  is unset; tests must always set it.
- `yq` must be mikefarah v4+ (`-p toml`); python-yq's CLI is incompatible.
- Exit codes are stable API: 0 ok, 1 usage, 2 config, 3 missing dependency.
- The script must be executed, never sourced. Sourcing returns 1 (usage)
  and leaves the calling shell's options untouched; `set -euo pipefail` is
  only reached on the executed path. Recommended rc-file integration (guard
  on `$TMUX`, run as a background child with a timeout) is documented in the
  README's Shell integration section.
- stdout is reserved for machine-readable output (`--list`); all logs go to
  stderr as `level=... msg="..." key=value` pairs.
