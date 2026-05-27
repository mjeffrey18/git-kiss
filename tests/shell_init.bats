#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk shell-init emits a gk wrapper function" {
  run bash "$GK" shell-init
  assert_success
  assert_output --partial "gk() {"
  assert_output --partial 'cd "$_gk_dir"'
  assert_output --partial '${1:-}'
  assert_output --partial '|| return 0'
}

@test "gk shell-init works outside a git repo" {
  cd /tmp
  run bash "$GK" shell-init
  assert_success
  assert_output --partial "gk() {"
}

@test "gk shell-init output is valid shell" {
  bash "$GK" shell-init > "$BATS_TEST_TMPDIR/init.sh"
  run bash -n "$BATS_TEST_TMPDIR/init.sh"
  assert_success
}
