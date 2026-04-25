{ writeShellApplication, coreutils }:
writeShellApplication {
  name = "du-exporter";
  runtimeInputs = [ coreutils ];
  text = ''
    OUTDIR="/var/lib/prometheus-node-exporter-textfiles"
    TMPFILE=""
    TMPFILE=$(mktemp "$OUTDIR/.dirsize.prom.XXXXXX")
    THRESHOLD=104857600

    cleanup() { [ -n "$TMPFILE" ] && rm -f "$TMPFILE"; }
    trap cleanup EXIT

    du_output=$(du --block-size=1 -d5 /home/m 2>/dev/null) || {
      echo "du-exporter: du failed (exit code $?)" >&2
      exit 1
    }

    printf '# HELP dirsize_bytes Disk usage of directory in bytes\n' > "$TMPFILE"
    printf '# TYPE dirsize_bytes gauge\n' >> "$TMPFILE"

    while IFS=$'\t' read -r size path; do
      if [ "$size" -ge "$THRESHOLD" ]; then
        printf 'dirsize_bytes{path="%s"} %s\n' "$path" "$size" >> "$TMPFILE"
      fi
    done <<< "$du_output"

        trap - EXIT
    chmod 644 "$TMPFILE"
    mv "$TMPFILE" "$OUTDIR/dirsize.prom"
  '';
}
