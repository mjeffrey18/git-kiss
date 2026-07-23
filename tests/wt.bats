#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  if [[ -n "${LOCKED_DIR_TO_RESTORE:-}" ]]; then
    chmod u+w "$LOCKED_DIR_TO_RESTORE" 2>/dev/null || true
  fi
  teardown_test_repo
}

# ─── wt nf ──────────────────────────────────────────────────────────────────

@test "gk wt nf creates worktree with feature branch" {
  run bash "$GK" wt nf login
  assert_success
  assert_output --partial "Worktree created"

  # Worktree directory should exist
  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--login"
  [ -d "$wt_dir" ]

  # Branch should exist
  run git branch --list "feature/login"
  assert_output --partial "feature/login"
}

@test "gk wt nf applies initials" {
  write_legacy_config "$REPO_DIR/.gitkiss" INITIALS=mj
  git add .gitkiss && git commit -m "add initials" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" wt nf login
  assert_success

  run git branch --list "feature/mj-login"
  assert_output --partial "feature/mj-login"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--mj-login"
  [ -d "$wt_dir" ]
}

@test "gk wt nf lowercases name" {
  run bash "$GK" wt nf My-Feature
  assert_success

  run git branch --list "feature/my-feature"
  assert_output --partial "feature/my-feature"
}

@test "gk wt nf without name fails" {
  run bash "$GK" wt nf
  assert_failure
  assert_output --partial "Usage"
}

# ─── wt nb ──────────────────────────────────────────────────────────────────

@test "gk wt nb creates worktree with plain branch" {
  run bash "$GK" wt nb hotfix-db
  assert_success
  assert_output --partial "Worktree created"

  # Branch should NOT have feature/ prefix
  run git branch --list "hotfix-db"
  assert_output --partial "hotfix-db"

  run git branch --list "feature/hotfix-db"
  refute_output --partial "feature/hotfix-db"
}

@test "gk wt nb without name fails" {
  run bash "$GK" wt nb
  assert_failure
  assert_output --partial "Usage"
}

@test "gk wt nb rejects an invalid generated branch before fetching" {
  run bash "$GK" wt nb 'bad..branch'
  assert_failure
  assert_output --partial "Invalid generated worktree branch"
  [ "$(git worktree list | wc -l | tr -d ' ')" -eq 1 ]
  ! git show-ref --verify --quiet refs/heads/bad..branch
}

# ─── wt ls ──────────────────────────────────────────────────────────────────

@test "gk wt ls shows main worktree" {
  run bash "$GK" wt ls
  assert_success
  assert_output --partial "0"
  assert_output --partial "main"
}

@test "gk wt ls shows numbered worktrees" {
  bash "$GK" wt nb hotfix-one >/dev/null 2>&1
  bash "$GK" wt nf login >/dev/null 2>&1

  run bash "$GK" wt ls
  assert_success
  assert_output --partial "0"
  assert_output --partial "1"
  assert_output --partial "2"
  assert_output --partial "hotfix-one"
  assert_output --partial "feature/login"
}

@test "gk wt ls truncates long branch names before the path column" {
  local long_branch="feature/this-branch-name-is-deliberately-long-for-the-table"
  local wt_dir="$BATS_TEST_TMPDIR/repo--long-branch"
  git worktree add "$wt_dir" -b "$long_branch" main >/dev/null 2>&1

  run bash "$GK" wt ls
  assert_success
  assert_output --partial "feature/this-branch-name-is..."
  refute_output --partial "$long_branch"
}

@test "gk wt ls marks current worktree" {
  local repo_parent
  repo_parent="$(cd "$(dirname "$REPO_DIR")" && pwd -P)"
  run env HOME="$repo_parent" bash "$GK" wt ls
  assert_success
  # Current marker character (●) should be present
  assert_output --partial "●"
  assert_output --partial "~/repo (current)"
}

# ─── wt rm ──────────────────────────────────────────────────────────────────

@test "gk wt rm by index removes worktree" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  # Index 1 should be the new worktree (0 is main)
  run bash "$GK" wt rm 1
  assert_success
  assert_output --partial "Worktree removed"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  [ ! -e "$wt_dir" ]
  [ ! -L "$wt_dir" ]

  run git worktree list --porcelain
  assert_success
  refute_output --partial "worktree $wt_dir"
}

