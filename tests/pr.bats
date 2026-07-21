#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo

  # Stub gh: record argv (one arg per line) to a file, then exit 0.
  # Lives in BATS_TEST_TMPDIR so bats cleans it up - no manual removal needed.
  export GH_STUB_DIR="$BATS_TEST_TMPDIR/gh-stub"
  mkdir -p "$GH_STUB_DIR"
  export GH_ARGS_FILE="$GH_STUB_DIR/args"
  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$GH_ARGS_FILE"
exit 0
STUB
  chmod +x "$GH_STUB_DIR/gh"
  export PATH="$GH_STUB_DIR:$PATH"
}

teardown() {
  teardown_test_repo
}

@test "gk pr dies without a title" {
  create_feature_branch "login"

  run bash "$GK" pr
  assert_failure
  assert_output --partial "Usage"
}

@test "gk pr requires the gh CLI" {
  create_feature_branch "login"

  # Build an isolated PATH with the tools gk needs but deliberately no 'gh',
  # so 'command -v gh' fails even though gh may be installed on the runner.
  local nogh_bin c real
  nogh_bin="$BATS_TEST_TMPDIR/nogh-bin"
  mkdir -p "$nogh_bin"
  for c in bash git cat dirname sed grep tr awk date jq env head printf; do
    real="$(command -v "$c" 2>/dev/null || true)"
    [[ -n "$real" ]] && ln -sf "$real" "$nogh_bin/$c"
  done

  run env PATH="$nogh_bin" bash "$GK" pr "My title"
  assert_failure
  assert_output --partial "is not installed"
}

@test "gk pr fails when not on a feature branch" {
  # setup leaves us on main
  run bash "$GK" pr "My title"
  assert_failure
  assert_output --partial "Not on a feature branch"
}

@test "gk pr calls gh pr create with base, title and --fill" {
  create_feature_branch "login"

  run bash "$GK" pr "My PR title"
  assert_success

  run cat "$GH_ARGS_FILE"
  assert_line --index 0 "pr"
  assert_line --index 1 "create"
  assert_line --index 2 "--base"
  assert_line --index 3 "main"
  assert_line --index 4 "--title"
  assert_line --index 5 "My PR title"
  assert_line --index 6 "--fill"
}

@test "gk pr forwards extra flags through to gh" {
  create_feature_branch "login"

  run bash "$GK" pr "My PR title" --draft
  assert_success

  run cat "$GH_ARGS_FILE"
  assert_line --index 7 "--draft"
}
