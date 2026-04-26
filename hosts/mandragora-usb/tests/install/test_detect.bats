#!/usr/bin/env bats

setup() {
    DETECT="$BATS_TEST_DIRNAME/../../install/detect.sh"
}

@test "detect.sh is executable" {
    [ -x "$DETECT" ]
}

@test "_resolve_boot_disk returns the disk holding /" {
    run bash -c 'source "'"$DETECT"'" --source-only; _resolve_boot_disk'
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^/dev/ ]]
}

@test "_list_block_disks excludes loop, ram, partitions" {
    run bash -c 'source "'"$DETECT"'" --source-only; _list_block_disks'
    [ "$status" -eq 0 ]
    refute_partitions=$(echo "$output" | grep -E '/dev/(sd[a-z]+[0-9]+|nvme[0-9]+n[0-9]+p[0-9]+|mmcblk[0-9]+p[0-9]+|loop[0-9]+|ram[0-9]+)$' || true)
    [ -z "$refute_partitions" ]
}

@test "_filter_targets excludes the boot disk" {
    run bash -c '
        source "'"$DETECT"'" --source-only
        _resolve_boot_disk() { echo /dev/sda; }
        echo -e "/dev/sda\n/dev/sdb\n/dev/nvme0n1" | _filter_targets
    '
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ /dev/sda$ ]]
    [[ "$output" =~ /dev/sdb ]]
    [[ "$output" =~ /dev/nvme0n1 ]]
}
