#!/usr/bin/env zsh
# install.sh — install ccmux tools, tmux config, and iTerm2 profile
#
# Usage: install.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_DIR="${0:A:h}"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
fi
INSTALL_HOME="${INSTALL_HOME:-$HOME}"
BIN_DIR="$INSTALL_HOME/.local/bin"
TMUX_CONF="$INSTALL_HOME/.tmux.conf"
DYNAMIC_PROFILES_DIR="$INSTALL_HOME/Library/Application Support/iTerm2/DynamicProfiles"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo "${GREEN}[OK]${NC} $1"; }
warn()  { echo "${YELLOW}[WARN]${NC} $1"; }
error() { echo "${RED}[ERROR]${NC} $1" >&2; }

# --- Step 1: Check dependencies ---
missing=()
for cmd in tmux claude git; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("$cmd")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  error "Missing dependencies: ${missing[*]}"
  [[ "$DRY_RUN" == false ]] && exit 1
fi
info "Dependencies found: tmux, claude, git"

# --- Step 2: Check iTerm2 ---
if [[ "$TERM_PROGRAM" != "iTerm.app" ]] && [[ "$DRY_RUN" == false ]]; then
  warn "Not running inside iTerm2. iTerm2 preference will not be set."
  warn "Run this from iTerm2, or manually set: defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2"
else
  if [[ "$DRY_RUN" == false ]]; then
    defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2
    info "iTerm2 tmux preference configured (OpenTmuxWindowsIn = tabs)"
  else
    echo "[DRY-RUN] Would set: defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 2"
  fi
fi

# --- Step 3: Symlink tmux.conf ---
if [[ -f "$TMUX_CONF" ]] && [[ ! -L "$TMUX_CONF" ]]; then
  if [[ "$DRY_RUN" == false ]]; then
    cp "$TMUX_CONF" "${TMUX_CONF}.backup.$(date +%Y%m%d%H%M%S)"
    warn "Existing ~/.tmux.conf backed up"
  else
    echo "[DRY-RUN] Would backup $TMUX_CONF"
  fi
fi
if [[ "$DRY_RUN" == false ]]; then
  ln -sf "$SCRIPT_DIR/tmux.conf" "$TMUX_CONF"
  info "Symlinked tmux.conf → ~/.tmux.conf"
else
  echo "[DRY-RUN] Would symlink $SCRIPT_DIR/tmux.conf → $TMUX_CONF"
fi

# --- Step 4: Symlink scripts ---
mkdir -p "$BIN_DIR"
for script in ccmux ccmux-list ccmux-kill ccmux-dashboard; do
  target="$BIN_DIR/$script"
  if [[ "$DRY_RUN" == false ]]; then
    ln -sf "$SCRIPT_DIR/bin/$script" "$target"
  else
    echo "[DRY-RUN] Would symlink $SCRIPT_DIR/bin/$script → $target"
  fi
done
info "Symlinked scripts to $BIN_DIR/"

# --- Step 5: Check PATH ---
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  warn "$BIN_DIR is not in your PATH."
  warn "Add this to your ~/.zshrc:"
  warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# --- Step 6: Copy dynamic profile ---
if [[ -d "$DYNAMIC_PROFILES_DIR" ]]; then
  if [[ "$DRY_RUN" == false ]]; then
    cp "$SCRIPT_DIR/iterm2/claude-code.json" "$DYNAMIC_PROFILES_DIR/"
    info "Copied iTerm2 dynamic profile"
  else
    echo "[DRY-RUN] Would copy $SCRIPT_DIR/iterm2/claude-code.json → $DYNAMIC_PROFILES_DIR/"
  fi
else
  warn "iTerm2 DynamicProfiles directory not found. Skipping profile install."
fi

# --- Step 7: Start tmux server ---
if [[ "$DRY_RUN" == false ]]; then
  tmux start-server 2>/dev/null || true
  info "tmux server started"
else
  echo "[DRY-RUN] Would start tmux server"
fi

echo ""
info "Installation complete! Open a new iTerm2 window with the 'Claude Code' profile for the dashboard."
info "Run 'ccmux <project-path>' to start a Claude Code session."
