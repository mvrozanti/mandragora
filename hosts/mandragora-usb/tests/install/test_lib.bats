#!/usr/bin/env bats

@test "bats is callable" {
    run echo hello
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}
