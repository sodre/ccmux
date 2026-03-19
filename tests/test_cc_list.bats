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