@test "gk wt rm works when invoked from the selected worktree" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"

  run bash -c 'cd "$1" && bash "$2" wt rm 1' _ "$wt_dir" "$GK"
  assert_success
  assert_output --partial "Worktree removed"
  refute_output --partial "Unable to read current working directory"
  assert_output --partial "Branch hotfix-db deleted"
  [ ! -e "$wt_dir" ]
  [ ! -L "$wt_dir" ]

  run git -C "$REPO_DIR" worktree list --porcelain
  assert_success
  refute_output --partial "worktree $wt_dir"
}

@test "gk wt rm reports partial removal when a nested directory is undeletable" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local wt_dir locked_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  locked_dir="$wt_dir/locked"
  mkdir -p "$locked_dir"
  echo "locked" > "$locked_dir/file"
  LOCKED_DIR_TO_RESTORE="$locked_dir"
  chmod u-w "$locked_dir"

  run bash "$GK" wt 'rm!' 1
  chmod u+w "$locked_dir"
  LOCKED_DIR_TO_RESTORE=""

  assert_failure
  assert_output --partial "registration is absent, but filesystem entry remains"
  refute_output --partial "Worktree removed"
  [ -e "$wt_dir" ] || [ -L "$wt_dir" ]

  run git -C "$REPO_DIR" worktree list --porcelain
  assert_success
  refute_output --partial "worktree $wt_dir"
}

@test "gk wt rm catches a recreated worktree path after Git removal" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local wt_dir fake_bin real_git
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  real_git="$(command -v git)"
  fake_bin="$(install_recreating_git_shim)"

  run env PATH="$fake_bin:$PATH" REAL_GIT="$real_git" bash "$GK" wt 'rm!' 1
  assert_failure
  assert_output --partial "registration is absent, but filesystem entry remains"
  refute_output --partial "Worktree removed"
  [ -d "$wt_dir" ]

  run git -C "$REPO_DIR" worktree list --porcelain
  assert_success
  refute_output --partial "worktree $wt_dir"
}

@test "gk wt rm by name removes worktree" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  run bash "$GK" wt rm hotfix-db
  assert_success
  assert_output --partial "Worktree removed"
}

@test "gk wt rm by partial name removes worktree" {
  bash "$GK" wt nf login >/dev/null 2>&1

  run bash "$GK" wt rm login
  assert_success
  assert_output --partial "Worktree removed"
}

@test "gk wt rm refuses to remove main worktree" {
  run bash "$GK" wt rm 0
  assert_failure
  assert_output --partial "Cannot remove the main worktree"
}

@test "gk wt rm with out-of-range index fails" {
  run bash "$GK" wt rm 99
  assert_failure
  assert_output --partial "out of range"
}

@test "gk wt rm with unknown name fails" {
  run bash "$GK" wt rm nonexistent
  assert_failure
  assert_output --partial "Worktree not found"
}

@test "gk wt rm without argument fails" {
  run bash "$GK" wt rm
  assert_failure
  assert_output --partial "Usage"
}

# ─── wt clean ───────────────────────────────────────────────────────────────

@test "gk wt clean with no merged worktrees does nothing" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  # Add a commit so the branch is not merged
  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  echo "work" > "$wt_dir/work.txt"
  git -C "$wt_dir" add -A >/dev/null 2>&1
  git -C "$wt_dir" commit -m "work" >/dev/null 2>&1

  run bash "$GK" wt clean
  assert_success
  assert_output --partial "No merged worktrees"

  # Worktree should still exist
  [ -d "$wt_dir" ]
}

@test "gk wt clean prompts before removing" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  # Without confirmation, clean should list worktrees but not remove them
  run bash "$GK" wt clean <<< "n"
  assert_success
  assert_output --partial "The following merged worktrees will be removed"
  assert_output --partial "hotfix-db"
  assert_output --partial "Aborted"

  # Worktree should still exist
  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  [ -d "$wt_dir" ]
}

@test "gk wt clean! removes merged worktrees without prompt" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  # The branch was just created from main with no extra commits, so it's "merged"
  run bash "$GK" wt 'clean!'
  assert_success
  assert_output --partial "Cleaned up"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  [ ! -d "$wt_dir" ]
}

