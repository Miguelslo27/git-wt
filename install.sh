#!/usr/bin/env bash
# git-wt installer — copies the binary, injects the shell wrapper,
# and optionally installs the agent skill for supported AI coding agents.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$REPO_ROOT/bin/git-wt"
SKILL_SRC="$REPO_ROOT/skills/git-wt"
INSTALL_DIR="${GWT_INSTALL_DIR:-$HOME/.local/bin}"
BIN_DEST="$INSTALL_DIR/git-wt"
MARKER_START="# >>> git-wt >>>"
MARKER_END="# <<< git-wt <<<"

# Agent skill targets (name:path) — paths as of 2026-04.
SKILL_TARGETS=(
  "claude:$HOME/.claude/skills/git-wt"
  "cursor:$HOME/.cursor/skills/git-wt"
  "copilot:$HOME/.copilot/skills/git-wt"
  "codex:$HOME/.agents/skills/git-wt"
)

SKILL_MODE=""          # "" | "all" | "none" | "select"
SKILL_SELECT=""        # comma list when MODE=select

build_wrapper() {
  printf '%s\n' "$MARKER_START"
  printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' \
    "$INSTALL_DIR" "$INSTALL_DIR"
  cat <<'FUNC'
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
FUNC
  printf '%s\n' "$MARKER_END"
}
WRAPPER=$(build_wrapper)

# --- colors (stderr is a tty) ------------------------------------------------
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  _C=$'\033[0m' _B=$'\033[1m' _DIM=$'\033[2m'
  _GRN=$'\033[32m' _YLW=$'\033[33m' _RED=$'\033[31m' _CYN=$'\033[36m'
else
  _C= _B= _DIM= _GRN= _YLW= _RED= _CYN=
fi

info() { printf '%b\n' "${_GRN}${_B}==>${_C} $*"; }
warn() { printf '%b\n' "${_YLW}warning:${_C} $*" >&2; }
err()  { printf '%b\n' "${_RED}error:${_C} $*" >&2; }

# Accumulator for "next steps" block printed at the end.
NEXT_STEPS=()
add_step() { NEXT_STEPS+=("$1"); }

print_next_steps() {
  [ "${#NEXT_STEPS[@]}" -eq 0 ] && return
  printf '\n%b\n\n' "${_B}next steps:${_C}" >&2
  local i=1
  for step in "${NEXT_STEPS[@]}"; do
    printf '  %b\n' "${_DIM}${i}.${_C} ${step}" >&2
    i=$((i + 1))
  done
  printf '\n' >&2
}

usage() {
  cat <<EOF
Usage: install.sh [options]

Options:
  --skill                Install the agent skill for all supported agents.
  --no-skill             Skip the agent skill entirely.
  --skill-for=<list>     Comma-separated list: claude, cursor, copilot, codex, all.
  -h, --help             Show this help.

If no skill flag is passed and stdin is a terminal, the installer asks
interactively. Non-interactive runs without a flag skip the skill.
EOF
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --skill)            SKILL_MODE="all" ;;
      --no-skill)         SKILL_MODE="none" ;;
      --skill-for=*)      SKILL_MODE="select"; SKILL_SELECT="${arg#*=}" ;;
      -h|--help)          usage; exit 0 ;;
      *) err "unknown option: $arg"; usage; exit 1 ;;
    esac
  done
}

install_binary() {
  [ -f "$BIN_SRC" ] || { err "$BIN_SRC not found"; exit 1; }
  mkdir -p "$INSTALL_DIR"
  install -m 0755 "$BIN_SRC" "$BIN_DEST"
  info "installed binary → $BIN_DEST"
}

inject_wrapper() {
  local rc="$1"
  [ -e "$rc" ] || touch "$rc"
  if grep -qF "$MARKER_START" "$rc"; then
    local tmp perms
    tmp=$(mktemp)
    perms=$(stat -f '%Lp' "$rc" 2>/dev/null || stat -c '%a' "$rc" 2>/dev/null || echo "644")
    awk -v s="$MARKER_START" -v e="$MARKER_END" '
      BEGIN { skip=0 }
      $0==s { skip=1; next }
      $0==e && skip { skip=0; next }
      !skip { print }
    ' "$rc" > "$tmp"
    chmod "$perms" "$tmp"
    mv "$tmp" "$rc"
    printf '\n%s\n' "$WRAPPER" >> "$rc"
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
      info "added ${_CYN}export PATH=\"$INSTALL_DIR:\$PATH\"${_C} to your shell rc"
      ;;
  esac
}

