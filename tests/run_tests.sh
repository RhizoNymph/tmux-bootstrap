#!/usr/bin/env bash
#
# Test suite for bin/tmux-bootstrap. Runs every test against an isolated
# tmux server (via -L socket) so the user's real tmux server is never touched.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/tmux-bootstrap"
SOCKET="tbtest-$$"
export TMUX_BOOTSTRAP_SOCKET="$SOCKET"
unset TMUX

TESTTMP=""
PASS=0
FAIL=0

tmx() { tmux -L "$SOCKET" "$@"; }

setup() {
  TESTTMP="$(mktemp -d)"
}

teardown() {
  tmx kill-server 2>/dev/null
  rm -rf "$TESTTMP"
}

assert_eq() {
  local exp=$1 got=$2 msg=$3
  if [[ "$exp" != "$got" ]]; then
    echo "assert_eq failed: $msg (expected='$exp' got='$got')"
    return 1
  fi
}

assert_rc() {
  local exp=$1 got=$2 msg=$3
  assert_eq "$exp" "$got" "exit code: $msg"
}

wait_for_file() {
  local f=$1 i
  for i in $(seq 1 50); do
    [[ -e "$f" ]] && return 0
    sleep 0.1
  done
  echo "timed out waiting for file: $f"
  return 1
}

run_test() {
  local fn=$1 out
  setup
  if out=$("$fn" 2>&1); then
    PASS=$((PASS + 1))
    echo "PASS $fn"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL $fn"
    sed 's/^/       /' <<<"$out"
  fi
  teardown
}

# --- tests -------------------------------------------------------------------

test_missing_config() {
  bash "$SCRIPT" -c "$TESTTMP/nope.toml" >/dev/null 2>&1
  assert_rc 2 $? "missing config file"
}

test_invalid_toml() {
  printf 'this is = = not toml\n' >"$TESTTMP/c.toml"
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 2 $? "invalid TOML"
}

test_no_sessions_table() {
  printf '[other]\nx = 1\n' >"$TESTTMP/c.toml"
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 2 $? "config without sessions table"
}

test_simple_session() {
  mkdir -p "$TESTTMP/proj"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.alpha]
dir = "$TESTTMP/proj"
cmd = "touch $TESTTMP/alpha-ran"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 0 $? "simple session" || return 1
  tmx has-session -t "=alpha" 2>/dev/null || { echo "session alpha was not created"; return 1; }
  # Wait for the startup command's marker first: right after new-session the
  # pane process is still the tmux fork (with the invoker's cwd), so reading
  # pane_current_path before the shell execs races.
  wait_for_file "$TESTTMP/alpha-ran" || return 1
  local p
  p=$(tmx display -p -t "=alpha:" '#{pane_current_path}')
  assert_eq "$TESTTMP/proj" "$p" "session start dir" || return 1
}

test_session_with_windows() {
  mkdir -p "$TESTTMP/proj" "$TESTTMP/other"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.beta]
dir = "$TESTTMP/proj"

[[sessions.beta.windows]]
name = "editor"
cmd = "touch $TESTTMP/w-editor"

[[sessions.beta.windows]]
name = "server"
dir = "$TESTTMP/other"
cmd = "touch $TESTTMP/w-server"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 0 $? "session with windows" || return 1
  local names
  names=$(tmx list-windows -t "=beta" -F '#{window_name}' | paste -sd' ')
  assert_eq "editor server" "$names" "window names in order" || return 1
  local p
  p=$(tmx display -p -t "=beta:editor" '#{pane_current_path}')
  assert_eq "$TESTTMP/proj" "$p" "window without dir inherits session dir" || return 1
  p=$(tmx display -p -t "=beta:server" '#{pane_current_path}')
  assert_eq "$TESTTMP/other" "$p" "window dir override" || return 1
  wait_for_file "$TESTTMP/w-editor" || return 1
  wait_for_file "$TESTTMP/w-server" || return 1
}

