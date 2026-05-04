# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A small Bash project: a single-file CLI (`bin/git-wt`) that wraps `git worktree` so that `git wt switch <branch>` can both create the worktree and move the user's shell into it. There is no build system, package manager, or test suite — everything is plain `bash` + `awk`.

## Common commands

```sh
./install.sh                    # install binary, inject shell wrapper, optionally install skill
./install.sh --no-skill         # skip the agent-skill prompt (useful in CI / non-interactive runs)
./install.sh --skill-for=claude # install the skill only for selected agents
./uninstall.sh                  # reverse install: remove binary, wrapper block, and skill copies

GWT_INSTALL_DIR=/some/dir ./install.sh   # override binary destination (default: ~/.local/bin)

bin/git-wt help                 # run the CLI directly without installing
bin/git-wt version              # bump VERSION at bin/git-wt:6 when releasing
```

There are no linters or tests configured. When changing `bin/git-wt`, exercise it manually in a throwaway repo (create / switch / list / rm with both clean and dirty trees).

## Architecture — the two halves

The trick that makes `git wt switch` actually `cd` is that the work is split between two artifacts that **must stay in sync**:

1. **`bin/git-wt`** — the real binary. A subprocess cannot change its parent shell's `cwd`, so this script does all the worktree work and **prints the destination path as the final line of stdout**. All decorative/log output (`info`, `warn`, `report`, etc.) goes to **stderr** via the helpers at [bin/git-wt:23-45](bin/git-wt#L23-L45). Anything that goes to stdout will be interpreted as a path by the wrapper.

2. **Shell wrapper function** — injected into `~/.zshrc` / `~/.bashrc` by `install.sh`. It shadows `git`, intercepts `git wt switch`, captures the binary's stdout, and `cd`s into it. Defined in [install.sh:25-43](install.sh#L25-L43). Other `git` invocations (and other `git wt` subcommands like `list` / `rm`) fall through to `command git`, so the binary handles them directly.

Implication when editing: any new subcommand that should change the user's directory must (a) print exactly one path on stdout's last line, and (b) be added to the wrapper's `if` branch in `install.sh`. Everything else stays purely in the binary.

## Worktree layout convention

`bin/git-wt` places sibling worktrees next to the main repo:

```
<parent>/<repo>/                    # main worktree
<parent>/<repo>-worktrees/<slug>/   # one dir per branch
```

`<slug>` is the branch name with `/` flattened to `-` (see `sanitize_branch` at [bin/git-wt:80-82](bin/git-wt#L80-L82)). Branch resolution order in `cmd_switch` ([bin/git-wt:95-159](bin/git-wt#L95-L159)): existing worktree → local branch → `origin/<branch>` (tracking) → new branch from `HEAD`.

## Installer details that matter

- **Idempotent rc edits.** The wrapper is delimited by `# >>> git-wt >>>` / `# <<< git-wt <<<` markers. `inject_wrapper` ([install.sh:106-127](install.sh#L106-L127)) strips any existing block before re-appending, and **preserves the rc file's original mode** via `stat -f`/`stat -c`. Keep this behavior when modifying — clobbering perms on `~/.zshrc` is a regression.
- **PATH injection.** The wrapper block also prepends `~/.local/bin` (or `$GWT_INSTALL_DIR`) to `$PATH` if absent, so users don't have to edit their rc twice.
- **Skill targets** are listed once at [install.sh:15-20](install.sh#L15-L20) (`SKILL_TARGETS`). Adding a new agent means appending an entry there and to the prompt in `prompt_skill_targets`. `uninstall.sh` has its own parallel list at [uninstall.sh:11-16](uninstall.sh#L11-L16) — keep both in sync.

## The bundled agent skill

`skills/git-wt/SKILL.md` is the **source of truth** for the agent skill that the installer copies into `~/.claude/skills/git-wt/`, `~/.cursor/skills/git-wt/`, etc. Edit it here, not in the installed copies — the installer overwrites them on next run. The skill instructs agents on when to suggest an isolated worktree and how to drive `git wt` (notably: stdout's last line is the destination path; everything else is on stderr).

## Project conventions

- Shell scripts use `set -euo pipefail` and ANSI color helpers gated on `[ -t 2 ] && [ -z "${NO_COLOR:-}" ]`. Honor `NO_COLOR` in any new output.
- All user-facing messages from `bin/git-wt` go to stderr. Reserve stdout for machine-readable output (currently: the destination path).
- Target POSIX-ish bash + GNU/BSD coreutils. The codebase already does dual `stat -f`/`stat -c` fallbacks for macOS vs. Linux — follow that pattern for any new platform-specific call.
