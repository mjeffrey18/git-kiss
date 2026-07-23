#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk migrate converts legacy repo .gitkiss into team + local + .bak" {
  write_legacy_config "$REPO_DIR/.gitkiss" \
    DEVELOP_BRANCH=develop STAGING_BRANCH=staging USE_TAGS=true INITIALS=mj \
    WORKTREE_COPY=".env config/local"
  git add .gitkiss && git commit -m "legacy" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash -c 'bash "$1" migrate > "$2"' _ "$GK" "$BATS_TEST_TMPDIR/migrate.stdout"
  assert_success
  assert_equal "$(cat "$BATS_TEST_TMPDIR/migrate.stdout")" ""

  [ -f "$REPO_DIR/.gitkiss.jsonc" ]
  [ -f "$REPO_DIR/.gitkiss.local.jsonc" ]
  [ -f "$REPO_DIR/.gitkiss.bak" ]
  [ ! -f "$REPO_DIR/.gitkiss" ]

  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .main_branch)" "main"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .develop_branch)" "develop"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .use_tags)" "true"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.local.jsonc" .initials)" "mj"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.local.jsonc" '.worktree_copy | length')" "2"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.local.jsonc" '.worktree_copy[0]')" ".env"

  run grep -qxF ".gitkiss.local.jsonc" "$REPO_DIR/.gitignore"
  assert_success
}

@test "gk migrate global config writes ~/.gk/.gitkiss.jsonc" {
  cat > "$HOME/.git-kiss" <<'EOF'
FEATURE_PREFIX=glob/
INITIALS=gg
USE_TAGS=false
WORKTREE_COPY=""
EOF
  run bash -c 'bash "$1" migrate > "$2"' _ "$GK" "$BATS_TEST_TMPDIR/migrate.stdout"
  assert_success
  assert_equal "$(cat "$BATS_TEST_TMPDIR/migrate.stdout")" ""
  [ -f "$HOME/.gk/.gitkiss.jsonc" ]
  [ -f "$HOME/.git-kiss.bak" ]
  [ ! -f "$HOME/.git-kiss" ]
  assert_equal "$(jget "$HOME/.gk/.gitkiss.jsonc" .feature_prefix)" "glob/"
  assert_equal "$(jget "$HOME/.gk/.gitkiss.jsonc" .initials)" "gg"
}

@test "gk migrate keeps a legacy global JSONC file when the destination collides" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  printf '{ "feature_prefix": "existing/" }\n' > "$HOME/.gk/.gitkiss.jsonc"
  printf '{ "feature_prefix": "legacy/" }\n' > "$HOME/.git-kiss.jsonc"

  run bash -c 'bash "$1" migrate > "$2"' _ "$GK" "$BATS_TEST_TMPDIR/migrate.stdout"
  assert_success
  assert_equal "$(cat "$BATS_TEST_TMPDIR/migrate.stdout")" ""
  [ -f "$HOME/.git-kiss.jsonc" ]
  assert_equal "$(jget "$HOME/.gk/.gitkiss.jsonc" .feature_prefix)" "existing/"
}

@test "gk migrate leaves a legacy global JSONC file intact when secure preparation fails" {
  set_temp_home
  printf '{ "feature_prefix": "legacy/" }\n' > "$HOME/.git-kiss.jsonc"
  ln -s "$BATS_TEST_TMPDIR/missing-gk-directory" "$HOME/.gk"

  run bash -c 'bash "$1" migrate > "$2"' _ "$GK" "$BATS_TEST_TMPDIR/migrate.stdout"
  assert_failure
  assert_equal "$(cat "$BATS_TEST_TMPDIR/migrate.stdout")" ""
  [ -f "$HOME/.git-kiss.jsonc" ]
}

@test "ordinary commands keep loading legacy global JSONC when secure preparation fails" {
  set_temp_home
  rm -f "$REPO_DIR/.gitkiss"
  printf '{ "feature_prefix": "legacy/" }\n' > "$HOME/.git-kiss.jsonc"
  ln -s "$BATS_TEST_TMPDIR/missing-gk-directory" "$HOME/.gk"

  GK_DEBUG=1 run bash "$GK" wt ls
  assert_success
  assert_output --partial "feature_prefix=legacy/ (global legacy)"
  [ -f "$HOME/.git-kiss.jsonc" ]
}

