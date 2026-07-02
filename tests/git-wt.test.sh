#!/usr/bin/env bash
# tests/git-wt.test.sh — hermetic smoke tests for bin/git-wt.
#
# No external test framework (no bats). Builds a throwaway git repo fixture in
# a mktemp sandbox, points HOME / XDG_* into the sandbox so the real user
# cache/config is never touched, and drives the repo's own bin/git-wt.
#
# Run:  bash tests/git-wt.test.sh
# Exit: 0 when every assertion passes, 1 otherwise.
set -u

# --- locate the repo under test ----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
GWT_BIN="$REPO_ROOT/bin/git-wt"

if [ ! -x "$GWT_BIN" ]; then
  printf 'error: %s not found or not executable\n' "$GWT_BIN" >&2
  exit 1
fi

# --- sandbox ------------------------------------------------------------------
# pwd -P: resolve symlinks (macOS mktemp returns /var/... which is /private/var/...)
# so path comparisons against `git worktree list` output are stable.
SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# Never touch the real user's HOME / cache / config.
export HOME="$SANDBOX/home"
export XDG_CACHE_HOME="$SANDBOX/xdg-cache"
export XDG_CONFIG_HOME="$SANDBOX/xdg-config"
mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME"

# Hermetic git: no system/global config leakage, fixed identity.
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="git-wt-test"
export GIT_AUTHOR_EMAIL="git-wt-test@example.invalid"
export GIT_COMMITTER_NAME="git-wt-test"
export GIT_COMMITTER_EMAIL="git-wt-test@example.invalid"

# Deterministic output; never hit the network for the upstream version nudge.
export NO_COLOR=1
export GWT_NO_VERSION_CHECK=1
unset GWT_NO_ENV GWT_NO_DEPS GWT_ASSUME_YES GWT_DEBUG 2>/dev/null || true

# --- tiny harness --------------------------------------------------------------
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL - %s\n' "$1"
  shift
  local line
  for line in "$@"; do printf '       %s\n' "$line"; done
}

assert_eq() { # <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected: $2" "actual:   $3"; fi
}

assert_rc_zero() { # <desc> <rc>
  if [ "$2" -eq 0 ]; then pass "$1"; else fail "$1" "expected exit 0, got $2" "stderr: $(tail -n 3 "$STDERR_F" | tr '\n' ' ')"; fi
}

assert_rc_nonzero() { # <desc> <rc>
  if [ "$2" -ne 0 ]; then pass "$1"; else fail "$1" "expected non-zero exit, got 0"; fi
}

assert_file_contains() { # <desc> <file> <needle>
  if grep -qF -- "$3" "$2"; then pass "$1"; else fail "$1" "missing: $3" "in: $2" "content: $(tr '\n' '|' < "$2")"; fi
}

assert_file_not_contains() { # <desc> <file> <needle>
  if grep -qF -- "$3" "$2"; then fail "$1" "unexpected: $3" "in: $2"; else pass "$1"; fi
}

assert_dir_exists() { # <desc> <dir>
  if [ -d "$2" ]; then pass "$1"; else fail "$1" "missing directory: $2"; fi
}

assert_dir_missing() { # <desc> <dir>
  if [ ! -d "$2" ]; then pass "$1"; else fail "$1" "directory still exists: $2"; fi
}

STDOUT_F="$SANDBOX/stdout"
STDERR_F="$SANDBOX/stderr"

# run_gwt <workdir> [VAR=val ...] -- <git-wt args...>
# Runs bin/git-wt in <workdir> with stdin from /dev/null (non-tty), capturing
# stdout/stderr to $STDOUT_F/$STDERR_F and the exit code in $RC.
run_gwt() {
  local dir="$1"; shift
  local envs=("GWT_NO_VERSION_CHECK=1")
  while [ "$1" != "--" ]; do envs+=("$1"); shift; done
  shift
  RC=0
  (cd "$dir" && env "${envs[@]}" "$GWT_BIN" "$@" --no-version-check \
    </dev/null >"$STDOUT_F" 2>"$STDERR_F") || RC=$?
}

last_stdout_line() { tail -n 1 "$STDOUT_F"; }
stdout_line_count() { grep -c '' "$STDOUT_F" || true; }

# --- fixture -------------------------------------------------------------------
FIXTURE="$SANDBOX/work/repo"
WT_ROOT="$SANDBOX/work/repo-worktrees"
mkdir -p "$FIXTURE"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" symbolic-ref HEAD refs/heads/main
printf 'hello\n' > "$FIXTURE/file.txt"
git -C "$FIXTURE" add file.txt
git -C "$FIXTURE" commit -qm "initial commit"

printf '# git-wt smoke tests\n'
printf '# binary under test: %s\n' "$GWT_BIN"
printf '# sandbox: %s\n\n' "$SANDBOX"

