# Keystats Threat Model

`keystats` is the highest-sensitivity data pipeline on Mandragora: it
observes every keystroke on the `keyd` virtual keyboard. This page states
what it collects, where that lives, how it is encrypted, who can read the
key, the retention policy, and the residual risks that remain by design.

Module: [`nix/modules/desktop/keystats.nix`](../nix/modules/desktop/keystats.nix).
Daemon: `nix/snippets/keystats-capture.py`. Web UI:
`nix/snippets/keystats-web.py`. Retention: `nix/snippets/keystats-retention.py`.

## What is collected

Two SQLCipher databases under `/persistent/keystats/`:

- `stats.db` — anonymous aggregates only: per-keycode counts, keycode
  bigram counts, per-minute WPM buckets, per-window-class counts, session
  boundaries. No raw text, no keystroke order beyond adjacent-pair bigrams.
- `text.db` — typed **words** for the `kl.mvr.ac` wordcloud, gated hard:
  only from allow-listed window classes, never from blocked classes
  (password managers, polkit/gcr prompts) or windows whose title matches a
  password/login/OTP regex, and never words matching the entropy/shape/
  stop-word filters or the sops-encrypted `secretBlacklist`. A word is only
  persisted after it recurs (≥5 occurrences across ≥3 distinct days),
  which structurally excludes one-off secrets.

Text capture is opt-in via `mandragora.keystats.captureText.enable`.

## Where it lives

Both DBs and the plaintext blacklist (when `secretBlacklist` is unset)
live in `/persistent/keystats/` (dir `0700 m:users`). The DB files carry
mode `0644` but are unreadable by other users because the parent directory
denies traversal, and are ciphertext regardless. The `/persistent`
subvolume survives reboot; root is wiped each boot (impermanence).

## Encryption

SQLCipher (AES, `cipher_compatibility = 4`) with a 256-bit key supplied as
64 hex chars. The daemon and retention job open the DB read/write, the web
UI opens it read-only (`?mode=ro` + `PRAGMA query_only`). The DB is never
copied out in plaintext and row contents are never logged — the daemon and
retention job emit counts only.

## Who can read the key

The keys are sops-nix secrets (`keystats/db_key`, `keystats/text_db_key`)
materialised at `/run/secrets/keystats-db-key` and
`/run/secrets/keystats-text-db-key` with **`owner = m`, `mode = 0400`**.
Readers are therefore: **root** (owns the sops mount `/run/secrets.d`) and
**user `m`** (the secret owner). No other user, and no unprivileged process
of another user, can read the key. The key is passed to Python by
**file path** (env var `*_KEY_FILE`), never on the command line and never
as a key **value** in the environment, so it cannot leak via
`/proc/<pid>/cmdline` or another user's view of `/proc/<pid>/environ` (that
file is `0400` owner-only anyway). It is never written to journald.

## Retention policy

`keystats-retention` runs daily (systemd user timer, `Persistent`):

- Rolls up `wpm_bucket` minute rows older than **90 days** into a
  `wpm_daily` aggregate, then deletes the fine-grained minute rows.
- Deletes `session` rows whose `end_epoch` is older than 90 days.
- On `text.db`: halves `word_count` for words unseen in 30 days (dropping
  those that reach zero) and deletes `word_candidate` day-rows older than
  90 days.
- `VACUUM`s both DBs so freed pages return to the OS.

Aggregate counters (`keycode_count`, `bigram_count`, `class_count`) have no
timestamp and are retained indefinitely by design — they carry no
time-localised content.

## Residual risks (accepted)

- **Memory scraping.** The plaintext key and decrypted pages exist in the
  daemon's and web UI's address space while running. A root-level attacker
  (or `m` with a debugger) can read process memory; SQLCipher protects
  data at rest, not in RAM. `MemorySwapMax = 0` keeps key/plaintext pages
  out of swap.
- **Backups.** `/persistent/keystats` is not currently mirrored off-host.
  If `/persistent` is ever added to a backup/sync set, the ciphertext DBs
  travel with it — safe only as long as the sops key does not. Never back
  up `/run/secrets` alongside the DB.
- **Wordcloud inference.** `text.db` deliberately trades some privacy for
  the wordcloud. The gating + recurrence threshold make secret leakage
  unlikely but not impossible; treat `kl.mvr.ac` as sensitive and keep it
  behind its existing auth.
- **The `m` account is the trust boundary.** Anyone with `m`'s session can
  read the key and decrypt everything. There is no defence against a
  compromised primary account here, by design (no FDE, single-user box).
