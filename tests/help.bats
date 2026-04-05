#!/usr/bin/env bats

setup() {
  load 'test_helper/setup'
  setup_test_repo
}

teardown() {
  teardown_test_repo
}

@test "gk help shows usage" {
  run bash "$GK" help
  assert_success
  assert_output --partial "git-kiss"
  assert_output --partial "COMMANDS"
  assert_output --partial "nf <name>"
  assert_output --partial "wt <cmd>"
}

@test "gk --help shows usage" {
  run bash "$GK" --help
  assert_success
  assert_output --partial "COMMANDS"
}

@test "gk with no args shows help" {
  run bash "$GK"
  assert_success
  assert_output --partial "COMMANDS"
}

@test "gk version shows version number" {
  run bash "$GK" version
  assert_success
  assert_output --partial "gk v"
}

@test "gk --version shows version number" {
  run bash "$GK" --version
  assert_success
  assert_output --partial "gk v"
}

@test "gk unknown command fails" {
  run bash "$GK" foobar
  assert_failure
  assert_output --partial "Unknown command: foobar"
}

@test "gk wt help shows worktree usage" {
  run bash "$GK" wt help
  assert_success
  assert_output --partial "git-kiss worktree"
  assert_output --partial "nf <name>"
  assert_output --partial "nb <name>"
  assert_output --partial "rm <index|name>"
}

@test "gk wt with no subcommand shows help" {
  run bash "$GK" wt
  assert_success
  assert_output --partial "git-kiss worktree"
}

@test "gk wt unknown subcommand fails" {
  run bash "$GK" wt foobar
  assert_failure
  assert_output --partial "Unknown worktree command: foobar"
}
