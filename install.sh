#!/usr/bin/env bash
# git-wt installer — copies the binary and injects the shell wrapper.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_ROOT/bin/git-wt"
INSTALL_DIR="${GWT_INSTALL_DIR:-$HOME/.local/bin}"
BIN_DEST="$INSTALL_DIR/git-wt"
MARKER_START="# >>> git-wt >>>"
MARKER_END="# <<< git-wt <<<"

WRAPPER=$(cat <<'EOF'
# >>> git-wt >>>
git() {
  if [ "$1" = "wt" ] && [ "$2" = "switch" ]; then
    shift 2
    local _gwt_dir
    _gwt_dir=$(command git-wt switch "$@") || return $?
    [ -n "$_gwt_dir" ] && cd "$_gwt_dir"
  else
    command git "$@"
  fi
}
# <<< git-wt <<<
EOF
)

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

install_binary() {
  [ -f "$BIN_SRC" ] || { echo "error: $BIN_SRC not found" >&2; exit 1; }
  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$BIN_SRC" "$BIN_DEST"
  info "installed binary → $BIN_DEST"
}

inject_wrapper() {
  local rc="$1"
  [ -e "$rc" ] || touch "$rc"
  if grep -qF "$MARKER_START" "$rc"; then
    local tmp
    tmp=$(mktemp)
    awk -v s="$MARKER_START" -v e="$MARKER_END" -v w="$WRAPPER" '
      BEGIN { skip=0 }
      $0==s { print w; skip=1; next }
      $0==e && skip { skip=0; next }
      !skip { print }
    ' "$rc" > "$tmp"
    mv "$tmp" "$rc"
    info "updated wrapper in $rc"
  else
    printf '\n%s\n' "$WRAPPER" >> "$rc"
    info "added wrapper to $rc"
  fi
}

check_path() {
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      warn "$INSTALL_DIR is not in your \$PATH. Add to your shell rc:"
      printf '  export PATH="%s:$PATH"\n' "$INSTALL_DIR"
      ;;
  esac
}

check_fzf() {
  if ! command -v fzf >/dev/null 2>&1; then
    warn "fzf not found (optional — enables interactive 'git wt switch')"
    if command -v brew >/dev/null 2>&1; then
      printf '  install with: brew install fzf\n'
    elif command -v apt-get >/dev/null 2>&1; then
      printf '  install with: sudo apt install fzf\n'
    fi
  fi
}

main() {
  install_binary

  local touched=0
  if [ -f "$HOME/.zshrc" ] || [ "${SHELL##*/}" = "zsh" ]; then
    inject_wrapper "$HOME/.zshrc"; touched=1
  fi
  if [ -f "$HOME/.bashrc" ] || [ "${SHELL##*/}" = "bash" ]; then
    inject_wrapper "$HOME/.bashrc"; touched=1
  fi
  [ "$touched" = 0 ] && warn "no ~/.zshrc or ~/.bashrc found — add the wrapper manually"

  check_path
  check_fzf
  info "done. Restart your shell or: source ~/.zshrc  (or ~/.bashrc)"
}

main "$@"
