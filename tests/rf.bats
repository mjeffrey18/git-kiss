#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk rf rebases feature onto base" {
  create_feature_branch "login"

  # Add a commit to main
  git checkout main >/dev/null 2>&1
  echo "main update" > main-update.txt
  git add -A && git commit -m "main update" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  git checkout feature/login >/dev/null 2>&1

  run bash "$GK" rf
  assert_success
  assert_output --partial "up to date with main"

  # Feature branch should now have main's commit
  [ -f "$REPO_DIR/main-update.txt" ]
}

@test "gk rf fails on dirty tree" {
  create_feature_branch "login"
  echo "dirty" > dirty.txt

  run bash "$GK" rf
  assert_failure
  assert_output --partial "Working tree is dirty"
}

@test "gk rf fails when not on feature branch" {
  run bash "$GK" rf
  assert_failure
  assert_output --partial "Not on a feature branch"
}
