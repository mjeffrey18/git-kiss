#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
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