test_skip_existing_session() {
  mkdir -p "$TESTTMP/proj"
  tmx new-session -d -s gamma -n preexisting -c "$TESTTMP" || { echo "manual setup failed"; return 1; }
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.gamma]
dir = "$TESTTMP/proj"

[[sessions.gamma.windows]]
name = "editor"
cmd = "touch $TESTTMP/should-not-run"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 0 $? "skip existing" || return 1
  local names
  names=$(tmx list-windows -t "=gamma" -F '#{window_name}' | paste -sd' ')
  assert_eq "preexisting" "$names" "existing session left untouched" || return 1
  sleep 0.3
  [[ -e "$TESTTMP/should-not-run" ]] && { echo "command ran in an existing session"; return 1; }
  return 0
}

test_dry_run_creates_nothing() {
  mkdir -p "$TESTTMP/proj"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.alpha]
dir = "$TESTTMP/proj"
cmd = "touch $TESTTMP/alpha-ran"
EOF
  bash "$SCRIPT" -n -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 0 $? "dry run" || return 1
  tmx has-session -t "=alpha" 2>/dev/null && { echo "dry run created a session"; return 1; }
  [[ -e "$TESTTMP/alpha-ran" ]] && { echo "dry run ran a command"; return 1; }
  return 0
}

test_subset_selection() {
  mkdir -p "$TESTTMP/proj"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.alpha]
dir = "$TESTTMP/proj"

[sessions.beta]
dir = "$TESTTMP/proj"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" alpha >/dev/null 2>&1
  assert_rc 0 $? "subset selection" || return 1
  tmx has-session -t "=alpha" 2>/dev/null || { echo "selected session not created"; return 1; }
  tmx has-session -t "=beta" 2>/dev/null && { echo "unselected session was created"; return 1; }
  return 0
}

test_unknown_session_arg() {
  mkdir -p "$TESTTMP/proj"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.alpha]
dir = "$TESTTMP/proj"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" nope >/dev/null 2>&1
  assert_rc 2 $? "unknown session name" || return 1
  tmx has-session -t "=alpha" 2>/dev/null && { echo "sessions were created despite the error"; return 1; }
  return 0
}

test_cmd_and_windows_conflict() {
  mkdir -p "$TESTTMP/proj"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.alpha]
dir = "$TESTTMP/proj"
cmd = "true"

[[sessions.alpha.windows]]
name = "editor"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 2 $? "session with both cmd and windows"
}

test_invalid_session_name() {
  mkdir -p "$TESTTMP/proj"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions."a:b"]
dir = "$TESTTMP/proj"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 2 $? "session name with tmux-reserved character"
}

test_list() {
  mkdir -p "$TESTTMP/proj"
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.alpha]
dir = "$TESTTMP/proj"

[sessions.beta]
dir = "$TESTTMP/proj"
EOF
  local out
  out=$(bash "$SCRIPT" -l -c "$TESTTMP/c.toml" 2>/dev/null | sort | paste -sd' ')
  assert_rc 0 $? "list" || return 1
  assert_eq "alpha beta" "$out" "listed session names"
}

test_missing_dir() {
  cat >"$TESTTMP/c.toml" <<EOF
[sessions.alpha]
dir = "$TESTTMP/does-not-exist"
EOF
  bash "$SCRIPT" -c "$TESTTMP/c.toml" >/dev/null 2>&1
  assert_rc 2 $? "nonexistent session dir"
}

# --- runner ------------------------------------------------------------------

run_test test_missing_config
run_test test_invalid_toml
run_test test_no_sessions_table
run_test test_simple_session
run_test test_session_with_windows
run_test test_skip_existing_session
run_test test_dry_run_creates_nothing
run_test test_subset_selection
run_test test_unknown_session_arg
run_test test_cmd_and_windows_conflict
run_test test_invalid_session_name
run_test test_list
run_test test_missing_dir

echo
echo "passed=$PASS failed=$FAIL"
[[ $FAIL -eq 0 ]]
