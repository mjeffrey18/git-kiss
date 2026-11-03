#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk ff parks the base worktree after confirmation" {
  create_feature_branch parking
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  local before
  before="$(git rev-parse main)"
  run bash "$GK" ff <<< y
  assert_success
  [ "$(git -C "$REPO_DIR--base" branch --show-current)" = park/base ]
  [ "$(git rev-parse park/base)" = "$before" ]
  git merge-base --is-ancestor feature/parking main
  [ "$(git rev-list --parents -n 1 main | wc -w | tr -d ' ')" = 3 ]
}

@test "gk ff! automatically parks the canonical worktree and pushes" {
  git worktree add -b feature/parking "$REPO_DIR--feature" main >/dev/null 2>&1
  echo feature > "$REPO_DIR--feature/feature.txt"
  git -C "$REPO_DIR--feature" add feature.txt
  git -C "$REPO_DIR--feature" commit -qm feature
  cd "$REPO_DIR--feature"
  run bash "$GK" 'ff!' </dev/null
  assert_success
  [ "$(git -C "$REPO_DIR" branch --show-current)" = park/repo ]
  [ "$(git rev-parse main)" = "$(git --git-dir="$REMOTE_DIR" rev-parse main)" ]
}

@test "gk ff declines parking on no and EOF" {
  create_feature_branch decline
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  run bash "$GK" ff <<< n
  assert_failure
  run bash "$GK" ff </dev/null
  assert_failure
  [ "$(git -C "$REPO_DIR--base" branch --show-current)" = main ]
  [ "$(git branch --show-current)" = feature/decline ]
}

@test "gk ff! refuses dirty worktrees and park branch collisions" {
  create_feature_branch guards
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  echo dirty > "$REPO_DIR--base/dirty.txt"
  run bash "$GK" 'ff!'
  assert_failure
  assert_output --partial "dirty worktree"
  [ "$(git -C "$REPO_DIR--base" branch --show-current)" = main ]
  git -C "$REPO_DIR--base" add dirty.txt
  git -C "$REPO_DIR--base" commit -qm dirty
  git branch park/base
  run bash "$GK" 'ff!'
  assert_failure
  assert_output --partial "already exists"
  [ "$(git -C "$REPO_DIR--base" branch --show-current)" = main ]
}

@test "gk ff! refuses a worktree with an unfinished operation" {
  create_feature_branch guards
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  mkdir "$(git -C "$REPO_DIR--base" rev-parse --git-path rebase-merge)"
  run bash "$GK" 'ff!'
  assert_failure
  assert_output --partial "Git operation in progress"
  [ "$(git -C "$REPO_DIR--base" branch --show-current)" = main ]
}

@test "gk ff leaves owner parked if destination pull fails" {
  create_feature_branch failure
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  git remote set-url origin "$BATS_TEST_TMPDIR/missing"
  run bash "$GK" 'ff!'
  assert_failure
  assert_output --partial "will remain parked"
  [ "$(git -C "$REPO_DIR--base" branch --show-current)" = park/base ]
}

@test "gk ff merges feature into base with merge commit" {
  create_feature_branch "login"

  run bash "$GK" ff
  assert_success
  assert_output --partial "merged into main"

  # Should now be on main
  run git branch --show-current
  assert_output "main"

  # Should have a merge commit
  run git log --oneline -1
  assert_output --partial "Merge branch 'feature/login' into main"
}

@test "gk ff! accepts a non-prefixed branch, pushes the base, and deletes the branch" {
  git checkout -b t3code/check-v2-error-translations >/dev/null 2>&1
  echo "translations" > translations.txt
  git add -A && git commit -m "check translations" >/dev/null 2>&1
  git push -u origin t3code/check-v2-error-translations >/dev/null 2>&1

  run bash "$GK" 'ff!'
  assert_success
  assert_output --partial "deleted"

  # Base was pushed: the bare remote's main has the merge commit.
  run git --git-dir="$REMOTE_DIR" log main --oneline
  assert_output --partial "Merge branch 't3code/check-v2-error-translations' into main"

  # Local feature branch was deleted.
  run git branch --list t3code/check-v2-error-translations
  refute_output --partial "t3code/check-v2-error-translations"

  # Remote feature branch was deleted.
  run git ls-remote --heads origin t3code/check-v2-error-translations
  refute_output --partial "t3code/check-v2-error-translations"
}

@test "gk ff fails on dirty tree" {
  create_feature_branch "login"
  echo "dirty" > dirty.txt

  run bash "$GK" ff
  assert_failure
  assert_output --partial "Working tree is dirty"
}

@test "gk ff rejects the configured main branch" {
  run bash "$GK" ff
  assert_failure
  assert_output --partial "configured workflow branch: main"
}

@test "gk ff rejects configured workflow branches even when they match the feature prefix" {
  write_legacy_config "$REPO_DIR/.gitkiss" MAIN_BRANCH=feature/main DEVELOP_BRANCH=feature/develop STAGING_BRANCH=feature/staging
  git add .gitkiss && git commit -m "configure prefixed workflow branches" >/dev/null 2>&1
  git branch feature/main
  git branch feature/develop
  git branch feature/staging

  local branch
  for branch in feature/main feature/develop feature/staging; do
    git checkout "$branch" >/dev/null 2>&1
    run bash "$GK" ff
    assert_failure
    assert_output --partial "configured workflow branch: $branch"
  done
}

@test "gk ff rejects detached HEAD" {
  git checkout --detach >/dev/null 2>&1

  run bash "$GK" ff
  assert_failure
  assert_output --partial "Detached HEAD"
}

@test "gk ff fails when behind base branch" {
  create_feature_branch "login"

  # Add a commit to main that feature doesn't have
  git checkout main >/dev/null 2>&1
  echo "new main work" > main-work.txt
  git add -A && git commit -m "main work" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  git checkout feature/login >/dev/null 2>&1

  run bash "$GK" ff
  assert_failure
  assert_output --partial "behind"
}
