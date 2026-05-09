#!/usr/bin/env bats

setup() {
    DETECT_SH="$BATS_TEST_DIRNAME/../../install/detect.sh"
    LIB_SH="$BATS_TEST_DIRNAME/../../install/lib.sh"
}

teardown() {
    if [[ -n "${LIVE_MARKER_DIR:-}" ]]; then
        rm -rf "$LIVE_MARKER_DIR"
    fi
    return 0
}

@test "detect.sh refuses without /etc/mandragora-live marker" {
    LIVE_MARKER_DIR="$(mktemp -d)"
    run env MANDRAGORA_LIVE_MARKER="$LIVE_MARKER_DIR/missing" bash "$DETECT_SH"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "live USB" ]]
}

@test "detect.sh _require_live_environment passes when marker exists" {
    LIVE_MARKER_DIR="$(mktemp -d)"
    : > "$LIVE_MARKER_DIR/marker"
    run bash -c "
        source '$DETECT_SH' --source-only
        MANDRAGORA_LIVE_MARKER='$LIVE_MARKER_DIR/marker' _require_live_environment
        echo ok
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ok ]]
}

@test "validate_token rejects shell metachars in hostname" {
    run bash -c "source '$LIB_SH'; validate_token hostname 'x\"; abort \"pwn'"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "invalid hostname" ]]
}

@test "validate_token rejects semicolon in user" {
    run bash -c "source '$LIB_SH'; validate_token user 'm; bad'"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "invalid user" ]]
}

@test "validate_token rejects space in keymap" {
    run bash -c "source '$LIB_SH'; validate_token keymap 'us extra'"
    [ "$status" -ne 0 ]
    [[ "$output" =~ "invalid keymap" ]]
}

@test "validate_token rejects empty value" {
    run bash -c "source '$LIB_SH'; validate_token hostname ''"
    [ "$status" -ne 0 ]
}

@test "validate_token rejects 64-char value (over limit)" {
    long=$(printf 'a%.0s' {1..64})
    run bash -c "source '$LIB_SH'; validate_token hostname '$long'"
    [ "$status" -ne 0 ]
}

@test "validate_token accepts well-formed names" {
    run bash -c "source '$LIB_SH'; validate_token hostname 'valid-host_42'; validate_token user 'm'; validate_token keymap 'us'"
    [ "$status" -eq 0 ]
}

@test "validate_token accepts 63-char value (at limit)" {
    long=$(printf 'a%.0s' {1..63})
    run bash -c "source '$LIB_SH'; validate_token hostname '$long'"
    [ "$status" -eq 0 ]
}
