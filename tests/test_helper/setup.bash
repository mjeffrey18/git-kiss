#!/usr/bin/env bash

# Shared test helpers for git-kiss tests

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Path to the gk script under test
GK="${BATS_TEST_DIRNAME}/../bin/gk"

# Create a fresh git repo with a remote (bare) for each test
setup_test_repo() {
  # Create a bare "remote" repo
  export REMOTE_DIR="$(mktemp -d)"
  git init --bare "$REMOTE_DIR" >/dev/null 2>&1

  # Create the working repo
  export REPO_DIR="$(mktemp -d)"
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
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=
STAGING_BRANCH=
FEATURE_PREFIX=feature/
USE_TAGS=false
INITIALS=
EOF
  git add .gitkiss
  git commit -m "add gitkiss config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
}

# Create a full flow repo (main + develop + staging)
setup_full_flow_repo() {
  setup_test_repo

  # Update config for full flow on main first
  cat > "$REPO_DIR/.gitkiss" <<EOF
MAIN_BRANCH=main
DEVELOP_BRANCH=develop
STAGING_BRANCH=staging
FEATURE_PREFIX=feature/
USE_TAGS=true
INITIALS=
EOF
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

# Clean up temp directories
teardown_test_repo() {
  if [[ -n "${REPO_DIR:-}" && -d "$REPO_DIR" ]]; then
    rm -rf "$REPO_DIR"
  fi
  if [[ -n "${REMOTE_DIR:-}" && -d "$REMOTE_DIR" ]]; then
    rm -rf "$REMOTE_DIR"
  fi
  # Clean up any worktree sibling directories
  if [[ -n "${REPO_DIR:-}" ]]; then
    local parent
    parent="$(dirname "$REPO_DIR")"
    local base
    base="$(basename "$REPO_DIR")"
    for wt_dir in "$parent/${base}"--*; do
      if [[ -d "$wt_dir" ]]; then
        rm -rf "$wt_dir"
      fi
    done
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
