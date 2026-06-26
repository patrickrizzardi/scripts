#!/usr/bin/env bats

setup() {
    export HOME="$(mktemp -d)"
    # shellcheck source=../helper.sh
    source "${BATS_TEST_DIRNAME}/../helper.sh"
}

teardown() {
    rm -rf "$HOME"
}

@test "helper.sh sources without errors" {
    true
}
