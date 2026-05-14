#!/usr/bin/env bats

setup() {
    LIB="$BATS_TEST_DIRNAME/../../install/lib.sh"
    # shellcheck disable=SC1090
    source "$LIB"
}

@test "log_info prints to stderr with prefix" {
    run bash -c 'source "'"$LIB"'"; log_info "hello" 2>&1 1>/dev/null'
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[info\].*hello ]]
}

@test "log_error prints to stderr with prefix" {
    run bash -c 'source "'"$LIB"'"; log_error "bad" 2>&1 1>/dev/null'
    [ "$status" -eq 0 ]
    [[ "$output" =~ \[error\].*bad ]]
}

@test "die exits non-zero with message" {
    run bash -c 'source "'"$LIB"'"; die "broken"'
    [ "$status" -ne 0 ]
    [[ "$output" =~ broken ]]
}

@test "require_root fails when not root" {
    run bash -c 'source "'"$LIB"'"; (export EUID=1000; require_root)'
    [ "$status" -ne 0 ]
    [[ "$output" =~ root ]]
}

@test "confirm_typed accepts the expected token" {
    run bash -c 'source "'"$LIB"'"; echo "YES" | confirm_typed YES "are you sure"'
    [ "$status" -eq 0 ]
}

@test "confirm_typed rejects wrong input" {
    run bash -c 'source "'"$LIB"'"; echo "no" | confirm_typed YES "are you sure"'
    [ "$status" -ne 0 ]
}
