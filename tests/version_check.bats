#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo

  # These tests exercise the real version-check code path, so opt back in
  # (setup_test_repo disables it via GK_NO_VERSION_CHECK=1 by default).
  unset GK_NO_VERSION_CHECK

  # Create a fake install directory for version check tests
  export FAKE_INSTALL_DIR="$BATS_TEST_TMPDIR/fake-install"
  mkdir -p "$FAKE_INSTALL_DIR"
  export FAKE_GK="$FAKE_INSTALL_DIR/gk"
  cp "$GK" "$FAKE_GK"
  cp "${BATS_TEST_DIRNAME}/../bin/.git-kiss-version" "$FAKE_INSTALL_DIR/.git-kiss-version"
  chmod +x "$FAKE_GK"

  # Stub curl so the check never touches the network. It prints
  # $GK_FAKE_REMOTE_VERSION (default a low version, so no update is reported).
  export CURL_STUB_DIR="$BATS_TEST_TMPDIR/curl-stub"
  mkdir -p "$CURL_STUB_DIR"
  cat > "$CURL_STUB_DIR/curl" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "${GK_FAKE_REMOTE_VERSION:-0.0.0}"
STUB
  chmod +x "$CURL_STUB_DIR/curl"

  # curl stub first, then the fake install dir, then the real PATH.
  export PATH="$CURL_STUB_DIR:$FAKE_INSTALL_DIR:$PATH"

  # HOME is already isolated to a temp dir by setup_test_repo, so the stamp
  # file lands there and never pollutes the real home.
}

teardown() {
  teardown_test_repo
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
  [ -f "$HOME/.gk/version_check" ]
}

@test "version check stamp contains a unix timestamp" {
  bash "$FAKE_GK" version >/dev/null 2>&1 || true

  local stamp
  stamp="$(cat "$HOME/.gk/version_check")"
  # Should be a number
  [[ "$stamp" =~ ^[0-9]+$ ]]
}

@test "version check does not re-check within 24 hours" {
  # Write a recent timestamp
  mkdir -p "$HOME/.gk"
  date +%s > "$HOME/.gk/version_check"

  run bash "$FAKE_GK" version
  assert_success
  # No update message should appear (we skipped the network check)
  refute_output --partial "Update available"
}

@test "version check triggers after 24 hours" {
  # Write an old timestamp (2 days ago)
  local old_stamp
  old_stamp=$(( $(date +%s) - 172800 ))
  mkdir -p "$HOME/.gk"
  echo "$old_stamp" > "$HOME/.gk/version_check"

  # Run gk — the network fetch is stubbed, so this exercises the check path
  # without leaving the machine. We verify it doesn't crash and updates the stamp.
  run bash "$FAKE_GK" version
  assert_success

  local new_stamp
  new_stamp="$(cat "$HOME/.gk/version_check")"
  # Stamp should be updated to something newer than old_stamp
  [ "$new_stamp" -gt "$old_stamp" ]
}

@test "GK_NO_VERSION_CHECK=1 suppresses the check entirely (no stamp written)" {
  GK_NO_VERSION_CHECK=1 run bash "$FAKE_GK" version
  assert_success

  # The short-circuit returns before the stamp file is ever written.
  [ ! -f "$HOME/.gk/version_check" ]
  refute_output --partial "Update available"
}

# ─── semver comparison ───────────────────────────────────────────────────────
# Drive the compare logic inside check_version via the curl stub. A fresh HOME
# means no stamp file, so the check always triggers.

# Usage: run_version_compare <local> <remote>
run_version_compare() {
  local version_home
  echo "$1" > "$FAKE_INSTALL_DIR/.git-kiss-version"
  export GK_FAKE_REMOTE_VERSION="$2"
  version_home="$(mktemp -d "$BATS_TEST_TMPDIR/version-home.XXXXXX")"
  run env HOME="$version_home" bash "$FAKE_GK" version
}

@test "version check reports an update only when the remote is newer" {
  # Remote genuinely newer -> update available.
  run_version_compare "1.2.3" "1.2.4"    # newer patch
  assert_output --partial "Update available"
  run_version_compare "1.2.3" "1.3.0"    # newer minor
  assert_output --partial "Update available"
  run_version_compare "1.2.3" "2.0.0"    # newer major
  assert_output --partial "Update available"
  run_version_compare "1.2.3" "1.3"      # fewer parts, but newer minor
  assert_output --partial "Update available"
  run_version_compare "1.2.3" "1.3.0.0"  # more parts, but newer minor
  assert_output --partial "Update available"

  # Remote equal or older -> no update message.
  run_version_compare "1.2.3" "1.2.3"    # equal
  refute_output --partial "Update available"
  run_version_compare "1.2.3" "1.2.2"    # older patch
  refute_output --partial "Update available"
  run_version_compare "1.2.3" "1.1.9"    # older minor
  refute_output --partial "Update available"
  run_version_compare "1.2.3" "0.9.9"    # older major
  refute_output --partial "Update available"
  run_version_compare "1.2.3" "1.2"      # fewer parts, older (1.2.0 < 1.2.3)
  refute_output --partial "Update available"
  run_version_compare "1.2.3" "1.2.2.9"  # more parts, older patch
  refute_output --partial "Update available"
}

@test "version warning is written to stderr" {
  echo "1.2.3" > "$FAKE_INSTALL_DIR/.git-kiss-version"
  export GK_FAKE_REMOTE_VERSION="1.2.4"
  local version_home stdout err_file
  version_home="$(mktemp -d "$BATS_TEST_TMPDIR/version-home.XXXXXX")"
  stdout="$BATS_TEST_TMPDIR/stdout"
  err_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c 'env HOME="$1" bash "$2" version > "$3" 2> "$4"' _ \
    "$version_home" "$FAKE_GK" "$stdout" "$err_file"
  assert_success
  assert_output ""
  assert_equal "$(cat "$stdout")" "gk v1.2.3"
  [[ "$(cat "$err_file")" == *"Update available"* ]]
  [[ "$(cat "$err_file")" == *"Run: curl -fsSL"* ]]
}
