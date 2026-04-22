{ writeShellApplication, coreutils }:
writeShellApplication {
  name = "du-exporter";
  runtimeInputs = [ coreutils ];
  text = ''
    OUTDIR="/var/lib/prometheus-node-exporter-textfiles"
    TMPFILE=$(mktemp "$OUTDIR/.dirsize.prom.XXXXXX")
    THRESHOLD=104857600

    printf '# HELP dirsize_bytes Disk usage of directory in bytes\n' > "$TMPFILE"
    printf '# TYPE dirsize_bytes gauge\n' >> "$TMPFILE"

    while IFS=$'\t' read -r size path; do
      if [ "$size" -ge "$THRESHOLD" ]; then
        printf 'dirsize_bytes{path="%s"} %s\n' "$path" "$size" >> "$TMPFILE"
      fi
    done < <(du --block-size=1 -d5 /home/m 2>/dev/null)

    mv "$TMPFILE" "$OUTDIR/dirsize.prom"
  '';
}
