# git-wt

A small wrapper around `git worktree` that lets you switch worktrees the way
you switch branches — including actually moving your shell into the target
directory.

```sh
git wt switch feature/login   # creates worktree if missing, cds into it
git wt list                   # shows all worktrees, marks current
git wt rm feature/login       # removes the worktree (warns if dirty)
```

## Why

`git worktree` is great but clumsy day-to-day: a subprocess can't change your
shell's `cwd`, so there's no built-in "switch to this worktree" command.
`git-wt` solves that with a binary plus a tiny shell function that `cd`s into
the path the binary prints.

## Install

```sh
git clone https://github.com/Miguelslo27/git-wt.git
cd git-wt
./install.sh
```

The installer:

1. Copies `bin/git-wt` to `~/.local/bin/git-wt` (override with `GWT_INSTALL_DIR`).
2. Injects a wrapper function into `~/.zshrc` and/or `~/.bashrc`, delimited
   by `# >>> git-wt >>>` / `# <<< git-wt <<<` markers (idempotent).
3. Warns if `~/.local/bin` isn't on your `$PATH`.
4. Suggests installing `fzf` if missing (optional, enables interactive picker).

Restart your shell (or `source` your rc) afterwards.

## Usage

| Command | What it does |
| --- | --- |
| `git wt switch <branch>` | Switch to the worktree for `<branch>`. Creates one if it doesn't exist (tracks `origin/<branch>` if it exists remotely, otherwise creates a new branch from `HEAD`). |
| `git wt switch` | With no arg, opens an `fzf` picker over existing worktrees. |
| `git wt list` | Pretty-prints worktrees, marks the one you're in with `*`. |
| `git wt rm <branch>` | Removes the worktree for `<branch>`. Prompts if it has uncommitted changes. |
| `git wt help` | Show help. |
| `git wt version` | Show version. |

## Layout

Worktrees are created next to the main repo:

```
~/Work/
├── myrepo/                       # main worktree
└── myrepo-worktrees/
    ├── feature-login/            # branch "feature/login"
    └── hotfix-prod/              # branch "hotfix/prod"
```

Branch names containing `/` are flattened to `-` for the directory name.

## Requirements

- `git` 2.5+ (for worktree support)
- `bash` or `zsh`
- `fzf` (optional — only for argument-less `git wt switch`)

## Uninstall

```sh
./uninstall.sh
```

Removes the binary and the wrapper block from your shell rc files.

## License

MIT — see [LICENSE](LICENSE).
