# tmux-bootstrap

Start your tmux sessions from a declarative TOML file.

`tmux-bootstrap` reads a config of named sessions — each with a start
directory and either a single startup command or a list of named windows —
and creates any session that isn't already running. Existing sessions are
skipped, so it's safe to run on every login (e.g. from your shell profile).

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
