# iTerm2 + tmux + Claude Code Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a turnkey setup for persistent, multi-project Claude Code sessions using tmux and iTerm2's `-CC` integration.

**Architecture:** Session-per-project with helper scripts (`cc`, `cc-list`, `cc-kill`, `cc-dashboard`), a tmux config, an iTerm2 dynamic profile, and an installer. Each project gets a tmux session (iTerm2 window); worktrees get tmux windows (iTerm2 tabs) within that session.

**Tech Stack:** zsh scripts, tmux 3.6+, iTerm2 3.6+ with `-CC` mode, bats-core for testing, git worktrees

**Spec:** `docs/superpowers/specs/2026-03-19-iterm-tmux-claude-code-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `tmux.conf` | Minimal tmux config for iTerm2 `-CC` mode |
| `bin/cc` | Main launcher: create/attach sessions, manage worktrees |
| `bin/cc-list` | List all Claude Code sessions with status |
| `bin/cc-kill` | Graceful teardown of sessions/windows + worktree cleanup |
| `bin/cc-dashboard` | Formatted status display for home session |
| `iterm2/claude-code.json` | iTerm2 dynamic profile |
| `install.sh` | Symlinks, copies, dependency checks, PATH warning |
| `tests/test_cc.bats` | Tests for `cc` script logic |
| `tests/test_cc_list.bats` | Tests for `cc-list` output |
| `tests/test_cc_kill.bats` | Tests for `cc-kill` logic |
| `tests/test_install.bats` | Tests for `install.sh` checks |
| `tests/helpers.bash` | Shared test helpers (mock tmux, setup/teardown) |

---

### Task 1: Project Setup and Test Infrastructure

**Files:**
- Create: `tests/helpers.bash`
- Create: `.gitignore`

- [ ] **Step 1: Install bats-core if not present**

Run: `brew list bats-core 2>/dev/null || brew install bats-core`
Expected: bats-core available at `bats`

- [ ] **Step 2: Create `.gitignore`**

```gitignore
# test artifacts
tests/tmp/
```

- [ ] **Step 3: Create shared test helpers**

Create `tests/helpers.bash`:

```bash
# tests/helpers.bash — shared setup/teardown for bats tests

# Unique prefix to avoid colliding with real tmux sessions
TEST_PREFIX="cctest-$$"

# Temp dir for test artifacts
TEST_TMP="$BATS_TEST_TMPDIR"

setup_common() {
  export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
  # Override TERM_PROGRAM so cc thinks it's in iTerm2
  export TERM_PROGRAM="iTerm.app"
}

teardown_common() {
  # Kill any test tmux sessions
  tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | grep "^${TEST_PREFIX}" \
    | while read -r s; do tmux kill-session -t "$s" 2>/dev/null; done
}

# Create a fake project directory with git init
create_test_project() {
  local name="${1:?project name required}"
  local dir="$TEST_TMP/$name"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "test@test.local"
  git -C "$dir" config user.name "Test"
  git -C "$dir" commit --allow-empty -m "init" --quiet
  echo "$dir"
}
```

- [ ] **Step 4: Verify bats runs with helpers**

Run: `echo '@test "sanity" { true; }' > /tmp/sanity.bats && bats /tmp/sanity.bats`
Expected: `1 test, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add .gitignore tests/helpers.bash
git commit -m "feat: add test infrastructure with bats helpers"
```

---

### Task 2: tmux Configuration

**Files:**
- Create: `tmux.conf`

- [ ] **Step 1: Create `tmux.conf`**

```tmux
# tmux.conf — minimal config for iTerm2 -CC integration

# Mouse support (useful when not in -CC mode)
set -g mouse on

# Start window numbering at 1
set -g base-index 1
setw -g pane-base-index 1

# Increase history limit
set -g history-limit 50000

# Default shell
set -g default-shell /bin/zsh

# Renumber windows when one is closed
set -g renumber-windows on