@test "gk wt clean! reports a recreated path as an incomplete removal" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local wt_dir fake_bin real_git
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  real_git="$(command -v git)"
  fake_bin="$(install_recreating_git_shim)"

  run env PATH="$fake_bin:$PATH" REAL_GIT="$real_git" bash "$GK" wt 'clean!'
  assert_failure
  assert_output --partial "registration is absent, but filesystem entry remains"
  assert_output --partial "Could not remove hotfix-db"
  refute_output --partial "Removed hotfix-db"
  git show-ref --verify --quiet refs/heads/hotfix-db
}

# ─── wt co ─────────────────────────────────────────────────────────────────

@test "gk wt co outputs selected worktree path" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  # A normal command may migrate global JSONC first, but that diagnostic must
  # remain on stderr so shell integration receives only the selected path.
  printf '{ "feature_prefix": "global/" }\n' > "$HOME/.git-kiss.jsonc"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"

  # Select index 1 (the new worktree) - capture stdout only
  local result
  result="$(GK_NO_VERSION_CHECK=1 bash "$GK" wt co <<< "1")"
  # Resolve symlinks for macOS /var -> /private/var
  [ "$(cd "$result" && pwd -P)" = "$(cd "$wt_dir" && pwd -P)" ]
}

@test "gk wt co interactive selector shows worktree status details" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local wt_dir stdout err_file
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  stdout="$BATS_TEST_TMPDIR/stdout"
  err_file="$BATS_TEST_TMPDIR/stderr"

  echo "committed" > "$wt_dir/committed.txt"
  git -C "$wt_dir" add committed.txt
  git -C "$wt_dir" commit -m "worktree commit" >/dev/null 2>&1
  echo "dirty" > "$wt_dir/dirty.txt"

  run bash -c 'bash "$1" wt co <<< "1" > "$2" 2> "$3"' _ "$GK" "$stdout" "$err_file"
  assert_success
  [ "$(cd "$(cat "$stdout")" && pwd -P)" = "$(cd "$wt_dir" && pwd -P)" ]

  local selector
  selector="$(cat "$err_file")"
  [[ "$selector" == *"Branch"* ]]
  [[ "$selector" == *"Path"* ]]
  [[ "$selector" == *"Status"* ]]
  [[ "$selector" == *"hotfix-db"* ]]
  [[ "$selector" == *"$wt_dir"* ]]
  [[ "$selector" == *"1↑"* ]]
  [[ "$selector" == *"*"* ]]
  [[ "$selector" == *"Switch to [#]:"* ]]
}

@test "gk wt co selects a displayed index directly without reading stdin" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local wt_dir stdout err_file
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  stdout="$BATS_TEST_TMPDIR/stdout"
  err_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c 'bash "$1" wt co 1 <<< "0" > "$2" 2> "$3"' _ "$GK" "$stdout" "$err_file"
  assert_success
  [ "$(cd "$(cat "$stdout")" && pwd -P)" = "$(cd "$wt_dir" && pwd -P)" ]
  [[ "$(cat "$err_file")" != *"Switch to [#]"* ]]
  [[ "$(cat "$err_file")" != *"Status"* ]]
}

@test "gk wt co fails for a malformed project store" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  mkdir -p "$HOME/.gk"
  printf '{ invalid\n' > "$HOME/.gk/projects.jsonc"

  local wt_dir err_file
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  err_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c 'result="$(bash "$1" wt co 1 2> "$2")"; status=$?; printf "%s" "$result"; exit "$status"' _ "$GK" "$err_file"
  assert_failure
  [[ "$(cat "$err_file")" == *"Invalid project store"* ]]
}

@test "gk wt co fails for a non-object project store" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  mkdir -p "$HOME/.gk"
  printf '[]\n' > "$HOME/.gk/projects.jsonc"

  local wt_dir err_file
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  err_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c 'result="$(bash "$1" wt co 1 2> "$2")"; status=$?; printf "%s" "$result"; exit "$status"' _ "$GK" "$err_file"
  assert_failure
  [[ "$(cat "$err_file")" == *"Invalid project store"* ]]
}

@test "gk wt co with no other worktrees shows message" {
  run bash "$GK" wt co
  assert_success
  assert_output --partial "No other worktrees"
}

@test "gk wt co with invalid index fails" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  run bash "$GK" wt co <<< "99"
  assert_failure
  assert_output --partial "Invalid selection"
}

@test "gk wt co with current worktree selected shows message" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  # Select index 0 (main/current worktree)
  run bash "$GK" wt co <<< "0"
  assert_success
  assert_output --partial "Already in that worktree"
}

