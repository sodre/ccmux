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

### Key Constraint: tmux `-CC` mode

iTerm2's tmux `-CC` integration attaches **one iTerm2 window per tmux session**. A single `-CC` client cannot display multiple sessions simultaneously. This means:

- Each project session opens as a **separate iTerm2 native window**
- Within that window, tmux windows appear as **native iTerm2 tabs**
- Switching between projects means switching between iTerm2 windows (Cmd+`)

### Prerequisite: iTerm2 tmux window restore preference

iTerm2 must be configured to restore tmux windows as **tabs in the current window** (not as separate native windows, which is the default). Without this, each tmux window within a session would open as a separate iTerm2 window instead of a tab.

The `install.sh` script configures this automatically:
```
defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2
```
(Value `2` = tabs in the attaching window.)

### Requirement: `cc` must be run from within iTerm2

The `tmux -CC attach` command communicates with its parent iTerm2 process via the control protocol. Running `cc` from Terminal.app, a script, or any non-iTerm2 context will render raw escape sequences instead of opening an iTerm2 window. The `cc` script validates that `$TERM_PROGRAM` is `iTerm.app` and exits with an error if not.

### Session Layout

```
tmux session: "home"              → iTerm2 Window 1
  └── window 1: dashboard (shows all sessions + status)

tmux session: "<project-name>"    → iTerm2 Window 2
  ├── window 1: main        → [claude code | shell]
  ├── window 2: <worktree>  → [claude code | shell]  (optional)
  └── ...

tmux session: "<other-project>"   → iTerm2 Window 3
  └── window 1: main        → [claude code | shell]
```

Each project gets its own tmux session, which maps to its own iTerm2 window. Within a session, each worktree (or the main branch) gets its own window (iTerm2 tab). Each window has a vertical split: left pane for Claude Code, right pane for a shell.

### Component Diagram

```
┌─────────────────────────────────────────────────┐
│                    iTerm2                         │
│  ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │ Window: home│ │Window: myapp│ │Window: ... │  │
│  │ [dashboard] │ │ Tab: main   │ │ Tab: main  │  │
│  │             │ │ Tab: wt1    │ │            │  │
│  └─────────────┘ └─────────────┘ └───────────┘  │
│     each window = one tmux -CC attach             │
├─────────────────────────────────────────────────┤
│                  tmux server                      │
│  session:home   session:myapp   session:...      │
├─────────────────────────────────────────────────┤
│               Helper Scripts                      │
│  cc  ·  cc-list  ·  cc-kill  ·  cc-dashboard     │
└─────────────────────────────────────────────────┘
```

## Component Details

### 1. tmux Configuration (`tmux.conf`)

Minimal config optimized for iTerm2 `-CC` integration:

- Mouse support enabled
- Window numbering starts at 1
- Increased history limit
- Default shell: zsh
- No custom prefix key — in `-CC` mode, iTerm2 handles window/pane management natively

**Note:** The initial window split is handled by the `cc` script, not by a tmux hook. The `after-new-window` hook does not fire for the first window of `new-session`, and has known issues with hook variables being unset (tmux #3439). Explicit splits in the helper scripts are more reliable.

Stored in repo as `tmux.conf`, symlinked to `~/.tmux.conf`.

### 2. Helper Scripts (`bin/`)

#### `cc <project-path> [worktree-name]`

Main entry point for creating and attaching to sessions.

- **No worktree-name:** Opens the main branch at the project path
  1. Derives session name from directory name
  2. If session doesn't exist: creates tmux session, explicitly splits into two panes (claude | shell), creates "home" session (background, no attach) if the tmux server has no "home" session yet, then opens iTerm2 via `tmux -CC attach` to the **project** session
  3. If session exists and already has a "main" window: checks if a `-CC` client is already attached via `tmux list-clients -t <session> -F '#{client_control_mode}'` (value `1` = control-mode client). If yes, prints a message and exits (the iTerm2 window already exists — user can Cmd+` to it). If no `-CC` client is attached, attaches via `tmux -CC attach`.
  4. If session exists but no "main" window: creates the window with split, then attaches (same `-CC` client check as above)
- **With worktree-name:** Opens an isolated worktree
  1. Creates git worktree at `../<project>-<worktree-name>` (sibling directory) if it doesn't already exist
  2. Creates a new window in the project's session, named after the worktree
  3. Explicitly splits the new window — both panes cd to the worktree path
  4. If not already attached to this session, attaches via `tmux -CC`

Left pane runs `claude`, right pane is a zsh shell.

#### `cc-list`

Displays a table of all running Claude Code sessions:
- Session name, window name, working directory, claude status (running/stopped), git branch
- Queries tmux and pgrep for process status

#### `cc-kill <session> [window]`

