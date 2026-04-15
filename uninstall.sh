#!/usr/bin/env bash
# git-wt uninstaller — removes the binary, the shell wrapper block,
# and any installed agent skill directories.
set -euo pipefail

INSTALL_DIR="${GWT_INSTALL_DIR:-$HOME/.local/bin}"
BIN_DEST="$INSTALL_DIR/git-wt"
MARKER_START="# >>> git-wt >>>"
MARKER_END="# <<< git-wt <<<"

SKILL_PATHS=(
  "$HOME/.claude/skills/git-wt"
  "$HOME/.cursor/skills/git-wt"
  "$HOME/.copilot/skills/git-wt"
  "$HOME/.agents/skills/git-wt"
)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

remove_wrapper() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  grep -qF "$MARKER_START" "$rc" || return 0
  local tmp
  tmp=$(mktemp)
  awk -v s="$MARKER_START" -v e="$MARKER_END" '
    BEGIN { skip=0 }
    $0==s { skip=1; next }
    $0==e && skip { skip=0; next }
    !skip { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"
  info "removed wrapper from $rc"
}

remove_skill() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  rm -rf "$dir"
  info "removed skill at $dir"
}

if [ -f "$BIN_DEST" ]; then
  rm -f "$BIN_DEST"
  info "removed $BIN_DEST"
fi

remove_wrapper "$HOME/.zshrc"
remove_wrapper "$HOME/.bashrc"

for skill_dir in "${SKILL_PATHS[@]}"; do
  remove_skill "$skill_dir"
done

info "done. Restart your shell."