@test "gk wt co directly selecting the current worktree writes no stdout" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local stdout err_file
  stdout="$BATS_TEST_TMPDIR/stdout"
  err_file="$BATS_TEST_TMPDIR/stderr"
  run bash -c 'bash "$1" wt co 0 > "$2" 2> "$3"' _ "$GK" "$stdout" "$err_file"
  assert_success
  assert_equal "$(cat "$stdout")" ""
  [[ "$(cat "$err_file")" == *"Already in that worktree."* ]]
}

@test "gk wt co directly selects current worktree when it is the only worktree" {
  local stdout err_file
  stdout="$BATS_TEST_TMPDIR/stdout"
  err_file="$BATS_TEST_TMPDIR/stderr"
  run bash -c 'bash "$1" wt co 0 > "$2" 2> "$3"' _ "$GK" "$stdout" "$err_file"
  assert_success
  assert_equal "$(cat "$stdout")" ""
  [[ "$(cat "$err_file")" == *"Already in that worktree."* ]]
}

@test "gk wt co direct mode does not trigger onboarding" {
  rm "$REPO_DIR/.gitkiss"

  run_in_pty bash "$GK" wt co 0
  assert_success
  [[ "$output" != *"Set up git-kiss for this project?"* ]]
  [ ! -f "$REPO_DIR/.gitkiss.jsonc" ]
  [ ! -f "$REPO_DIR/.gitkiss.local.jsonc" ]
  [ ! -e "$HOME/.gk/projects.jsonc" ]
}

@test "gk wt co rejects invalid direct indices without selector output" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local choice stdout err_file
  for choice in 01 08 -1 1.0 999999999999999999999999999999999999999999; do
    stdout="$BATS_TEST_TMPDIR/stdout-$choice"
    err_file="$BATS_TEST_TMPDIR/stderr-$choice"
    run bash -c 'bash "$1" wt co "$2" > "$3" 2> "$4"' _ "$GK" "$choice" "$stdout" "$err_file"
    assert_failure
    assert_equal "$(cat "$stdout")" ""
    [[ "$(cat "$err_file")" == *"Invalid selection: $choice"* ]]
  done
}

@test "gk wt co rejects surplus direct arguments" {
  local stdout err_file
  stdout="$BATS_TEST_TMPDIR/stdout"
  err_file="$BATS_TEST_TMPDIR/stderr"
  run bash -c 'bash "$1" wt co 0 1 > "$2" 2> "$3"' _ "$GK" "$stdout" "$err_file"
  assert_failure
  assert_equal "$(cat "$stdout")" ""
  [[ "$(cat "$err_file")" == *"Usage: gk wt co [index]"* ]]
}

@test "gk wt co aborts safely on EOF" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local stdout err_file
  stdout="$BATS_TEST_TMPDIR/stdout"
  err_file="$BATS_TEST_TMPDIR/stderr"
  run bash -c 'bash "$1" wt co </dev/null > "$2" 2> "$3"' _ "$GK" "$stdout" "$err_file"
  assert_success
  assert_equal "$(cat "$stdout")" ""
  assert_output ""
  [[ "$(cat "$err_file")" == *"Aborted."* ]]
}

# ─── wt nf/nb upstream tracking ───────────────────────────────────────────

@test "gk wt nf does not track upstream" {
  bash "$GK" wt nf login >/dev/null 2>&1

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--login"

  # Branch should not have an upstream set
  run git -C "$wt_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>&1
  assert_failure
}

@test "gk wt nb does not track upstream" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"

  run git -C "$wt_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>&1
  assert_failure
}

# ─── WORKTREE_COPY ─────────────────────────────────────────────────────────

@test "gk wt nf copies files from WORKTREE_COPY config" {
  # Create gitignored files in the main repo
  echo "secret=123" > "$REPO_DIR/.env"
  mkdir -p "$REPO_DIR/config/local"
  echo "local_setting=true" > "$REPO_DIR/config/local/dev.conf"

  # Configure WORKTREE_COPY
  write_legacy_config "$REPO_DIR/.gitkiss" WORKTREE_COPY=".env config/local"
  git add .gitkiss && git commit -m "add config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" wt nf copier
  assert_success
  assert_output --partial "Copied 2 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--copier"

  # Files should exist in the worktree
  [ -f "$wt_dir/.env" ]
  [ -f "$wt_dir/config/local/dev.conf" ]

  # Content should match
  [ "$(cat "$wt_dir/.env")" = "secret=123" ]
  [ "$(cat "$wt_dir/config/local/dev.conf")" = "local_setting=true" ]
}

