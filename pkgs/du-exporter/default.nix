{ writeShellApplication, coreutils }:
writeShellApplication {
  name = "du-exporter";
  runtimeInputs = [ coreutils ];
  text = ''
    OUTDIR="/var/lib/prometheus-node-exporter-textfiles"
    TMPFILE=""
    TMPFILE=$(mktemp "$OUTDIR/.dirsize.prom.XXXXXX")
    SIZE_THRESHOLD=104857600
    INODE_THRESHOLD=100

    cleanup() { [ -n "$TMPFILE" ] && rm -f "$TMPFILE"; }
    trap cleanup EXIT

    # Collect Sizes
    du_size=$(du --block-size=1 -d5 /home/m 2>/dev/null)
    # Collect Inodes
    du_inodes=$(du --inodes -d5 /home/m 2>/dev/null)

    printf '# HELP dirsize_bytes Disk usage of directory in bytes\n' > "$TMPFILE"
    printf '# TYPE dirsize_bytes gauge\n' >> "$TMPFILE"
    while IFS=$'\t' read -r size path; do
      if [ "$size" -ge "$SIZE_THRESHOLD" ]; then
        printf 'dirsize_bytes{path="%s"} %s\n' "$path" "$size" >> "$TMPFILE"
      fi
    done <<< "$du_size"

    printf '# HELP dir_inode_count Number of inodes (files/dirs) in directory\n' >> "$TMPFILE"
    printf '# TYPE dir_inode_count gauge\n' >> "$TMPFILE"
    while IFS=$'\t' read -r count path; do
      if [ "$count" -ge "$INODE_THRESHOLD" ]; then
        printf 'dir_inode_count{path="%s"} %s\n' "$path" "$count" >> "$TMPFILE"
      fi
    done <<< "$du_inodes"

    trap - EXIT
    chmod 644 "$TMPFILE"
    mv "$TMPFILE" "$OUTDIR/dirsize.prom"
  '';
}
