---
name: git-wt
description: Consult this skill at the start of any task that will modify code in a git repository (implement, add, create, build, refactor, fix, change, update, experiment) and also when the user explicitly mentions worktrees, isolation, parallel branches, or working without affecting their current branch. The skill decides whether to suggest an isolated worktree based on the current branch, dirty state, and task scope, and manages worktrees via the `git wt` CLI. Skip the suggestion for trivial edits, read-only questions, or after the user has declined earlier in the session.
---

# git-wt skill

Use the `git wt` CLI to keep non-trivial work isolated without disturbing the user's current branch.

## When to suggest a worktree

Evaluate these signals **before** starting the task:

1. **Explicit request** — the user mentions worktree, isolation, a parallel branch, or experimenting without affecting the current branch.
2. **Protected current branch** — the current branch matches any of (case-insensitive): `main`, `master`, `develop`, `dev`, `staging`, `stage`, `stg`, `production`, `prod`, `release/*`, `hotfix/*`.
3. **Dirty working tree that could conflict** — `git status --porcelain` reports changes in files the task will touch.
4. **Current worktree mismatches the task** — the user is on a non-main worktree, but its branch name and recent commits are unrelated to what was just asked.

Only proceed to suggest if the task also looks **non-trivial**. Make a quick estimation first: peek at the relevant files before asking. Treat the task as trivial and skip the suggestion when any of these apply:

- Typo fix, doc-only change, or a single-line edit.
- Read-only task (explain, summarize, find, review).
- Questions about the codebase.
- The user already declined a worktree suggestion earlier in this session.

When in doubt, default to **not** suggesting — a noisy prompt is worse than a missed one.

## How to ask

Ask once, concisely, and offer both execution modes plus an opt-out:

> "This looks non-trivial and you're on `<branch>`. Want me to work in an isolated worktree?
> (A) I work there and show you the diff, or (B) I set it up so you can `cd` into it. Or we stay here."

If the user declines, **remember that decision for the rest of the session** and do not ask again.

## Branch naming

When creating a new worktree, propose a branch name derived from the task:

| Task type | Suggested prefix |
| --- | --- |
| Feature work | `feature/<kebab-slug>` |
| Bug fix | `fix/<kebab-slug>` |
| Experiment or spike | `experiment/<kebab-slug>` |
| Refactor | `refactor/<kebab-slug>` |

Confirm the name with the user before creating.

## Base branch policy

**Applies only to creating a new branch.** Switching into an already-existing branch (local or `origin/`) does not use this policy — `git wt switch <existing>` brings the branch as-is.

When creating a new branch (`feature/*`, `fix/*`, `refactor/*`, `experiment/*`), the new branch must always be cut from the **latest** `dev` — or from the latest `main` if `dev` exists neither locally nor on `origin`.

### Resolve the base

Use `dev` when either ref exists:

```sh
git show-ref --verify --quiet refs/heads/dev \
  || git show-ref --verify --quiet refs/remotes/origin/dev
```

Otherwise use `main`. Same rule for every prefix listed in *Branch naming* — `experiment/*` is not exempt.

### Update the base before creating

1. Refresh remote refs:

   ```sh
   git fetch origin --prune
   ```

2. Locate which worktree, if any, has `<base>` as HEAD by parsing `git worktree list --porcelain`.

3. **Path A — `<base>` is checked out in some worktree `<base-wt>`:**

   1. If `git -C <base-wt> status --porcelain` is non-empty (dirty), stash with an identifiable message:

      ```sh
      git -C <base-wt> stash push -u -m "git-wt: pre-pull $(date +%s)"
      ```

      The `-u` flag includes untracked files so nothing is left behind.

   2. Fast-forward the base:

      ```sh
      git -C <base-wt> pull --ff-only
      ```

   3. If a stash was created in step 3.i, restore it:

      ```sh
      git -C <base-wt> stash pop
      ```

   4. Create the new branch from there. The CLI creates from HEAD, which is now the updated base:

      ```sh
      cd <base-wt> && git wt switch <new-branch>
      ```

4. **Path B — `<base>` is not checked out in any worktree:**

   1. Fast-forward the local ref directly, without needing a working tree:

      ```sh
      git fetch origin <base>:<base>
      ```

      This updates `refs/heads/<base>` in place. No stash dance is needed because there is no working tree to disturb.

   2. Create the new worktree from the updated local ref using raw `git worktree`:

      ```sh
      git worktree add -b <new-branch> <dest> <base>
      ```

      where `<dest>` follows the existing layout: `<parent>/<repo>-worktrees/<sanitized-branch>` (`/` flattened to `-`).

### Stop and ask the user when

The agent must surface and stop instead of resolving automatically:

- **`pull --ff-only` fails because the local `<base>` has diverged from `origin/<base>`** (local commits ahead, or history rewritten). Do not `rebase`, `merge`, or `reset --hard` without explicit consent.
- **`stash pop` reports a conflict** — the remote modified files the user had also modified. The original changes remain in `git stash list` (recoverable with `git stash apply <ref>`); tell the user the worktree at `<base-wt>` has conflict markers and let them resolve.

## Commands

### Create or switch

```sh
git wt switch <branch>
```

- Creates the worktree if it does not exist. Tracks `origin/<branch>` when that remote branch exists, otherwise creates a new local branch from `HEAD`.
- **When `<branch>` is new (no local ref, no `origin/<branch>`), follow [Base branch policy](#base-branch-policy) first.** The CLI itself always cuts from current `HEAD`, so positioning HEAD on the updated base — or using the raw `git worktree add` fallback — is the agent's responsibility.
- Prints a human-readable report to **stderr**.
- Prints the **target path as the last line of stdout**. Capture it like this:

```sh
target=$(git wt switch feature/x | tail -n1)
# inside your own shell commands only — this cannot change the user's interactive shell cwd
cd "$target"
```

### List

```sh
git wt list
```

Marks the current worktree with `*`.

### Remove

```sh
git wt rm <branch>
```

**Always confirm with the user before running `rm`**, even when the skill is authorized to execute shell commands. Warn explicitly if the worktree has uncommitted changes, and never pass `--force` without explicit user approval.

## Execution modes

### Mode A — agent works in the worktree

1. Run `git wt switch <branch>` and capture the path from the last stdout line.
2. Run every subsequent command scoped to that path (`git -C <path> ...` or `cd <path> && ...`). The user's interactive shell must remain untouched.
3. When the task is done, summarize the diff and point the user at the worktree path so they can review it.

### Mode B — hand off to the user

1. Run `git wt switch <branch>` to create and prepare the worktree.
2. Tell the user:

   > "Ready. Run `cd <path>` to move there. `git wt` is wired into your shell, so it can `cd` automatically when you invoke it yourself."

3. Do not continue editing inside that worktree unless the user explicitly asks.

## Guardrails

- Never run `git wt rm` without confirmation.
- Never force-remove a dirty worktree unless the user explicitly authorizes it.
- Do not create a worktree for read-only tasks — answer the question instead.
- If `git wt` is not installed, say so and point the user at `https://github.com/Miguelslo27/git-wt`. Do not silently fall back to raw `git worktree` unless the user asks for it.

## Output parsing reminder

`git wt` sends decorative output to stderr. When capturing the destination path programmatically, read stdout only and take the last line.