check_fzf() {
  if ! command -v fzf >/dev/null 2>&1; then
    warn "fzf not found (optional — enables interactive ${_B}git wt switch${_C})"
    local cmd=""
    if command -v brew >/dev/null 2>&1; then
      cmd="brew install fzf"
    elif command -v apt-get >/dev/null 2>&1; then
      cmd="sudo apt install fzf"
    elif command -v pacman >/dev/null 2>&1; then
      cmd="sudo pacman -S fzf"
    elif command -v dnf >/dev/null 2>&1; then
      cmd="sudo dnf install fzf"
    fi
    if [ -n "$cmd" ]; then
      add_step "Install fzf ${_DIM}(optional — enables interactive picker)${_C}:

     ${_CYN}${cmd}${_C}
"
    else
      add_step "Install fzf ${_DIM}(optional — enables interactive picker)${_C}"
    fi
  fi
}

install_skill_to() {
  local dest="$1"
  mkdir -p "$dest"
  cp "$SKILL_SRC/SKILL.md" "$dest/SKILL.md"
  info "installed skill → $dest"
}

# Ask the user which agents to target. Writes the result into SKILL_SELECT.
prompt_skill_targets() {
  printf '\n'
  info "agent skill — makes AI coding agents aware of 'git wt'"
  printf '  supported agents:\n'
  printf '    [1] Claude Code      (~/.claude/skills/git-wt/)\n'
  printf '    [2] Cursor           (~/.cursor/skills/git-wt/)\n'
  printf '    [3] GitHub Copilot   (~/.copilot/skills/git-wt/)\n'
  printf '    [4] OpenAI Codex     (~/.agents/skills/git-wt/)\n'
  printf '    [a] all of the above\n'
  printf '    [n] none\n'
  printf '  select (e.g. 1,3 or a) [default: a]: '
  local reply
  read -r reply || reply=""
  reply="${reply:-a}"

  case "$reply" in
    n|N|none) SKILL_MODE="none"; return ;;
    a|A|all)  SKILL_MODE="all"; return ;;
  esac

  local picked=""
  local IFS=','
  for token in $reply; do
    token="${token// /}"
    case "$token" in
      1|claude)  picked="${picked},claude" ;;
      2|cursor)  picked="${picked},cursor" ;;
      3|copilot) picked="${picked},copilot" ;;
      4|codex)   picked="${picked},codex" ;;
      "" ) ;;
      *) warn "ignoring unknown target: $token" ;;
    esac
  done
  picked="${picked#,}"

  if [ -z "$picked" ]; then
    SKILL_MODE="none"
  else
    SKILL_MODE="select"
    SKILL_SELECT="$picked"
  fi
}

install_skill() {
  [ -d "$SKILL_SRC" ] || { warn "skill source not found at $SKILL_SRC — skipping"; return; }

  # Resolve mode when not set explicitly.
  if [ -z "$SKILL_MODE" ]; then
    if [ -t 0 ]; then
      prompt_skill_targets
    else
      info "non-interactive run — skipping agent skill (use --skill or --skill-for=...)"
      SKILL_MODE="none"
    fi
  fi

  case "$SKILL_MODE" in
    none)
      info "agent skill: skipped"
      return
      ;;
    all)
      for entry in "${SKILL_TARGETS[@]}"; do
        install_skill_to "${entry#*:}"
      done
      ;;
    select)
      local IFS=','
      for name in $SKILL_SELECT; do
        name="${name// /}"
        [ -z "$name" ] && continue
        local matched=0
        for entry in "${SKILL_TARGETS[@]}"; do
          if [ "${entry%%:*}" = "$name" ]; then
            install_skill_to "${entry#*:}"
            matched=1
            break
          fi
        done
        if [ "$matched" = 0 ]; then
          warn "unknown skill target: $name"
        fi
      done
      ;;
  esac
}

main() {
  parse_args "$@"
  install_binary

  local touched=0
  if [ -f "$HOME/.zshrc" ] || [ "${SHELL##*/}" = "zsh" ]; then
    inject_wrapper "$HOME/.zshrc"; touched=1
  fi
  if [ -f "$HOME/.bashrc" ] || [ "${SHELL##*/}" = "bash" ]; then
    inject_wrapper "$HOME/.bashrc"; touched=1
  fi
  if [ "$touched" = 0 ]; then
    warn "no ~/.zshrc or ~/.bashrc found — add the wrapper manually"
  fi

  check_path
  check_fzf
  install_skill

  add_step "Restart your shell or run:

     ${_CYN}source ~/.zshrc${_C}  ${_DIM}(or ~/.bashrc)${_C}"

  info "installation complete"
  print_next_steps
}

main "$@"
