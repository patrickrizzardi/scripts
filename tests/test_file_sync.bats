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

@test "_rsync_build_pairs_from_dir: builds correct source|target lines" {
    run _rsync_build_pairs_from_dir "/mnt/c/src" "/home/user/dest" "plugins" "settings.json"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "/mnt/c/src/plugins|/home/user/dest/plugins" ]
    [ "${lines[1]}" = "/mnt/c/src/settings.json|/home/user/dest/settings.json" ]
}

@test "_rsync_build_pairs_from_dir: handles single item" {
    run _rsync_build_pairs_from_dir "/src" "/dest" "foo"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "/src/foo|/dest/foo" ]
    [ "${#lines[@]}" -eq 1 ]
}

@test "_rsync_generate_sync_sh_content: uses rsync -a --delete for directories" {
    run _rsync_generate_sync_sh_content
    [ "$status" -eq 0 ]
    [[ "$output" == *"rsync -a --delete"* ]]
}

@test "_rsync_generate_sync_sh_content: uses rsync -a for files" {
    run _rsync_generate_sync_sh_content
    [[ "$output" == *'rsync -a "$source"'* ]]
}

@test "_rsync_generate_sync_sh_content: reads pairs.conf" {
    run _rsync_generate_sync_sh_content
    [[ "$output" == *"pairs.conf"* ]]
}

@test "_rsync_generate_sync_sh_content: logs errors to sync.log" {
    run _rsync_generate_sync_sh_content
    [[ "$output" == *"sync.log"* ]]
}

@test "_rsync_generate_service_content: uses %h for home dir" {
    run _rsync_generate_service_content
    [[ "$output" == *"%h/.config/rsync-sync/sync.sh"* ]]
}

@test "_rsync_generate_timer_content: sets 30s interval" {
    run _rsync_generate_timer_content
    [[ "$output" == *"OnUnitActiveSec=30s"* ]]
}

@test "_rsync_generate_timer_content: sets 1s accuracy" {
    run _rsync_generate_timer_content
    [[ "$output" == *"AccuracySec=1s"* ]]
}

@test "_rsync_write_config: creates pairs.conf with all pairs" {
    _rsync_write_config "/src/a|/dest/a" "/src/b|/dest/b"
    [ -f "$HOME/.config/rsync-sync/pairs.conf" ]
    run cat "$HOME/.config/rsync-sync/pairs.conf"
    [ "${lines[0]}" = "/src/a|/dest/a" ]
    [ "${lines[1]}" = "/src/b|/dest/b" ]
}

@test "_rsync_write_config: sync.sh is executable" {
    _rsync_write_config "/src/a|/dest/a"
    [ -x "$HOME/.config/rsync-sync/sync.sh" ]
}

@test "_rsync_write_config: creates systemd service file" {
    _rsync_write_config "/src/a|/dest/a"
    [ -f "$HOME/.config/systemd/user/rsync-sync.service" ]
}

@test "_rsync_write_config: creates systemd timer file" {
    _rsync_write_config "/src/a|/dest/a"
    [ -f "$HOME/.config/systemd/user/rsync-sync.timer" ]
}
