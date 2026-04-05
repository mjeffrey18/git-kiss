#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk pf pushes feature branch to origin" {
  create_feature_branch "login"

  run bash "$GK" pf
  assert_success
  assert_output --partial "published to origin"

  # Remote should have the branch
  run git ls-remote --heads origin feature/login
  assert_output --partial "feature/login"
}

@test "gk pf fails when not on feature branch" {
  run bash "$GK" pf
  assert_failure
  assert_output --partial "Not on a feature branch"
}
