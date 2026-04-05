#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk uses repo .gitkiss config" {
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=
STAGING_BRANCH=
FEATURE_PREFIX=feat/
USE_TAGS=false
INITIALS=ab
EOF
  git add .gitkiss && git commit -m "custom config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf login
  assert_success

  run git branch --show-current
  assert_output "feat/ab-login"
}

@test "gk works without config file (uses defaults)" {
  rm -f "$REPO_DIR/.gitkiss"

  # With defaults, base branch is develop which doesn't exist,
  # so nf will fail trying to checkout develop.
  # But help should still work.
  run bash "$GK" help
  assert_success
  assert_output --partial "git-kiss"
}

@test "gk outside git repo fails" {
  cd /tmp
  run bash "$GK" help
  assert_failure
  assert_output --partial "Not a git repository"
}
