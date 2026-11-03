#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

remote_base_advance() {
  git clone -q "$REMOTE_DIR" "$BATS_TEST_TMPDIR/writer" -b main
  git -C "$BATS_TEST_TMPDIR/writer" config user.name Test
  git -C "$BATS_TEST_TMPDIR/writer" config user.email test@test.com
  echo update > "$BATS_TEST_TMPDIR/writer/remote.txt"
  git -C "$BATS_TEST_TMPDIR/writer" add remote.txt
  git -C "$BATS_TEST_TMPDIR/writer" commit -qm remote-update
  git -C "$BATS_TEST_TMPDIR/writer" push -q origin main
}

@test "gk rf --remote fetches a newer base held by another worktree" {
  create_feature_branch remote
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  local base_before
  base_before="$(git rev-parse main)"
  remote_base_advance
  run bash "$GK" rf --remote
  assert_success
  [ "$(git branch --show-current)" = feature/remote ]
  [ "$(git rev-parse main)" = "$base_before" ]
  [ "$(git -C "$REPO_DIR--base" branch --show-current)" = main ]
  git merge-base --is-ancestor origin/main HEAD
  [ -f remote.txt ]
}

@test "gk rf offers remote fallback after checkout failure" {
  create_feature_branch fallback
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  remote_base_advance
  run bash "$GK" rf <<< y
  assert_success
  assert_output --partial "checkout failed"
  git merge-base --is-ancestor origin/main HEAD
  [ "$(git branch --show-current)" = feature/fallback ]
}

@test "gk rf declines remote fallback on no or EOF" {
  create_feature_branch decline
  git worktree add "$REPO_DIR--base" main >/dev/null 2>&1
  local before
  before="$(git rev-parse HEAD)"
  run bash "$GK" rf <<< n
  assert_failure
  [ "$(git rev-parse HEAD)" = "$before" ]
  run bash "$GK" rf </dev/null
  assert_failure
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "gk rf stops after a base pull conflict without remote fallback" {
  echo local > conflict.txt
  git add conflict.txt && git commit -qm local-base
  git checkout -b feature/pull-conflict >/dev/null 2>&1
  git clone -q "$REMOTE_DIR" "$BATS_TEST_TMPDIR/writer" -b main
  git -C "$BATS_TEST_TMPDIR/writer" config user.name Test
  git -C "$BATS_TEST_TMPDIR/writer" config user.email test@test.com
  echo remote > "$BATS_TEST_TMPDIR/writer/conflict.txt"
  git -C "$BATS_TEST_TMPDIR/writer" add conflict.txt
  git -C "$BATS_TEST_TMPDIR/writer" commit -qm remote-base
  git -C "$BATS_TEST_TMPDIR/writer" push -q origin main
  run bash "$GK" rf <<< y
  assert_failure
  assert_output --partial "git rebase --abort"
  refute_output --partial "Remote rebasing excludes"
  [ -d "$(git rev-parse --git-path rebase-merge)" ]
  git rebase --abort
}

@test "gk rf offers remote fallback after a pull failure with no operation" {
  create_feature_branch missing-remote
  git remote set-url origin "$BATS_TEST_TMPDIR/missing"
  run bash "$GK" rf <<< y
  assert_failure
  assert_output --partial "pull failed"
  [ "$(git branch --show-current)" = feature/missing-remote ]
}

@test "gk rf --remote excludes unpushed base commits and rejects unknown arguments" {
  create_feature_branch remote-only
  git checkout main >/dev/null 2>&1
  echo local > local.txt
  git add local.txt && git commit -qm unpushed
  git checkout feature/remote-only >/dev/null 2>&1
  run bash "$GK" rf --remote
  assert_success
  [ ! -f local.txt ]
  run bash "$GK" rf --unknown
  assert_failure
  assert_output --partial "Usage:"
}

@test "gk rf --remote stops on fetch failure without rebasing a stale ref" {
  create_feature_branch fetch-failure
  local before
  before="$(git rev-parse HEAD)"
  git remote set-url origin "$BATS_TEST_TMPDIR/missing"
  run bash "$GK" rf --remote
  assert_failure
  refute_output --partial "Rebasing"
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(git branch --show-current)" = feature/fetch-failure ]
}

@test "gk rf rebases a non-prefixed branch onto base" {
  git checkout -b t3code/login >/dev/null 2>&1
  echo "branch work" > branch-work.txt
  git add -A && git commit -m "branch work" >/dev/null 2>&1

  # Add a commit to main
  git checkout main >/dev/null 2>&1
  echo "main update" > main-update.txt
  git add -A && git commit -m "main update" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  git checkout t3code/login >/dev/null 2>&1

  run bash "$GK" rf
  assert_success
  assert_output --partial "up to date with main"

  # Working branch should now have main's commit
  [ -f "$REPO_DIR/main-update.txt" ]
}

@test "gk rf reports recovery guidance on a rebase conflict" {
  # Diverge the same line of the same file on main and the feature branch.
  git checkout main >/dev/null 2>&1
  echo "base version" > conflict.txt
  git add -A && git commit -m "base change" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  # Branch from before the base change, then change the same file differently.
  git checkout -b feature/conflict main~1 >/dev/null 2>&1
  echo "feature version" > conflict.txt
  git add -A && git commit -m "feature change" >/dev/null 2>&1

  run bash "$GK" rf
  assert_failure
  assert_output --partial "git rebase --abort"

  # Clean up the in-progress rebase so teardown can remove the repo cleanly.
  git rebase --abort >/dev/null 2>&1 || true
}

@test "gk rf fails on dirty tree" {
  create_feature_branch "login"
  echo "dirty" > dirty.txt

  run bash "$GK" rf
  assert_failure
  assert_output --partial "Working tree is dirty"
}

@test "gk rf rejects the configured main branch" {
  run bash "$GK" rf
  assert_failure
  assert_output --partial "configured workflow branch: main"
}
