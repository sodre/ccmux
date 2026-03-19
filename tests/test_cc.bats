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