# --- 0. syntax gate: bash -n over the shipped scripts ---------------------------
for script in bin/git-wt install.sh uninstall.sh; do
  if bash -n "$REPO_ROOT/$script" 2>"$STDERR_F"; then
    pass "syntax gate: bash -n $script"
  else
    fail "syntax gate: bash -n $script" "$(cat "$STDERR_F")"
  fi
done

# --- 0b. version consistency -----------------------------------------------------
GWT_VERSION="$(awk -F'"' '/^VERSION=/{print $2; exit}' "$GWT_BIN")"
if [ -n "$GWT_VERSION" ]; then
  pass "version: VERSION= present in bin/git-wt ($GWT_VERSION)"
else
  fail "version: VERSION= present in bin/git-wt" "no VERSION=\"...\" line found"
fi
if printf '%s' "$GWT_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  pass "version: VERSION is semver-shaped"
else
  fail "version: VERSION is semver-shaped" "got: '$GWT_VERSION'"
fi
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- version
assert_eq "version: 'git-wt version' prints VERSION on stdout" "$GWT_VERSION" "$(last_stdout_line)"

# --- 1. switch <branch> creates the worktree, stdout last line is the path -------
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- switch feature/x
assert_rc_zero "switch feature/x: exits 0" "$RC"
assert_dir_exists "switch feature/x: worktree created at <parent>/<repo>-worktrees/feature-x" "$WT_ROOT/feature-x"
assert_eq "switch feature/x: stdout last line is the worktree path" "$WT_ROOT/feature-x" "$(last_stdout_line)"
assert_eq "switch feature/x: stdout carries ONLY the path (decoration stays on stderr)" "1" "$(stdout_line_count)"
assert_file_contains "switch feature/x: decorative report went to stderr" "$STDERR_F" "created"
if git -C "$WT_ROOT/feature-x" rev-parse --abbrev-ref HEAD >"$STDOUT_F" 2>/dev/null; then
  assert_eq "switch feature/x: worktree has branch feature/x checked out" "feature/x" "$(last_stdout_line)"
else
  fail "switch feature/x: worktree has branch feature/x checked out" "not a git worktree"
fi

# --- 2. switch to an EXISTING worktree still prints the path -----------------------
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- switch feature/x
assert_rc_zero "switch existing feature/x: exits 0" "$RC"
assert_eq "switch existing feature/x: stdout last line is still the path" "$WT_ROOT/feature-x" "$(last_stdout_line)"
assert_eq "switch existing feature/x: stdout stays machine-readable (1 line)" "1" "$(stdout_line_count)"

# --- 3. switch --from ---------------------------------------------------------------
# Advance feature/x so it diverges from main; then cut feature/y from main while
# standing INSIDE the feature/x worktree, proving --from overrides current HEAD.
printf 'x change\n' >> "$WT_ROOT/feature-x/file.txt"
git -C "$WT_ROOT/feature-x" commit -qam "diverge feature/x"

run_gwt "$WT_ROOT/feature-x" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- switch feature/y --from main
assert_rc_zero "switch --from main: exits 0" "$RC"
assert_eq "switch --from main: stdout last line is the new path" "$WT_ROOT/feature-y" "$(last_stdout_line)"
MAIN_SHA="$(git -C "$FIXTURE" rev-parse main)"
X_SHA="$(git -C "$FIXTURE" rev-parse feature/x)"
Y_SHA="$(git -C "$FIXTURE" rev-parse feature/y)"
assert_eq "switch --from main: feature/y starts at main's commit" "$MAIN_SHA" "$Y_SHA"
if [ "$Y_SHA" != "$X_SHA" ]; then
  pass "switch --from main: feature/y did NOT branch from current HEAD (feature/x)"
else
  fail "switch --from main: feature/y did NOT branch from current HEAD (feature/x)" "feature/y == feature/x == $Y_SHA"
fi

# --from against a branch already checked out in a worktree must error.
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- switch feature/x --from main
assert_rc_nonzero "switch --from with checked-out branch: non-zero exit" "$RC"
assert_file_contains "switch --from with checked-out branch: error on stderr" "$STDERR_F" "--from only applies to new branches"

# --from against an existing local branch (not checked out) must also error.
git -C "$FIXTURE" branch local-only main
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- switch local-only --from main
assert_rc_nonzero "switch --from with existing local branch: non-zero exit" "$RC"
assert_file_contains "switch --from with existing local branch: error on stderr" "$STDERR_F" "already exists"

# --- 4. list marks the current worktree ----------------------------------------------
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- list
assert_rc_zero "list: exits 0" "$RC"
if grep -E '^  \* ' "$STDERR_F" | grep -qF "$FIXTURE"; then
  pass "list: current (main) worktree is marked with *"
else
  fail "list: current (main) worktree is marked with *" "stderr: $(tr '\n' '|' < "$STDERR_F")"
fi
assert_file_contains "list: other worktrees are listed" "$STDERR_F" "$WT_ROOT/feature-x"
if grep -F "$WT_ROOT/feature-x" "$STDERR_F" | grep -q '\*'; then
  fail "list: non-current worktree is NOT starred" "feature/x line carries a *"
