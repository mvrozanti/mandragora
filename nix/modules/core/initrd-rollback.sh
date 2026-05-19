@mkdir@ -p /mnt

@mount@ -t btrfs -o subvol=/ /dev/disk/by-label/NIXOS /mnt

if [ -e "/mnt/root-active" ]; then
    subvols=$(@btrfs@ subvolume list -o /mnt/root-active | @awk@ '{print $NF}')
    for subvol in $subvols; do
        @btrfs@ subvolume delete "/mnt/$subvol"
    done
    @btrfs@ subvolume delete -c "/mnt/root-active"
fi

if [ -e "/mnt/root-blank" ]; then
    @btrfs@ subvolume snapshot "/mnt/root-blank" "/mnt/root-active"
else
    @btrfs@ subvolume create "/mnt/root-active"
fi

@umount@ /mnt
