#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk cm commits all changes" {
  echo "hello" > newfile.txt
  run bash "$GK" cm "add newfile"
  assert_success
  assert_output --partial "Committed: add newfile"

  run git log --oneline -1
  assert_output --partial "add newfile"
}

@test "gk cm without message fails" {
  run bash "$GK" cm
  assert_failure
  assert_output --partial "Usage"
}

@test "gk cm with clean tree fails" {
  run bash "$GK" cm "nothing to do"
  assert_failure
  assert_output --partial "Nothing to commit"
}

@test "gk cm stages untracked files" {
  echo "new" > untracked.txt
  run bash "$GK" cm "add untracked"
  assert_success

  # File should be tracked now
  run git log --oneline --name-only -1
  assert_output --partial "untracked.txt"
}
