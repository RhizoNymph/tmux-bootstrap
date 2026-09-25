# tmux-bootstrap

Start your tmux sessions from a declarative TOML file.

`tmux-bootstrap` reads a config of named sessions — each with a start
directory and either a single startup command or a list of named windows —
and creates any session that isn't already running. Existing sessions are
skipped, so re-running is safe. See [Shell integration](#shell-integration)
for running it at login without risking your shell.

## Dependencies

- [`tmux`](https://github.com/tmux/tmux)
- [`yq`](https://github.com/mikefarah/yq) v4+ (mikefarah's Go yq; used for
  TOML → JSON. The python-yq CLI is not compatible.)
- [`jq`](https://github.com/jqlang/jq)

## Install

It's a single bash script — copy it anywhere on your `PATH`:

```sh
git clone https://github.com/quantnymph/tmux-bootstrap
install -m 755 tmux-bootstrap/bin/tmux-bootstrap ~/.local/bin/
```

## Usage

```
tmux-bootstrap                  # start everything in the default config
tmux-bootstrap api notes        # only these sessions
tmux-bootstrap -c dev.toml -n   # dry-run an alternate config
tmux-bootstrap -l               # list configured session names
```

Default config path: `${XDG_CONFIG_HOME:-~/.config}/tmux-bootstrap/sessions.toml`.

## Config

Each `[sessions.<name>]` table defines one tmux session:

```toml
# One window, one startup command:
[sessions.notes]
dir = "~/notes"           # start directory (default "~"), leading ~ expands
cmd = "nvim"              # optional startup command

# Or named windows (mutually exclusive with a session-level cmd):
[sessions.api]
dir = "~/Code/api"

[[sessions.api.windows]]
name = "editor"           # optional window name
cmd = "nvim"              # optional startup command

[[sessions.api.windows]]
name = "server"
dir = "~/Code/api/srv"    # optional, defaults to the session dir
cmd = "make dev"
```

See [`examples/sessions.toml`](examples/sessions.toml) for a fuller,
annotated example. Commands are typed into the window's shell with
`send-keys`, so the window stays open after the command exits.

## Shell integration

`tmux-bootstrap` is a program, not a library. **Never `source` it** from
`~/.bashrc` or `~/.profile`: it enables `set -euo pipefail` and calls `exit`
on any error, so a sourced copy would kill or cripple every login shell
(including the ones your display manager starts) the moment yq is missing or
the config has a typo. The script detects this and returns an error instead
of running, but the safe pattern is to run it as a child process:

```bash
# ~/.bashrc — place it after the interactive-shell check
if [[ -z ${TMUX:-} ]] && command -v tmux-bootstrap >/dev/null 2>&1; then
  _tb_log="${XDG_STATE_HOME:-$HOME/.local/state}/tmux-bootstrap.log"
  mkdir -p "${_tb_log%/*}" 2>/dev/null
  ( timeout 10 tmux-bootstrap >>"$_tb_log" 2>&1 & )
  unset _tb_log
fi
```

- `$TMUX` empty: every tmux window runs your rc file too; this stops the
  windows the tool just created from re-running it.
- `command -v`: an uninstalled tool is a no-op, not an error at login.
- Background subshell: the tool can never `exit` your shell or leak its
  shell options, and its exit status is not your shell's.
- `timeout`: a hung tmux server or yq cannot stall every new terminal.
- Log file: failures stay visible without printing over your prompt.

Do not `exec tmux` from an rc file, and keep any `tmux attach` behind the
same `$TMUX` guard. Before logging out, prove the change from the terminal
you edited in:

```sh
bash -i -c 'echo shell survived'
```

If a login shell ever does break, you do not need rescue media: add
`systemd.unit=rescue.target` to the kernel line in GRUB, or over ssh run
`ssh -t host bash --norc --noprofile`.

## Exit codes and output

| Code | Meaning |
| ---- | ------- |
| 0 | success |
| 1 | usage error (bad CLI invocation) |
| 2 | config error (missing/invalid config, unknown session, bad dir) |
| 3 | missing dependency |

Logs are `key=value` pairs on stderr; `--list` output is on stdout.

## Tests

```sh
bash tests/run_tests.sh
```

The suite runs against a private tmux server socket; your own tmux
sessions are never touched.

## License

[MIT](LICENSE)
