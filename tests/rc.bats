#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk rc resets the last commit and keeps changes unstaged" {
  git checkout -b feature/reset >/dev/null 2>&1
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
  git checkout -b feature/empty-reset >/dev/null 2>&1
  git commit --allow-empty -m "empty commit" >/dev/null 2>&1
  run bash "$GK" rc
  assert_success
  assert_output --partial "Commit was empty"
}

@test "gk rc refuses a dirty tree and rc! is explicit force" {
  git checkout -b feature/dirty-reset >/dev/null 2>&1
  git commit --allow-empty -m "reset me" >/dev/null 2>&1
  echo dirty > dirty.txt
  run bash "$GK" rc
  assert_failure
  assert_output --partial "Working tree is dirty"

  run bash "$GK" rc!
  assert_success
  assert_output --partial "Last commit reset"
}

@test "gk rc refuses configured base branches and published commits" {
  git commit --allow-empty -m "base reset" >/dev/null 2>&1
  run bash "$GK" rc
  assert_failure
  assert_output --partial "configured base branch"

  git checkout -b feature/published >/dev/null 2>&1
  git commit --allow-empty -m "published reset" >/dev/null 2>&1
  git push origin feature/published >/dev/null 2>&1
  run bash "$GK" rc
  assert_failure
  assert_output --partial "already published"
}

@test "gk rc rejects root commits" {
  git checkout --orphan root-reset >/dev/null 2>&1
  git rm -rf . >/dev/null 2>&1
  printf 'MAIN_BRANCH=root-reset\nUSE_TAGS=false\n' > .gitkiss
  git add .gitkiss && git commit -m "root" >/dev/null 2>&1

  run bash "$GK" rc
  assert_failure
  assert_output --partial "No commits to reset"
}

@test "gk rc rejects merge commits" {
  git checkout -b feature/merge-reset >/dev/null 2>&1
  git commit --allow-empty -m "merge base" >/dev/null 2>&1
  git checkout -b feature/merge-side HEAD~1 >/dev/null 2>&1
  git commit --allow-empty -m "side" >/dev/null 2>&1
  git checkout feature/merge-reset >/dev/null 2>&1
  git merge --no-ff feature/merge-side -m "merge side" >/dev/null 2>&1
  run bash "$GK" rc
  assert_failure
  assert_output --partial "merge commit"
}
