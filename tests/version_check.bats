#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo

  # Create a fake install directory for version check tests
  export FAKE_INSTALL_DIR="$(mktemp -d)"
  export FAKE_GK="$FAKE_INSTALL_DIR/gk"
  cp "$GK" "$FAKE_GK"
  cp "${BATS_TEST_DIRNAME}/../bin/.git-kiss-version" "$FAKE_INSTALL_DIR/.git-kiss-version"
  chmod +x "$FAKE_GK"
  export PATH="$FAKE_INSTALL_DIR:$PATH"

  # Override HOME so stamp file lands in a temp dir
  export REAL_HOME="$HOME"
  export HOME="$(mktemp -d)"
}

teardown() {
  teardown_test_repo
  if [[ -n "${FAKE_INSTALL_DIR:-}" && -d "$FAKE_INSTALL_DIR" ]]; then
    rm -rf "$FAKE_INSTALL_DIR"
  fi
  if [[ -n "${HOME:-}" && "$HOME" != "$REAL_HOME" && -d "$HOME" ]]; then
    rm -rf "$HOME"
  fi
  export HOME="$REAL_HOME"
}

@test "gk reads version from .git-kiss-version file" {
  run bash "$FAKE_GK" version
  assert_success
  # Should match whatever version is in the file
  local expected
  expected="$(cat "${BATS_TEST_DIRNAME}/../bin/.git-kiss-version" | tr -d '[:space:]')"
  assert_output --partial "$expected"
}

@test "gk version reflects updated version file" {
  echo "9.9.9" > "$FAKE_INSTALL_DIR/.git-kiss-version"
  run bash "$FAKE_GK" version
  assert_success
  assert_output --partial "9.9.9"
}

@test "version check creates stamp file" {
  # Run any command — version check runs after
  bash "$FAKE_GK" version >/dev/null 2>&1 || true

  # Stamp file should exist in HOME
  [ -f "$HOME/.gk_version_check" ]
}

@test "version check stamp contains a unix timestamp" {
  bash "$FAKE_GK" version >/dev/null 2>&1 || true

  local stamp
  stamp="$(cat "$HOME/.gk_version_check")"
  # Should be a number
  [[ "$stamp" =~ ^[0-9]+$ ]]
}

@test "version check does not re-check within 24 hours" {
  # Write a recent timestamp
  date +%s > "$HOME/.gk_version_check"

  run bash "$FAKE_GK" version
  assert_success
  # No update message should appear (we skipped the network check)
  refute_output --partial "Update available"
}

@test "version check triggers after 24 hours" {
  # Write an old timestamp (2 days ago)
  local old_stamp
  old_stamp=$(( $(date +%s) - 172800 ))
  echo "$old_stamp" > "$HOME/.gk_version_check"

  # Run gk — this will try to hit the network
  # We just verify it doesn't crash and updates the stamp
  run bash "$FAKE_GK" version
  assert_success

  local new_stamp
  new_stamp="$(cat "$HOME/.gk_version_check")"
  # Stamp should be updated to something newer than old_stamp
  [ "$new_stamp" -gt "$old_stamp" ]
}
