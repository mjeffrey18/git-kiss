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
  mkdir -p "$HOME/.gk"
  cat > "$HOME/.gk/.gitkiss.jsonc" <<'EOF'
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

@test "project store is applied between shared and local configuration" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  local key
  key="$(cd "$REPO_DIR" && pwd -P)"
  jq -n --arg key "$key" '{($key): {feature_prefix: "project/", initials: "ps"}}' > "$HOME/.gk/projects.jsonc"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "", "feature_prefix": "team/", "use_tags": false }
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "initials": "local" }
EOF
  git add -A && git commit -m "project store layer" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf thing
  assert_success
  run git branch --show-current
  assert_output "project/local-thing"
}

@test "malformed project store is ignored with a warning" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  printf '{ invalid\n' > "$HOME/.gk/projects.jsonc"

  run bash "$GK" version
  assert_success
  assert_output --partial "malformed project store"
}

@test "linked worktrees share the canonical project-store key" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  local key wt_dir
  key="$(cd "$REPO_DIR" && pwd -P)"
  wt_dir="$BATS_TEST_TMPDIR/repo--linked"
  jq -n --arg key "$key" '{($key): {feature_prefix: "linked/"}}' > "$HOME/.gk/projects.jsonc"
  git worktree add "$wt_dir" -b linked-test main >/dev/null 2>&1

  GK_DEBUG=1 run bash -c 'cd "$1" && bash "$2" version' _ "$wt_dir" "$GK"
  assert_success
  assert_output --partial "FEATURE_PREFIX=linked/"
}

@test "scalar, array and null project entries are ignored" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  local key
  key="$(cd "$REPO_DIR" && pwd -P)"

  for entry in '"bad"' '[]' 'null'; do
    jq -n --arg key "$key" --argjson entry "$entry" '{($key): $entry}' > "$HOME/.gk/projects.jsonc"
    GK_DEBUG=1 run bash "$GK" version
    assert_success
    assert_output --partial "Ignoring malformed project entry"
    refute_output --partial "FEATURE_PREFIX=bad"
  done
}

@test "a non-object project store is ignored" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  printf '[]\n' > "$HOME/.gk/projects.jsonc"

  run bash "$GK" version
  assert_success
  assert_output --partial "Ignoring malformed project store: $HOME/.gk/projects.jsonc"
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

@test "gk init refuses non-interactive use" {
  run bash "$GK" init
  assert_failure
  assert_output --partial "interactive terminal"
}
