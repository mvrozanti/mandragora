#!/usr/bin/env bash
usage() {
  echo "usage: mandragora-sops-decrypt <input-type> <output-type> <file>" >&2
  echo "  types: yaml json dotenv binary; <file> is read as the calling user" >&2
  exit 2
}

[ "$#" -eq 3 ] || usage
for t in "$1" "$2"; do
  case "$t" in yaml | json | dotenv | binary) ;; *) usage ;; esac
done

reader=()
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  reader=(runuser -u "$SUDO_USER" --)
fi

"${reader[@]}" cat -- "$3" \
  | (cd / && env -i PATH="$PATH" SOPS_AGE_KEY_FILE="$AGE_KEY_FILE" \
    sops decrypt --input-type "$1" --output-type "$2" /dev/stdin)
