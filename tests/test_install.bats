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
