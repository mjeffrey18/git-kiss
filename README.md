# git-kiss

Keep It Simple, Stupid — a dead-simple CLI wrapper for git and github cli (optional) for clean git workflows.

`gk` wraps common git operations into short commands that keep your branch history clean and linear. Most operations use **rebasing** to avoid unnecessary merge commits and keep your history easy to follow. The one exception is `gk ff` (feature finish), which uses a **merge commit with `--no-ff`** so you can always see where a feature was integrated.

## Install

**Homebrew:**

> Coming soon...

**curl:**

```bash
curl -fsSL https://raw.githubusercontent.com/mjeffrey18/git-kiss/main/install.sh | bash
```

## Quick Start

```bash
cd your-repo
gk init              # create a JSONC config (choose full or simple flow)
gk nf <feature-name> # start a feature branch
# ... make changes, commit ...
gk pf                # publish branch to remote
gk pr <title>        # create a pull request (requires gh CLI)
gk rf                # rebase feature with latest base branch changes
gk ff                # finish feature (merge into base branch)
```

## Commands

| Command           | Description                                                             |
| ----------------- | ----------------------------------------------------------------------- |
| `gk nf "<name>"`  | **New feature** — create a feature branch from the base branch          |
| `gk ff` / `ff!`   | **Finish feature** — merge feature into base branch (merge commit)      |
| `gk sf` / `sf!`   | **Squash feature** — rebase onto base and squash all commits into one   |
| `gk cm "<msg>"`   | **Commit** — add all changes and commit with message                    |
| `gk pf`           | **Publish feature** — push feature branch to remote                     |
| `gk pr "<title>"` | **Pull request** — create a PR via `gh` CLI (supports extra `gh` flags) |
| `gk rf`           | **Rebase feature** — rebase feature against base branch                 |
| `gk ds` / `ds!`   | **Deploy staging** — rebase feature onto staging branch                 |
| `gk dp` / `dp!`   | **Deploy production** — rebase develop into main and tag a release      |
| `gk wt <cmd>`     | **Worktree** — manage git worktrees (see below)                         |
| `gk init`         | **Init** — generate a `.gitkiss.jsonc` config file                      |
| `gk help`         | **Help** — show usage                                                   |

### Pull Requests

