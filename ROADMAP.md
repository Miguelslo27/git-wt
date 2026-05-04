# Roadmap

Backlog of work for this project. Tasks flow: `ROADMAP.md` → `IN_PROGRESS.md` → `HISTORY.md`.

Each task lives here as a heading with whatever description it needs (acceptance criteria, design notes, sub-tasks). When work starts, move the block to `IN_PROGRESS.md`.

---

## High Priority

### Bootstrap new worktree on `git wt switch`: auto-copy `.env` and offer dependency install

When `git wt switch` creates (or first enters) a worktree, getting it to a runnable state still takes manual work: copying ignored env files from the main worktree and running the right package manager by hand. This task makes `switch` do both, while keeping the current stdout contract intact.

- [ ] Detect the project's language/toolchain by scanning the new worktree for marker files (e.g. `package.json` + lockfile variant for npm/pnpm/yarn/bun, `pyproject.toml` / `requirements.txt` / `Pipfile` / `poetry.lock`, `Cargo.toml`, `go.mod`, `Gemfile`, `composer.json`). Support multiple matches (polyglot repos) by listing all detected toolchains.
- [ ] After the worktree is ready, prompt the user (on stderr, reading from the controlling tty) whether to run the install command for each detected toolchain. Show the exact command before running it. Default answer must be safe for non-interactive shells.
- [ ] Auto-copy `.env` (and `.env.local`, `.env.*` variants if present) from the main worktree into the new worktree without prompting. Skip silently if no env files exist in the source. Never overwrite an existing file in the destination — log a warning to stderr instead.
- [ ] Preserve the stdout contract: the final line of stdout must remain the destination path. All prompts, progress, and logs go to stderr via the existing `info` / `warn` / `report` helpers ([bin/git-wt:23-45](bin/git-wt#L23-L45)).
- [ ] Add non-interactive flags: at minimum `--no-deps` (skip the install prompt entirely), `--no-env` (skip env-file copy), and `--yes` / `-y` (auto-accept the install prompt for the detected toolchain). Define corresponding env vars (e.g. `GWT_NO_DEPS`, `GWT_NO_ENV`, `GWT_ASSUME_YES`) so CI can opt out without arg plumbing. When stdin is not a tty, default to non-interactive (skip install, still copy env).
- [ ] Document the new flags and the auto-copy behavior in `git wt help` output and in the README usage section. Mention which env files are copied and the "never overwrite" rule.
- [ ] Update the bundled skill at [skills/git-wt/SKILL.md](skills/git-wt/SKILL.md) so agents know about the new flags and the env-copy behavior.

**Acceptance:** running `git wt switch <new-branch>` in a Node repo with a `.env` in the main worktree results in (a) the new worktree containing a copy of `.env`, (b) a prompt offering to run the detected install command, (c) the destination path still being the only thing on stdout, and (d) `git wt switch --no-deps --no-env <branch>` and the equivalent env-var form completing without any prompts. `git wt help` lists the new flags.

## Medium Priority

## Low Priority / Ideas

### Configure tracking policy for `.claude/settings.json`

The repo currently leaves `.claude/settings.json` untracked. Each Claude Code session accumulates a different set of approved permissions, so committing the file as-is causes recurring merge conflicts, while leaving it ignored loses any shared baseline. Decide and apply a stable policy.

- [ ] Decide whether the file should be tracked, ignored, or split (e.g. tracked baseline + local override).
- [ ] If tracked: prune ad-hoc / per-session entries from the committed copy and document the convention in `CLAUDE.md`.
- [ ] If ignored: add `.claude/settings.json` (or the whole `.claude/`) to `.gitignore` and, optionally, ship a `.claude/settings.example.json` baseline.
- [ ] Make the rule consistent across worktrees so a clean clone does not show the file as a permanent untracked entry.

**Acceptance:** the chosen policy is documented in `CLAUDE.md`, the repo no longer shows `.claude/settings.json` as a permanent untracked file in clean clones, and the rule applies consistently across worktrees.
