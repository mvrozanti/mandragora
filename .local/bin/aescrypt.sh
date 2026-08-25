#!/usr/bin/env bash
set -euo pipefail

MODE=encrypt
OUT=""

usage() {
  cat >&2 <<'EOF'
Usage: aescrypt [-d] [-o FILE] < input > output

AES-256-CBC with PBKDF2 (600000 iterations, SHA-256) and a random salt,
base64-armoured so the result is safe to paste, scp, or store as text.

Data is read from stdin; the passphrase is read from the terminal, so
piping works and the passphrase never appears in argv, the environment,
or shell history.

  printf %s 'secret string' | aescrypt > secret.aes
  aescrypt -d < secret.aes
  aescrypt -o /tmp/key.aes < key.txt

Options:
  -d          Decrypt instead of encrypt.
  -o FILE     Write to FILE, created mode 0600, instead of stdout.
  -h, --help  Show this help.

openssl enc gives confidentiality but not authentication: a tampered
file decrypts to garbage rather than being reported as tampered. When
you want authenticated encryption, use 'age -p' instead.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--decrypt) MODE=decrypt; shift ;;
    -o|--out)
      OUT="${2:-}"
      if [ -z "$OUT" ]; then usage; exit 1; fi
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "aescrypt: unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [ ! -e /dev/tty ]; then
  echo "aescrypt: no terminal available to read the passphrase" >&2
  exit 1
fi

if [ -t 0 ]; then
  echo "aescrypt: no input on stdin — pipe data in or redirect a file" >&2
  usage
  exit 1
fi

args=(enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha256 -salt -a)
if [ "$MODE" = decrypt ]; then
  args+=(-d)
fi

if [ -n "$OUT" ]; then
  umask 077
  openssl "${args[@]}" -out "$OUT"
  chmod 600 "$OUT"
else
  openssl "${args[@]}"
fi