@test "gk wt nf skips missing WORKTREE_COPY entries" {
  write_legacy_config "$REPO_DIR/.gitkiss" WORKTREE_COPY=".env .nonexistent"
  echo "val=1" > "$REPO_DIR/.env"
  git add .gitkiss && git commit -m "add config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" wt nf skipper
  assert_success
  assert_output --partial "Copied 1 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--skipper"
  [ -f "$wt_dir/.env" ]
  [ ! -e "$wt_dir/.nonexistent" ]
}

@test "gk wt nf with empty WORKTREE_COPY does nothing" {
  run bash "$GK" wt nf empty
  assert_success
  refute_output --partial "Copied"
}

@test "gk wt nf expands globs in worktree_copy (jsonc)" {
  rm -f "$REPO_DIR/.gitkiss"
  echo "a" > "$REPO_DIR/.env.local"
  echo "b" > "$REPO_DIR/.env.prod"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "",
  "feature_prefix": "feature/", "use_tags": false }
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "worktree_copy": [".env.*"] }
EOF
  git add -A && git commit -m "glob config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" wt nf globber
  assert_success
  assert_output --partial "Copied 2 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--globber"
  [ -f "$wt_dir/.env.local" ]
  [ -f "$wt_dir/.env.prod" ]
}

@test "gk wt nf glob with no matches copies nothing" {
  rm -f "$REPO_DIR/.gitkiss"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "",
  "feature_prefix": "feature/", "use_tags": false }
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "worktree_copy": ["nope.*"] }
EOF
  git add -A && git commit -m "glob config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" wt nf nomatch
  assert_success
  refute_output --partial "Copied"
}

# ─── .worktreeinclude ──────────────────────────────────────────────────────

@test "gk wt nf copies files listed in .worktreeinclude" {
  echo "secret=123" > "$REPO_DIR/.env"
  mkdir -p "$REPO_DIR/config/local"
  echo "local_setting=true" > "$REPO_DIR/config/local/dev.conf"

  cat > "$REPO_DIR/.worktreeinclude" <<'EOF'
# gitignored files to seed into new worktrees
.env

config/local
EOF

  run bash "$GK" wt nf includer
  assert_success
  assert_output --partial "Copied 2 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--includer"
  [ -f "$wt_dir/.env" ]
  [ -f "$wt_dir/config/local/dev.conf" ]
}

@test "gk wt nf ignores comments and blank lines in .worktreeinclude" {
  echo "v=1" > "$REPO_DIR/.env"
  printf '\n# only a comment\n\n   \n.env\n' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nf commented
  assert_success
  assert_output --partial "Copied 1 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--commented"
  [ -f "$wt_dir/.env" ]
}

@test "gk wt nf expands globs from .worktreeinclude" {
  echo "a" > "$REPO_DIR/.env.local"
  echo "b" > "$REPO_DIR/.env.prod"
  echo '.env.*' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nf globinc
  assert_success
  assert_output --partial "Copied 2 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--globinc"
  [ -f "$wt_dir/.env.local" ]
  [ -f "$wt_dir/.env.prod" ]
}

@test "gk wt nf uses .worktreeinclude instead of configured worktree_copy" {
  rm -f "$REPO_DIR/.gitkiss"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "",
  "feature_prefix": "feature/", "use_tags": false }
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "worktree_copy": [".env"] }
EOF
  git add -A && git commit -m "config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  echo "from-config" > "$REPO_DIR/.env"
  echo "from-include" > "$REPO_DIR/local.conf"
  echo 'local.conf' > "$REPO_DIR/.worktreeinclude"

  DEBUG=1 run bash "$GK" wt nf include-wins
  assert_success
  assert_output --partial "Copied 1 item(s)"
  assert_output --partial ".worktreeinclude present; configured worktree_copy suppressed"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--include-wins"
  [ ! -f "$wt_dir/.env" ]
  [ -f "$wt_dir/local.conf" ]
}

@test "an empty or comment-only .worktreeinclude suppresses configured worktree_copy" {
  rm -f "$REPO_DIR/.gitkiss"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "",
  "feature_prefix": "feature/", "use_tags": false }
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "worktree_copy": [".env"] }
EOF
  git add -A && git commit -m "config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  echo "v=1" > "$REPO_DIR/.env"
  printf '\n# intentionally empty\n\n' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nf empty-include
  assert_success
  refute_output --partial "Copied"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--empty-include"
  [ ! -f "$wt_dir/.env" ]
}

