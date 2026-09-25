#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk pf pushes a non-prefixed branch to origin" {
  git checkout -b hotfix/login >/dev/null 2>&1

  run bash "$GK" pf
  assert_success
  assert_output --partial "published to origin"

  # Remote should have the branch
  run git ls-remote --heads origin hotfix/login
  assert_output --partial "hotfix/login"
}

@test "gk pf rejects the configured main branch" {
  run bash "$GK" pf
  assert_failure
  assert_output --partial "configured workflow branch: main"
}