`gk pr` requires a title and automatically targets the base branch. Any additional flags are passed directly to [`gh pr create`](https://cli.github.com/manual/gh_pr_create):

```bash
gk pr "Add user authentication"
gk pr "Fix login bug" --draft
gk pr "Update API" --reviewer octocat --label enhancement
gk pr "Refactor auth" --body "Switched to JWT tokens"
```

### Worktrees

`gk wt` makes it easy to work on multiple branches simultaneously using [git worktrees](https://git-scm.com/docs/git-worktree). Each worktree gets its own directory as a sibling to your main repo:

```
~/projects/my-repo/              ← main worktree
~/projects/my-repo--login/       ← gk wt nf login
~/projects/my-repo--hotfix-db/   ← gk wt nb hotfix-db
```

| Command           | Description                                                |
| ----------------- | ---------------------------------------------------------- |
| `gk wt nf <name>` | New worktree with a feature branch (uses prefix/initials)  |
| `gk wt nb <name>` | New worktree with a plain branch                           |
| `gk wt ls`        | List all worktrees with status                             |
| `gk wt rm <id>`   | Remove a worktree by index or branch name                  |
| `gk wt clean`     | Remove all worktrees with merged branches                  |
| `gk wt co`        | Interactively select a worktree (cds into it when shell-init is enabled) |

```bash
gk wt nf task1      # create worktree with feature/mj-task1 branch
gk wt nb hotfix-db  # create worktree with hotfix-db branch
gk wt ls            # list all worktrees (numbered)
gk wt co            # interactively switch to a worktree (see below)
gk wt rm 2          # remove worktree #2
gk wt rm task1      # remove worktree matching "task1"
gk wt clean         # clean up merged worktrees
```

To get `gk wt co` to `cd` you straight into the chosen worktree, add shell integration
to your `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(gk shell-init)"
```

Alternatively, you can add a manual alias if you prefer not to wrap `gk`:

```bash
alias wtco='cd $(gk wt co)'
```

`gk wt ls` output:

```
  #    Branch                         Path                                     Status
  ─────────────────────────────────────────────────────────────────────────────────
● 0    main                           ~/projects/my-repo
  1    feature/mj-login               ~/projects/my-repo--mj-login             3↑ 1↓
  2    feature/mj-signup              ~/projects/my-repo--mj-signup            2↑ *
  3    hotfix-db                      ~/projects/my-repo--hotfix-db            1↑
```

- `●` = current worktree
- `*` = dirty working tree
- `↑↓` = commits ahead/behind base branch

All other `gk` commands (`cm`, `pf`, `rf`, `pr`, etc.) work inside worktrees — just `cd` into one and use `gk` as normal.

## How It Works

git-kiss uses **rebasing** for almost everything. This keeps your commit history linear and easy to read — no tangled merge spaghetti. The only exception is `gk ff` which creates a **merge commit** (`--no-ff`) so you can clearly see where each feature was integrated.

### Full Flow

Branches: `main` ← `develop` ← `feature/*` with `staging` and release tags.

Best for teams with a release process, staging environment, and versioned deploys.

```
main         ●─────────────────────────●──── v1.0.1
              \                       /
develop        ●───●───●─────●───●───●
                \     /       \     /
feature/login    ●──●     feature/signup
                              ●──●

staging        ●───●───●  (rebased from feature for testing)
```

**What happens at each step:**

```
gk nf <initial>-<feature-name> →  develop ──branch──→ feature/login
                                   (rebase: pull latest develop first)

gk rf                          →  feature/login is rebased onto latest develop
                                   (rebase: clean linear history)

gk ff                          →  feature/login ──merge──→ develop
                                   (merge commit: marks where feature was integrated)

gk ds                          →  feature/signup ──rebase──→ staging
                                   (rebase: staging gets feature commits on top)

gk dp                          →  develop ──rebase──→ main + tag v1.0.1
                                   (rebase: main stays linear, tag marks release)
```

### Simple Flow

Branches: `main` ← `feature/*` — no develop branch, no staging, no tags.

Best for small teams or projects that deploy directly from main.

```
main         ●───●───●─────●───●───●
              \     /       \     /
feature/login  ●──●     feature/signup
                              ●──●
```

**What happens at each step:**

```
gk nf login         →  main ──branch──→ feature/login
                        (rebase: pull latest main first)

gk rf               →  feature/login is rebased onto latest main
                        (rebase: clean linear history)

gk ff               →  feature/login ──merge──→ main
                        (merge commit: marks where feature was integrated)
```

### Why rebase + merge commit?

- **Rebase everywhere else** keeps the history linear. No unnecessary merge commits cluttering up `git log`.
- **Merge commit on finish** (`--no-ff`) creates a single marker in history showing exactly when a feature landed. You can always find it with `git log --merges`.

The result is a clean, readable history:

```
* abc1234  Merge branch 'feature/login' into develop
|\
| * def5678  Add login validation
| * ghi9012  Add login form
|/
* jkl3456  Merge branch 'feature/signup' into develop
|\
| * mno7890  Add signup flow
|/
* pqr1234  Initial commit
```

## Configuration

git-kiss reads JSONC config from up to three cascading layers. Each later layer
overrides keys set by earlier ones, so you only set what you want to change:

| Location               | Scope                                   | Tracked    |
| ---------------------- | --------------------------------------- | ---------- |
| `~/.git-kiss.jsonc`    | global personal defaults for all repos  | n/a        |
| `.gitkiss.jsonc`       | per-repo team config                    | commit it  |
| `.gitkiss.local.jsonc` | per-repo personal overrides             | gitignored |

Run `gk init` to generate config, or `gk migrate` to upgrade a pre-JSONC `.gitkiss`.

```jsonc
// .gitkiss.jsonc - committed team config
{
  "main_branch": "main",
  "develop_branch": "develop",
  "staging_branch": "staging",
  "feature_prefix": "feature/",
  "use_tags": true
}
```

```jsonc
// .gitkiss.local.jsonc - gitignored personal overrides
{
  "initials": "mj",
  "worktree_copy": [".env*", "config/local"]
}
```

| Key              | Default    | Description                                                     |
| ---------------- | ---------- | --------------------------------------------------------------- |
| `main_branch`    | `main`     | Production branch                                               |
| `develop_branch` | `develop`  | Integration branch (`""` for simple flow)                       |
| `staging_branch` | `staging`  | Staging branch (`""` if unused)                                 |
| `feature_prefix` | `feature/` | Prefix for feature branches                                     |
| `use_tags`       | `true`     | Auto-increment semver tags on `gk dp`                           |
| `initials`       |            | Prepended to feature branches (e.g. `mj`) - usually in `.local` |
| `worktree_copy`  | `[]`       | Files/folders (literal or glob) copied into new worktrees       |

> Comments must be on their own line (`//`). Inline and `/* */` comments aren't supported.

## Requirements

- **git** (obviously)
- **jq** - required for reading config. `brew install jq` (macOS) / `apt install jq` (Linux).
- **gh** (GitHub CLI) — only needed for `gk pr`. [Install here](https://cli.github.com).

## License

MIT
