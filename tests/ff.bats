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

@test "gk ff fails on dirty tree" {
  create_feature_branch "login"
  echo "dirty" > dirty.txt

  run bash "$GK" ff
  assert_failure
  assert_output --partial "Working tree is dirty"
}

@test "gk ff fails when not on feature branch" {
  run bash "$GK" ff
  assert_failure
  assert_output --partial "Not on a feature branch"
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
