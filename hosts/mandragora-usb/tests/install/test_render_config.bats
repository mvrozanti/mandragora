#!/usr/bin/env bats

setup() {
    RND="$BATS_TEST_DIRNAME/../../install/render-config.sh"
}

@test "render-config.sh is executable" {
    [ -x "$RND" ]
}

@test "_detect_microcode returns intel for GenuineIntel" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_microcode_from_vendor GenuineIntel
    '
    [ "$status" -eq 0 ]
    [ "$output" = "intel-ucode" ]
}

@test "_detect_microcode returns amd for AuthenticAMD" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_microcode_from_vendor AuthenticAMD
    '
    [ "$status" -eq 0 ]
    [ "$output" = "amd-ucode" ]
}

@test "_detect_gpu intel sets video driver" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_gpu_from_id "8086:1234"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "intel" ]
}

@test "_detect_gpu amd from 1002 vendor id" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_gpu_from_id "1002:abcd"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "amd" ]
}

@test "_detect_gpu unknown returns 'none'" {
    run bash -c '
        source "'"$RND"'" --source-only
        _detect_gpu_from_id "9999:0000"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

@test "_render_template substitutes placeholders" {
    tmpl=$(mktemp)
    out=$(mktemp)
    cat > "$tmpl" <<-'TPL'
hostname=@HOSTNAME@
user=@USER@
TPL
    run bash -c '
        source "'"$RND"'" --source-only
        _render_template "'"$tmpl"'" "'"$out"'" \
            HOSTNAME=foo USER=m
    '
    [ "$status" -eq 0 ]
    grep -q "hostname=foo" "$out"
    grep -q "user=m" "$out"
    rm -f "$tmpl" "$out"
}
