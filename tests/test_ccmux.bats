#!/usr/bin/env bats

load helpers

setup() {
  setup_common
  TEST_PROJECT=$(create_test_project "${TEST_PREFIX}-proj")
}

teardown() {
  teardown_common
}

@test "ccmux fails outside iTerm2" {
  export TERM_PROGRAM="Apple_Terminal"
  run ccmux "$TEST_PROJECT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"iTerm2"* ]]
}

@test "ccmux fails with no arguments" {
  run ccmux
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "ccmux creates tmux session named after project directory" {
  # Use --no-attach to skip the tmux -CC attach (can't use in tests)
  run ccmux --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local expected_session="${TEST_PREFIX}-proj"
  run tmux has-session -t "$expected_session"
  [ "$status" -eq 0 ]
}

@test "ccmux creates session with two panes" {
  run ccmux --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local session="${TEST_PREFIX}-proj"
  local pane_count
  pane_count=$(tmux list-panes -t "${session}:main" 2>/dev/null | wc -l | tr -d ' ')
  [ "$pane_count" -eq 2 ]
}

@test "ccmux creates home session on first invocation" {
  run ccmux --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  run tmux has-session -t "home"
  [ "$status" -eq 0 ]
}

@test "ccmux is idempotent — second call does not create duplicate windows" {
  run ccmux --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local session="${TEST_PREFIX}-proj"
  local window_count_before
  window_count_before=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')

  run ccmux --no-attach "$TEST_PROJECT"
  [ "$status" -eq 0 ]

  local window_count_after
  window_count_after=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')
  [ "$window_count_before" -eq "$window_count_after" ]
}

@test "ccmux with worktree creates git worktree and new window" {
  run ccmux --no-attach "$TEST_PROJECT" test-feature
  [ "$status" -eq 0 ]

  # Check worktree exists
  [ -d "${TEST_PROJECT}/../${TEST_PREFIX}-proj-test-feature" ]

  # Check tmux window exists
  local session="${TEST_PREFIX}-proj"
  run tmux list-windows -t "$session" -F '#{window_name}'
  [[ "$output" == *"test-feature"* ]]
}

@test "ccmux with worktree is idempotent" {
  run ccmux --no-attach "$TEST_PROJECT" test-feature
  [ "$status" -eq 0 ]

  local session="${TEST_PREFIX}-proj"
  local window_count_before
  window_count_before=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')

  run ccmux --no-attach "$TEST_PROJECT" test-feature
  [ "$status" -eq 0 ]

  local window_count_after
  window_count_after=$(tmux list-windows -t "$session" | wc -l | tr -d ' ')
  [ "$window_count_before" -eq "$window_count_after" ]
}
