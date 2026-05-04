# History

Completed work log. Tasks flow: `ROADMAP.md` → `IN_PROGRESS.md` → `HISTORY.md`.

Newest first. Each entry references the PR(s) that delivered the work.

> **Note:** Entries below predate the adoption of the roadmap-tracking flow and were reconstructed from `git log`. They link to commits on `main` instead of PRs.

---

## 2026-04

### Preserve file permissions when updating shell rc — 2026-04-16
**Commit:** [46c5f15](https://github.com/Miguelslo27/git-wt/commit/46c5f152f5bc8cd088c42473a90ef3e29c939d05)

The installer was rewriting `~/.zshrc` / `~/.bashrc` with `mktemp + mv`, which dropped the file mode to `0600` and broke `source ~/.zshrc` with "permission denied".

**Delivered:**
- `inject_wrapper` and `remove_wrapper` now capture the original mode with `stat -f` (BSD) / `stat -c` (GNU) before swapping the file in.
- `chmod` restores those permissions on the temp file before `mv`.

**Tests:** manual — installed/uninstalled on macOS and confirmed `stat ~/.zshrc` keeps the original mode.

### Auto-inject PATH export into shell rc — 2026-04-16
**Commit:** [de06ecd](https://github.com/Miguelslo27/git-wt/commit/de06ecdefdd88e21e30163b0ced7393d04c0553b)

Users had to add `~/.local/bin` to `$PATH` manually after install. The installer now does it inside the wrapper block.

**Delivered:**
- Wrapper block in `.zshrc` / `.bashrc` contains a conditional `export PATH` guarded by a `case` against `:$PATH:` to avoid duplicates.
- Removed the manual "add to your rc" step from the post-install message in favor of an inline confirmation.

**Tests:** manual — verified the export is not duplicated when `~/.local/bin` is already on `$PATH`.

### Group "next steps" block with copy-friendly commands — 2026-04-16
**Commit:** [72ac26b](https://github.com/Miguelslo27/git-wt/commit/72ac26b1be42db64fc5403753f58be9a627bbc1f)

Post-install warnings and actionable shell commands were interleaved, making them hard to copy-paste.

**Delivered:**
- Actionable commands (PATH export, `fzf` install, shell restart) are now collected into a numbered "next steps" block printed at the end of the run.
- Fixed `set -e` exiting silently when `install_skill` returned `1` (the `[ ] && warn` pattern).
- Fixed BSD `awk` failing on the multiline `-v` argument in `inject_wrapper`.
- Added `pacman` / `dnf` detection for `fzf` install hints in both the binary and the installer.

**Tests:** manual — ran the installer on macOS (zsh + Homebrew) and Linux (bash + apt).

### Interactive skill installer and broader skill trigger — 2026-04-15
**Commit:** [9cb2d12](https://github.com/Miguelslo27/git-wt/commit/9cb2d125104f89a9c46b060f61da608808abd03c)

The agent skill from the previous commit shipped with no installer support and a description too narrow to fire on real coding tasks.

**Delivered:**
- `install.sh` drives skill installation: interactive prompt in a TTY, plus flags `--skill`, `--no-skill`, `--skill-for=<list>` (claude, cursor, copilot, codex, all). Non-TTY runs without flags skip the skill.
- `uninstall.sh` removes the installed skill directories alongside the binary and wrapper.
- `SKILL.md` description rewritten around universal coding-task verbs (implement, add, create, refactor, fix, …) so the skill is actually consulted on real changes; per-condition filtering stays in the body.

**Tests:** manual — installed across all four agent targets and verified the skill is picked up.

### Add git-wt agent skill (open skills spec) — 2026-04-15
**Commit:** [8431a57](https://github.com/Miguelslo27/git-wt/commit/8431a57c4c3604085b8e0a8e58cf8386babab7d9)

Bundle a portable skill so AI coding agents (Claude, Cursor, Copilot, Codex) can discover and drive `git wt` consistently.

**Delivered:**
- New `skills/git-wt/SKILL.md` defining when to suggest a worktree (explicit request, protected branch, dirty tree that may conflict, mismatched worktree) and when to stay silent (trivial edits, read-only, prior decline).
- Two documented execution modes: (A) agent works in the worktree and returns a diff; (B) agent prepares it and hands the user a `cd` instruction.
- Documents stdout/stderr parsing rules, branch-naming conventions per task type, and destructive-operation guardrails (`rm` always confirms; never `--force` without explicit approval).

**Tests:** manual — sanity-checked SKILL activation in Claude Code.

### Colorized, informative output for all commands — 2026-04-14
**Commit:** [0ea3ce9](https://github.com/Miguelslo27/git-wt/commit/0ea3ce9eb25d4e4fdbf1e4193e302c5597c1de1a)

The CLI's output was plain and didn't make the result of each action obvious.

**Delivered:**
- All user-facing output goes through styled helpers (`info` / `warn` / `err` / `report`) that respect `NO_COLOR` and non-TTY stderr.
- `switch` distinguishes "created" vs "switched to" and annotates the source of a new worktree (local branch / tracking `origin/<branch>` / new from `HEAD`).
- `list` highlights the current worktree and aligns branch / path columns.
- `rm` surfaces the dirty-worktree warning in color and suggests follow-up branch cleanup.
- stdout stays reserved for the destination path so the shell wrapper can `cd` unchanged.

**Tests:** manual — exercised each subcommand in a sample repo with `NO_COLOR` set and unset.

### Initial commit — git-wt v0.1.0 — 2026-04-14
**Commit:** [df4bd30](https://github.com/Miguelslo27/git-wt/commit/df4bd308fda3ab1bc209b322cd7f15cf9ffc0393)

Project bootstrap: a Bash CLI that wraps `git worktree` so you can switch between worktrees like you switch branches, including `cd`-ing into the target directory.

**Delivered:**
- `bin/git-wt` with `switch` / `list` / `rm` subcommands (portable bash).
- `install.sh` copies the binary to `~/.local/bin` and injects a shell wrapper into `~/.zshrc` and/or `~/.bashrc` between idempotent markers.
- `uninstall.sh` reverses the installation.
- `README.md` and MIT `LICENSE`.

**Tests:** manual — installed on macOS (zsh) and ran each subcommand.
