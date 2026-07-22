#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
  command -v expect >/dev/null || skip "expect is required for TTY onboarding tests"
  rm -f "$REPO_DIR/.gitkiss"
  set_temp_home
}

teardown() {
  teardown_test_repo
}

file_mode() {
  local mode

  if mode="$(stat -c '%a' "$1" 2>/dev/null)" && [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "$mode"
    return 0
  fi

  if mode="$(stat -f '%Lp' "$1" 2>/dev/null)" && [[ "$mode" =~ ^[0-7]{3,4}$ ]]; then
    printf '%s\n' "$mode"
    return 0
  fi

  return 1
}

run_init_tty() {
  local destination="$1"
  local main_branch="${2:-main}"
  local develop_branch="${3:-develop}"
  local global_exists="${4:-false}"
  run env REPO_PATH="$REPO_DIR" GK_PATH="$GK" DESTINATION="$destination" MAIN_BRANCH="$main_branch" DEVELOP_BRANCH="$develop_branch" GLOBAL_EXISTS="$global_exists" expect -c '
    set timeout 10
    cd $env(REPO_PATH)
    spawn -noecho bash $env(GK_PATH) init
    expect -exact "Main branch (default: $env(MAIN_BRANCH)): "
    send "\r"
    expect -exact "Develop branch (blank for simple flow) \[$env(DEVELOP_BRANCH)\]: "
    send "\r"
    expect -exact "Staging branch (leave blank to skip): "
    send "\r"
    expect -exact "Feature prefix (default: feature/ if blank): "
    send "\r"
    expect -exact "Use tags? \[Y/n\]: "
    send "\r"
    expect -exact "Your initials (leave blank to skip): "
    send "\r"
    expect -exact "Worktree copy paths, space-separated \[\]: "
    send "\r"
    expect -exact "Choose where to store the config\r\n"
    if {$env(GLOBAL_EXISTS) eq "true"} {
      expect -exact "1) Global project store\r\n2) This repo (Git tracked)\r\n3) This repo (local only)\r\nSelect \[1-3\]: "
    } else {
      expect -exact "1) Global\r\n2) Global project store\r\n3) This repo (Git tracked)\r\n4) This repo (local only)\r\nSelect \[1-4\]: "
    }
    send "$env(DESTINATION)\r"
    expect eof
  '
}

@test "TTY init writes each selected destination" {
  run_init_tty 1
  assert_success
  [ -f "$HOME/.gk/.gitkiss.jsonc" ]
  assert_equal "$(file_mode "$HOME/.gk")" "700"
  assert_equal "$(file_mode "$HOME/.gk/.gitkiss.jsonc")" "600"
  run_init_tty 1 main develop true
  assert_success
  [ -f "$HOME/.gk/projects.jsonc" ]
  assert_equal "$(file_mode "$HOME/.gk/projects.jsonc")" "600"
  run_init_tty 2 main develop true
  assert_success
  [ -f "$REPO_DIR/.gitkiss.jsonc" ]
  rm -f "$REPO_DIR/.gitkiss.jsonc"
  run_init_tty 3 main develop true
  assert_success
  [ -f "$REPO_DIR/.gitkiss.local.jsonc" ]
  run grep -qxF ".gitkiss.local.jsonc" "$REPO_DIR/.gitignore"
  assert_success
}

@test "TTY init detects master and dev when preferred branches are absent" {
  git branch -m main master
  git update-ref -d refs/remotes/origin/main
  git branch dev
  run_init_tty 3 master dev
  assert_success
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .main_branch)" "master"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .develop_branch)" "dev"
}

@test "TTY init persists blank and default values" {
  run_init_tty 3
  assert_success
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .main_branch)" "main"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .develop_branch)" "develop"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .staging_branch)" ""
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .feature_prefix)" "feature/"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .initials)" ""
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .worktree_copy | jq -c .)" "[]"
}