@test "gk migrate moves legacy global JSONC without overwriting a new config" {
  set_temp_home
  printf '{ "feature_prefix": "legacy/" }\n' > "$HOME/.git-kiss.jsonc"
  run bash "$GK" migrate
  assert_success
  [ -f "$HOME/.gk/.gitkiss.jsonc" ]
  [ ! -f "$HOME/.git-kiss.jsonc" ]
  assert_equal "$(jget "$HOME/.gk/.gitkiss.jsonc" .feature_prefix)" "legacy/"

  printf '{ "feature_prefix": "old/" }\n' > "$HOME/.git-kiss.jsonc"
  run bash "$GK" migrate
  assert_success
  [ -f "$HOME/.git-kiss.jsonc" ]
  assert_equal "$(jget "$HOME/.gk/.gitkiss.jsonc" .feature_prefix)" "legacy/"
}

@test "ordinary command migrates legacy global JSONC and preserves a collision" {
  set_temp_home
  printf '{ "feature_prefix": "ordinary/" }\n' > "$HOME/.git-kiss.jsonc"
  run bash "$GK" wt ls
  assert_success
  [ -f "$HOME/.gk/.gitkiss.jsonc" ]
  [ ! -f "$HOME/.git-kiss.jsonc" ]

  printf '{ "feature_prefix": "collision/" }\n' > "$HOME/.git-kiss.jsonc"
  run bash "$GK" wt ls
  assert_success
  [ -f "$HOME/.git-kiss.jsonc" ]
  assert_output --partial "migration skipped"
}

@test "legacy .gitkiss is read in place when non-interactive (no migration)" {
  write_legacy_config "$REPO_DIR/.gitkiss" FEATURE_PREFIX=feat/ INITIALS=zz
  git add .gitkiss && git commit -m "legacy" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf thing
  assert_success
  [ ! -f "$REPO_DIR/.gitkiss.jsonc" ]
  run git branch --show-current
  assert_output "feat/zz-thing"
}

@test "legacy config debug reports the winning repo layer" {
  write_legacy_config "$REPO_DIR/.gitkiss" FEATURE_PREFIX=legacy/ INITIALS=zz WORKTREE_COPY=".env"
  git add .gitkiss && git commit -m "legacy debug provenance" >/dev/null 2>&1

  DEBUG=1 run bash "$GK" wt ls
  assert_success
  assert_output --partial "feature_prefix=legacy/ (repo legacy)"
  assert_output --partial "initials=zz (repo legacy)"
  assert_output --partial "worktree_copy=.env (repo legacy)"
}

@test "legacy config never executes command substitutions and rejects unsupported keys" {
  local marker="$BATS_TEST_TMPDIR/legacy-executed"
  printf 'FEATURE_PREFIX=$(touch %s)\n' "$marker" > "$REPO_DIR/.gitkiss"
  git add .gitkiss && git commit -m "malicious legacy" >/dev/null 2>&1

  run bash "$GK" wt ls
  assert_failure
  assert_output --partial "Unsafe or unsupported legacy"
  [ ! -e "$marker" ]

  printf 'UNSUPPORTED_KEY=value\n' > "$REPO_DIR/.gitkiss"
  git add .gitkiss && git commit -m "unsupported legacy" >/dev/null 2>&1
  run bash "$GK" wt ls
  assert_failure
  assert_output --partial "Unsafe or unsupported legacy"
}

@test "legacy config accepts indented comments and rejects JSON-sensitive scalar values" {
  cat > "$REPO_DIR/.gitkiss" <<'EOF'

  # indented comment
FEATURE_PREFIX=feat/
DEVELOP_BRANCH=
STAGING_BRANCH=
USE_TAGS=false
INITIALS=ok
EOF
  git add .gitkiss && git commit -m "indented legacy" >/dev/null 2>&1
  run bash "$GK" nf sample
  assert_success
  run git branch --show-current
  assert_output "feat/ok-sample"

  git checkout main >/dev/null 2>&1
  printf 'INITIALS="tab\tvalue"\n' > "$REPO_DIR/.gitkiss"
  git add .gitkiss && git commit -m "tab legacy" >/dev/null 2>&1
  run bash "$GK" migrate
  assert_failure
  assert_output --partial "Unsafe or unsupported legacy"
}

@test "gk migrate with nothing to migrate is a no-op" {
  rm -f "$REPO_DIR/.gitkiss"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "",
  "feature_prefix": "feature/", "use_tags": false }
EOF
  git add -A && git commit -m "already jsonc" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" migrate
  assert_success
  assert_output --partial "Nothing to migrate"
}
