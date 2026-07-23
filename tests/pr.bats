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


@test "gk pr ls requires the gh CLI" {
  create_feature_branch "login"

  # Build an isolated PATH with the tools gk needs but deliberately no 'gh'
  local nogh_bin c real
  nogh_bin="$BATS_TEST_TMPDIR/nogh-bin"
  mkdir -p "$nogh_bin"
  for c in bash git cat dirname sed grep tr awk date jq env head printf; do
    real="$(command -v "$c" 2>/dev/null || true)"
    [[ -n "$real" ]] && ln -sf "$real" "$nogh_bin/$c"
  done

  run env PATH="$nogh_bin" bash "$GK" pr ls
  assert_failure
  assert_output --partial "is not installed"
}

@test "gk pr ls shows branches with no PRs" {
  create_feature_branch "login"
  git checkout main >/dev/null 2>&1

  # Override the gh stub to return empty PR list for 'pr list'
  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  echo '[]'
  exit 0
fi
printf '%s\n' "\$@" > "$GH_ARGS_FILE"
exit 0
STUB
  chmod +x "$GH_STUB_DIR/gh"

  run bash "$GK" pr ls
  assert_success
  assert_output --partial "feature/login"
  assert_output --partial "No pull requests found"
}

@test "gk pr ls shows matching PR links" {
  create_feature_branch "login"
  git checkout main >/dev/null 2>&1

  # Override the gh stub to return a PR matching feature/login
  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  echo '[{"number":42,"headRefName":"feature/login","isDraft":false,"url":"https://github.com/test/repo/pull/42","title":"Add login feature","createdAt":"2026-08-13T00:00:00Z"}]'
  exit 0
fi
printf '%s\n' "\$@" > "$GH_ARGS_FILE"
exit 0
STUB
  chmod +x "$GH_STUB_DIR/gh"

  run bash "$GK" pr ls
  assert_success
  assert_output --partial "feature/login"
  assert_output --partial "#42"
  assert_output --partial "https://github.com/test/repo/pull/42"
}

@test "gk pr ls shows the worktree that owns a branch" {
  create_feature_branch "login"
  git checkout main >/dev/null 2>&1
  local wt_dir="$BATS_TEST_TMPDIR/repo--login"
  git worktree add "$wt_dir" feature/login >/dev/null 2>&1

  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  echo '[{"number":42,"headRefName":"feature/login","isDraft":false,"url":"https://github.com/test/repo/pull/42","title":"Add login feature","createdAt":"2026-08-13T00:00:00Z"}]'
  exit 0
fi
exit 1
STUB
  chmod +x "$GH_STUB_DIR/gh"

  run bash -c 'cd "$1" && bash "$2" pr ls' _ "$wt_dir" "$GK"
  assert_success
  assert_output --partial "repo--login"
  assert_output --partial "●"
}

@test "gk pr ls fetches enough PRs and displays status icons" {
  create_feature_branch "login"
  git checkout main >/dev/null 2>&1

  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  printf '%s\\n' "\$@" > "$GH_ARGS_FILE"
  echo '[{"number":42,"headRefName":"feature/login","isDraft":false,"url":"https://github.com/test/repo/pull/42","title":"Add login feature","createdAt":"2026-08-13T00:00:00Z"}]'
  exit 0
fi
exit 1
STUB
  chmod +x "$GH_STUB_DIR/gh"

  run bash "$GK" pr ls
  assert_success
  assert_output --partial "Worktree"
  assert_output --partial "● open"

  run cat "$GH_ARGS_FILE"
  assert_line --partial "--limit"
  assert_line --partial "1000"
}

@test "gk pr ls shows multiple branches with mixed PR state" {
  create_feature_branch "login"
  git checkout main >/dev/null 2>&1
  git checkout -b "feature/signup" >/dev/null 2>&1
  echo "signup" > signup.txt
  git add -A >/dev/null 2>&1
  git commit -m "add signup" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1

  # Override the gh stub to return a PR for login but not signup
  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  echo '[{"number":42,"headRefName":"feature/login","isDraft":false,"url":"https://github.com/test/repo/pull/42","title":"Add login feature","createdAt":"2026-08-13T00:00:00Z"}]'
  exit 0
fi
printf '%s\n' "\$@" > "$GH_ARGS_FILE"
exit 0
STUB
  chmod +x "$GH_STUB_DIR/gh"

  run bash "$GK" pr ls
  assert_success
  assert_output --partial "feature/login"
  assert_output --partial "#42"
  assert_output --partial "feature/signup"
  assert_output --partial "feature/signup"
}

@test "gk pr ls classifies draft and failing pull requests" {
  create_feature_branch "draft"
  git checkout main >/dev/null 2>&1
  git checkout -b "feature/failing" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1

  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  echo '[
    {"number":1,"headRefName":"feature/draft","isDraft":true,"url":"https://github.com/test/repo/pull/1","title":"Draft PR","createdAt":"2026-08-13T00:00:00Z"},
    {"number":2,"headRefName":"feature/failing","isDraft":false,"url":"https://github.com/test/repo/pull/2","title":"Failing PR","createdAt":"2026-08-13T00:00:00Z"}
  ]'
  exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "checks" && "\$3" == "2" ]]; then
  echo '[{"bucket":"fail"}]'
  exit 0
fi
exit 1
STUB
  chmod +x "$GH_STUB_DIR/gh"

  run bash "$GK" pr ls
  assert_success
  assert_output --partial "feature/draft"
  assert_output --partial "feature/failing"
  assert_output --partial "✕ failing"
}

@test "gk pr list is alias for ls" {
  create_feature_branch "login"
  git checkout main >/dev/null 2>&1

  # Override the gh stub to return empty PR list
  cat > "$GH_STUB_DIR/gh" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
  echo '[]'
  exit 0
fi
printf '%s\n' "\$@" > "$GH_ARGS_FILE"
exit 0
STUB
  chmod +x "$GH_STUB_DIR/gh"

  run bash "$GK" pr list
  assert_success
  assert_output --partial "feature/login"
}
