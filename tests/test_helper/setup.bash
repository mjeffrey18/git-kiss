#!/usr/bin/env bash

# Shared test helpers for git-kiss tests

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Path to the gk script under test
GK="${BATS_TEST_DIRNAME}/../bin/gk"

# Create a fresh git repo with a remote (bare) for each test
setup_test_repo() {
  # Never let ordinary tests stamp a file or hit the network.
  export GK_NO_VERSION_CHECK=1

  set_temp_home

  # Create a bare "remote" repo
  export REMOTE_DIR="$BATS_TEST_TMPDIR/remote"
  mkdir -p "$REMOTE_DIR"
  git init --bare "$REMOTE_DIR" >/dev/null 2>&1

  # Create the working repo
  export REPO_DIR="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"
  git init >/dev/null 2>&1
  git checkout -b main >/dev/null 2>&1

  # Minimal git config for tests
  git config user.email "test@test.com"
  git config user.name "Test User"

  # Initial commit so branches work
  echo "init" > README.md
  git add README.md
  git commit -m "initial commit" >/dev/null 2>&1

  # Add the bare repo as origin
  git remote add origin "$REMOTE_DIR"
  git push -u origin main >/dev/null 2>&1

  # Write a simple flow .gitkiss config and commit it so tree stays clean
  write_legacy_config "$REPO_DIR/.gitkiss"
  git add .gitkiss
  git commit -m "add gitkiss config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
}

# Create a full flow repo (main + develop + staging)
setup_full_flow_repo() {
  setup_test_repo

  # Update config for full flow on main first
  write_legacy_config "$REPO_DIR/.gitkiss" DEVELOP_BRANCH=develop STAGING_BRANCH=staging USE_TAGS=true
  git add .gitkiss
  git commit -m "update gitkiss config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  # Create develop branch
  git checkout -b develop >/dev/null 2>&1
  git push -u origin develop >/dev/null 2>&1

  # Create staging branch
  git checkout -b staging >/dev/null 2>&1
  git push -u origin staging >/dev/null 2>&1

  git checkout develop >/dev/null 2>&1
}

# Restore the environment after each test. All temp dirs (temp home, repo,
# remote, worktree siblings) live inside BATS_TEST_TMPDIR, which bats deletes
# itself after the test.
teardown_test_repo() {
  if [[ -n "${ORIG_HOME:-}" ]]; then
    export HOME="$ORIG_HOME"
    unset ORIG_HOME
  fi
}

# Helper: create a feature branch with a commit
create_feature_branch() {
  local name="${1:-test-feature}"
  git checkout main >/dev/null 2>&1
  git checkout -b "feature/$name" >/dev/null 2>&1
  echo "feature work" > "feature-$name.txt"
  git add -A >/dev/null 2>&1
  git commit -m "add $name" >/dev/null 2>&1
}

# Write a legacy shell-format .gitkiss config to $1. Remaining args are KEY=VALUE
# overrides on top of the simple-flow defaults. Valid keys:
#   MAIN_BRANCH DEVELOP_BRANCH STAGING_BRANCH FEATURE_PREFIX USE_TAGS INITIALS WORKTREE_COPY
# WORKTREE_COPY is only emitted when explicitly provided (kept quoted, legacy style).
write_legacy_config() {
  local path="$1"; shift
  local MAIN_BRANCH="main" DEVELOP_BRANCH="" STAGING_BRANCH="" \
        FEATURE_PREFIX="feature/" USE_TAGS="false" INITIALS=""
  local worktree_copy_set=0 WORKTREE_COPY=""
  local kv
  for kv in "$@"; do
    case "$kv" in
      MAIN_BRANCH=*)    MAIN_BRANCH="${kv#*=}" ;;
      DEVELOP_BRANCH=*) DEVELOP_BRANCH="${kv#*=}" ;;
      STAGING_BRANCH=*) STAGING_BRANCH="${kv#*=}" ;;
      FEATURE_PREFIX=*) FEATURE_PREFIX="${kv#*=}" ;;
      USE_TAGS=*)       USE_TAGS="${kv#*=}" ;;
      INITIALS=*)       INITIALS="${kv#*=}" ;;
      WORKTREE_COPY=*)  WORKTREE_COPY="${kv#*=}"; worktree_copy_set=1 ;;
      *) echo "write_legacy_config: unknown key '$kv'" >&2; return 1 ;;
    esac
  done
  {
    echo "MAIN_BRANCH=$MAIN_BRANCH"
    echo "DEVELOP_BRANCH=$DEVELOP_BRANCH"
    echo "STAGING_BRANCH=$STAGING_BRANCH"
    echo "FEATURE_PREFIX=$FEATURE_PREFIX"
    echo "USE_TAGS=$USE_TAGS"
    echo "INITIALS=$INITIALS"
    if [[ "$worktree_copy_set" == 1 ]]; then
      echo "WORKTREE_COPY=\"$WORKTREE_COPY\""
    fi
  } > "$path"
}

# Point HOME at a throwaway dir so global config / version stamps don't touch
# real $HOME. The dir lives inside BATS_TEST_TMPDIR so bats deletes it - the
# suite itself only restores $HOME in teardown_test_repo.
set_temp_home() {
  : "${BATS_TEST_TMPDIR:?set_temp_home requires bats (BATS_TEST_TMPDIR unset)}"
  export ORIG_HOME="${ORIG_HOME:-$HOME}"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# Run a command under a pseudo-terminal, preserving each argument boundary.
run_in_pty() {
  command -v expect >/dev/null || skip "expect is required for TTY onboarding tests"
  run expect -f "$BATS_TEST_DIRNAME/test_helper/run_in_pty.exp" -- "$@"
}

# Read a value from a JSONC file (strips full-line // comments first).
jget() {
  grep -v '^[[:space:]]*//' "$1" | jq -r "$2"
}
