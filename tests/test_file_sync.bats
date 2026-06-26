#!/usr/bin/env bats

setup() {
    export HOME="$(mktemp -d)"
    # shellcheck source=../helper.sh
    source "${BATS_TEST_DIRNAME}/../helper.sh"
}

teardown() {
    rm -rf "$HOME"
}

@test "helper.sh sources and defines display_menu function" {
    declare -f display_menu
}

@test "_rsync_apply_selection: returns items at selected positions" {
    run _rsync_apply_selection "1 3" "alpha" "beta" "gamma" "delta"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "gamma" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "_rsync_apply_selection: ignores out-of-range numbers" {
    run _rsync_apply_selection "1 99" "alpha" "beta"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = "alpha" ]
}

@test "_rsync_apply_selection: ignores non-numeric tokens" {
    run _rsync_apply_selection "1 abc 2" "alpha" "beta" "gamma"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "beta" ]
}
