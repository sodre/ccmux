# iTerm2 + tmux + Claude Code Multi-Session Setup

## Overview

A configuration and tooling setup that enables persistent, multi-project Claude Code sessions using tmux for session management and iTerm2's native tmux integration (`-CC` mode) for a seamless GUI experience.

## Goals

- **Persistent sessions** — Claude Code keeps running even if iTerm2 closes; reconnect anytime
- **Multi-project switching** — multiple Claude Code instances running simultaneously, one per project, easily switchable
- **Git worktree support** — spawn additional Claude Code sessions in isolated worktrees for parallel branch development
- **Beginner-friendly** — turnkey setup with helper scripts; no tmux expertise required
- **Scalable** — comfortable from 2 to 8+ concurrent sessions

## Architecture: Session-per-project with launcher dashboard

### Session Layout

```
tmux session: "home"
  └── window 0: dashboard (shows all sessions + status)

tmux session: "<project-name>"
  ├── window 0: main        → [claude code | shell]
  ├── window 1: <worktree>  → [claude code | shell]  (optional)
  └── ...
```

Each project gets its own tmux session. Within a session, each worktree (or the main branch) gets its own window. Each window has a vertical split: left pane for Claude Code, right pane for a shell. iTerm2 `-CC` mode maps tmux sessions to native iTerm2 window groups and tmux windows to native tabs.

### Component Diagram

```
┌─────────────────────────────────────────────┐
│                  iTerm2                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│  │  home    │ │  myapp   │ │  iterm   │     │
│  │ (dash)   │ │ main|wt1 │ │  main    │     │
│  └──────────┘ └──────────┘ └──────────┘     │
│         ↕ tmux -CC integration               │
├─────────────────────────────────────────────┤
│                 tmux server                   │
│  session:home  session:myapp  session:iterm  │
├─────────────────────────────────────────────┤
│              Helper Scripts                   │
│  cc  ·  cc-list  ·  cc-kill  ·  cc-dashboard │
└─────────────────────────────────────────────┘
```

## Component Details

### 1. tmux Configuration (`tmux.conf`)

Minimal config optimized for iTerm2 `-CC` integration:

- Mouse support enabled
- Window numbering starts at 1
- Increased history limit
- Default shell: zsh
- Hook on `after-new-window` to default to vertical split layout (left: Claude Code, right: shell)
- No custom prefix key — in `-CC` mode, iTerm2 handles window/pane management natively

Stored in repo as `tmux.conf`, symlinked to `~/.tmux.conf`.

### 2. Helper Scripts (`bin/`)

#### `cc <project-path> [worktree-name]`

Main entry point for creating and attaching to sessions.

- **No worktree-name:** Opens the main branch at the project path
  1. Derives session name from directory name
  2. If session doesn't exist: creates tmux session, splits into two panes (claude | shell), opens iTerm2 via `tmux -CC attach`
  3. If session exists: creates a new window named "main" with the same split layout
  4. Creates "home" session with dashboard on first invocation if it doesn't exist
- **With worktree-name:** Opens an isolated worktree
  1. Creates git worktree at `../<project>-<worktree-name>` (sibling directory)
  2. Creates a new window in the project's session, named after the worktree
  3. Both panes cd to the worktree path

Left pane runs `claude`, right pane is a zsh shell.

#### `cc-list`

Displays a table of all running Claude Code sessions:
- Session name, window name, working directory, claude status (running/stopped), git branch
- Queries tmux and pgrep for process status

#### `cc-kill <session> [window]`

Clean teardown:
- Without window: kills entire tmux session (with confirmation prompt)
- With window: kills the window and runs `git worktree remove` on the associated path if it was a worktree

#### `cc-dashboard`

Read-only status display used by the home session:
- Shows same info as `cc-list` in a formatted table
- Run via `watch -n30 cc-dashboard` in the home session for auto-refresh
- Low overhead — just queries tmux state and pgrep

### 3. iTerm2 Dynamic Profile (`iterm2/claude-code.json`)

A JSON profile installed to `~/Library/Application Support/iTerm2/DynamicProfiles/`:

- Name: "Claude Code"
- Initial command: attaches to home tmux session via `-CC` mode
- Slightly distinct background color for visual identification
- Unlimited scrollback (delegated to iTerm2 by `-CC` mode)
- No custom keybindings — standard iTerm2 shortcuts (Cmd+T, Cmd+D, Cmd+number)

### 4. Installation (`install.sh`)

Steps:
1. Symlink `tmux.conf` → `~/.tmux.conf` (backs up existing if present)
2. Symlink `bin/cc`, `bin/cc-list`, `bin/cc-kill`, `bin/cc-dashboard` → `~/.local/bin/`
3. Copy `iterm2/claude-code.json` → `~/Library/Application Support/iTerm2/DynamicProfiles/`
4. Verify dependencies: `tmux`, `claude`, `git`

Uninstall: remove symlinks and dynamic profile. Nothing invasive.

## Repo Structure

```
iterm/
├── bin/
│   ├── cc              # main launcher
│   ├── cc-list         # list sessions
│   ├── cc-kill         # teardown sessions/worktrees
│   └── cc-dashboard    # dashboard display script
├── iterm2/
│   └── claude-code.json  # dynamic profile
├── tmux.conf           # tmux configuration
└── install.sh          # symlinks and copies everything into place
```

## Usage Examples

```bash
# Start working on a project
cc ~/ghq/github.com/sodre/myapp

# Add a worktree for a feature branch
cc ~/ghq/github.com/sodre/myapp feat-auth

# See what's running
cc-list

# Kill a worktree window (cleans up git worktree too)
cc-kill myapp feat-auth

# Kill an entire project session
cc-kill myapp
```

## Design Decisions

- **iTerm2 `-CC` mode over raw tmux:** Eliminates tmux learning curve. Native scrollback, mouse support, cmd+click links. Best UX for tmux beginners.
- **Session-per-project over single session:** Clean isolation, scales better, maps naturally to iTerm2 window groups.
- **Sibling directory worktrees:** `../<project>-<worktree>` avoids nesting worktrees inside the main repo and keeps paths predictable.
- **Dashboard as passive `watch`:** No daemon, no state file, no complexity. Just a periodic query of tmux state.
- **Symlink-based install:** Easy to update (just `git pull`), easy to uninstall, no copied scripts going stale.
