# Overview

```yaml
Overview:
  description: >
    tmux-bootstrap: a single-script CLI that reads a TOML file declaring
    named tmux sessions (start directory, optional named windows, startup
    commands) and creates any that are not already running.
  subsystems:
    - cli (bin/tmux-bootstrap): source guard, argument parsing, dependency
      checks, logging
    - config: TOML -> JSON via yq, schema validation via jq
    - tmux-driver: session/window creation and command injection via tmux,
      isolated behind a wrapper that honors TMUX_BOOTSTRAP_SOCKET
    - tests (tests/run_tests.sh): black-box suite against an isolated tmux
      server socket
  data_flow: >
    sessions.toml -> yq (TOML->JSON) -> jq queries (validation, session and
    window fields) -> tmux new-session / new-window (-P -F pane_id) ->
    tmux send-keys to the returned pane id. Structured key=value logs go to
    stderr; --list output goes to stdout.

Features Index:
  session-bootstrap:
    description: Create configured tmux sessions/windows idempotently from TOML
    entry_points: [bin/tmux-bootstrap]
    depends_on: []
    doc: docs/features/session-bootstrap.md
```
