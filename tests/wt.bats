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
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=
STAGING_BRANCH=
FEATURE_PREFIX=feature/
USE_TAGS=false
INITIALS=mj
EOF
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

  local wt_dir
  wt_dir="$(dirname "$REPO_DIR")/$(basename "$REPO_DIR")--hotfix-db"

  # Select index 1 (the new worktree) — capture stdout only
  local result
  result="$(bash "$GK" wt co <<< "1" 2>/dev/null)"
  # Resolve symlinks for macOS /var -> /private/var
  [ "$(cd "$result" && pwd -P)" = "$(cd "$wt_dir" && pwd -P)" ]
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
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=
STAGING_BRANCH=
FEATURE_PREFIX=feature/
USE_TAGS=false
INITIALS=
WORKTREE_COPY=".env config/local"
EOF
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
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=
STAGING_BRANCH=
FEATURE_PREFIX=feature/
USE_TAGS=false
INITIALS=
WORKTREE_COPY=".env .nonexistent"
EOF
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
