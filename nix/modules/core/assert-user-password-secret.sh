secret=/run/secrets-for-users/user/password
fail() {
  echo "FATAL: $1" >&2
  echo "Refusing to rewrite /etc/shadow: with mutableUsers=false a missing secret" >&2
  echo "locks m's account and an empty one blanks its password. Aborting activation so" >&2
  echo "the live /etc/shadow is left untouched. Fix the sops user/password secret and" >&2
  echo "re-run the switch; at boot, recover from a console (no full-disk encryption)." >&2
  exit 1
}
[ -f "$secret" ] || fail "$secret does not exist (sops user/password not deployed)."
[ -s "$secret" ] || fail "$secret is empty (sops user/password decrypted to nothing)."
[ "$(head -c1 "$secret")" = '$' ] || fail "$secret does not begin with '\$' (not a crypt hash)."