@test "linked-worktree commands use the canonical main-worktree include file" {
  echo "main-include" > "$REPO_DIR/main-include.env"
  echo 'main-include.env' > "$REPO_DIR/.worktreeinclude"
  git worktree add "$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--source" -b source main >/dev/null 2>&1
  local source_wt target_wt
  source_wt="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--source"
  echo 'missing-in-linked-worktree.env' > "$source_wt/.worktreeinclude"

  run bash -c 'cd "$1" && bash "$2" wt nb target' _ "$source_wt" "$GK"
  assert_success
  target_wt="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--target"
  [ -f "$target_wt/main-include.env" ]
}

@test "gk wt nf copies a literal path containing spaces" {
  echo "space-safe" > "$REPO_DIR/local settings.env"
  echo 'local settings.env' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nf spaced
  assert_success
  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--spaced"
  [ -f "$wt_dir/local settings.env" ]
  assert_equal "$(cat "$wt_dir/local settings.env")" "space-safe"
}

@test "gk wt nb treats metacharacters in the repository path literally" {
  local metachar_repo wt_dir
  metachar_repo="$BATS_TEST_TMPDIR/repo[1]"
  mv "$REPO_DIR" "$metachar_repo"
  export REPO_DIR="$metachar_repo"
  cd "$REPO_DIR"

  echo "literal-root" > "$REPO_DIR/.env"
  echo '.env' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nb metachar-root
  assert_success
  assert_output --partial "Copied 1 item(s)"

  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--metachar-root"
  [ -f "$wt_dir/.env" ]
  assert_equal "$(cat "$wt_dir/.env")" "literal-root"
}

@test "gk wt nf rejects absolute and traversal copy patterns" {
  local pattern name
  local -a patterns=('/tmp/not-allowed' '../not-allowed' 'nested/../not-allowed')
  local -a names=(unsafe-absolute unsafe-parent unsafe-nested)
  local index
  for index in "${!patterns[@]}"; do
    pattern="${patterns[$index]}"
    name="${names[$index]}"
    printf '%s\n' "$pattern" > "$REPO_DIR/.worktreeinclude"
    run bash "$GK" wt nf "$name"
    assert_failure
    assert_output --partial "Unsafe worktree copy pattern"
    refute_output --partial "Fetching latest"
    ! git show-ref --verify --quiet "refs/heads/feature/$name"
    [ ! -d "$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--$name" ]
  done
}

@test "gk wt nf refuses symlink copy sources" {
  ln -s "$BATS_TEST_TMPDIR" "$REPO_DIR/outside-link"
  echo 'outside-link' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nf symlinked
  assert_failure
  assert_output --partial "refuses symlinks"
  ! git show-ref --verify --quiet refs/heads/feature/symlinked
  [ ! -d "$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--symlinked" ]
}

@test "gk wt nf refuses nested symlinks before creating a worktree" {
  mkdir -p "$REPO_DIR/config/local"
  ln -s "$BATS_TEST_TMPDIR" "$REPO_DIR/config/local/outside-link"
  echo 'config' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nf nested-symlinked
  assert_failure
  assert_output --partial "refuses symlinks"
  ! git show-ref --verify --quiet refs/heads/feature/nested-symlinked
  [ ! -d "$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--nested-symlinked" ]
}

@test "gk wt clean reports a locked worktree removal failure" {
  bash "$GK" wt nb locked-clean >/dev/null 2>&1
  local wt_dir branch
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--locked-clean"
  branch="locked-clean"
  git worktree lock --reason "test lock" "$wt_dir"

  run bash "$GK" 'wt' 'clean!'
  assert_failure
  assert_output --partial "Could not remove $branch"
  refute_output --partial "Removed $branch"
  [ -d "$wt_dir" ]
  git show-ref --verify --quiet "refs/heads/$branch"
  git worktree unlock "$wt_dir"
}

@test "gk wt nb copies files listed in .worktreeinclude" {
  echo "v=1" > "$REPO_DIR/.env"
  echo '.env' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nb hotfix-db
  assert_success
  assert_output --partial "Copied 1 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  [ -f "$wt_dir/.env" ]
}
