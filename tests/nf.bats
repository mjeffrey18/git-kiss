#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk nf creates a feature branch" {
  run bash "$GK" nf test-feature
  assert_success
  assert_output --partial "feature/test-feature"

  run git branch --show-current
  assert_output "feature/test-feature"
}

@test "gk nf lowercases branch name" {
  run bash "$GK" nf My-Feature
  assert_success

  run git branch --show-current
  assert_output "feature/my-feature"
}

@test "gk nf replaces spaces with hyphens" {
  run bash "$GK" nf "my cool feature"
  assert_success

  run git branch --show-current
  assert_output "feature/my-cool-feature"
}

@test "gk nf with initials prepends them" {
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=
STAGING_BRANCH=
FEATURE_PREFIX=feature/
USE_TAGS=false
INITIALS=mj
EOF
  git add .gitkiss && git commit -m "update config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf login
  assert_success

  run git branch --show-current
  assert_output "feature/mj-login"
}

@test "gk nf without name fails" {
  run bash "$GK" nf
  assert_failure
  assert_output --partial "Usage"
}

@test "gk nf branches from develop in full flow" {
  # Set up develop branch
  git checkout -b develop >/dev/null 2>&1
  echo "develop work" > develop.txt
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=develop
STAGING_BRANCH=staging
FEATURE_PREFIX=feature/
USE_TAGS=true
INITIALS=
EOF
  git add -A && git commit -m "develop work" >/dev/null 2>&1
  git push -u origin develop >/dev/null 2>&1

  run bash "$GK" nf login
  assert_success

  # Should have develop.txt since it branched from develop
  [ -f "$REPO_DIR/develop.txt" ]
}
