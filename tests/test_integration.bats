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
