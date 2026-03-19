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
