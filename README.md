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
gk init              # interactively create global, project, shared, or local JSONC config
gk nf <feature-name> # start a feature branch
# ... make changes, commit ...
gk pf                # publish branch to remote
gk pr <title>        # create a pull request (requires gh CLI)
gk pr ls             # list PRs for local branches
gk rf                # rebase feature with latest base branch changes
gk ff                # finish feature (merge into base branch)
```

## Commands

| Command           | Description                                                              |
| ----------------- | ------------------------------------------------------------------------ |
| `gk nf "<name>"`  | **New feature** — create a feature branch from the base branch           |
| `gk ff` / `ff!`   | **Finish feature** — merge feature into base branch (merge commit)       |
| `gk sf` / `sf!`   | **Squash feature** — squash all commits on the branch into one           |
| `gk cm "<msg>"`   | **Commit** — add all changes and commit with message                     |
| `gk rc` / `rc!`   | **Reset commit** - safely undo the last commit, keeping changes unstaged |
| `gk pf`           | **Publish feature** — push feature branch to remote                      |
| `gk pr "<title>"` | **Pull request** — create a PR via `gh` CLI (supports extra `gh` flags)  |
| `gk pr ls`        | **Pull requests** - list PRs for local branches                          |
| `gk rf`           | **Rebase feature** — rebase feature against base branch                  |
| `gk ds` / `ds!`   | **Deploy staging** — rebase feature onto staging branch                  |
| `gk dp` / `dp!`   | **Deploy production** — rebase develop into main and tag a release       |
| `gk wt <cmd>`     | **Worktree** — manage git worktrees (see below)                          |
| `gk init`         | **Init** — interactively generate configuration in one selected scope    |
| `gk migrate`      | **Migrate** — convert legacy shell configuration to JSONC                |
| `gk shell-init`   | **Shell init** — print shell integration for `gk wt co`                  |
| `gk version`      | **Version** — print the installed version (`--version` too)              |
| `gk help`         | **Help** — show usage                                                    |

### Pull Requests

`gk pr` requires a title and automatically targets the base branch. Any additional flags are passed directly to [`gh pr create`](https://cli.github.com/manual/gh_pr_create):

```bash
gk pr "Add user authentication"
gk pr "Fix login bug" --draft
gk pr "Update API" --reviewer octocat --label enhancement
gk pr "Refactor auth" --body "Switched to JWT tokens"
```

Use `gk pr ls` to see pull requests for every local branch, including branches in linked worktrees.

## Worktrees

`gk wt` makes it easy to work on multiple branches simultaneously using [git worktrees](https://git-scm.com/docs/git-worktree). Each worktree gets its own directory as a sibling to your main repo:

```
~/projects/my-repo/              ← main worktree
~/projects/my-repo--login/       ← gk wt nf login
~/projects/my-repo--hotfix-db/   ← gk wt nb hotfix-db
```

| Command            | Description                                                                          |
| ------------------ | ------------------------------------------------------------------------------------ |
| `gk wt nf <name>`  | New worktree with a feature branch (uses prefix/initials)                            |
| `gk wt nb <name>`  | New worktree with a plain branch                                                     |
| `gk wt ls`         | List all worktrees with status                                                       |
| `gk wt rm <id>`    | Remove a worktree by index or branch name (prompts if dirty)                         |
| `gk wt rm! <id>`   | Remove a worktree, skipping the dirty-tree prompt                                    |
| `gk wt clean`      | Remove merged worktrees (skips any with uncommitted changes)                         |
| `gk wt clean!`     | Remove merged worktrees, including any with uncommitted changes                      |
| `gk wt co [index]` | Select from the worktree status table or use a displayed index (cds with shell-init) |

```bash
gk wt nf task1      # create worktree with feature/mj-task1 branch
gk wt nb hotfix-db  # create worktree with hotfix-db branch
gk wt ls            # list all worktrees (numbered)
gk wt co            # interactively switch to a worktree (see below)
gk wt co 2          # switch directly to displayed worktree index 2
gk wt rm 2          # remove worktree #2
gk wt rm task1      # remove worktree matching "task1"
gk wt clean         # clean up merged worktrees
```

### Seeding files into new worktrees

A new worktree is a fresh checkout of the base branch, so anything you don't commit — `.env` files, local config, editor settings — won't be there. git-kiss can copy those over automatically from your main worktree when it creates one.

`.worktreeinclude` is authoritative whenever it exists in the canonical main
worktree. If it is absent, git-kiss falls back to `worktree_copy` from the
effective configuration. An empty or comment-only include file intentionally
copies nothing.

| Source                                            | Tracked         | Best for                             |
| ------------------------------------------------- | --------------- | ------------------------------------ |
| `.worktreeinclude` in the canonical main worktree | commit it       | authoritative team-wide copy list    |
| `worktree_copy` in your `.gitkiss.*.jsonc`        | varies by layer | fallback when no include file exists |

#### .worktreeinclude

`.worktreeinclude` uses the same format as `.gitignore` — one glob per line, `#` comments, blank lines ignored:

