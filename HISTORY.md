# History

Completed work log. Tasks flow: `ROADMAP.md` → `IN_PROGRESS.md` → `HISTORY.md`.

Newest first. Each entry references the PR(s) that delivered the work.

> **Note:** Entries below predate the adoption of the roadmap-tracking flow and were reconstructed from `git log`. They link to commits on `main` instead of PRs.

---

## 2026-07

### Automated smoke-test suite + CI — 2026-07-01
**PR:** _pending_ (branch `feature/smoke-tests-ci`)

The repo shipped a 555-line load-bearing bash CLI with zero automated tests; the stdout-last-line-is-path contract that the shell wrapper depends on was only verified by hand. This PR adds a hermetic test suite and a GitHub Actions workflow so every PR proves the contract still holds.

**Delivered:**
- `tests/git-wt.test.sh` — dependency-free (plain bash, no bats) smoke tests: builds a throwaway repo fixture in `mktemp -d`, sandboxes `HOME` / `XDG_CACHE_HOME` / `XDG_CONFIG_HOME` so real user cache/config is never touched, and drives `bin/git-wt` with `GWT_NO_VERSION_CHECK=1` / `--no-version-check` and non-tty stdin. 51 assertions covering: `switch` create/existing (path on stdout's last line, decoration on stderr only), `--from <base>` cutting from the named base (not current HEAD) and erroring on existing/checked-out branches, `list` starring the current worktree with empty stdout, `rm` on clean worktrees returning the main worktree path, `rm` on dirty worktrees aborting without force-removal when stdin is non-tty, refusal to remove the main worktree, unknown-flag errors, `.env` propagation on create plus the `GWT_NO_ENV=1` opt-out, a `bash -n` syntax gate over all three shipped scripts, and a non-empty semver-shaped `VERSION` check against `bin/git-wt:6`.
- `.github/workflows/ci.yml` — runs on `pull_request` and `push` to `main` with `permissions: contents: read`; two ubuntu jobs: `shellcheck --shell=bash --severity=warning` over `bin/git-wt`, `install.sh`, `uninstall.sh`, `tests/*.sh`, and the test suite itself.
- Lint-only source fixes so shellcheck passes at `-S warning`: empty color assignments now use `var=''` (SC1007) in `bin/git-wt:30` and `install.sh:55`, and the malformed directive `# shellcheck disable=SC2086 -- …` at `bin/git-wt:228` (a SC1072/SC1073 parse error) now uses the valid `# comment` form. No behavior change.
- `CLAUDE.md` — the "no linters or tests" claim replaced by a "Tests and linting" section documenting how to run both.

**Tests:** `bash tests/git-wt.test.sh` → 51 passed, 0 failed (macOS, bash); `shellcheck -S warning -s bash bin/git-wt install.sh uninstall.sh tests/*.sh` clean (shellcheck 0.11.0); `bash -n` passes on all scripts. No genuine behavioral bugs surfaced — dirty-`rm` with non-tty stdin correctly aborts via `read` EOF under `set -euo pipefail` before any `--force` removal.

### Ignore `.claude/` directory — 2026-05-22
**PR:** [#9](https://github.com/AkaLab-Tech/git-wt/pull/9)

The repo left `.claude/settings.json` (and the rest of the `.claude/` directory) as a permanent untracked entry, which caused noise on every `git status` and forced a stash/pop dance around every `git pull` on `main`. We evaluated three policies — track full file, track baseline + local override, ignore everything — and picked ignore-everything: the directory holds per-user Claude Code state (permissions, history, settings) that accumulates differently per session, so any shared baseline would generate constant merge conflicts without compensating value.

**Delivered:**
- New top-level `.gitignore` with a single `.claude/` entry and a comment cross-referencing `CLAUDE.md` for the rationale. Applies to every worktree automatically because they share the `.git/` directory.
- `CLAUDE.md` "Project conventions" gains a bullet documenting the decision, including the explicit rejection of the baseline-plus-override option so future sessions don't relitigate it.
- No `.claude/settings.example.json` baseline shipped; each clone starts fresh.

**Tests:** in the worktree, created stub files at `.claude/settings.json` and `.claude/history.jsonl`, ran `git status --short`, and confirmed no output (the directory is silently ignored). After merge, the `?? .claude/` entry that has appeared in every `git status` of this session disappears from the main worktree as well.

### Rate-limited version check + `git wt self-update` — 2026-05-22
**PR:** [#8](https://github.com/AkaLab-Tech/git-wt/pull/8)

The installer was pull-based (clone + `./install.sh`), so users had no signal that newer releases existed and no in-place upgrade path. This PR closes both gaps: a once-per-day nudge and a `self-update` subcommand that drives the existing installer end-to-end. Both are opt-out-able and silent in CI by default.

**Delivered:**
- `version_check` runs at the start of every subcommand (except `help` / `version` / `self-update`). Reads a tiny KV cache at `${XDG_CACHE_HOME:-$HOME/.cache}/git-wt/version-check`; on miss/stale, `_fetch_upstream_version` tries `curl --max-time 2` then `wget --timeout=2` against the upstream raw `bin/git-wt`, extracts `VERSION=` with `awk`. Hardcoded URL with `GWT_UPSTREAM_URL` as an undocumented test override.
- `_version_lt` uses `sort -V` (GNU + BSD) for semver-ish comparison. Nudge fires via the existing `info` helper (stderr only — `switch`'s stdout path contract is untouched).
- Opt-outs: `--no-version-check` flag (stripped from `$@` before subcommand parsers see it), `GWT_NO_VERSION_CHECK=1` env var, `GWT_VERSION_CHECK_TTL` for cache TTL (default 86400s), and auto-skip when stdin is non-tty and `CI` / `GITHUB_ACTIONS` is set. Network/parse failures are silent unless `GWT_DEBUG=1`.
- `cmd_self_update` reads `${XDG_CONFIG_HOME:-$HOME/.config}/git-wt/install.conf` (written by `install.sh`), refuses if the clone path is missing/not-a-repo/dirty, runs `git -C <clone> pull --ff-only` followed by `<clone>/install.sh`, reports `before → after`, and deletes the cache so the nudge stops.
- `install.sh` gains `record_install_config` which persists `clone_path=` to `install.conf` on every install. `uninstall.sh` removes the cache file, `install.conf`, and `rmdir`s the parent XDG dirs if they're empty.
- `VERSION` bumped to `0.4.0` (new public CLI surface). `git wt help` now has a `Version check:` section; the README has a `Staying up to date` section with the knob table; `skills/git-wt/SKILL.md` documents the `--no-version-check` guidance for agents invoking `git wt` programmatically.

**Tests:** smoke-tested with `GWT_UPSTREAM_URL=file:///tmp/...` mocking a 9.9.9 upstream. Cases: (1) cache miss + nudge fires + cache written; (2) cache hit within TTL (broken URL on retry still shows the cached nudge, proving no network call); (3) cache miss + bad URL + `GWT_VERSION_CHECK_TTL=0` is silent without `GWT_DEBUG=1`, logs a warning with it; (4) `--no-version-check` suppresses; (5) `GWT_NO_VERSION_CHECK=1` suppresses; (6) `CI=1` and `GITHUB_ACTIONS=true` with non-tty stdin both auto-skip; (7) `self-update` against a bare + clone fixture: pulls, runs install.sh (marker file written), reports `up to date at 0.4.0`; (8) dirty fake clone aborts `self-update` with actionable error and exit 1; (9) missing `install.conf` aborts with actionable error. `bash -n` passes on `bin/git-wt`, `install.sh`, and `uninstall.sh`; `git wt help` renders the new sections; `git wt version` reports `0.4.0`.

### Bootstrap new worktrees on switch (env-copy + install prompt) — 2026-05-22
**PR:** [#7](https://github.com/AkaLab-Tech/git-wt/pull/7)

`git wt switch` left a freshly-created worktree in a "checked out but not runnable" state: the user had to copy ignored env files from the main worktree and run the right package manager by hand. This PR teaches `switch` to do both in its create path, while keeping the stdout-last-line-is-path contract intact and staying out of the way in CI.

**Delivered:**
- `bootstrap_env_files` copies `.env` and `.env.*` files from the main worktree into the new one. Never overwrites — collisions warn and skip. Bypass with `--no-env` or `GWT_NO_ENV=1`.
- `detect_toolchains` scans for marker files and emits one `<toolchain>|<install command>` line per match, supporting polyglot repos: pnpm/yarn/bun/npm via lockfiles + `package.json`; poetry/pipenv/pip via `poetry.lock`/`Pipfile`/`requirements.txt` (lone `pyproject.toml` is skipped with a warning because the install command is ambiguous); `Cargo.toml`, `go.mod`, `Gemfile`, `composer.json` for Rust/Go/Ruby/PHP.
- `prompt_install` reads `[y/N]` from `/dev/tty` per detected toolchain (or auto-accepts when `--yes`/`-y`/`GWT_ASSUME_YES=1`), runs the install command inside the new worktree with stdout redirected to stderr so chatter never leaks into the path output. Tools missing from `PATH` are skipped with a warning, not an error.
- New flags `--no-env`, `--no-deps`, `--yes`/`-y` in `cmd_switch` argument parser, plus env-var equivalents (`GWT_NO_ENV`, `GWT_NO_DEPS`, `GWT_ASSUME_YES`). Bootstrap runs only on create — switching to an existing worktree is unchanged.
- Non-tty stdin (CI, pipes) auto-skips the install prompt while still copying env files; `--yes` overrides for forced installs in CI.
- `VERSION` bumped to `0.3.0` (new public CLI surface). `git wt help`, the README usage table, and `skills/git-wt/SKILL.md` document the new flags, env vars, and behavior.

**Tests:** manual smoke tests in a throwaway polyglot repo (`package.json` + `Cargo.toml` + `go.mod` + `Gemfile` + gitignored `.env`/`.env.local`/`.env.production`) covered: `--no-deps` (env copied, no prompt); `--no-deps --no-env` (nothing copied); non-tty stdin without flags (env copied, prompt auto-skipped); `--yes` with non-tty (every toolchain auto-run, missing-from-PATH fallback skipped cargo, npm/go/bundle ran for real); `GWT_NO_DEPS=1 GWT_NO_ENV=1` env-var equivalents; stdout-only output is exactly the worktree path; collision case with a tracked `.env` triggered the skip-with-warning path while other env files copied through; switching to an existing worktree did **not** re-run bootstrap; regression on unknown flags and `--from <base>` co-existence with the new flags.

### Add `--from <base>` flag to `git wt switch` — 2026-05-22
**PR:** [#5](https://github.com/AkaLab-Tech/git-wt/pull/5)

`git wt switch` always cut new branches from the current `HEAD`, which forced the bundled skill to fall back to raw `git worktree add` whenever the base branch (e.g. `dev`) was not checked out in any worktree. `--from <base>` collapses Path A and Path B of the base-branch policy into a single, uniform `git wt switch` call.

**Delivered:**
- `cmd_switch` parses `--from <base>` and `--from=<base>`; the flag may appear before or after the branch name. Unknown flags and `--from` without a value are rejected.
- `<base>` is validated with `git rev-parse --verify <base>^{commit}` and accepts any commit-ish (local ref, `origin/<name>`, SHA). The CLI does not auto-fetch — refreshing the base stays the skill's responsibility.
- When `--from` is supplied and `<branch>` already exists in a worktree, locally, or on `origin/`, the command errors with a distinct message per case instead of silently ignoring the flag.
- `git worktree add` is invoked with `--no-track` so a remote-tracking base does not silently set upstream on the new branch. The `report` keeps suggesting `git push -u origin <branch>` for explicit setup.
- `skills/git-wt/SKILL.md` base-branch policy collapses to `git wt switch <new> --from <base>` in both Path A (drop the `cd <base-wt>`) and Path B (drop the raw `git worktree add` fallback). The Path A stash/pull/pop dance for updating the base ref stays.
- `VERSION` bumped to `0.2.0`. README usage table and `git wt help` document the new flag.

**Tests:** manual smoke tests in a throwaway repo with `origin/dev` present and no local `dev` — covered the happy path (new branch from `origin/dev`, no auto-tracking), all five conflict error paths (worktree / local branch / `origin/<branch>` / bogus base / missing value / missing branch / unknown flag), both `--from <base>` and `--from=<base>` forms with flag placed before or after the branch name, the stdout last-line `cd` contract, and regression of plain `git wt switch <new>` cutting from current `HEAD`.

## 2026-04

### Preserve file permissions when updating shell rc — 2026-04-16
**Commit:** [46c5f15](https://github.com/AkaLab-Tech/git-wt/commit/46c5f152f5bc8cd088c42473a90ef3e29c939d05)

The installer was rewriting `~/.zshrc` / `~/.bashrc` with `mktemp + mv`, which dropped the file mode to `0600` and broke `source ~/.zshrc` with "permission denied".

**Delivered:**
- `inject_wrapper` and `remove_wrapper` now capture the original mode with `stat -f` (BSD) / `stat -c` (GNU) before swapping the file in.
- `chmod` restores those permissions on the temp file before `mv`.

**Tests:** manual — installed/uninstalled on macOS and confirmed `stat ~/.zshrc` keeps the original mode.

### Auto-inject PATH export into shell rc — 2026-04-16
**Commit:** [de06ecd](https://github.com/AkaLab-Tech/git-wt/commit/de06ecdefdd88e21e30163b0ced7393d04c0553b)

Users had to add `~/.local/bin` to `$PATH` manually after install. The installer now does it inside the wrapper block.

**Delivered:**
- Wrapper block in `.zshrc` / `.bashrc` contains a conditional `export PATH` guarded by a `case` against `:$PATH:` to avoid duplicates.
- Removed the manual "add to your rc" step from the post-install message in favor of an inline confirmation.

**Tests:** manual — verified the export is not duplicated when `~/.local/bin` is already on `$PATH`.

### Group "next steps" block with copy-friendly commands — 2026-04-16
**Commit:** [72ac26b](https://github.com/AkaLab-Tech/git-wt/commit/72ac26b1be42db64fc5403753f58be9a627bbc1f)

Post-install warnings and actionable shell commands were interleaved, making them hard to copy-paste.

**Delivered:**
- Actionable commands (PATH export, `fzf` install, shell restart) are now collected into a numbered "next steps" block printed at the end of the run.
- Fixed `set -e` exiting silently when `install_skill` returned `1` (the `[ ] && warn` pattern).
- Fixed BSD `awk` failing on the multiline `-v` argument in `inject_wrapper`.
- Added `pacman` / `dnf` detection for `fzf` install hints in both the binary and the installer.

**Tests:** manual — ran the installer on macOS (zsh + Homebrew) and Linux (bash + apt).

### Interactive skill installer and broader skill trigger — 2026-04-15
**Commit:** [9cb2d12](https://github.com/AkaLab-Tech/git-wt/commit/9cb2d125104f89a9c46b060f61da608808abd03c)

The agent skill from the previous commit shipped with no installer support and a description too narrow to fire on real coding tasks.

**Delivered:**
- `install.sh` drives skill installation: interactive prompt in a TTY, plus flags `--skill`, `--no-skill`, `--skill-for=<list>` (claude, cursor, copilot, codex, all). Non-TTY runs without flags skip the skill.
- `uninstall.sh` removes the installed skill directories alongside the binary and wrapper.
- `SKILL.md` description rewritten around universal coding-task verbs (implement, add, create, refactor, fix, …) so the skill is actually consulted on real changes; per-condition filtering stays in the body.

**Tests:** manual — installed across all four agent targets and verified the skill is picked up.

### Add git-wt agent skill (open skills spec) — 2026-04-15
**Commit:** [8431a57](https://github.com/AkaLab-Tech/git-wt/commit/8431a57c4c3604085b8e0a8e58cf8386babab7d9)

Bundle a portable skill so AI coding agents (Claude, Cursor, Copilot, Codex) can discover and drive `git wt` consistently.

**Delivered:**
- New `skills/git-wt/SKILL.md` defining when to suggest a worktree (explicit request, protected branch, dirty tree that may conflict, mismatched worktree) and when to stay silent (trivial edits, read-only, prior decline).
- Two documented execution modes: (A) agent works in the worktree and returns a diff; (B) agent prepares it and hands the user a `cd` instruction.
- Documents stdout/stderr parsing rules, branch-naming conventions per task type, and destructive-operation guardrails (`rm` always confirms; never `--force` without explicit approval).

**Tests:** manual — sanity-checked SKILL activation in Claude Code.

### Colorized, informative output for all commands — 2026-04-14
**Commit:** [0ea3ce9](https://github.com/AkaLab-Tech/git-wt/commit/0ea3ce9eb25d4e4fdbf1e4193e302c5597c1de1a)

The CLI's output was plain and didn't make the result of each action obvious.

**Delivered:**
- All user-facing output goes through styled helpers (`info` / `warn` / `err` / `report`) that respect `NO_COLOR` and non-TTY stderr.
- `switch` distinguishes "created" vs "switched to" and annotates the source of a new worktree (local branch / tracking `origin/<branch>` / new from `HEAD`).
- `list` highlights the current worktree and aligns branch / path columns.
- `rm` surfaces the dirty-worktree warning in color and suggests follow-up branch cleanup.
- stdout stays reserved for the destination path so the shell wrapper can `cd` unchanged.

**Tests:** manual — exercised each subcommand in a sample repo with `NO_COLOR` set and unset.

### Initial commit — git-wt v0.1.0 — 2026-04-14
**Commit:** [df4bd30](https://github.com/AkaLab-Tech/git-wt/commit/df4bd308fda3ab1bc209b322cd7f15cf9ffc0393)

Project bootstrap: a Bash CLI that wraps `git worktree` so you can switch between worktrees like you switch branches, including `cd`-ing into the target directory.

**Delivered:**
- `bin/git-wt` with `switch` / `list` / `rm` subcommands (portable bash).
- `install.sh` copies the binary to `~/.local/bin` and injects a shell wrapper into `~/.zshrc` and/or `~/.bashrc` between idempotent markers.
- `uninstall.sh` reverses the installation.
- `README.md` and MIT `LICENSE`.

**Tests:** manual — installed on macOS (zsh) and ran each subcommand.
