#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk migrate converts legacy repo .gitkiss into team + local + .bak" {
  cat > "$REPO_DIR/.gitkiss" <<'EOF'
MAIN_BRANCH=main
DEVELOP_BRANCH=develop
STAGING_BRANCH=staging
FEATURE_PREFIX=feature/
USE_TAGS=true
INITIALS=mj
WORKTREE_COPY=".env config/local"
EOF
  git add .gitkiss && git commit -m "legacy" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" migrate
  assert_success

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

@test "gk migrate global config writes ~/.git-kiss.jsonc" {
  set_temp_home
  cat > "$HOME/.git-kiss" <<'EOF'
FEATURE_PREFIX=glob/
INITIALS=gg
USE_TAGS=false
WORKTREE_COPY=""
EOF
  run bash "$GK" migrate
  assert_success
  [ -f "$HOME/.git-kiss.jsonc" ]
  [ -f "$HOME/.git-kiss.bak" ]
  [ ! -f "$HOME/.git-kiss" ]
  assert_equal "$(jget "$HOME/.git-kiss.jsonc" .feature_prefix)" "glob/"
  assert_equal "$(jget "$HOME/.git-kiss.jsonc" .initials)" "gg"
}

@test "legacy .gitkiss is read in place when non-interactive (no migration)" {
  cat > "$REPO_DIR/.gitkiss" <<'EOF'
MAIN_BRANCH=main
DEVELOP_BRANCH=
STAGING_BRANCH=
FEATURE_PREFIX=feat/
USE_TAGS=false
INITIALS=zz
EOF
  git add .gitkiss && git commit -m "legacy" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf thing
  assert_success
  [ ! -f "$REPO_DIR/.gitkiss.jsonc" ]
  run git branch --show-current
  assert_output "feat/zz-thing"
}

@test "gk migrate with nothing to migrate is a no-op" {
  set_temp_home
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
