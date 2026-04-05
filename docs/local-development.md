# Local Development

## Prerequisites

- **git** (any recent version)
- **bash** 4.0+ (macOS ships with 3.x — install via `brew install bash` if needed)
- **bats-core** for running tests

## Setup

Clone the repo and initialise the test submodules:

```bash
git clone https://github.com/mjeffrey18/git-kiss.git
cd git-kiss
git submodule update --init --recursive
```

Install bats-core:

```bash
brew install bats-core
```

## Running Locally

You can run `gk` directly from the repo without installing:

```bash
bash bin/gk help
bash bin/gk version
```

Or make it available on your PATH for the current session:

```bash
export PATH="$PWD/bin:$PATH"
gk help
```

To test against a real repo, `cd` into any git repository and run commands using the full path:

```bash
cd ~/my-project
bash ~/path/to/git-kiss/bin/gk nf my-feature
```

## Testing

Run the full test suite:

```bash
bats tests/
```

Run a single test file:

```bash
bats tests/wt.bats
bats tests/ff.bats
```

Run a specific test by name:

```bash
bats tests/wt.bats --filter "gk wt ls"
```

### How Tests Work

Each test creates a temporary git repo with a bare remote in `/tmp`, runs `gk` commands against it, and cleans up afterwards. No real repos are touched.

- **`tests/test_helper/setup.bash`** — shared helpers (`setup_test_repo`, `setup_full_flow_repo`, `teardown_test_repo`, `create_feature_branch`)
- **`tests/test_helper/bats-support/`** — assertion support library (git submodule)
- **`tests/test_helper/bats-assert/`** — `assert_success`, `assert_output`, etc. (git submodule)

### Writing Tests

When adding new tests, keep these in mind:

1. **Commit config changes** — if you write a `.gitkiss` file mid-test, `git add` and commit it. Otherwise commands that pull from origin will fail with "dirty tree" errors.

2. **Avoid interactive prompts** — commands like `gk ff`, `gk dp`, `gk ds` use `read` for confirmation. Use the `!` variants (`ff!`, `dp!`, `ds!`) in tests, or test the failure path instead.

3. **Use the `GK` variable** — it points to `bin/gk` relative to the test directory:
   ```bash
   run bash "$GK" nf my-feature
   assert_success
   ```

4. **Test structure** — use `setup()` and `teardown()` in every `.bats` file:
   ```bash
   setup() {
     load 'test_helper/setup'
     setup_test_repo          # or setup_full_flow_repo
   }

   teardown() {
     teardown_test_repo
   }
   ```

## Debugging

Set `GK_DEBUG=1` to enable debug logging. All debug output goes to stderr in dimmed text, so it won't interfere with stdout (e.g. `gk wt co`).

```bash
GK_DEBUG=1 gk help
```

This logs:

- Config loading (which files were found/loaded, resolved values)
- Command dispatch (which command and args are being run)
- Version check (stamp file state, whether the HTTP call was made or skipped, version comparison result)

You can also combine it with other commands:

```bash
GK_DEBUG=1 gk nf my-feature
GK_DEBUG=1 gk wt ls
```

## Installing Locally

To install your local version system-wide (overwriting any existing install):

```bash
chmod +x bin/gk
cp bin/gk /usr/local/bin/gk
```

Or with sudo if needed:

```bash
sudo cp bin/gk /usr/local/bin/gk
```

## Project Structure

```
bin/gk                          # the CLI script
install.sh                      # curl-based installer
tests/
  test_helper/
    setup.bash                  # shared test helpers
    bats-support/               # git submodule
    bats-assert/                # git submodule
  help.bats                     # help, version, unknown commands
  nf.bats                       # new feature branch
  ff.bats                       # finish feature
  sf.bats                       # squash feature
  cm.bats                       # commit
  pf.bats                       # publish feature
  rf.bats                       # rebase feature
  wt.bats                       # worktree commands
  deploy.bats                   # ds/dp deploy commands
  version_check.bats            # version check system
  config.bats                   # configuration loading
```
