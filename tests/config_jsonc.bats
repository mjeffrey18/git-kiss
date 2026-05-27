#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
  # Remove the legacy config setup_test_repo created; these tests use JSONC.
  rm -f "$REPO_DIR/.gitkiss"
}

teardown() {
  teardown_test_repo
}

@test "reads scalar string keys from .gitkiss.jsonc" {
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
// team config
{
  "main_branch": "main",
  "develop_branch": "",
  "staging_branch": "",
  "feature_prefix": "feat/",
  "use_tags": false
}
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "initials": "ab" }
EOF
  git add -A && git commit -m "jsonc config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf login
  assert_success
  run git branch --show-current
  assert_output "feat/ab-login"
}

@test "use_tags false is respected (not lost to default)" {
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "",
  "feature_prefix": "feature/", "use_tags": false }
EOF
  git add -A && git commit -m "jsonc" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
  GK_DEBUG=1 run bash "$GK" version
  assert_success
  assert_output --partial "USE_TAGS=false"
}

@test "local layer overrides team layer; team overrides global" {
  set_temp_home   # isolates ~/.git-kiss.jsonc to a temp dir

  cat > "$HOME/.git-kiss.jsonc" <<'EOF'
{ "feature_prefix": "global/", "initials": "gg" }
EOF
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "",
  "feature_prefix": "team/", "use_tags": false }
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "feature_prefix": "local/", "initials": "mj" }
EOF
  git add -A && git commit -m "layers" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf thing
  assert_success
  run git branch --show-current
  assert_output "local/mj-thing"   # local prefix + local initials win
}

@test "malformed .gitkiss.jsonc is ignored with a warning, not a crash" {
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "feature_prefix": "feature/",  // inline comment breaks jq
EOF
  git add -A && git commit -m "bad jsonc" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" version
  assert_success
  assert_output --partial "malformed config"
}

@test "gk init (simple flow) writes JSONC team + local and gitignores local" {
  # gk init doesn't require a clean tree, so we don't commit after removing .gitkiss.
  rm -f "$REPO_DIR/.gitkiss"
  printf '2\nmj\n' | bash "$GK" init >/dev/null 2>&1

  [ -f "$REPO_DIR/.gitkiss.jsonc" ]
  [ -f "$REPO_DIR/.gitkiss.local.jsonc" ]
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .develop_branch)" ""
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .use_tags)" "false"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.local.jsonc" .initials)" "mj"

  run grep -qxF ".gitkiss.local.jsonc" "$REPO_DIR/.gitignore"
  assert_success
}

@test "gk init (full flow) sets develop, staging, tags" {
  rm -f "$REPO_DIR/.gitkiss"
  printf '1\nab\n' | bash "$GK" init >/dev/null 2>&1

  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .develop_branch)" "develop"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .staging_branch)" "staging"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .use_tags)" "true"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.local.jsonc" .initials)" "ab"
}

@test "gk init does not silently overwrite an existing .gitkiss.local.jsonc" {
  rm -f "$REPO_DIR/.gitkiss"
  printf '2\nmj\n' | bash "$GK" init >/dev/null 2>&1

  # User customises their personal file.
  printf '{ "initials": "mj", "worktree_copy": [".env"] }\n' > "$REPO_DIR/.gitkiss.local.jsonc"

  # Re-running init and declining the overwrite must preserve the customisation.
  printf 'n\n' | bash "$GK" init >/dev/null 2>&1
  assert_equal "$(jget "$REPO_DIR/.gitkiss.local.jsonc" '.worktree_copy[0]')" ".env"
}
