#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
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

@test "gk wt ls marks current worktree" {
  run bash "$GK" wt ls
  assert_success
  # Current marker character (●) should be present
  assert_output --partial "●"
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
  [ ! -d "$wt_dir" ]
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

# ─── wt co ─────────────────────────────────────────────────────────────────

@test "gk wt co outputs selected worktree path" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  # A normal command may migrate global JSONC first, but that diagnostic must
  # remain on stderr so shell integration receives only the selected path.
  printf '{ "feature_prefix": "global/" }\n' > "$HOME/.git-kiss.jsonc"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"

  # Select index 1 (the new worktree) — capture stdout only
  local result
  result="$(GK_NO_VERSION_CHECK=1 bash "$GK" wt co <<< "1")"
  # Resolve symlinks for macOS /var -> /private/var
  [ "$(cd "$result" && pwd -P)" = "$(cd "$wt_dir" && pwd -P)" ]
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
}

@test "gk wt co command substitution keeps a malformed project-store warning on stderr" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  mkdir -p "$HOME/.gk"
  printf '{ invalid\n' > "$HOME/.gk/projects.jsonc"

  local wt_dir err_file
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  err_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c 'result="$(bash "$1" wt co 1 2> "$2")"; status=$?; printf "%s" "$result"; exit "$status"' _ "$GK" "$err_file"
  assert_success
  assert_equal "$output" "$(cd "$wt_dir" && pwd -P)"
  [[ "$(cat "$err_file")" == *"Ignoring malformed project store: $HOME/.gk/projects.jsonc"* ]]
}

@test "gk wt co command substitution keeps a non-object project-store warning on stderr" {
  bash "$GK" wt nb hotfix-db >/dev/null 2>&1

  mkdir -p "$HOME/.gk"
  printf '[]\n' > "$HOME/.gk/projects.jsonc"

  local wt_dir err_file
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"
  err_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c 'result="$(bash "$1" wt co 1 2> "$2")"; status=$?; printf "%s" "$result"; exit "$status"' _ "$GK" "$err_file"
  assert_success
  assert_equal "$output" "$(cd "$wt_dir" && pwd -P)"
  [[ "$(cat "$err_file")" == *"Ignoring malformed project store: $HOME/.gk/projects.jsonc"* ]]
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

@test "gk wt nf merges worktree_copy config with .worktreeinclude" {
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

  run bash "$GK" wt nf merged
  assert_success
  assert_output --partial "Copied 2 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--merged"
  [ -f "$wt_dir/.env" ]
  [ -f "$wt_dir/local.conf" ]
}

@test "gk wt nf copies a file in both worktree_copy and .worktreeinclude only once" {
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
  echo '.env' > "$REPO_DIR/.worktreeinclude"

  run bash "$GK" wt nf deduped
  assert_success
  assert_output --partial "Copied 1 item(s)"

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--deduped"
  [ -f "$wt_dir/.env" ]
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