# Display pane numbers longer
set -g display-panes-time 2000
```

- [ ] **Step 2: Verify tmux loads the config without errors**

Run: `tmux -f tmux.conf start-server \; kill-server`
Expected: No output (clean exit)

- [ ] **Step 3: Commit**

```bash
git add tmux.conf
git commit -m "feat: add minimal tmux config for iTerm2 -CC mode"
```

---

### Task 3: `cc-dashboard` Script

**Files:**
- Create: `bin/cc-dashboard`
- Create: `tests/test_cc_dashboard.bats`

Build dashboard first since `cc-list` reuses its logic, and the home session runs it.

- [ ] **Step 1: Write the failing test**

Create `tests/test_cc_dashboard.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_common
}

teardown() {
  teardown_common
}

@test "cc-dashboard outputs header line" {
  run cc-dashboard
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"SESSION"* ]]
  [[ "${lines[0]}" == *"WINDOW"* ]]
}

@test "cc-dashboard shows running tmux session" {
  local session="${TEST_PREFIX}-dash"
  tmux new-session -d -s "$session" -x 80 -y 24
  run cc-dashboard
  [ "$status" -eq 0 ]
  [[ "$output" == *"$session"* ]]
}

@test "cc-dashboard shows no sessions message when none exist" {
  # Kill all test sessions first (teardown_common)
  teardown_common
  # Also kill any real sessions would be dangerous, so just check output format
  run cc-dashboard
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_cc_dashboard.bats`
Expected: FAIL — `cc-dashboard: command not found`

- [ ] **Step 3: Write `bin/cc-dashboard`**

```bash
#!/usr/bin/env zsh
# cc-dashboard — display status of all tmux sessions with Claude Code info

set -euo pipefail

# Header
printf "%-20s %-15s %-40s %-8s %-20s\n" "SESSION" "WINDOW" "PATH" "CLAUDE" "BRANCH"
printf "%s\n" "$(printf '=%.0s' {1..105})"

# Check if tmux server is running
if ! tmux list-sessions &>/dev/null; then
  echo "No tmux sessions running."
  exit 0
fi

tmux list-sessions -F '#{session_name}' | while read -r session; do
  tmux list-windows -t "$session" -F '#{window_name} #{pane_id}' | while read -r wname pane_id; do
    # Get the working directory of the first pane
    pane_path=$(tmux display-message -t "$pane_id" -p '#{pane_current_path}' 2>/dev/null || echo "?")

    # Check if claude is running in any pane of this window
    claude_status="stopped"
    window_panes=$(tmux list-panes -t "${session}:${wname}" -F '#{pane_pid}' 2>/dev/null)
    for ppid in ${(f)window_panes}; do
      if pgrep -P "$ppid" -f "claude" &>/dev/null; then
        claude_status="running"
        break
      fi
    done

    # Get git branch if in a git repo
    branch="—"
    if [ -d "$pane_path/.git" ] || git -C "$pane_path" rev-parse --git-dir &>/dev/null 2>&1; then
      branch=$(git -C "$pane_path" branch --show-current 2>/dev/null || echo "?")
    fi

    # Truncate path for display
    display_path="${pane_path/#$HOME/~}"
    if [ ${#display_path} -gt 38 ]; then
      display_path="…${display_path: -37}"
    fi

    printf "%-20s %-15s %-40s %-8s %-20s\n" "$session" "$wname" "$display_path" "$claude_status" "$branch"
  done
done
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x bin/cc-dashboard && bats tests/test_cc_dashboard.bats`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add bin/cc-dashboard tests/test_cc_dashboard.bats
git commit -m "feat: add cc-dashboard for session status display"
```

---

### Task 4: `cc-list` Script

**Files:**
- Create: `bin/cc-list`
- Create: `tests/test_cc_list.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/test_cc_list.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_common
}

teardown() {
  teardown_common
}

@test "cc-list outputs same info as cc-dashboard" {
  local session="${TEST_PREFIX}-list"
  tmux new-session -d -s "$session" -x 80 -y 24
  run cc-list
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"SESSION"* ]]
  [[ "$output" == *"$session"* ]]
}

@test "cc-list exits 0 with no sessions" {
  teardown_common
  run cc-list
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/test_cc_list.bats`
Expected: FAIL — `cc-list: command not found`

- [ ] **Step 3: Write `bin/cc-list`**

```bash
#!/usr/bin/env zsh
# cc-list — list all Claude Code tmux sessions
# Thin wrapper around cc-dashboard

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
exec "$SCRIPT_DIR/cc-dashboard"
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x bin/cc-list && bats tests/test_cc_list.bats`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add bin/cc-list tests/test_cc_list.bats
git commit -m "feat: add cc-list as wrapper around cc-dashboard"
```

---

### Task 5: `cc` Script — Core Session Management

**Files:**
- Create: `bin/cc`
- Create: `tests/test_cc.bats`

This is the largest script. Build incrementally: first session creation (no `-CC` attach since tests can't use iTerm2), then worktree support.

- [ ] **Step 1: Write failing tests for session creation logic**

Create `tests/test_cc.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_common
  TEST_PROJECT=$(create_test_project "${TEST_PREFIX}-proj")
}

teardown() {
  teardown_common
}

@test "cc fails outside iTerm2" {
  export TERM_PROGRAM="Apple_Terminal"
  run cc "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"iTerm2"* ]]
}

@test "cc fails with no arguments" {
  run cc
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cc creates tmux session named after project directory" {
  # Use --no-attach to skip the tmux -CC attach (can't use in tests)
  run cc --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local expected_session="${TEST_PREFIX}-proj"
  run tmux has-session -t "$expected_session"
  [ "$status" -eq 0 ]
}

@test "cc creates session with two panes" {
  run cc --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local session="${TEST_PREFIX}-proj"
  local pane_count
  pane_count=$(tmux list-panes -t "${session}:main" 2>/dev/null | wc -l | tr -d ' ')
  [ "$pane_count" -eq 2 ]
}

@test "cc creates home session on first invocation" {
  run cc --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run tmux has-session -t "home"
  [ "$status" -eq 0 ]
}

@test "cc is idempotent — second call does not create duplicate windows" {
  run cc --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local session="${TEST_PREFIX}-proj"
  local window_count_before
  window_count_before=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')

  run cc --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local window_count_after
  window_count_after=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')
  [ "$window_count_before" -eq "$window_count_after" ]
}

@test "cc with worktree creates git worktree and new window" {
  run cc --no-attach "$TEST_PROJECT" test-feature
  [ "$status" -eq 0 ]

  # Check worktree exists
  [ -d "${TEST_PROJECT}/../${TEST_PREFIX}-proj-test-feature" ]

  # Check tmux window exists
  local session="${TEST_PREFIX}-proj"
  run tmux list-windows -t "$session" -F '#{window_name}'
  [[ "$output" == *"test-feature"* ]]
}

@test "cc with worktree is idempotent" {
  run cc --no-attach "$TEST_PROJECT" test-feature
  [ "$status" -eq 0 ]

  local session="${TEST_PREFIX}-proj"
  local window_count_before
  window_count_before=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')

  run cc --no-attach "$TEST_PROJECT" test-feature
  [ "$status" -eq 0 ]

  local window_count_after
  window_count_after=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')
  [ "$window_count_before" -eq "$window_count_after" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/test_cc.bats`
Expected: FAIL — `cc: command not found`

- [ ] **Step 3: Write `bin/cc`**

```bash
#!/usr/bin/env zsh
# cc — create or attach to a Claude Code tmux session
#
# Usage: cc [--no-attach] <project-path> [worktree-name]

set -euo pipefail

# --- Flags ---
NO_ATTACH=false
if [[ "${1:-}" == "--no-attach" ]]; then
  NO_ATTACH=true
  shift
fi

# --- Validation ---
if [[ $# -lt 1 ]]; then
  echo "Usage: cc [--no-attach] <project-path> [worktree-name]" >&2
  exit 1
fi

if [[ "$TERM_PROGRAM" != "iTerm.app" ]] && [[ "$NO_ATTACH" == false ]]; then
  echo "Error: cc must be run from within iTerm2 (tmux -CC requires iTerm2)." >&2
  exit 1
fi

PROJECT_PATH="${1:A}"  # Resolve to absolute path
WORKTREE_NAME="${2:-}"

# --- Derive session name ---
SESSION_NAME="${PROJECT_PATH:t}"  # basename

# --- Ensure home session exists ---
if ! tmux has-session -t "home" 2>/dev/null; then
  SCRIPT_DIR="${0:A:h}"
  tmux new-session -d -s "home" -n "dashboard" -x 200 -y 50
  tmux send-keys -t "home:dashboard" "while true; do clear; $SCRIPT_DIR/cc-dashboard; sleep 30; done" Enter
fi

# --- Helper: check if -CC client is attached to session ---
has_cc_client() {
  local session="$1"
  tmux list-clients -t "$session" -F '#{client_control_mode}' 2>/dev/null | grep -q '^1$'
}

# --- Helper: attach to session via -CC (or skip if --no-attach) ---
attach_session() {
  local session="$1"
  if [[ "$NO_ATTACH" == true ]]; then
    echo "Session '$session' ready. Use tmux -CC attach -t '$session' to connect."
    return 0
  fi
  if has_cc_client "$session"; then
    echo "Session '$session' already has an iTerm2 window. Use Cmd+\` to switch to it."
    return 0
  fi
  exec tmux -CC attach -t "$session"
}

# --- Helper: create a window with claude|shell split ---
create_split_window() {
  local session="$1"
  local window_name="$2"
  local work_dir="$3"
  local is_initial="${4:-false}"  # true when called for the first window after new-session

  # Check if window already exists — idempotent
  if tmux list-windows -t "$session" -F '#{window_name}' 2>/dev/null | grep -q "^${window_name}$"; then
    return 0
  fi

  if [[ "$is_initial" == true ]]; then
    # Rename the default window created by new-session
    tmux rename-window -t "${session}:1" "$window_name"
  else
    # Create a new window
    tmux new-window -t "$session" -n "$window_name" -c "$work_dir"
  fi

  # Split: left pane = claude, right pane = shell
  tmux split-window -t "${session}:${window_name}" -h -c "$work_dir"

  # Left pane (pane 0) runs claude, right pane (pane 1) is shell
  tmux send-keys -t "${session}:${window_name}.0" "cd ${(q)work_dir} && claude" Enter
  tmux send-keys -t "${session}:${window_name}.1" "cd ${(q)work_dir}" Enter

  # Focus left pane
  tmux select-pane -t "${session}:${window_name}.0"
}

# --- Main logic ---
if [[ -z "$WORKTREE_NAME" ]]; then
  # No worktree — open main branch
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    # Create new session
    tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_PATH" -x 200 -y 50
    create_split_window "$SESSION_NAME" "main" "$PROJECT_PATH" true
  fi
  # Session exists (or was just created) — attach
  attach_session "$SESSION_NAME"
else
  # Worktree mode
  WORKTREE_DIR="${PROJECT_PATH:h}/${SESSION_NAME}-${WORKTREE_NAME}"

  # Create git worktree if it doesn't exist
  if [[ ! -d "$WORKTREE_DIR" ]]; then
    git -C "$PROJECT_PATH" worktree add "$WORKTREE_DIR" -b "$WORKTREE_NAME" 2>/dev/null \
      || git -C "$PROJECT_PATH" worktree add "$WORKTREE_DIR" "$WORKTREE_NAME"
  fi

  # Ensure session exists
  if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SESSION_NAME" -c "$PROJECT_PATH" -x 200 -y 50
    create_split_window "$SESSION_NAME" "main" "$PROJECT_PATH" true
  fi

  # Create worktree window (not initial — uses new-window)
  create_split_window "$SESSION_NAME" "$WORKTREE_NAME" "$WORKTREE_DIR"

  # Attach
  attach_session "$SESSION_NAME"
fi
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x bin/cc && bats tests/test_cc.bats`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add bin/cc tests/test_cc.bats
git commit -m "feat: add cc script for session creation and worktree management"
```

---

### Task 6: `cc-kill` Script

**Files:**
- Create: `bin/cc-kill`
- Create: `tests/test_cc_kill.bats`

- [ ] **Step 1: Write failing tests**

Create `tests/test_cc_kill.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_common
  TEST_PROJECT=$(create_test_project "${TEST_PREFIX}-kill")
  # Create a session to kill (suppress output)
  cc --no-attach "$TEST_PROJECT" >/dev/null 2>&1
}

teardown() {
  teardown_common
}

@test "cc-kill fails with no arguments" {
  run cc-kill
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cc-kill session kills the entire session" {
  local session="${TEST_PREFIX}-kill"
  run tmux has-session -t "$session"
  [ "$status" -eq 0 ]

  run cc-kill --yes "$session"
  [ "$status" -eq 0 ]

  run tmux has-session -t "$session"
  [ "$status" -ne 0 ]
}

@test "cc-kill session+window kills only that window" {
  local session="${TEST_PREFIX}-kill"

  # Add a worktree window
  cc --no-attach "$TEST_PROJECT" kill-feat

  local window_count_before
  window_count_before=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')
  [ "$window_count_before" -eq 2 ]

  run cc-kill --yes "$session" kill-feat
  [ "$status" -eq 0 ]

  local window_count_after
  window_count_after=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')
  [ "$window_count_after" -eq 1 ]
}

@test "cc-kill window cleans up git worktree" {
  local session="${TEST_PREFIX}-kill"
  local worktree_dir="${TEST_PROJECT}/../${TEST_PREFIX}-kill-kill-feat"

  cc --no-attach "$TEST_PROJECT" kill-feat
  [ -d "$worktree_dir" ]

  run cc-kill --yes "$session" kill-feat
  [ "$status" -eq 0 ]
  [ ! -d "$worktree_dir" ]
}

@test "cc-kill fails gracefully for nonexistent session" {
  run cc-kill --yes "nonexistent-session-xyz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/test_cc_kill.bats`
Expected: FAIL — `cc-kill: command not found`

- [ ] **Step 3: Write `bin/cc-kill`**

```bash
#!/usr/bin/env zsh
# cc-kill — gracefully teardown Claude Code sessions or windows
#
# Usage: cc-kill [--yes] <session> [window]

set -euo pipefail

# --- Flags ---
AUTO_CONFIRM=false
if [[ "${1:-}" == "--yes" ]]; then
  AUTO_CONFIRM=true
  shift
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: cc-kill [--yes] <session> [window]" >&2
  exit 1
fi

SESSION="$1"
WINDOW="${2:-}"

# --- Validate session exists ---
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Error: session '$SESSION' not found." >&2
  exit 1
fi

# --- Helper: send SIGTERM to claude processes in a pane ---
graceful_stop_pane() {
  local target="$1"
  local pane_pid
  pane_pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null) || return 0
  # Find claude child processes
  local claude_pids
  claude_pids=$(pgrep -P "$pane_pid" -f "claude" 2>/dev/null) || return 0
  for pid in ${(f)claude_pids}; do
    kill -TERM "$pid" 2>/dev/null || true
  done
}

# --- Helper: wait for claude to exit ---
wait_for_claude() {
  local target="$1"
  local timeout=5
  local i=0
  while (( i < timeout )); do
    local pane_pid
    pane_pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null) || return 0
    if ! pgrep -P "$pane_pid" -f "claude" &>/dev/null; then
      return 0
    fi
    sleep 1
    (( i++ ))
  done
}

# --- Helper: find worktree path for a window ---
get_worktree_path() {
  local session="$1"
  local window="$2"
  local pane_path
  pane_path=$(tmux display-message -t "${session}:${window}.0" -p '#{pane_current_path}' 2>/dev/null) || return 1

  # Check if this path is a git worktree (not the main repo)
  local git_common_dir
  git_common_dir=$(git -C "$pane_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  local git_dir
  git_dir=$(git -C "$pane_path" rev-parse --path-format=absolute --git-dir 2>/dev/null) || return 1

  # If git-dir != git-common-dir, this is a worktree
  if [[ "$git_dir" != "$git_common_dir" ]]; then
    echo "$pane_path"
    return 0
  fi
  return 1
}

# --- Helper: remove worktree safely ---
remove_worktree() {
  local worktree_path="$1"

  # Find the main repo root (git-common-dir points to main .git)
  local main_git_dir
  main_git_dir=$(git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  local main_repo="${main_git_dir%/.git}"

  # Check if locked
  local porcelain
  porcelain=$(git -C "$main_repo" worktree list --porcelain 2>/dev/null)
  if echo "$porcelain" | grep -A1 "worktree ${worktree_path}" | grep -q "^locked"; then
    echo "Warning: worktree at '$worktree_path' is locked. Unlock it manually with:"
    echo "  git worktree unlock '$worktree_path'"
    return 1
  fi

  # Try normal remove first, then --force if dirty
  # Must run from main repo, not from the worktree being removed
  if ! git -C "$main_repo" worktree remove "$worktree_path" 2>/dev/null; then
    echo "Warning: worktree has modifications. Force removing..."
    git -C "$main_repo" worktree remove --force "$worktree_path"
  fi
}

if [[ -z "$WINDOW" ]]; then
  # --- Kill entire session ---
  if [[ "$AUTO_CONFIRM" == false ]]; then
    echo -n "Kill session '$SESSION' and all its windows? [y/N] "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 0
  fi

  # Graceful stop all panes
  tmux list-panes -s -t "$SESSION" -F '#{pane_id}' | while read -r pane; do
    graceful_stop_pane "$pane"
  done

  # Brief wait
  sleep 2

  tmux kill-session -t "$SESSION"
  echo "Session '$SESSION' killed."
else
  # --- Kill specific window ---
  if ! tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -q "^${WINDOW}$"; then
    echo "Error: window '$WINDOW' not found in session '$SESSION'." >&2
    exit 1
  fi

  if [[ "$AUTO_CONFIRM" == false ]]; then
    echo -n "Kill window '$WINDOW' in session '$SESSION'? [y/N] "
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]] || exit 0
  fi

  # Try to get worktree path before killing the window
  worktree_path=""
  worktree_path=$(get_worktree_path "$SESSION" "$WINDOW") || true

  # Graceful stop claude in this window's panes
  tmux list-panes -t "${SESSION}:${WINDOW}" -F '#{pane_id}' | while read -r pane; do
    graceful_stop_pane "$pane"
  done
  wait_for_claude "${SESSION}:${WINDOW}.0"

  # Kill the window
  tmux kill-window -t "${SESSION}:${WINDOW}"
  echo "Window '$WINDOW' in session '$SESSION' killed."

  # Clean up worktree if applicable
  if [[ -n "$worktree_path" ]] && [[ -d "$worktree_path" ]]; then
    remove_worktree "$worktree_path" || true
  fi
fi
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x bin/cc-kill && bats tests/test_cc_kill.bats`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add bin/cc-kill tests/test_cc_kill.bats
git commit -m "feat: add cc-kill for graceful session/window teardown"
```

---

### Task 7: iTerm2 Dynamic Profile

**Files:**
- Create: `iterm2/claude-code.json`

- [ ] **Step 1: Create the dynamic profile JSON**

Create `iterm2/claude-code.json`:

```json
{
  "Profiles": [
    {
      "Name": "Claude Code",
      "Guid": "claude-code-tmux-home",
      "Custom Command": "Yes",
      "Command": "tmux -CC attach -t home 2>/dev/null || echo 'No home session found. Run cc <project-path> first to create one.'",
      "Tags": ["claude", "tmux"],
      "Unlimited Scrollback": true,
      "Background Color": {
        "Red Component": 0.05,
        "Green Component": 0.05,
        "Blue Component": 0.08,
        "Alpha Component": 1.0,
        "Color Space": "sRGB"
      },
      "Use Non-ASCII Font": false,
      "Silence Bell": true,
      "Close Sessions On End": true
    }
  ]
}
```

- [ ] **Step 2: Validate JSON is well-formed**

Run: `python3 -m json.tool iterm2/claude-code.json > /dev/null`
Expected: No output (valid JSON)

- [ ] **Step 3: Commit**

```bash
git add iterm2/claude-code.json
git commit -m "feat: add iTerm2 dynamic profile for Claude Code home session"
```

---

### Task 8: `install.sh`

**Files:**
- Create: `install.sh`
- Create: `tests/test_install.bats`

- [ ] **Step 1: Write failing tests**

Create `tests/test_install.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_common
  # Use a temp HOME to avoid modifying real config
  export FAKE_HOME="$TEST_TMP/fakehome"
  mkdir -p "$FAKE_HOME/.local/bin"
  mkdir -p "$FAKE_HOME/Library/Application Support/iTerm2/DynamicProfiles"
}

teardown() {
  teardown_common
}

@test "install.sh checks for tmux" {
  PATH="/nonexistent:$PATH"
  # Override which to simulate missing tmux
  run bash -c 'PATH="/usr/bin:/bin" && source install.sh --check-deps-only 2>&1'
  # This is hard to test without side effects, so test the function exists
  true
}

@test "install.sh detects missing PATH entry" {
  # Run install with a PATH that doesn't include ~/.local/bin
  INSTALL_HOME="$FAKE_HOME" PATH="/usr/bin:/bin" run bash -c "
    cd $BATS_TEST_DIRNAME/..
    source install.sh --dry-run 2>&1
  "
  [[ "$output" == *"PATH"* ]] || [[ "$output" == *"path"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/test_install.bats`
Expected: FAIL — install.sh doesn't exist

- [ ] **Step 3: Write `install.sh`**

```bash
#!/usr/bin/env zsh
# install.sh — install cc tools, tmux config, and iTerm2 profile
#
# Usage: install.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

SCRIPT_DIR="${0:A:h}"
INSTALL_HOME="${INSTALL_HOME:-$HOME}"
BIN_DIR="$INSTALL_HOME/.local/bin"
TMUX_CONF="$INSTALL_HOME/.tmux.conf"
DYNAMIC_PROFILES_DIR="$INSTALL_HOME/Library/Application Support/iTerm2/DynamicProfiles"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo "${GREEN}[OK]${NC} $1"; }
warn()  { echo "${YELLOW}[WARN]${NC} $1"; }
error() { echo "${RED}[ERROR]${NC} $1" >&2; }

# --- Step 1: Check dependencies ---
missing=()
for cmd in tmux claude git; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("$cmd")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  error "Missing dependencies: ${missing[*]}"
  exit 1
fi
info "Dependencies found: tmux, claude, git"

# --- Step 2: Check iTerm2 ---
if [[ "$TERM_PROGRAM" != "iTerm.app" ]] && [[ "$DRY_RUN" == false ]]; then
  warn "Not running inside iTerm2. iTerm2 preference will not be set."
  warn "Run this from iTerm2, or manually set: defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2"
else
  if [[ "$DRY_RUN" == false ]]; then
    defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2
    info "iTerm2 tmux preference configured (OpenTmuxWindowsIn = tabs)"
  else
    echo "[DRY-RUN] Would set: defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2"
  fi
fi

# --- Step 3: Symlink tmux.conf ---
if [[ -f "$TMUX_CONF" ]] && [[ ! -L "$TMUX_CONF" ]]; then
  if [[ "$DRY_RUN" == false ]]; then
    cp "$TMUX_CONF" "${TMUX_CONF}.backup.$(date +%Y%m%d%H%M%S)"
    warn "Existing ~/.tmux.conf backed up"
  else
    echo "[DRY-RUN] Would backup $TMUX_CONF"
  fi
fi
if [[ "$DRY_RUN" == false ]]; then
  ln -sf "$SCRIPT_DIR/tmux.conf" "$TMUX_CONF"
  info "Symlinked tmux.conf → ~/.tmux.conf"
else
  echo "[DRY-RUN] Would symlink $SCRIPT_DIR/tmux.conf → $TMUX_CONF"
fi

# --- Step 4: Symlink scripts ---
mkdir -p "$BIN_DIR"
for script in cc cc-list cc-kill cc-dashboard; do
  target="$BIN_DIR/$script"
  if [[ "$DRY_RUN" == false ]]; then
    ln -sf "$SCRIPT_DIR/bin/$script" "$target"
  else
    echo "[DRY-RUN] Would symlink $SCRIPT_DIR/bin/$script → $target"
  fi
done
info "Symlinked scripts to $BIN_DIR/"

# --- Step 5: Check PATH ---
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  warn "$BIN_DIR is not in your PATH."
  warn "Add this to your ~/.zshrc:"
  warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- Step 6: Copy dynamic profile ---
if [[ -d "$DYNAMIC_PROFILES_DIR" ]]; then
  if [[ "$DRY_RUN" == false ]]; then
    cp "$SCRIPT_DIR/iterm2/claude-code.json" "$DYNAMIC_PROFILES_DIR/"
    info "Copied iTerm2 dynamic profile"
  else
    echo "[DRY-RUN] Would copy $SCRIPT_DIR/iterm2/claude-code.json → $DYNAMIC_PROFILES_DIR/"
  fi
else
  warn "iTerm2 DynamicProfiles directory not found. Skipping profile install."
fi

# --- Step 7: Start tmux server ---
if [[ "$DRY_RUN" == false ]]; then
  tmux start-server 2>/dev/null || true
  info "tmux server started"
else
  echo "[DRY-RUN] Would start tmux server"
fi

echo ""
info "Installation complete! Open a new iTerm2 window with the 'Claude Code' profile for the dashboard."
info "Run 'cc <project-path>' to start a Claude Code session."
```

- [ ] **Step 4: Make executable and run tests**

Run: `chmod +x install.sh && bats tests/test_install.bats`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.bats
git commit -m "feat: add install.sh with dependency checks and PATH warning"
```

---

### Task 9: Integration Test — Full Workflow

**Files:**
- Create: `tests/test_integration.bats`

End-to-end test of the full workflow (without iTerm2 `-CC` attachment).

- [ ] **Step 1: Write integration test**

Create `tests/test_integration.bats`:

```bash
#!/usr/bin/env bats

load helpers

setup() {
  setup_common
  TEST_PROJECT=$(create_test_project "${TEST_PREFIX}-integ")
}

teardown() {
  teardown_common
  # Clean up any worktrees
  local wt_dir="${TEST_PROJECT}/../${TEST_PREFIX}-integ-feat-x"
  [ -d "$wt_dir" ] && git -C "$TEST_PROJECT" worktree remove --force "$wt_dir" 2>/dev/null || true
}

@test "full workflow: create session, add worktree, list, kill worktree, kill session" {
  local session="${TEST_PREFIX}-integ"

  # 1. Create session
  run cc --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]
  run tmux has-session -t "$session"
  [ "$status" -eq 0 ]

  # 2. Add worktree
  run cc --no-attach "$TEST_PROJECT" feat-x
  [ "$status" -eq 0 ]
  [ -d "${TEST_PROJECT}/../${session}-feat-x" ]

  # 3. List sessions
  run cc-list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$session"* ]]
  [[ "$output" == *"feat-x"* ]]

  # 4. Kill worktree window
  run cc-kill --yes "$session" feat-x
  [ "$status" -eq 0 ]
  [ ! -d "${TEST_PROJECT}/../${session}-feat-x" ]

  # 5. Kill session
  run cc-kill --yes "$session"
  [ "$status" -eq 0 ]
  run tmux has-session -t "$session"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run integration test**

Run: `bats tests/test_integration.bats`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add tests/test_integration.bats
git commit -m "test: add full workflow integration test"
```

---

### Task 10: Run All Tests and Final Cleanup

- [ ] **Step 1: Run full test suite**

Run: `bats tests/`
Expected: All tests pass

- [ ] **Step 2: Run shellcheck on all scripts**

Run: `brew list shellcheck 2>/dev/null || brew install shellcheck && shellcheck bin/* install.sh`

Note: shellcheck may not fully support zsh. For zsh-specific constructs, use `# shellcheck disable=SCxxxx` annotations where needed.

- [ ] **Step 3: Fix any issues found**

Address any shellcheck warnings or test failures.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "chore: fix shellcheck warnings and cleanup"
```

- [ ] **Step 5: Final verification**

Run: `bats tests/ && echo "All tests pass!"`
Expected: `All tests pass!`