else
  pass "list: non-current worktree is NOT starred"
fi
# list is informational only: nothing on stdout for the shell wrapper to cd into.
assert_eq "list: stdout is empty (no path output)" "0" "$(stdout_line_count)"

# --- 5. rm on a CLEAN worktree ----------------------------------------------------------
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- rm feature/x
assert_rc_zero "rm clean feature/x: exits 0" "$RC"
assert_eq "rm clean feature/x: stdout last line is the MAIN worktree path" "$FIXTURE" "$(last_stdout_line)"
assert_eq "rm clean feature/x: stdout carries only the path" "1" "$(stdout_line_count)"
assert_dir_missing "rm clean feature/x: worktree directory removed" "$WT_ROOT/feature-x"

# --- 6. rm on a DIRTY worktree with non-tty stdin must NOT force-remove -------------------
# cmd_rm warns, then prompts with `read -r ans` on stdin; under set -euo pipefail
# an EOF (non-tty /dev/null stdin) makes `read` fail and the script abort BEFORE
# `git worktree remove --force` runs. Assert that safe behavior: non-zero exit,
# worktree still present, nothing on stdout.
printf 'dirty\n' > "$WT_ROOT/feature-y/untracked.txt"
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- rm feature/y
assert_rc_nonzero "rm dirty feature/y (non-tty stdin): non-zero exit" "$RC"
assert_dir_exists "rm dirty feature/y (non-tty stdin): worktree NOT removed" "$WT_ROOT/feature-y"
assert_file_contains "rm dirty feature/y: warns about uncommitted changes on stderr" "$STDERR_F" "uncommitted changes"
assert_eq "rm dirty feature/y: no path emitted on stdout (wrapper must not cd)" "0" "$(stdout_line_count)"
# Explicit refusal via piped "n" answers the prompt without a tty and must abort too.
RC=0
(cd "$FIXTURE" && printf 'n\n' | env GWT_NO_VERSION_CHECK=1 GWT_NO_ENV=1 GWT_NO_DEPS=1 \
  "$GWT_BIN" rm feature/y --no-version-check >"$STDOUT_F" 2>"$STDERR_F") || RC=$?
assert_rc_nonzero "rm dirty feature/y (piped 'n'): non-zero exit" "$RC"
assert_dir_exists "rm dirty feature/y (piped 'n'): worktree NOT removed" "$WT_ROOT/feature-y"

# --- 7. rm refuses to remove the main worktree ----------------------------------------------
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- rm main
assert_rc_nonzero "rm main: non-zero exit" "$RC"
assert_file_contains "rm main: refusal message on stderr" "$STDERR_F" "refusing to remove the main worktree"
assert_dir_exists "rm main: main worktree untouched" "$FIXTURE"

# --- 8. unknown flag ----------------------------------------------------------------------------
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- switch feature/z --bogus
assert_rc_nonzero "switch --bogus: non-zero exit" "$RC"
assert_file_contains "switch --bogus: error on stderr" "$STDERR_F" "unknown flag: --bogus"
assert_eq "switch --bogus: nothing on stdout" "0" "$(stdout_line_count)"
assert_dir_missing "switch --bogus: no worktree created" "$WT_ROOT/feature-z"

# --- 9. .env propagation on create ---------------------------------------------------------------
printf 'SECRET=1\n' > "$FIXTURE/.env"
run_gwt "$FIXTURE" GWT_NO_DEPS=1 -- switch feature/env   # note: GWT_NO_ENV deliberately unset
assert_rc_zero "switch feature/env (env-copy on): exits 0" "$RC"
assert_eq "switch feature/env: stdout last line is the path" "$WT_ROOT/feature-env" "$(last_stdout_line)"
if [ -f "$WT_ROOT/feature-env/.env" ] && [ "$(cat "$WT_ROOT/feature-env/.env")" = "SECRET=1" ]; then
  pass "switch feature/env: .env copied from the main worktree"
else
  fail "switch feature/env: .env copied from the main worktree" "missing or wrong content at $WT_ROOT/feature-env/.env"
fi
assert_file_contains "switch feature/env: copy reported on stderr" "$STDERR_F" "copied env file"
# And the opt-out actually opts out:
run_gwt "$FIXTURE" GWT_NO_ENV=1 GWT_NO_DEPS=1 -- switch feature/noenv
assert_rc_zero "switch feature/noenv (GWT_NO_ENV=1): exits 0" "$RC"
if [ -f "$WT_ROOT/feature-noenv/.env" ]; then
  fail "switch feature/noenv: GWT_NO_ENV=1 skips the env copy" ".env was copied despite GWT_NO_ENV=1"
else
  pass "switch feature/noenv: GWT_NO_ENV=1 skips the env copy"
fi

# --- summary ---------------------------------------------------------------------------------------
printf '\n# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
