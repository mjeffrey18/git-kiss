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
  GK_DEBUG=1 run bash "$GK" wt ls
  assert_success
  assert_output --partial "use_tags=false (repo)"
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

@test "repo configuration overrides global-project configuration before local configuration" {
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
  assert_output "team/local-thing"
}

@test "malformed project store fails closed" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  printf '{ invalid\n' > "$HOME/.gk/projects.jsonc"

  run bash "$GK" wt ls
  assert_failure
  assert_output --partial "Invalid project store"
}

@test "linked worktrees use the canonical project-store key" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  local key wt_dir
  key="$(cd "$REPO_DIR" && pwd -P)"
  wt_dir="$BATS_TEST_TMPDIR/repo--linked"
  jq -n --arg key "$key" '{($key): {feature_prefix: "linked/"}}' > "$HOME/.gk/projects.jsonc"
  git worktree add "$wt_dir" -b linked-test main >/dev/null 2>&1

  GK_DEBUG=1 run bash -c 'cd "$1" && bash "$2" wt ls' _ "$wt_dir" "$GK"
  assert_success
  assert_output --partial "global project"
  refute_output --partial "gk-project."

}

@test "all four layers use global, global project, repo, local precedence per key" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  local key
  key="$(cd "$REPO_DIR" && pwd -P)"
  cat > "$HOME/.gk/.gitkiss.jsonc" <<'EOF'
{ "feature_prefix": "global/", "initials": "global", "worktree_copy": ["global.env"] }
EOF
  jq -n --arg key "$key" '{($key): {feature_prefix: "project/", initials: "project", worktree_copy: ["project.env"]}}' > "$HOME/.gk/projects.jsonc"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "", "feature_prefix": "repo/", "use_tags": false, "worktree_copy": ["repo.env"] }
EOF
  cat > "$REPO_DIR/.gitkiss.local.jsonc" <<'EOF'
{ "initials": "local", "worktree_copy": [] }
EOF
  git add -A && git commit -m "four config layers" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" nf thing
  assert_success
  run git branch --show-current
  assert_output "repo/local-thing"
}

@test "DEBUG=1 writes configuration diagnostics to stderr and DEBUG=0 overrides GK_DEBUG" {
  local stdout_file stderr_file
  stdout_file="$BATS_TEST_TMPDIR/debug.stdout"
  stderr_file="$BATS_TEST_TMPDIR/debug.stderr"
  run bash -c 'DEBUG=1 bash "$1" wt ls > "$2" 2> "$3"' _ "$GK" "$stdout_file" "$stderr_file"
  assert_success
  [[ "$(cat "$stdout_file")" != *"[debug]"* ]]
  [[ "$(cat "$stderr_file")" == *"config effective:"* ]]

  run env DEBUG=0 GK_DEBUG=1 bash "$GK" wt ls
  assert_success
  refute_output --partial "[debug]"
}

@test "scalar, array and null project entries fail closed" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  local key
  key="$(cd "$REPO_DIR" && pwd -P)"

  for entry in '"bad"' '[]' 'null'; do
    jq -n --arg key "$key" --argjson entry "$entry" '{($key): $entry}' > "$HOME/.gk/projects.jsonc"
    GK_DEBUG=1 run bash "$GK" wt ls
    assert_failure
    assert_output --partial "Invalid project entry"
  done
}

@test "a non-object project store fails closed" {
  set_temp_home
  mkdir -p "$HOME/.gk"
  printf '[]\n' > "$HOME/.gk/projects.jsonc"

  run bash "$GK" wt ls
  assert_failure
  assert_output --partial "Invalid project store"
}

@test "malformed .gitkiss.jsonc fails closed" {
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "feature_prefix": "feature/",  // inline comment breaks jq
EOF
  git add -A && git commit -m "bad jsonc" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1

  run bash "$GK" wt ls
  assert_failure
  assert_output --partial "Invalid configuration"
}

@test "gk init refuses non-interactive use" {
  run bash "$GK" init
  assert_failure
  assert_output --partial "interactive terminal"
}

@test "JSONC type, key and ref validation fails closed" {
  local invalid
  for invalid in \
    '{"use_tags":"false"}' \
    '{"main_branch":42}' \
    '{"worktree_copy":[".env",7]}' \
    '{"main_branch":"bad ref"}' \
    '{"unsupported":true}'; do
    printf '%s\n' "$invalid" > "$REPO_DIR/.gitkiss.jsonc"
    git add .gitkiss.jsonc && git commit -m "invalid jsonc" >/dev/null 2>&1
    run bash "$GK" wt ls
    assert_failure
    assert_output --partial "Invalid"
    git reset --hard HEAD~1 >/dev/null 2>&1
  done
}
