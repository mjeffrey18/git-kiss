#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk rc resets the last commit and keeps changes unstaged" {
  echo "new content" > file.txt
  git add file.txt
  git commit -m "add file" >/dev/null 2>&1

  run bash "$GK" rc
  assert_success
  assert_output --partial "Last commit reset"

  # Commit should be gone
  run git log --oneline -1
  assert_output --partial "add gitkiss config"

  # File should be untracked in working tree after reset
  run git status --porcelain
  assert_output --partial "file.txt"
}

@test "gk rc on an empty commit warns" {
  git commit --allow-empty -m "empty commit" >/dev/null 2>&1
  run bash "$GK" rc
  assert_success
  assert_output --partial "Commit was empty"
}
