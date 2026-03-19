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
