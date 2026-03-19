#!/usr/bin/env bats

load helpers

setup() {
  setup_common
}

teardown() {
  teardown_common
}

@test "ccmux-list outputs same info as ccmux-dashboard" {
  local session="${TEST_PREFIX}-list"
  tmux new-session -d -s "$session" -x 80 -y 24
  run ccmux-list
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"SESSION"* ]]
  [[ "$output" == *"$session"* ]]
}

@test "ccmux-list exits 0 with no sessions" {
  teardown_common
  run ccmux-list
  [ "$status" -eq 0 ]
}
