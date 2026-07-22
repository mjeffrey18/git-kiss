# Git Kiss (gk)

## Project Overview

git-kiss (`gk`) is a single-file Bash CLI tool that wraps common git operations into short commands for clean, rebase-based workflows. It lives at `bin/gk` and is installed to `/usr/local/bin/gk`.

## Architecture

- **Single script**: All logic is in `bin/gk` — no build step, dependencies are git, bash, and jq (jq required for config parsing; `gh` only for `gk pr`)
- **Config**: JSONC parsed with `jq`, loaded from four cascading layers: `~/.gk/.gitkiss.jsonc` (global) -> `.gitkiss.jsonc` (committed team) -> `~/.gk/projects.jsonc` (canonical main-worktree key) -> `.gitkiss.local.jsonc` (gitignored personal); later overrides earlier
- **Two flows**: "Full" (main/develop/staging with tags) and "Simple" (main/feature only)
- **Worktrees**: `gk wt` subcommands manage git worktrees as sibling directories (`repo--name`). When a worktree is created, files are seeded into it by combining the `worktree_copy` config array with patterns from an optional `.worktreeinclude` file in the project root (`.gitignore`-style: one glob per line, `#` comments, blank lines ignored); the two sources are merged and deduplicated
- **Version check**: Runs after every command, compares against GitHub, checks once per day via a timestamp file at `$HOME/.gk/version_check`. Set `GK_NO_VERSION_CHECK` to any non-empty value to disable it

## Key Conventions

- All branch operations use **rebase** except `gk ff` which uses `--no-ff` merge
- Feature branches must have the configured prefix (default `feature/`)
- Commands with `!` suffix (e.g. `ff!`, `dp!`) skip confirmation prompts and auto-push
- Exit early with `die()` on errors — script uses `set -euo pipefail`
- Legacy shell `.gitkiss` is auto-migrated when interactive (prompts the user), or read in place when non-interactive; `gk migrate` performs the conversion explicitly, splitting team vs personal config and backing the original up to `.bak`

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core) with bats-assert and bats-support as git submodules.

```bash
bats tests/           # run all tests
bats tests/wt.bats   # run a single test file
```

Each test creates a temp git repo with a bare remote in `setup()` and cleans up in `teardown()`. Shared helpers are in `tests/test_helper/setup.bash`.

When writing tests:

- Config changes must be committed (and pushed if the command pulls from origin) to avoid dirty tree errors
- Interactive commands (`read -r -p`) will hang in tests — use the `!` force variants
- The `GK` variable points to `bin/gk` relative to the test directory
- The shared setup exports `GK_NO_VERSION_CHECK=1` (and isolates `$HOME`) so the daily update check never runs or hits the network during tests

## File Structure

```
bin/gk                          # the CLI (single file)
install.sh                      # curl installer
tests/
  test_helper/
    setup.bash                  # shared setup/teardown helpers
    bats-support/               # git submodule
    bats-assert/                # git submodule
  *.bats                        # test files (one per command group)
```
