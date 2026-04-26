#!/usr/bin/env bats

setup() {
    FMT="$BATS_TEST_DIRNAME/../../install/format.sh"
}

@test "format.sh is executable" {
    [ -x "$FMT" ]
}

@test "_check_size accepts >=30 GB" {
    run bash -c 'source "'"$FMT"'" --source-only; _check_size 64424509440'
    [ "$status" -eq 0 ]
}

@test "_check_size warns at 30-60 GB" {
    run bash -c 'source "'"$FMT"'" --source-only; _check_size 42949672960 2>&1'
    [ "$status" -eq 0 ]
    [[ "$output" =~ small ]]
}

@test "_check_size refuses <30 GB" {
    run bash -c 'source "'"$FMT"'" --source-only; _check_size 10737418240'
    [ "$status" -ne 0 ]
}
