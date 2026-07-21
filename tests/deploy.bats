#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_full_flow_repo
}

teardown() {
  teardown_test_repo
}

# ─── ds (deploy staging) ────────────────────────────────────────────────────

@test "gk ds fails when not on feature branch" {
  run bash "$GK" ds
  assert_failure
  assert_output --partial "Not on a feature branch"
}

@test "gk ds! deploys the feature branch to staging" {
  git checkout develop >/dev/null 2>&1
  git checkout -b feature/staging-work >/dev/null 2>&1
  echo "staging feature" > staging-feature.txt
  git add -A && git commit -m "staging feature work" >/dev/null 2>&1

  run bash "$GK" 'ds!'
  assert_success
  assert_output --partial "Shipping to staging"

  # Local staging now contains the feature commit.
  run git log staging --oneline
  assert_output --partial "staging feature work"

  # origin/staging (the bare remote) was force-pushed with the same commit.
  run git --git-dir="$REMOTE_DIR" log staging --oneline
  assert_output --partial "staging feature work"
}

@test "gk ds! reports recovery guidance on a rebase conflict" {
  # Diverge the same line of the same file on develop and the feature branch.
  git checkout develop >/dev/null 2>&1
  echo "develop version" > conflict.txt
  git add -A && git commit -m "develop change" >/dev/null 2>&1
  git push origin develop >/dev/null 2>&1

  # Branch from before the develop change, then change the same file differently.
  git checkout -b feature/conflict develop~1 >/dev/null 2>&1
  echo "feature version" > conflict.txt
  git add -A && git commit -m "feature change" >/dev/null 2>&1

  run bash "$GK" 'ds!'
  assert_failure
  assert_output --partial "git rebase --abort"

  # Clean up the in-progress rebase so teardown can remove the repo cleanly.
  git rebase --abort >/dev/null 2>&1 || true
}

@test "gk ds fails without staging branch configured" {
  # Switch to simple flow (no staging)
  write_legacy_config "$REPO_DIR/.gitkiss" DEVELOP_BRANCH=develop USE_TAGS=true
  git add .gitkiss && git commit -m "remove staging" >/dev/null 2>&1

  git checkout -b feature/test >/dev/null 2>&1

  run bash "$GK" ds
  assert_failure
  assert_output --partial "STAGING_BRANCH is not configured"
}

# ─── dp (deploy production) ─────────────────────────────────────────────────

@test "gk dp fails when not on develop branch" {
  git checkout main >/dev/null 2>&1
  run bash "$GK" dp
  assert_failure
  assert_output --partial "You must be on develop"
}

@test "gk dp fails without develop branch configured" {
  write_legacy_config "$REPO_DIR/.gitkiss"
  git add .gitkiss && git commit -m "simple flow" >/dev/null 2>&1

  run bash "$GK" dp
  assert_failure
  assert_output --partial "DEVELOP_BRANCH is not configured"
}

@test "gk dp creates a version tag" {
  # Add a commit on develop
  echo "ready" > ready.txt
  git add -A && git commit -m "ready for release" >/dev/null 2>&1
  git push origin develop >/dev/null 2>&1

  run bash "$GK" 'dp!'
  assert_success
  assert_output --partial "v0.0.1"
  assert_output --partial "shipping to production"

  # Tag should exist
  run git tag -l "v0.0.1"
  assert_output "v0.0.1"
}

@test "gk dp increments existing tag" {
  echo "ready" > ready.txt
  git add -A && git commit -m "ready" >/dev/null 2>&1
  git push origin develop >/dev/null 2>&1

  bash "$GK" 'dp!' >/dev/null 2>&1

  # Back to develop for second release
  git checkout develop >/dev/null 2>&1
  echo "more" > more.txt
  git add -A && git commit -m "more work" >/dev/null 2>&1
  git push origin develop >/dev/null 2>&1

  run bash "$GK" 'dp!'
  assert_success
  assert_output --partial "v0.0.2"

  run git tag -l "v0.0.2"
  assert_output "v0.0.2"
}
