#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk sf! squashes multiple commits into one" {
  create_feature_branch "login"

  # Add more commits
  echo "second" > second.txt
  git add -A && git commit -m "second commit" >/dev/null 2>&1
  echo "third" > third.txt
  git add -A && git commit -m "third commit" >/dev/null 2>&1

  # Should have 3 commits on feature branch
  local count
  count="$(git rev-list --count main..HEAD)"
  [ "$count" -eq 3 ]

  run bash "$GK" 'sf!'
  assert_success
  assert_output --partial "3 commits squashed into one"

  # Should now have 1 commit
  count="$(git rev-list --count main..HEAD)"
  [ "$count" -eq 1 ]
}

@test "gk sf! with single commit does nothing" {
  create_feature_branch "login"

  run bash "$GK" 'sf!'
  assert_success
  assert_output --partial "nothing to squash"
}

@test "gk sf! fails on dirty tree" {
  create_feature_branch "login"
  echo "dirty" > dirty.txt

  run bash "$GK" 'sf!'
  assert_failure
  assert_output --partial "Working tree is dirty"
}

@test "gk sf! fails when not on feature branch" {
  run bash "$GK" 'sf!'
  assert_failure
  assert_output --partial "Not on a feature branch"
}

@test "gk sf! preserves commit messages in squashed commit" {
  create_feature_branch "login"
  echo "second" > second.txt
  git add -A && git commit -m "add login form" >/dev/null 2>&1

  run bash "$GK" 'sf!'
  assert_success

  run git log --format=%B -1
  assert_output --partial "add login"
  assert_output --partial "add login form"
}
