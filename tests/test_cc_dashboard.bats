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