```gitignore
.env
.env.*
config/local
.vscode/settings.json
```

#### worktree_copy (.gitkiss.jsonc / .gitkiss.local.jsonc)

`worktree_copy` is the JSON-array equivalent, set in any config layer:

```jsonc
// .gitkiss.local.jsonc - gitignored personal overrides
{
  "worktree_copy": [".env*", "config/local"],
}
```

Patterns are resolved as shell globs **relative to the project root** and copied from your main worktree's current working tree (so uncommitted files come across too). Literal paths containing spaces are supported. Absolute paths and `.` / `..` path components are rejected. Symlinks are refused rather than copied, so a copy source cannot escape the project root. Linked worktrees use the canonical main-worktree include file and inherit the main worktree's `.gitkiss.local.jsonc` unless they provide their own local override.

### Navigating between worktrees

To get `gk wt co` to `cd` you straight into the chosen worktree, add shell integration
to your `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(gk shell-init)"
```

Pass a displayed zero-based index to switch without the selector, which is useful in
shell scripts and when you already know the destination:

```bash
gk wt co 2
```

Alternatively, you can add a manual alias if you prefer not to wrap `gk`:

```bash
alias wtco='cd $(gk wt co)'
```

### Worktree status

`gk wt ls` and the interactive `gk wt co` selector show:

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

git-kiss reads JSONC config from five cascading layers. Each later layer
overrides keys set by earlier ones, so you only set what you want to change:

| Location               | Scope                                  | Tracked    |
| ---------------------- | -------------------------------------- | ---------- |
| `~/.gk/.gitkiss.jsonc` | global personal defaults for all repos | n/a        |
| `~/.gk/projects.jsonc` | per-project personal defaults          | n/a        |
| `.gitkiss.jsonc`       | per-repo team config                   | commit it  |
| `.gitkiss.local.jsonc` | per-repo personal overrides            | gitignored |

Project-store entries are keyed by the canonical main-worktree path, so linked
worktrees share settings. An empty `{}` entry acknowledges inherited settings
without prompting again. Run `gk init` in a terminal to generate configuration,
or `gk migrate` to upgrade legacy configuration.

`~/.gk/projects.jsonc` is machine-managed: edit it only when git-kiss is not
running, and do not commit or share it. The precedence order is built-in defaults,
global configuration, the project-store entry, shared repository configuration,
then local repository configuration. Legacy `~/.git-kiss.jsonc` is migrated to
`~/.gk/.gitkiss.jsonc` on the next normal command when no destination collision
exists; collisions leave the legacy file untouched.

```jsonc
// .gitkiss.jsonc - committed team config
{
  "main_branch": "main",
  "develop_branch": "develop",
  "staging_branch": "staging",
  "feature_prefix": "feature/",
  "use_tags": true,
}
```

```jsonc
// .gitkiss.local.jsonc - gitignored personal overrides
{
  "initials": "mj",
  "worktree_copy": [".env*", "config/local"],
}
```

| Key              | Default    | Description                                                                                                               |
| ---------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------- |
| `main_branch`    | `main`     | Production branch                                                                                                         |
| `develop_branch` | `develop`  | Integration branch (`""` for simple flow)                                                                                 |
| `staging_branch` | `staging`  | Staging branch (`""` if unused)                                                                                           |
| `feature_prefix` | `feature/` | Prefix for feature branches                                                                                               |
| `use_tags`       | `true`     | Auto-increment semver tags on `gk dp`                                                                                     |
| `initials`       |            | Prepended to feature branches (e.g. `mj`) - usually in `.local`                                                           |
| `worktree_copy`  | `[]`       | Files/folders (literal or glob) copied into new worktrees when no `.worktreeinclude` exists - see [Worktrees](#worktrees) |

> Comments must be on their own line (`//`). Inline and `/* */` comments aren't supported.

## Updating

`gk` checks GitHub for a newer release once a day and prints a one-line notice when an update is available - re-run the [curl installer](#install) to upgrade. The check runs after a command, never blocks it, and records the last-checked time in `~/.gk/version_check`.

Set the `GK_NO_VERSION_CHECK` environment variable to any non-empty value to disable the check entirely (handy for CI or air-gapped machines):

```bash
export GK_NO_VERSION_CHECK=1
```

## Requirements

- **git** (obviously)
- **jq** - required for reading config. `brew install jq` (macOS) / `apt install jq` (Linux).
- **gh** (GitHub CLI) — only needed for `gk pr`. [Install here](https://cli.github.com).

## License

MIT
