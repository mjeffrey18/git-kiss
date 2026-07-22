#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk shell-init emits a gk wrapper function" {
  run bash "$GK" shell-init
  assert_success
  assert_output --partial "gk() {"
  assert_output --partial 'cd "$_gk_dir"'
  assert_output --partial '${1:-}'
  assert_output --partial '|| return $?'
}

@test "gk shell-init works outside a git repo" {
  cd /tmp
  run bash "$GK" shell-init
  assert_success
  assert_output --partial "gk() {"
}

@test "gk shell-init output is valid shell" {
  bash "$GK" shell-init > "$BATS_TEST_TMPDIR/init.sh"
  run bash -n "$BATS_TEST_TMPDIR/init.sh"
  assert_success
}

@test "shell-init passes a direct index to gk wt co and changes directory" {
  local bin_dir target original
  bin_dir="$BATS_TEST_TMPDIR/bin"
  target="$BATS_TEST_TMPDIR/target worktree"
  original="$PWD"
  mkdir -p "$bin_dir" "$target"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$GK_TEST_TARGET"\n' > "$bin_dir/gk"
  chmod +x "$bin_dir/gk"

  run env PATH="$bin_dir:$PATH" GK_TEST_TARGET="$target" bash -c 'eval "$(bash "$1" shell-init)"; gk wt co 1; pwd' _ "$GK"
  assert_success
  assert_equal "$output" "$target"
  [ "$PWD" = "$original" ]
}

@test "shell-init preserves gk wt co failure and does not change directory" {
  local bin_dir original
  bin_dir="$BATS_TEST_TMPDIR/bin"
  original="$PWD"
  mkdir -p "$bin_dir"
  printf '#!/usr/bin/env bash\nprintf "failed\\n" >&2\nexit 7\n' > "$bin_dir/gk"
  chmod +x "$bin_dir/gk"

  run env PATH="$bin_dir:$PATH" bash -c 'eval "$(bash "$1" shell-init)"; gk wt co 1; status=$?; [ "$PWD" = "$2" ]; exit "$status"' _ "$GK" "$original"
  [ "$status" -eq 7 ]
  assert_output "failed"
}