Clean teardown with graceful shutdown:
- **Without window:** Sends SIGTERM to all Claude Code processes in the session, waits up to 5 seconds for graceful exit, then kills the entire tmux session (with confirmation prompt)
- **With window:** Sends SIGTERM to Claude Code in that window's pane, waits up to 5 seconds, kills the window, then runs `git worktree remove` on the associated path if it was a worktree. Uses `--force` if the worktree has modifications (with a warning). If the worktree is locked, detects this via `git worktree list --porcelain` and warns the user to unlock it manually rather than force-removing a locked worktree.

#### `cc-dashboard`

Read-only status display used by the home session:
- Shows same info as `cc-list` in a formatted table
- Run via a shell loop (`while true; do clear; cc-dashboard; sleep 30; done`) — no dependency on `watch` which is not installed by default on macOS
- Low overhead — just queries tmux state and pgrep

### 3. iTerm2 Dynamic Profile (`iterm2/claude-code.json`)

A JSON profile installed to `~/Library/Application Support/iTerm2/DynamicProfiles/`:

- Name: "Claude Code"
- Initial command: attaches to the "home" tmux session via `tmux -CC attach -t home` (creating it if needed). This is how the dashboard gets its own iTerm2 window — the user opens a new iTerm2 window/tab using the "Claude Code" profile. The `cc` script only creates the home session in the background; it does not attach to it.
- Slightly distinct background color for visual identification
- Unlimited scrollback (delegated to iTerm2 by `-CC` mode)
- No custom keybindings — standard iTerm2 shortcuts (Cmd+T, Cmd+D, Cmd+number, Cmd+` for window switching)

**Note:** iTerm2 DynamicProfiles does not support symlinked files — symlinks produce a "not readable" permission error (gnachman/iterm2#9107). The profile must be physically copied by `install.sh`. Run `install.sh` again after `git pull` to pick up profile changes.

### 4. Installation (`install.sh`)

Steps:
1. Verify dependencies: `tmux`, `claude`, `git`
2. Verify running inside iTerm2 (`$TERM_PROGRAM` = `iTerm.app`)
3. Configure iTerm2 tmux preference: `defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2`
4. Symlink `tmux.conf` → `~/.tmux.conf` (backs up existing if present)
5. Symlink `bin/cc`, `bin/cc-list`, `bin/cc-kill`, `bin/cc-dashboard` → `~/.local/bin/`
   - Verify `~/.local/bin` is in `$PATH`; if not, print a warning with instructions to add it (e.g., `export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc`)
6. Copy `iterm2/claude-code.json` → `~/Library/Application Support/iTerm2/DynamicProfiles/` (copy, not symlink — see note above)
7. Start tmux server if not running (`tmux start-server`)

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
# Start working on a project (opens new iTerm2 window)
cc ~/ghq/github.com/sodre/myapp

# Add a worktree for a feature branch (new tab in myapp window)
cc ~/ghq/github.com/sodre/myapp feat-auth

# Reattach to an existing project (opens iTerm2 window, no duplicates)
cc ~/ghq/github.com/sodre/myapp

# See what's running
cc-list

# Kill a worktree window (graceful Claude shutdown + git worktree cleanup)
cc-kill myapp feat-auth

# Kill an entire project session
cc-kill myapp

# Switch between project windows: Cmd+` in iTerm2
```

## Design Decisions

- **iTerm2 `-CC` mode over raw tmux:** Eliminates tmux learning curve. Native scrollback, mouse support, cmd+click links. Best UX for tmux beginners. Tradeoff: one iTerm2 window per tmux session (cannot merge multiple sessions into one window).
- **Session-per-project over single session:** Clean isolation, scales better. Each project gets its own iTerm2 window with worktrees as tabs within it.
- **Explicit splits over tmux hooks:** The `cc` script handles all pane splitting directly rather than relying on `after-new-window` hooks, which don't fire for the first window and have known variable issues.
- **Sibling directory worktrees:** `../<project>-<worktree>` avoids nesting worktrees inside the main repo and keeps paths predictable.
- **Dashboard as shell loop:** No dependency on `watch` (not default on macOS). Simple `while/sleep` loop in the home session.
- **Graceful Claude shutdown in cc-kill:** SIGTERM with timeout before force-killing, prevents `git worktree remove` failures from in-flight writes.
- **Copy (not symlink) for dynamic profile:** iTerm2 DynamicProfiles does not support symlinks (gnachman/iterm2#9107). The file must be physically present. Scripts are symlinked; the profile is copied.
- **Symlink-based install for scripts:** Easy to update (just `git pull`), easy to uninstall, no copied scripts going stale.
- **iTerm2-only requirement:** `cc` validates `$TERM_PROGRAM` is iTerm2 before proceeding. tmux `-CC` control protocol only works when the parent process is iTerm2.
- **Single `-CC` client per session:** `cc` checks for existing `-CC` attachments to avoid duplicate iTerm2 windows for the same session. Attaching two `-CC` clients to one session causes unpredictable behavior.
- **No force-remove of locked worktrees:** `cc-kill` warns and exits rather than double-forcing removal of locked worktrees, since locks are intentional.