@test "TTY init hides an existing global config and leaves it untouched" {
  mkdir -p "$HOME/.gk"
  printf '{ "feature_prefix": "global-keep/" }\n' > "$HOME/.gk/.gitkiss.jsonc"
  run_init_tty 1 main develop true
  assert_success
  assert_equal "$(jget "$HOME/.gk/.gitkiss.jsonc" .feature_prefix)" "global-keep/"
  [[ "$output" != *"Overwrite global config"* ]]
  [[ "$output" == *"$HOME/.gk/projects.jsonc"* ]]
  local key
  key="$(cd "$REPO_DIR" && pwd -P)"
  [[ "$output" == *"Project key: $key"* ]]
}

@test "TTY init prefers main and develop over master and dev" {
  git branch master
  git branch develop
  git branch dev
  run_init_tty 3
  assert_success
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .main_branch)" "main"
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .develop_branch)" "develop"
}

@test "TTY init keeps existing destination when overwrite is declined" {
  printf '{ "feature_prefix": "keep/" }\n' > "$REPO_DIR/.gitkiss.jsonc"
  run env REPO_PATH="$REPO_DIR" GK_PATH="$GK" expect -c '
    set timeout 10
    cd $env(REPO_PATH)
    spawn -noecho bash $env(GK_PATH) init
    expect -exact "Main branch (default: main): "; send "\r"
    expect -exact "Develop branch (blank for simple flow) \[develop\]: "; send "\r"
    expect -exact "Staging branch (leave blank to skip): "; send "\r"
    expect -exact "Feature prefix (default: feature/ if blank): "; send "\r"
    expect -exact "Use tags? \[Y/n\]: "; send "\r"
    expect -exact "Your initials (leave blank to skip): "; send "\r"
    expect -exact "Worktree copy paths, space-separated \[\]: "; send "\r"
    expect -exact "Choose where to store the config\r\n"
    expect -exact "1) Global\r\n2) Global project store\r\n3) This repo (Git tracked)\r\n4) This repo (local only)\r\nSelect \[1-4\]: "; send "3\r"
    expect "Overwrite shared config*"; send "n\r"
    expect eof
  '
  assert_success
  assert_equal "$(jget "$REPO_DIR/.gitkiss.jsonc" .feature_prefix)" "keep/"
}

@test "automatic onboarding decline writes an empty project acknowledgement" {
  run env REPO_PATH="$REPO_DIR" GK_PATH="$GK" expect -c '
    set timeout 10
    cd $env(REPO_PATH)
    spawn -noecho bash $env(GK_PATH) nf acknowledged
    expect -exact "Set up git-kiss for this project? \[Y/n\] "; send "n\r"
    expect eof
  '
  local key
  key="$(cd "$REPO_DIR" && pwd -P)"
  assert_equal "$(jq -c --arg key "$key" '.[$key]' "$HOME/.gk/projects.jsonc")" "{}"
}

@test "TTY help and version do not trigger onboarding" {
  run env REPO_PATH="$REPO_DIR" GK_PATH="$GK" expect -c 'cd $env(REPO_PATH); spawn -noecho bash $env(GK_PATH) version; expect eof'
  assert_success
  [ ! -e "$HOME/.gk/projects.jsonc" ]
}

@test "linked worktrees inherit config without an onboarding prompt" {
  rm -f "$REPO_DIR/.gitkiss"
  cat > "$REPO_DIR/.gitkiss.jsonc" <<'EOF'
{ "main_branch": "main", "develop_branch": "", "staging_branch": "", "feature_prefix": "feature/", "use_tags": false }
EOF
  git add -A && git commit -m "jsonc config" >/dev/null 2>&1
  git push origin main >/dev/null 2>&1
  local wt_dir="$BATS_TEST_TMPDIR/repo--linked"
  git worktree add "$wt_dir" -b linked-test main >/dev/null 2>&1

  run env REPO_PATH="$wt_dir" GK_PATH="$GK" expect -c '
    set timeout 10
    cd $env(REPO_PATH)
    spawn -noecho bash $env(GK_PATH) nf linked
    expect eof
  '
  assert_success
  [[ "$output" != *"Set up git-kiss for this project?"* ]]
}
