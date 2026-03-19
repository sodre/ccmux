# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Tooling for managing persistent, multi-project Claude Code sessions using tmux and iTerm2's `-CC` integration mode. All scripts are zsh.

## Commands

```bash
# Run all tests (21 tests across 6 files)
bats tests/

# Run a single test file
bats tests/test_ccmux.bats

# Run a specific test by name
bats tests/test_ccmux.bats -f "ccmux creates tmux session"

# Install (must run from iTerm2)
./install.sh

# Dry-run install (preview only)
./install.sh --dry-run

# Verify tmux config loads cleanly
tmux -f tmux.conf start-server \; kill-server
```

## Architecture

**Session-per-project model:** Each project gets a tmux session (= one iTerm2 window). Git worktrees become additional tmux windows (= iTerm2 tabs) within that session. Every window is split into two panes: left runs `claude`, right is a shell.

**Key constraint:** tmux `-CC` mode attaches one iTerm2 window per session. Multiple projects = multiple iTerm2 windows, switched via Cmd+`. The `ccmux` script validates `$TERM_PROGRAM == iTerm.app` because `-CC` control protocol only works from iTerm2.

**Script dependency chain:** `ccmux` creates sessions and calls `ccmux-dashboard` for the home session loop. `ccmux-list` is a thin wrapper around `ccmux-dashboard`. `ccmux-kill` uses `get_worktree_path` (comparing `--git-dir` vs `--git-common-dir` with `--path-format=absolute`) and runs `git worktree remove` from the main repo root.

**Pane splitting:** Done explicitly in the `ccmux` script's `create_split_window` function, not via tmux hooks (the `after-new-window` hook doesn't fire for the first window of `new-session`). The `is_initial` parameter distinguishes renaming the default window vs creating a new one.

**Home session:** Created in the background by `ccmux` on first invocation. The iTerm2 dynamic profile attaches to it — user opens a new iTerm2 window with the "Claude Code" profile to see the dashboard.

## Testing

Tests use bats-core. The `--no-attach` flag on `ccmux` bypasses iTerm2 `-CC` attachment for headless testing. `tests/helpers.bash` provides `setup_common`/`teardown_common` (session cleanup with unique `TEST_PREFIX`) and `create_test_project` (temp git repos with local user config for CI compatibility).

Shellcheck does not support zsh (`SC1071`), so the test suite is the primary validation.

## Install Behavior

- Scripts are **symlinked** to `~/.local/bin/` (updates via `git pull`)
- Dynamic profile is **copied** to iTerm2 DynamicProfiles (symlinks not supported — gnachman/iterm2#9107)
- `~/.tmux.conf` is symlinked (existing file backed up)
- iTerm2 preference `OpenTmuxWindowsIn` set to `2` (tabs in attaching window)
